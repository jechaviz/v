module testing

import os
import v.util

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

fn test_process_guard_execute_command_rejects_empty_command() {
	result := process_guard_execute_command('')
	assert result.exit_code == -1
	assert result.output.contains('vtest.resource.spawn_error=true')
	assert result.output.contains('empty command')
}

fn test_vtest_no_parallel_requested_is_explicit() {
	assert vtest_no_parallel_requested('-nocache -no-parallel')
	assert !vtest_no_parallel_requested('-nocache')
}

fn test_process_guard_host_pressure_message_is_actionable() {
	message :=
		process_guard_host_pressure_message('v test hot.v', 1200, util.MemoryBackpressurePlan{})
	assert message.contains('vtest.resource.blocked=true')
	assert message.contains('vtest.resource.reason=host_memory_pressure')
	assert message.contains('stream, chunk, cap allocations')
	assert message.contains('VMEM_BACKPRESSURE=strict')
	assert message.contains('VTEST_MEMORY_BACKPRESSURE_WAIT_MS')
}

fn test_process_guard_spawn_wait_ms_env() {
	with_process_guard_env({
		process_guard_spawn_wait_env: '25'
	}, fn () {
		assert process_guard_spawn_wait_ms() == 25
	})
	with_process_guard_env({
		process_guard_spawn_wait_env: '-1'
	}, fn () {
		assert process_guard_spawn_wait_ms() == process_guard_default_spawn_wait_ms
	})
}

fn with_process_guard_env(values map[string]string, body fn ()) {
	names := [
		process_guard_env,
		process_guard_limit_env,
		process_guard_limit_mb_env,
		process_guard_output_limit_env,
		process_guard_spawn_wait_env,
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
