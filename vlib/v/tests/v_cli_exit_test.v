import os

fn test_version_command_exits_cleanly_when_output_is_captured() {
	res := os.execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
	assert res.output.starts_with('V '), res.output
}

fn test_delegated_vtest_failure_reports_child_status() {
	missing_test := os.join_path(os.temp_dir(), 'v_missing_delegated_test_${os.getpid()}.v')
	os.rm(missing_test) or {}
	res := os.execute('${os.quoted_path(@VEXE)} test ${os.quoted_path(missing_test)}')
	assert res.exit_code != 0, res.exit_code_diagnostics('!= 0', label: @FN)
	assert res.output.contains('v.tool.command.failed=true')
	assert res.output.contains('v.tool.command.reason=tool_child_exit_nonzero')
	assert res.output.contains('v.tool.command.output_capture=inherited_stdio')
	assert res.output.contains('v.tool.command.child_exit_code=1')
	assert res.output.contains('v.tool.command.child_exit_code_meaning=child_exited_nonzero')
	assert res.output.contains('v.tool.command.parent_exit_code=1')
	assert res.output.contains('v.tool.command.tool=vtest.exe')
	assert res.output.contains('v.tool.command.action=inspect_vtest_failure_summary_or_rerun_failed_command')
}
