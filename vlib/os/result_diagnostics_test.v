import os

fn test_exit_code_diagnostics_reports_empty_output() {
	message := os.process_exit_code_diagnostics(2, '0',
		label:   @FN
		command: 'silent-tool --flag'
		reason:  'silent_tool_failed'
		action:  'inspect_silent_tool'
	)

	assert message.contains('vtest.assert.failed=true')
	assert message.contains('vtest.assert.reason=silent_tool_failed')
	assert message.contains('vtest.assert.expected_exit_code=0')
	assert message.contains('vtest.assert.actual_exit_code=2')
	assert message.contains('vtest.assert.output_empty=true')
	assert message.contains('vtest.assert.command=silent-tool --flag')
}

fn test_command_failure_report_reports_empty_output() {
	message := os.process_command_failure_report('v.test.command', 17,
		stage:   'compile'
		command: 'silent-cc main.c'
		reason:  'silent_child_failed'
		action:  'rerun_verbose'
		message: 'child failed without output'
	)

	assert message.contains('v.test.command.failed=true')
	assert message.contains('v.test.command.reason=silent_child_failed')
	assert message.contains('v.test.command.exit_code=17')
	assert message.contains('v.test.command.output_empty=true')
	assert message.contains('v.test.command.command=silent-cc main.c')
}
