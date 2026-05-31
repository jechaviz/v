import os
import rand

const vexe = os.quoted_path(@VEXE)

fn test_run_reports_silent_child_exit() {
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

	assert res.output.contains('v.run.command.failed=true'), res.output
	assert res.output.contains('v.run.command.stage=run_compiled_executable'), res.output
	assert res.output.contains('v.run.command.reason=compiled_executable_exit_nonzero'), res.output
	assert res.output.contains('v.run.command.output_capture=inherited_stdio'), res.output
	assert res.output.contains('v.run.command.command='), res.output
}
