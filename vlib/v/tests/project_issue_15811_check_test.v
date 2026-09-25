import os

const vexe = os.quoted_path(@VEXE)
const issue_15811_project = os.join_path(os.dir(@FILE), 'project_issue_15811')

fn test_private_c_redeclaration_order_checks_cleanly() {
	cmd := '${vexe} -check ${os.quoted_path(issue_15811_project)}'
	res := os.execute(cmd)
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN, command: cmd)
}
