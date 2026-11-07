// vtest retry: 3
import os
import time
import rand

const qvexe = os.quoted_path(@VEXE)

fn depend_on_command(cmd string) ? {
	path := os.find_abs_path_of_executable(cmd) or {
		println('skip: ${cmd} not found')
		return none
	}
	res := os.exec([path, '--version'])
	if res.exit_code != 0 {
		println('skip: ${cmd} does not support --version')
		return none
	}
	if !res.output.contains('GNU coreutils') {
		println('skip: ${cmd} is not from coreutils')
		return none
	}
}

fn execute(cmd string) os.Result {
	sw := time.new_stopwatch()
	res := os.exec(os.split_args(cmd) or { panic(err) })
	dt := sw.elapsed().milliseconds()
	failed := res.exit_code != 0
	reason := if failed { 'child_exit_nonzero' } else { 'completed' }
	eprintln('vtimeout_test.command.failed=${failed}')
	eprintln('vtimeout_test.command.reason=${reason}')
	eprintln('vtimeout_test.command.duration_ms=${dt}')
	eprintln('vtimeout_test.command.exit_code=${res.exit_code}')
	eprintln('vtimeout_test.command.exit_code_meaning=${os.process_exit_code_meaning(res.exit_code)}')
	eprintln('vtimeout_test.command.output_len=${res.output.len}')
	eprintln('vtimeout_test.command.command=${cmd}')
	return res
}

fn test_normal_exit_without_timeout_echo() {
	depend_on_command('echo') or { return }
	ee := execute('${qvexe} timeout 0.5 echo')
	assert ee.exit_code == 0, ee.exit_code_diagnostics('0', label: @FN)
	res := execute('${qvexe} timeout 0.5 echo z123')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
	assert res.output.contains('z123')
}

fn test_normal_exit_without_timeout_sleep() {
	depend_on_command('sleep') or { return }
	res := execute('${qvexe} timeout 0.5 sleep 0.1')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
	assert res.output == ''
}

fn test_exit_with_timeout() {
	depend_on_command('sleep') or { return }
	res := execute('${qvexe} timeout 0.5 sleep 3')
	assert res.exit_code == 124, res.exit_code_diagnostics('124', label: @FN)
	assert res.output.contains('vtimeout.command.failed=true'), res.output
	assert res.output.contains('vtimeout.command.reason=timeout'), res.output
	assert res.output.contains('vtimeout.command.output_capture=inherited_stdio'), res.output
}

fn test_child_exit_reports_diagnostics() {
	tmp_dir := os.join_path(os.vtmp_dir(), 'vtimeout_silent_child_${rand.ulid()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	source_path := os.join_path(tmp_dir, 'silent_child.v')
	exe_path := os.join_path(tmp_dir, 'silent_child')
	os.write_file(source_path, 'fn main() {\n\texit(17)\n}\n') or { panic(err) }
	build_cmd := '${qvexe} -o ${os.quoted_path(exe_path)} ${os.quoted_path(source_path)}'
	build_res := os.execute(build_cmd)
	assert build_res.exit_code == 0, build_res.exit_code_diagnostics('0',
		label:   @FN
		command: build_cmd
	)

	res := execute('${qvexe} timeout 10 ${os.quoted_path(exe_path)}')
	assert res.exit_code == 17, res.exit_code_diagnostics('17', label: @FN)
	assert res.output.contains('vtimeout.command.failed=true'), res.output
	assert res.output.contains('vtimeout.command.reason=child_exit_nonzero'), res.output
	assert res.output.contains('vtimeout.command.output_capture=inherited_stdio'), res.output
}
