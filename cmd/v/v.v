// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import hash
import os
import term
import v.help
import v.pref
import v.util
import v.util.vflags as util_vflags
import v.util.version
import v.builder
import v.builder.cbuilder
import v.builder.target_osbuilder

@[markused]
const external_tools = [
	'ast',
	'bin2v',
	'bug',
	'bug-report',
	'bug-report-send',
	'build-examples',
	'build-tools',
	'build-vbinaries',
	'bump',
	'check-md',
	'complete',
	'compress',
	'cover',
	'diff',
	'doc',
	'doctor',
	'download',
	'fmt',
	'git-fmt-hook',
	'gret',
	'ls',
	'missdoc',
	'quest',
	'reduce',
	'repl',
	'repeat',
	'retry',
	'self',
	'setup-freetype',
	'shader',
	'share',
	'should-compile-all',
	'sqlite',
	'symlink',
	'scan',
	'test',
	'test-all', // runs most of the tests and other checking tools, that will be run by the CI
	'test-cleancode',
	'test-fmt',
	'test-parser',
	'test-self',
	'time',
	'timeout',
	'tracev',
	'up',
	'vet',
	'wipe-cache',
	'watch',
	'where',
]
const delegated_v2_exe_env = 'V_V2_EXE'

fn run_delegate_compilation_command(command string) os.Result {
	$if windows {
		return os.exec(util_vflags.tokenize_to_args(command))
	} $else {
		return os.execute(command)
	}
}

struct DelegatedProcessResult {
	exit_code     int
	raw_exit_code int
	stdout        string
	stderr        string
	output        string
	error         string
	command       string
	executable    string
	cwd           string
}

fn run_delegated_process_echoed(executable string, args []string) DelegatedProcessResult {
	return run_delegated_process_echoed_with_env(executable, args, map[string]string{}, false)
}

fn run_delegated_process_echoed_with_environment(executable string, args []string, envs map[string]string) DelegatedProcessResult {
	return run_delegated_process_echoed_with_env(executable, args, envs, true)
}

fn run_delegated_process_echoed_with_env(executable string, args []string, envs map[string]string, use_custom_env bool) DelegatedProcessResult {
	command := '${os.quoted_path(executable)} ${args.map(os.quoted_path(it)).join(' ')}'
	cwd := os.getwd()
	mut process := os.new_process(executable)
	process.set_args(args)
	if use_custom_env {
		process.set_environment(envs)
	}
	process.set_redirect_stdio()
	process.wait()
	stdout := process.stdout_slurp()
	stderr := process.stderr_slurp()
	if stdout != '' {
		print(stdout)
	}
	if stderr != '' {
		eprint(stderr)
	}
	raw_exit_code := process.code
	process_error := process.err
	process.close()
	return DelegatedProcessResult{
		exit_code:     if raw_exit_code < 0 { 1 } else { raw_exit_code }
		raw_exit_code: raw_exit_code
		stdout:        stdout
		stderr:        stderr
		output:        stdout + stderr
		error:         process_error
		command:       command
		executable:    executable
		cwd:           cwd
	}
}

fn delegated_process_needs_parent_diagnostics(result DelegatedProcessResult) bool {
	return result.exit_code != 0
		&& (result.raw_exit_code < 0 || result.error != '' || result.output.trim_space() == '')
}

fn report_delegated_process_failure(prefix string, result DelegatedProcessResult, options os.CommandFailureDiagnostics) {
	eprintln(os.process_command_failure_report(prefix, result.raw_exit_code,
		stage:          options.stage
		command:        result.command
		reason:         options.reason
		action:         options.action
		message:        options.message
		output:         result.output
		stdout:         result.stdout
		stderr:         result.stderr
		output_capture: 'redirected_stdio_echoed'
		error:          result.error
	))
	eprintln('${prefix}.parent_exit_code=${result.exit_code}')
	eprintln('${prefix}.raw_exit_code=${result.raw_exit_code}')
	eprintln('${prefix}.stdout_bytes=${result.stdout.len}')
	eprintln('${prefix}.stderr_bytes=${result.stderr.len}')
	eprintln('${prefix}.cwd=${delegate_report_value(result.cwd)}')
	eprintln('${prefix}.executable=${delegate_report_value(result.executable)}')
}

@[unsafe]
fn timers_pointer(p &util.Timers) &util.Timers {
	// TODO: the static variable here is used as a workaround for the current incompatibility of -usecache and globals in the main module:
	mut static ptimers := unsafe { &util.Timers(nil) }
	if p != unsafe { nil } {
		ptimers = p
	}
	return ptimers
}

