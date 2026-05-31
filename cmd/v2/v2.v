// Copyright (c) 2020-2024 Joe Conigliaro. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import os
import time
import v2.pref
import v2.builder

fn main() {
	compile_args, runtime_args := split_eval_runtime_args(os.args[1..])

	// Check for subcommands
	if compile_args.len > 0 && compile_args[0] == 'ast' {
		run_ast_command(compile_args[1..])
		return
	}
	if compile_args.len > 0 && compile_args[0] == 'test-self' {
		run_test_self()
		return
	}

	mut prefs := pref.new_preferences_from_args(compile_args)

	files := get_files(compile_args)
	if files.len == 0 {
		eprintln('At least 1 .v file expected')
		exit(1)
	}
	mut eval_runtime_args := [files[0]]
	eval_runtime_args << runtime_args
	prefs.eval_runtime_args = eval_runtime_args

	mut b := builder.new_builder(&prefs)
	b.build(files)

	// Auto-run test binaries after compilation (matching v1 behavior)
	if prefs.output_file == '' && is_test_file(files) && should_auto_run_test_binary(&prefs) {
		last := os.file_name(files.last())
		output_name := if last.ends_with('.vv2') {
			last.all_before_last('.vv2')
		} else {
			last.all_before_last('.v')
		}
		if os.exists(output_name) {
			run_cmd := './' + output_name
			ret := os.system(run_cmd)
			os.rm(output_name) or {}
			c_file := output_name + '.c'
			if !prefs.keep_c && os.exists(c_file) {
				os.rm(c_file) or {}
			}
			if ret != 0 {
				eprintln(os.process_command_failure_report('v2.test_binary', ret,
					stage:          'auto_run_test_binary'
					command:        run_cmd
					reason:         'compiled_test_binary_failed'
					action:         'inspect_test_output_or_rerun_binary_directly'
					message:        'compiled v2 test binary exited with a non-zero status'
					output_capture: 'inherited_stdio'
				))
			}
			exit(ret)
		}
	}
}

fn split_eval_runtime_args(args []string) ([]string, []string) {
	for i, arg in args {
		if arg == '--' {
			return args[..i], args[i + 1..]
		}
	}
	return args, []string{}
}

fn run_ast_command(args []string) {
	if args.len == 0 {
		eprintln('Usage: v2 ast <file.v>')
		eprintln('Dumps AST to <file>_ast.json and <file>_ast_transformed.json')
		exit(1)
	}

	// Find the vast2 tool relative to vexe
	vroot := os.dir(@VEXE)
	vast2_path := os.join_path(vroot, 'cmd', 'tools', 'vast2', 'vast2')

	// Build vast2 if it doesn't exist
	if !os.exists(vast2_path) {
		eprintln('Building vast2 tool...')
		vast2_source := os.join_path(vroot, 'cmd', 'tools', 'vast2', 'vast2.v')
		build_cmd := '${@VEXE} ${vast2_source}'
		build_result := os.execute(build_cmd)
		if build_result.exit_code != 0 {
			eprintln(build_result.command_failure_report('v2.command',
				reason:  'vast2_build_failed'
				action:  'inspect_tool_build_output'
				message: 'Failed to build vast2 tool.'
				command: build_cmd
			))
			exit(1)
		}
	}

	// Run vast2 with the provided arguments
	cmd := '${vast2_path} ${args.join(' ')}'
	result := os.execute(cmd)
	print(result.output)
	if result.exit_code != 0 {
		eprintln(result.command_failure_report('v2.command',
			stage:   'vast2_run'
			reason:  'vast2_run_failed'
			action:  'inspect_vast2_output'
			message: 'vast2 command failed'
			command: cmd
		))
		exit(result.exit_code)
	}
}

fn is_test_file(files []string) bool {
	for file in files {
		if file.ends_with('_test.v') || file.ends_with('_test.vv2') {
			return true
		}
	}
	return false
}

fn should_auto_run_test_binary(prefs &pref.Preferences) bool {
	if prefs == unsafe { nil } {
		return true
	}
	if !prefs.can_run_target_binary_locally() {
		return false
	}
	return true
}

fn v2_report_value(value string) string {
	return value.trim_space().replace('\r', '\\r').replace('\n', '\\n')
}

fn system_redirecting_to_log(command string, log_path string) int {
	return os.system('${command} > ${os.quoted_path(log_path)} 2>&1')
}

