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
	assert message.contains('vtest.assert.actual_exit_code_meaning=child_exited_nonzero')
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
	assert message.contains('v.test.command.exit_code_meaning=child_exited_nonzero')
	assert message.contains('v.test.command.output_empty=true')
	assert message.contains('v.test.command.command=silent-cc main.c')
}

fn test_exit_minus_one_diagnostics_explain_process_failure() {
	message := os.process_command_failure_report('v.test.command', -1,
		stage:   'spawn'
		command: 'silent-cc main.c'
		reason:  'command_failed_without_stdio'
		action:  'inspect_process_launch_context'
		message: 'command failed before writing output'
	)

	assert message.contains('v.test.command.exit_code=-1')
	assert message.contains('v.test.command.exit_code_meaning=process_start_or_wait_failed')
	assert message.contains('v.test.command.possible_causes=')
	assert message.contains('process_spawn_failed')
	assert message.contains('terminated_before_stdio_flush')
}

fn test_command_failure_report_distinguishes_inherited_stdio() {
	message := os.process_command_failure_report('v.test.command', 1,
		command:        'tool --arg'
		reason:         'child_exit_nonzero'
		action:         'inspect_inherited_output'
		output_capture: 'inherited_stdio'
	)

	assert message.contains('v.test.command.output_capture=inherited_stdio')
	assert !message.contains('v.test.command.output_empty=true')
}
