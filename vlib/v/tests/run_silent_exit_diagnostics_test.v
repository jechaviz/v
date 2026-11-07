import os
import rand

const vexe = os.quoted_path(@VEXE)

fn test_run_propagates_silent_child_exit_without_parent_diagnostics() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_run_silent_exit_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'main.v')
	os.write_file(source_path, 'fn main() {\n\texit(17)\n}\n') or { panic(err) }
	cmd := '${vexe} run ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code == 17, res.exit_code_diagnostics('17',
		label:   @FN
		command: cmd
		reason:  'silent_child_should_exit_with_17'
		action:  'inspect_v_run_diagnostics'
	)

	assert !res.output.contains('v.run.command.failed=true'), res.output
}

fn test_run_does_not_duplicate_diagnostics_after_child_output() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_run_nonempty_exit_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'main.v')
	os.write_file(source_path, 'fn main() {\n\teprintln("child failure detail")\n\texit(17)\n}\n') or {
		panic(err)
	}
	cmd := '${vexe} run ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code == 17, res.exit_code_diagnostics('17', label: @FN, command: cmd)
	assert res.output.contains('child failure detail'), res.output
	assert !res.output.contains('v.run.command.failed=true'), res.output
}

fn test_run_preserves_redirected_stdin_through_builder_delegation() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_run_inherited_stdin_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'main.v')
	input_path := os.join_path(test_dir, 'input.txt')
	os.write_file(source_path,
		"import os\nfn main() {\n\tprintln('got:' + os.get_raw_line().trim_space())\n}\n") or {
		panic(err)
	}
	os.write_file(input_path, 'interactive input\n') or { panic(err) }
	cmd := '${vexe} run ${os.quoted_path(source_path)} < ${os.quoted_path(input_path)}'
	res := os.execute(cmd)

	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN, command: cmd)
	assert res.output.trim_space() == 'got:interactive input', res.output
}
