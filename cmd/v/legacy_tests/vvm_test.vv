module main

import os
import rand

const current_vexe = @VEXE

const delegated_marker = 'VVM-DELEGATED'

const requested_vvm_test_version = '99.99.99'

struct CmdResult {
	exit_code int
	output    string
	command   string
}

fn cmd_result_exit_code_diagnostics(res CmdResult, expected string, label string) string {
	return os.process_exit_code_diagnostics(res.exit_code, expected,
		label:          label
		command:        res.command
		output:         res.output
		output_capture: 'pipe'
	)
}

fn quoted_command(vexe string, args []string) string {
	mut parts := [os.quoted_path(vexe)]
	for arg in args {
		parts << os.quoted_path(arg)
	}
	return parts.join(' ')
}

fn test_parse_vvmrc_version() {
	assert parse_vvmrc_version('') == ''
	assert parse_vvmrc_version('   ') == ''
	assert parse_vvmrc_version('# only comments') == ''
	assert parse_vvmrc_version('\n# comment\n0.4.6\n') == '0.4.6'
	assert parse_vvmrc_version(' latest # comment ') == 'latest'
}

fn test_find_project_vvmrc_stops_at_stop_paths() {
	tmp_root := os.join_path(os.vtmp_dir(), 'vvmrc_stop_test_${rand.ulid()}')
	os.mkdir_all(tmp_root) or { panic(err) }
	defer {
		os.rmdir_all(tmp_root) or {}
	}
	project_dir := os.join_path(tmp_root, 'project')
	source_dir := os.join_path(project_dir, 'src')
	os.mkdir_all(source_dir) or { panic(err) }
	os.mkdir_all(os.join_path(project_dir, '.git')) or { panic(err) }
	os.write_file(os.join_path(tmp_root, '.vvmrc'), requested_vvm_test_version) or { panic(err) }
	main_v := os.join_path(source_dir, 'main.v')
	os.write_file(main_v, 'fn main() {}') or { panic(err) }
	assert find_project_vvmrc(main_v) == ''
	local_vvmrc := os.join_path(project_dir, '.vvmrc')
	os.write_file(local_vvmrc, requested_vvm_test_version) or { panic(err) }
	assert find_project_vvmrc(main_v) == os.real_path(local_vvmrc)
}

fn test_vvmrc_delegates_to_matching_compiler_executable() {
	tmp_root := os.join_path(os.vtmp_dir(), 'vvmrc_delegate_test_${rand.ulid()}')
	os.mkdir_all(tmp_root) or { panic(err) }
	defer {
		os.rmdir_all(tmp_root) or {}
	}
	bin_dir := os.join_path(tmp_root, 'bin')
	os.mkdir_all(bin_dir) or { panic(err) }
	fake_compiler_source := os.join_path(tmp_root, 'fake_compiler.v')
	os.write_file(fake_compiler_source,
		"import os\nfn main() {\n\tprintln('${delegated_marker} ' + os.args[1..].join(' '))\n}\n") or {
		panic(err)
	}
	fake_compiler_exe := os.join_path(bin_dir, if os.user_os() == 'windows' {
		'v${requested_vvm_test_version}.exe'
	} else {
		'v${requested_vvm_test_version}'
	})
	compile_cmd := '${os.quoted_path(current_vexe)} -o ${os.quoted_path(fake_compiler_exe)} ${os.quoted_path(fake_compiler_source)}'
	compile_res := os.execute(compile_cmd)
	assert compile_res.exit_code == 0, compile_res.exit_code_diagnostics('0',
		label:   @FN
		command: compile_cmd
	)

	project_dir := os.join_path(tmp_root, 'project')
	os.mkdir_all(project_dir) or { panic(err) }
	os.write_file(os.join_path(project_dir, '.vvmrc'), requested_vvm_test_version) or { panic(err) }
	os.write_file(os.join_path(project_dir, 'main.v'),
		"fn main() {\n\tprintln('from project')\n}\n") or { panic(err) }
	mut envs := os.environ()
	path_key := find_path_env_key(envs)
	envs[path_key] = '${bin_dir}${os.path_delimiter}${envs[path_key]}'
	envs['V_SKIP_VVMRC'] = ''
	res := run_v_command(project_dir, ['run', 'main.v'], envs)
	assert res.exit_code == 0, cmd_result_exit_code_diagnostics(res, '0', @FN)
	assert res.output.contains('${delegated_marker} run main.v'), res.output
}

