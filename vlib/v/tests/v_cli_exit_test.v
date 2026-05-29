import os

fn test_version_command_exits_cleanly_when_output_is_captured() {
	res := os.execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
	assert res.output.starts_with('V '), res.output
}
