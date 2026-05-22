module testing

import time

fn test_command_output_or_diagnostic_preserves_non_empty_output() {
	msg := command_output_or_diagnostic('compile', 'tiny_test.v', 'v test tiny_test.v', 1,
		'actual error', 1 * time.millisecond)
	assert msg == 'actual error'
}

fn test_command_output_or_diagnostic_reports_empty_output() {
	msg := command_output_or_diagnostic('compile', 'tiny_test.v', 'v test tiny_test.v', 1, '',
		1 * time.millisecond)
	assert msg.contains('vtest diagnostic: compile command failed; exit_code=1')
	assert msg.contains('file: tiny_test.v')
	assert msg.contains('cmd: v test tiny_test.v')
	assert msg.contains('no stdout/stderr captured')
	assert msg.contains('free_ram_mb=')
	assert msg.contains('free_virtual_mb=')
}