fn test_vvmrc_reports_silent_delegated_compiler_failure() {
	tmp_root := os.join_path(os.vtmp_dir(), 'vvmrc_silent_delegate_test_${rand.ulid()}')
	os.mkdir_all(tmp_root) or { panic(err) }
	defer {
		os.rmdir_all(tmp_root) or {}
	}
	bin_dir := os.join_path(tmp_root, 'bin')
	os.mkdir_all(bin_dir) or { panic(err) }
	fake_compiler_source := os.join_path(tmp_root, 'fake_failing_compiler.v')
	os.write_file(fake_compiler_source, 'fn main() {\n\texit(17)\n}\n') or { panic(err) }
	fake_compiler_exe := os.join_path(bin_dir, if os.user_os() == 'windows' {
		'v${requested_vvm_test_version}.exe'
	} else {
		'v${requested_vvm_test_version}'
	})
	compile_cmd := '${os.quoted_path(current_vexe)} -o ${os.quoted_path(fake_compiler_exe)} ${os.quoted_path(fake_compiler_source)}'
	compile_res := os.execute(compile_cmd)
	assert compile_res.exit_code == 0, compile_res.exit_code_diagnostics('0',
		label:   @FN
		command: compile_cmd
	)

	project_dir := os.join_path(tmp_root, 'project')
	os.mkdir_all(project_dir) or { panic(err) }
	os.write_file(os.join_path(project_dir, '.vvmrc'), requested_vvm_test_version) or { panic(err) }
	os.write_file(os.join_path(project_dir, 'main.v'), 'fn main() {}\n') or { panic(err) }
	mut envs := os.environ()
	path_key := find_path_env_key(envs)
	envs[path_key] = '${bin_dir}${os.path_delimiter}${envs[path_key]}'
	envs['V_SKIP_VVMRC'] = ''
	res := run_v_command(project_dir, ['run', 'main.v'], envs)
	assert res.exit_code == 17, cmd_result_exit_code_diagnostics(res, '17', @FN)
	assert res.output.contains('v.vvmrc.delegate.failed=true'), res.output
	assert res.output.contains('v.vvmrc.delegate.reason=vvmrc_delegate_exit_nonzero'), res.output
	assert res.output.contains('v.vvmrc.delegate.output_capture=redirected_stdio_echoed'), res.output
	assert res.output.contains('v.vvmrc.delegate.file='), res.output
	assert res.output.contains('v.vvmrc.delegate.requested_version=${requested_vvm_test_version}'), res.output
	assert res.output.contains('v.vvmrc.delegate.parent_exit_code=17'), res.output
	assert res.output.contains('v.vvmrc.delegate.stdout_bytes=0'), res.output
	assert res.output.contains('v.vvmrc.delegate.stderr_bytes=0'), res.output
	assert res.output.contains('v.vvmrc.delegate.cwd='), res.output
	assert res.output.contains('v.vvmrc.delegate.executable='), res.output
}

fn run_v_command(work_dir string, args []string, envs map[string]string) CmdResult {
	return run_v_command_with_exe(current_vexe, work_dir, args, envs)
}

fn run_v_command_with_exe(vexe string, work_dir string, args []string, envs map[string]string) CmdResult {
	mut process := os.new_process(vexe)
	process.set_work_folder(work_dir)
	process.set_args(args)
	process.set_environment(envs)
	process.set_redirect_stdio()
	process.run()
	process.wait()
	output := process.stdout_slurp() + process.stderr_slurp()
	exit_code := if process.code == -1 { 1 } else { process.code }
	process.close()
	return CmdResult{
		exit_code: exit_code
		output:    output
		command:   quoted_command(vexe, args)
	}
}

fn find_path_env_key(envs map[string]string) string {
	if 'PATH' in envs {
		return 'PATH'
	}
	if 'Path' in envs {
		return 'Path'
	}
	return 'PATH'
}
