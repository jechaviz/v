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

fn test_process_guard_compile_guard_is_explicit_opt_in() {
	with_process_guard_env({}, fn () {
		assert !process_guard_compile_enabled()
	})
	with_process_guard_env({
		process_guard_compile_env: '1'
	}, fn () {
		assert process_guard_compile_enabled()
	})
	with_process_guard_env({
		process_guard_compile_env: '0'
	}, fn () {
		assert !process_guard_compile_enabled()
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

fn test_process_guard_limit_bytes_to_mb_rounds_up() {
	assert process_guard_limit_bytes_to_mb(1) == 1
	assert process_guard_limit_bytes_to_mb(process_guard_bytes_per_mib) == 1
	assert process_guard_limit_bytes_to_mb(process_guard_bytes_per_mib + 1) == 2
}

fn test_process_guard_configures_child_builtin_limit() {
	with_process_guard_env({
		process_guard_limit_mb_env: '64'
	}, fn () {
		mut process := os.new_process(os.executable())
		process_guard_configure_child_environment(mut process, process_guard_limit_bytes())
		assert process.env_is_custom
		assert process_guard_test_env_value(process.env, process_guard_child_memory_limit_mb_env) == '64'
		assert process_guard_test_env_value(process.env, 'PATH') != ''
	})
}

fn test_process_guard_respects_child_builtin_guard_opt_out() {
	with_process_guard_env({
		process_guard_limit_mb_env:           '64'
		process_guard_child_memory_guard_env: '0'
	}, fn () {
		mut process := os.new_process(os.executable())
		process_guard_configure_child_environment(mut process, process_guard_limit_bytes())
		assert !process.env_is_custom
	})
}

fn test_process_guard_kill_message_is_designer_actionable() {
	message := process_guard_kill_message('sample.exe', 42, 3 * process_guard_bytes_per_gib,
		2 * process_guard_bytes_per_gib)
	assert message.contains('vtest.resource.killed=true')
	assert message.contains('vtest.resource.reason=child_memory_limit')
	assert message.contains('vtest.resource.action=kill_child_process')
	assert message.contains('vtest.resource.exit_code=-1')
	assert message.contains('stream, chunk, cap allocations')
	assert message.contains('VTEST_CHILD_MAX_MEMORY_MB')
}

fn test_process_guard_silent_failure_gets_telemetry() {
	result := process_guard_with_silent_diagnostics('silent.exe', os.Result{
		exit_code: 1
	})
	assert result.exit_code == 1, result.exit_code_diagnostics('1', label: @FN)
	assert result.output.contains('vtest.process.exit_without_output=true')
	assert result.output.contains('vtest.process.reason=exit_without_output')
	assert result.output.contains('vtest.process.action=collect_telemetry')
	assert result.output.contains('runtime.telemetry.')
	assert result.output.contains('VTEST_CHILD_MEMORY_GUARD')
}

fn test_process_guard_job_report_is_actionable() {
	message := process_guard_job_report(ProcessGuardJob{
		enabled:  true
		assigned: true
	}, 64 * process_guard_bytes_per_mib)
	assert message.contains('vtest.resource.job_object.enabled=true')
	assert message.contains('vtest.resource.job_object.state=assigned')
	assert message.contains('vtest.resource.job_object.reason=job_object_enforced')
	assert message.contains('vtest.resource.job_object.action=enforce_job_limits')
	assert message.contains('vtest.resource.job_object.assigned=true')
	assert message.contains('vtest.resource.job_object.limit_bytes=')
	assert message.contains('stream/chunk')
	assert message.contains('parent job nesting')
}

fn test_process_guard_job_report_explains_error_codes() {
	message := process_guard_job_report(ProcessGuardJob{
		enabled:      true
		create_error: 5
	}, 64 * process_guard_bytes_per_mib)
	assert message.contains('vtest.resource.job_object.state=create_failed')
	assert message.contains('vtest.resource.job_object.reason=job_object_create_failed')
	assert message.contains('vtest.resource.job_object.action=fallback_to_polling_guard')
	assert message.contains('vtest.resource.job_object.create_error=5')
	assert message.contains('vtest.resource.job_object.create_error_message=')
}

fn test_process_guard_recognizes_builtin_memory_guard_report() {
	assert process_guard_output_looks_memory_related('v.memory_guard.failed=true\nv.memory_guard.reason=process_memory_limit')
}

fn test_process_guard_execute_command_rejects_empty_command() {
	result := process_guard_execute_command('')
	assert result.exit_code == -1, result.exit_code_diagnostics('-1', label: @FN)
	assert result.output.contains('vtest.resource.spawn_error=true')
	assert result.output.contains('vtest.resource.reason=spawn_failed')
	assert result.output.contains('vtest.resource.action=abort_before_child_start')
	assert result.output.contains('vtest.resource.exit_code=-1')
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
	assert message.contains('vtest.resource.action=abort_before_child_start')
	assert message.contains('vtest.resource.exit_code=${process_guard_host_pressure_exit_code}')
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
		process_guard_compile_env,
		process_guard_limit_env,
		process_guard_limit_mb_env,
		process_guard_output_limit_env,
		process_guard_spawn_wait_env,
		process_guard_child_memory_guard_env,
		process_guard_child_memory_limit_mb_env,
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

fn process_guard_test_env_value(env []string, name string) string {
	for value in env {
		env_separator_idx := value.index('=') or { -1 }
		if env_separator_idx < 0 {
			continue
		}
		env_name := value[..env_separator_idx]
		mut matches := env_name == name
		$if windows {
			matches = env_name.to_lower() == name.to_lower()
		}
		if matches {
			return value[env_separator_idx + 1..]
		}
	}
	return ''
}
