module cbuilder

import os
import os.filelock
import strings
import time
import v.pref
import v.util
import v.builder
import v.gen.c

const reuse_tmpc_lock_wait_ms = 600_000

pub fn start() {
	mut args_and_flags := util.join_env_vflags_and_os_args()[1..]
	prefs, _ := pref.parse_args([], args_and_flags)
	builder.compile('build', prefs, compile_c)
}

pub fn compile_c(mut b builder.Builder) {
	if b.pref.is_verbose {
		println('all .v files before:')
	}
	$if windows {
		if builder.should_find_windows_host_c_compiler(b.pref) {
			b.find_win_cc() or {
				if b.pref.ccompiler_set_by_flag && b.pref.ccompiler != 'msvc' {
					builder.verror(err.msg())
				}
				builder.verror('
==================
Error: no C compiler detected.

You can find instructions on how to install one in the V wiki:
https://github.com/vlang/v/wiki/Installing-a-C-compiler-on-Windows

If you think you have one installed, make sure it is in your PATH.
If you do have one in your PATH, please raise an issue on GitHub:
https://github.com/vlang/v/issues/new/choose

You can also use `v doctor`, to see what V knows about your current environment.

You can also seek #help on Discord: https://discord.gg/vlang
')
			}
		}
	}
	mut files := b.get_builtin_files()
	files << b.get_user_files()
	b.set_module_lookup_paths()
	if b.pref.is_verbose {
		println('all .v files:')
		println(files)
	}
	mut out_name_c := b.get_vtmp_filename(b.pref.out_name, '.tmp.c')
	if b.pref.is_shared {
		out_name_c = b.get_vtmp_filename(b.pref.out_name, '.tmp.so.c')
	}
	if b.pref.reuse_tmpc {
		mut tmpc_lock := acquire_reuse_tmpc_lock(out_name_c) or { builder.verror(err.msg()) }
		defer {
			tmpc_lock.release()
		}
		build_c(mut b, files, out_name_c)
		if !b.pref.parallel_cc {
			b.cc()
		}
		return
	}
	build_c(mut b, files, out_name_c)
	if !b.pref.parallel_cc {
		b.cc()
	}
}

fn acquire_reuse_tmpc_lock(out_name_c string) !filelock.FileLock {
	lock_path := out_name_c + '.lock'
	os.mkdir_all(os.dir(lock_path)) or {
		return error('could not create -keepc lock directory `${os.dir(lock_path)}`: ${err}')
	}
	mut gate := filelock.new(lock_path)
	if !gate.wait_acquire(reuse_tmpc_lock_wait_ms * time.millisecond) {
		return error('timed out waiting for -keepc build artifact lock `${lock_path}`')
	}
	return gate
}

pub fn build_c(mut b builder.Builder, v_files []string, out_file string) {
	b.out_name_c = out_file
	b.pref.out_name_c = os.real_path(out_file)
	b.info('build_c(${out_file})')
	mut output2 := gen_c(mut b, v_files)
	if b.pref.is_vlines {
		output2 = c.fix_reset_dbg_line(output2, out_file)
	}
	os.write_file_array(out_file, output2) or { panic(err) }
	if b.pref.is_stats {
		b.stats_lines = output2.count(it == `\n`) + 1
		b.stats_bytes = output2.len
	}
}

pub fn gen_c(mut b builder.Builder, v_files []string) strings.Builder {
	b.front_and_middle_stages(v_files) or {
		if err.code() > 7000 {
			return []u8{}
		}
		builder.verror(err.msg())
	}

	util.timing_start('C GEN')
	result := c.gen(b.parsed_files, mut b.table, b.pref)
	util.timing_measure('C GEN')

	if b.pref.parallel_cc {
		b.cc() // Call it just to gen b.str_args
		util.timing_start('Parallel C compilation')
		parallel_cc(mut b, result) or { builder.verror(err.msg()) }
		util.timing_measure('Parallel C compilation')
	}

	return result.res_builder
}
