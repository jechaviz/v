module os

fn test_system_spawn_failed_exit_code_is_stable() {
	assert system_spawn_failed_exit_code > 0
	assert system_spawn_failed_exit_code != -1
	assert system_spawn_failed_exit_code <= 255
}

fn test_windows_system_failure_message_is_actionable() {
	$if windows {
		msg := windows_system_failure_message('v test tiny_test.v', 12, 8)
		assert msg.contains('os.system failed to start command on Windows')
		assert msg.contains('returning ${system_spawn_failed_exit_code} instead of -1')
		assert msg.contains('errno=12')
		assert msg.contains('win_error=8')
		assert msg.contains('cmd: v test tiny_test.v')
	}
}