fn main() {
	unbuffer_stdout()
	mut timers_should_print := false
	$if time_v ? {
		timers_should_print = true
	}
	if '-show-timings' in os.args {
		timers_should_print = true
	}
	mut timers := unsafe {
		timers_pointer(util.new_timers(
			should_print: timers_should_print
			label:        'main'
		))
	}
	timers.start('v start')
	timers.show('v start')
	timers.start('TOTAL')
	// use at_exit here, instead of defer, since some code paths later do early exit(0) or exit(1), for showing errors, or after `v run`
	at_exit(fn () {
		mut timers := unsafe { timers_pointer(nil) }
		timers.show('TOTAL')
	})!
	timers.start('v parsing CLI args')
	args := os.args[1..]

	if args.len == 0 || args[0] in ['-', 'repl'] {
		if args.len == 0 {
			// Running `./v` without args launches repl
			if os.is_atty(0) == 0 {
				mut args_and_flags := util.join_env_vflags_and_os_args()[1..].clone()
				args_and_flags << ['run', '-']
				pref.parse_args_and_show_errors(external_tools, args_and_flags, true)
			}
		}
		util.launch_tool(false, 'vrepl', os.args[1..])
		return
	}
	mut args_and_flags := util.join_env_vflags_and_os_args()[1..]
	prefs, command := pref.parse_args_and_show_errors(external_tools, args_and_flags, true)
	maybe_delegate_to_vvmrc(command, prefs)
	maybe_delegate_to_v2(command, prefs)
	if prefs.use_cache && os.user_os() == 'windows' {
		eprintln('-usecache is currently disabled on windows')
		exit(1)
	}
	timers.show('v parsing CLI args')

	setup_vbuild_env_vars(prefs)

	// Start calling the correct functions/external tools
	// Note for future contributors: Please add new subcommands in the `match` block below.
	if command in external_tools {
		// External tools
		util.launch_tool(prefs.is_verbose, 'v' + command, os.args[1..])
		return
	}
	match command {
		'run', 'crun', 'build', 'build-module' {
			rebuild(prefs)
			exit(0)
		}
		'help' {
			invoke_help_and_exit(args)
		}
		'version' {
			println(version.full_v_version(prefs.is_verbose))
			exit(0)
		}
		'new', 'init' {
			util.launch_tool(prefs.is_verbose, 'vcreate', os.args[1..])
			return
		}
		'install', 'link', 'list', 'outdated', 'remove', 'search', 'show', 'unlink', 'update',
		'upgrade' {
			util.launch_tool(prefs.is_verbose, 'vpm', os.args[1..])
			return
		}
		'vlib-docs' {
			util.launch_tool(prefs.is_verbose, 'vdoc', ['doc', 'vlib'])
		}
		'interpret' {
			eprintln('use v -v2 -eval file.v')
			exit(1)
		}
		'get' {
			eprintln('V Error: Use `v install` to install modules from vpm.vlang.io')
			exit(1)
		}
		'translate' {
			util.launch_tool(prefs.is_verbose, 'translate', os.args[1..])
			// exit(1)
			// return
		}
		else {
			if command.ends_with('.v') || os.exists(command) {
				// println('command')
				// println(prefs.path)
				rebuild(prefs)
				exit(0)
			}
		}
	}

	if prefs.is_help {
		invoke_help_and_exit(args)
	}

	other_commands := ['run', 'crun', 'build', 'build-module', 'help', 'version', 'new', 'init',
		'install', 'link', 'list', 'outdated', 'remove', 'search', 'show', 'unlink', 'update',
		'upgrade', 'vlib-docs', 'translate']
	mut all_commands := []string{}
	all_commands << external_tools
	all_commands << other_commands
	all_commands.sort()
	eprintln(util.new_suggestion(command, all_commands, similarity_threshold: 0.2).say('v: unknown command `${command}`'))
	eprintln('Run ${term.highlight_command('v help')} for usage.')
	exit(1)
}

fn invoke_help_and_exit(remaining []string) {
	match remaining.len {
		0, 1 { help.print_and_exit('default', exit_code: 0) }
		2 { help.print_and_exit(remaining[1], exit_code: 0) }
		else {}
	}

	eprintln('${term.highlight_command('v help')}: provide only one help topic.')
	eprintln('For usage information, use ${term.highlight_command('v help')}.')
	exit(1)
}

fn maybe_delegate_to_v2(command string, prefs &pref.Preferences) {
	is_ownership := '-ownership' in os.args
	if !prefs.use_v2 && !is_ownership {
		return
	}
	if !is_v2_relevant_command(command, prefs) {
		eprintln('v: `-v2`/`-ownership` currently support direct compilation only. Use `v -v2 hello.v` or `v -ownership module_dir`.')
		exit(1)
	}
	launch_v2_compiler(prefs.is_verbose, os.args[1..].filter(it != '-v2'), is_ownership)
}

fn is_v2_relevant_command(command string, prefs &pref.Preferences) bool {
	if prefs.path == '' || prefs.is_run || prefs.is_crun {
		return false
	}
	return prefs.path == command && (command.ends_with('.v') || os.exists(command))
}