fn command_log_output(log_path string) string {
	return os.read_file(log_path) or { 'unable to read command log `${log_path}`: ${err}' }
}

fn command_failure_report_with_log(prefix string, exit_code int, reason string, action string, message string, command string, log_path string) string {
	output := command_log_output(log_path)
	return os.process_command_failure_report(prefix, exit_code,
		reason:         reason
		action:         action
		message:        message
		command:        command
		output:         output
		output_capture: 'redirected_to_log'
		output_empty:   output == ''
	) + '\n${prefix}.log=${v2_report_value(log_path)}'
}

// get_files extracts source files from args, excluding options and their values
fn get_files(args []string) []string {
	return pref.source_files_from_args(args)
}

fn resolve_own_path() string {
	arg0 := os.args[0]
	if os.is_abs_path(arg0) {
		return arg0
	}
	return os.join_path(os.getwd(), arg0)
}

// detect_vroot walks up from `start` looking for a directory containing vlib/builtin.
fn detect_vroot(start string) string {
	mut dir := start
	if !os.is_abs_path(dir) {
		dir = os.join_path(os.getwd(), dir)
	}
	for _ in 0 .. 10 {
		if os.is_dir(os.join_path(dir, 'vlib', 'builtin')) {
			return dir
		}
		parent := os.dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return dir
}

fn run_test_self() {
	t0 := time.now()
	// Resolve the v2 binary's own path. Cannot use @VEXE because when v1
	// compiles v2, @VEXE bakes in v1's path instead of v2's.
	vexe := resolve_own_path()
	// Walk up from the binary to find the repo root (directory containing vlib/builtin).
	// This allows running from subdirectories like cmd/v2/.
	vroot := detect_vroot(vexe)
	v2_dir := os.join_path(vroot, 'cmd', 'v2')

	mut all_test_files := []string{}

	// Builtin test files
	for name in ['array_test.v', 'string_test.v', 'map_test.v'] {
		all_test_files << os.join_path(vroot, 'vlib', 'builtin', name)
	}

	// Math test
	all_test_files << os.join_path(vroot, 'vlib', 'math', 'math_test.v')

	// Sumtype tests in cmd/v2/
	v2_files := os.ls(v2_dir) or { []string{} }
	for file in v2_files {
		if file.starts_with('test_sumtype') && file.ends_with('.v') {
			all_test_files << os.join_path(v2_dir, file)
		}
	}

	// Cleanc regression tests
	cleanc_tests_dir := os.join_path(vroot, 'vlib', 'v2', 'gen', 'cleanc', 'tests')
	cleanc_files := os.ls(cleanc_tests_dir) or { []string{} }
	for file in cleanc_files {
		if file.ends_with('.v') && file != 'run_tests.v' {
			all_test_files << os.join_path(cleanc_tests_dir, file)
		}
	}

	total := all_test_files.len
	mut passed := 0
	mut failed := 0
	mut failed_files := []string{}

	eprintln('---- v2 test-self: ${total} test files ----')

	for i, test_file in all_test_files {
		short_name := test_file.replace(vroot + '/', '')
		t1 := time.now()

		// Determine output binary path
		base := os.file_name(test_file).all_before_last('.v')
		out_bin := os.join_path(os.temp_dir(), 'v2_test_self_${base}')

		// Compile via os.system to avoid pipe deadlocks with popen/GC.
		compile_cmd := '${vexe} -o ${out_bin} "${test_file}"'
		compile_log := '${out_bin}.compile.log'
		compile_ret := system_redirecting_to_log(compile_cmd, compile_log)
		compile_ms := f64(time.since(t1)) / f64(time.millisecond)

		if compile_ret != 0 || !os.exists(out_bin) {
			failed++
			failed_files << short_name
			eprintln(' FAIL  [${i + 1:4}/${total}] C: ${compile_ms:7.1} ms  ${short_name}')
			eprintln(command_failure_report_with_log('v2.test_self.compile', compile_ret,
				'test_compile_failed', 'inspect_reported_log_or_rerun_command',
				'v2 test-self compile command failed', compile_cmd, compile_log))
			os.rm(out_bin) or {}
			os.rm('${out_bin}.c') or {}
			continue
		}
		os.rm(compile_log) or {}

		// Run the compiled binary
		t2 := time.now()
		run_cmd := out_bin
		run_log := '${out_bin}.run.log'
		run_ret := system_redirecting_to_log(run_cmd, run_log)
		run_ms := f64(time.since(t2)) / f64(time.millisecond)

		if run_ret != 0 {
			failed++
			failed_files << short_name
			eprintln(' FAIL  [${i + 1:4}/${total}] C: ${compile_ms:7.1} ms, R: ${run_ms:7.1} ms  ${short_name}')
			eprintln(command_failure_report_with_log('v2.test_self.run', run_ret,
				'test_binary_failed', 'inspect_reported_log_or_rerun_binary_directly',
				'v2 test-self binary failed', run_cmd, run_log))
		} else {
			passed++
			eprintln('OK    [${i + 1:4}/${total}] C: ${compile_ms:7.1} ms, R: ${run_ms:7.1} ms  ${short_name}')
			os.rm(run_log) or {}
		}

		os.rm(out_bin) or {}
		os.rm('${out_bin}.c') or {}
	}

	elapsed := time.since(t0)
	eprintln('------------------------------------------------------------------------')
	eprintln('${passed} passed, ${failed} failed, ${total} total  (${elapsed})')
	if failed_files.len > 0 {
		eprintln('Failed:')
		for f in failed_files {
			eprintln('  ${f}')
		}
	}
	// Always run the self-compilation chain, even when some tests fail.
	// Self-compilation chain: v2 -> v3 -> v4 -> v5
	eprintln('')
	eprintln('---- v2 self-compilation chain ----')

	v2_source := os.join_path(v2_dir, 'v2.v')
	backend := 'cleanc'
	tmpdir := os.temp_dir()
	v3_bin := os.join_path(tmpdir, 'v2_self_v3')
	v4_bin := os.join_path(tmpdir, 'v2_self_v4')
	v5_bin := os.join_path(tmpdir, 'v2_self_v5')

	steps := [
		[vexe, v3_bin, 'v2 -> v3'],
		[v3_bin, v4_bin, 'v3 -> v4'],
		[v4_bin, v5_bin, 'v4 -> v5'],
	]

	for step in steps {
		compiler := step[0]
		out := step[1]
		label := step[2]
		ts := time.now()
		cmd := '${compiler} -gc none -o ${out} -backend ${backend} "${v2_source}"'
		log_path := '${out}.self_compile.log'
		ret := system_redirecting_to_log(cmd, log_path)
		ms := f64(time.since(ts)) / f64(time.millisecond)
		if ret != 0 || !os.exists(out) {
			eprintln(' FAIL  ${label}  (${ms:.1} ms)')
			eprintln(command_failure_report_with_log('v2.self_compile', ret, 'self_compile_failed',
				'inspect_reported_log_or_rerun_command', 'v2 self-compilation command failed', cmd,
				log_path))
			// Clean up
			for bin in [v3_bin, v4_bin, v5_bin] {
				os.rm(bin) or {}
				os.rm('${bin}.c') or {}
			}
			exit(1)
		}
		os.rm(log_path) or {}
		eprintln('OK    ${label}  (${ms:.1} ms)')
	}

	// Verify that v3 runs and produces expected output
	v3_probe_cmd := '${v3_bin} 2>&1'
	result := os.execute(v3_probe_cmd)
	expected := 'At least 1 .v file expected'
	if result.exit_code != 0 {
		eprintln(result.command_failure_report('v2.self_compile',
			reason:  'v3_probe_failed'
			action:  'inspect_probe_output'
			command: v3_probe_cmd
		))
	}
	if !result.output.contains(expected) {
		eprintln(os.process_command_failure_report('v2.self_compile', result.exit_code,
			reason:  'v3_probe_output_mismatch'
			action:  'inspect_probe_output'
			message: "v3 probe output did not contain expected text '${expected}'"
			command: v3_probe_cmd
			output:  result.output
		))
		for bin in [v3_bin, v4_bin, v5_bin] {
			os.rm(bin) or {}
			os.rm('${bin}.c') or {}
		}
		exit(1)
	}
	eprintln('OK    v3 output verified')

	// Clean up
	for bin in [v3_bin, v4_bin, v5_bin] {
		os.rm(bin) or {}
		os.rm('${bin}.c') or {}
	}

	total_elapsed := time.since(t0)
	eprintln('')
	if failed > 0 {
		eprintln('=== SELF-COMPILATION OK, but ${failed} test(s) failed ===')
		eprintln('Total time: ${total_elapsed}')
		exit(1)
	}
	eprintln('=== SELF-COMPILATION TEST PASSED ===')
	eprintln('Total time: ${total_elapsed}')
}
