module testing

import os

fn test_process_guard_default_policy_matches_host() {
	with_process_guard_env({}, fn () {
		$if windows {
			assert process_guard_enabled()
		} $else {
			assert !process_guard_enabled()
		}
	})
}

fn test_process_guard_env_overrides_default_policy() {
	with_process_guard_env({
		process_guard_env: '0'
	}, fn () {
		assert !process_guard_enabled()
	})
	with_process_guard_env({
		process_guard_env: '1'
	}, fn () {
		assert process_guard_enabled()
	})
}

fn test_process_guard_limit_parses_units() {
	with_process_guard_env({
		process_guard_limit_env: '64m'
	}, fn () {
		assert process_guard_limit_bytes() == u64(64) * process_guard_bytes_per_mib
	})
	with_process_guard_env({
		process_guard_limit_mb_env: '32'
	}, fn () {
		assert process_guard_limit_bytes() == u64(32) * process_guard_bytes_per_mib
	})
}

fn test_process_guard_kill_message_is_designer_actionable() {
	message := process_guard_kill_message('sample.exe', 42, 3 * process_guard_bytes_per_gib,
		2 * process_guard_bytes_per_gib)
	assert message.contains('vtest.resource.killed=true')
	assert message.contains('vtest.resource.reason=child_memory_limit')
	assert message.contains('stream, chunk, cap allocations')
	assert message.contains('VTEST_CHILD_MAX_MEMORY_MB')
}

fn test_process_guard_silent_failure_gets_telemetry() {
	result := process_guard_with_silent_diagnostics('silent.exe', os.Result{
		exit_code: 1
	})
	assert result.exit_code == 1
	assert result.output.contains('vtest.process.exit_without_output=true')
	assert result.output.contains('runtime.telemetry.')
	assert result.output.contains('VTEST_CHILD_MEMORY_GUARD')
}

fn with_process_guard_env(values map[string]string, body fn ()) {
	names := [
		process_guard_env,
		process_guard_limit_env,
		process_guard_limit_mb_env,
		process_guard_output_limit_env,
	]
	mut old := map[string]string{}
	for name in names {
		old[name] = os.getenv(name)
		os.unsetenv(name)
	}
	for name, value in values {
		os.setenv(name, value, true)
	}
	body()
	for name in names {
		if old[name] == '' {
			os.unsetenv(name)
		} else {
			os.setenv(name, old[name], true)
		}
	}
}