@[noreturn]
fn launch_v2_compiler(is_verbose bool, args []string, is_ownership bool) {
	vexe := pref.vexe_path()
	vroot := os.dir(vexe)
	util.set_vroot_folder(vroot)
	tool_name := if is_ownership { 'v2_ownership' } else { 'v2' }
	mut v2_exe := os.getenv(delegated_v2_exe_env)
	if v2_exe == '' {
		v2_main_source := os.join_path(vroot, 'cmd', 'v2', 'v2.v')
		v2_cmd_dir := os.join_path(vroot, 'cmd', 'v2')
		v2_vlib_dir := os.join_path(vroot, 'vlib', 'v2')
		v2_exe = cached_v2_executable_path(vroot, is_ownership)
		v2_exe_dir := os.dir(v2_exe)
		os.mkdir_all(v2_exe_dir) or {
			eprintln('cannot create `${v2_exe_dir}`: ${err}')
			exit(1)
		}
		if util.should_recompile_tool(vexe, v2_cmd_dir, tool_name, v2_exe)
			|| util.should_recompile_tool(vexe, v2_vlib_dir, tool_name, v2_exe) {
			d_flag := if is_ownership { '-d ownership ' } else { '' }
			compilation_command := '${os.quoted_path(vexe)} ${d_flag}-o ${os.quoted_path(v2_exe)} ${os.quoted_path(v2_main_source)}'
			if is_verbose {
				println('Compiling ${tool_name} with: "${compilation_command}"')
			}
			current_work_dir := os.getwd()
			os.chdir(vroot) or {}
			tool_compilation := run_delegate_compilation_command(compilation_command)
			os.chdir(current_work_dir) or {}
			if tool_compilation.exit_code != 0 {
				report_v2_compilation_failure(v2_main_source, compilation_command, tool_compilation)
				exit(1)
			}
		}
	} else if !os.is_file(v2_exe) {
		eprintln('v: `${delegated_v2_exe_env}` points to a missing executable: `${v2_exe}`')
		exit(1)
	}
	os.setenv('VCHILD', 'true', true)
	os.setenv('VEXE', os.real_path(v2_exe), true)
	$if windows {
		delegate_result := run_delegated_process_echoed(v2_exe, args)
		if delegated_process_needs_parent_diagnostics(delegate_result) {
			report_delegated_process_failure('v.delegate.v2', delegate_result,
				stage:   'v2_delegate'
				reason:  'v2_delegate_exit_nonzero_without_output'
				action:  'inspect_delegated_v2_command'
				message: 'delegated v2 compiler exited with a non-zero status without stdout/stderr'
			)
		}
		exit(delegate_result.exit_code)
	} $else {
		os.execvp(v2_exe, args) or {
			eprintln('> error while executing: ${v2_exe} ${args}')
			panic(err)
		}
	}
	exit(2)
}

fn report_v2_compilation_failure(source string, command string, result os.Result) {
	eprintln(result.command_failure_report('v.delegate',
		command: command
		reason:  'v2_compilation_failed'
		action:  'abort_delegated_compiler_launch'
		message: 'cannot compile delegated v2 compiler source: ${delegate_report_value(source)}'
	))
	eprintln('v.delegate.source=${delegate_report_value(source)}')
}

fn delegate_report_value(value string) string {
	return value.replace('\r', '\\r').replace('\n', '\\n')
}

fn cached_v2_executable_path(vroot string, is_ownership bool) string {
	vroot_hash := hash.sum64_string(os.real_path(vroot), 0).hex_full()
	exe_name := if is_ownership { 'v2_ownership' } else { 'v2' }
	return util.path_of_executable(os.join_path(os.vtmp_dir(), 'v', 'delegated_v2', vroot_hash,
		exe_name))
}

fn rebuild(prefs &pref.Preferences) {
	if prefs.os == .target_os && prefs.backend == .c {
		builder.compile('build', prefs, target_osbuilder.compile_target_os)
		return
	}
	match prefs.backend {
		.c {
			$if no_bootstrapv ? {
				// TODO: improve the bootstrapping with a split C backend here.
				// C code generated by `VEXE=v cmd/tools/builders/c_builder -os cross -o c.c cmd/tools/builders/c_builder.v`
				// is enough to bootstrap the C backend, and thus the rest, but currently bootstrapping relies on
				// `v -os cross -o v.c cmd/v` having a functional C codegen inside instead.
				util.launch_tool(prefs.is_verbose, 'builders/c_builder', os.args[1..])
			}
			builder.compile('build', prefs, cbuilder.compile_c)
		}
		.js_node, .js_freestanding, .js_browser {
			util.launch_tool(prefs.is_verbose, 'builders/js_builder', os.args[1..])
		}
		.interpret {
			eprintln('use v -v2 -eval file.v')
			exit(1)
		}
		.wasm {
			util.launch_tool(prefs.is_verbose, 'builders/wasm_builder', os.args[1..])
		}
	}
}

@[manualfree]
fn setup_vbuild_env_vars(prefs &pref.Preferences) {
	mut facts := []string{cap: 10}
	facts << prefs.os.lower()
	facts << prefs.ccompiler_type.str()
	facts << prefs.arch.str()
	if prefs.is_prod {
		facts << 'prod'
	}
	github_job := os.getenv('GITHUB_JOB')
	if github_job != '' {
		facts << github_job
	}
	pref.set_build_flags_and_defines(facts, prefs.compile_defines_all)
	unsafe { github_job.free() }
	unsafe { facts.free() }
}
