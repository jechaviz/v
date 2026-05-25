module testing

import os
import runtime
import strings
import time
import v.util
import v.util.vflags

const process_guard_env = 'VTEST_CHILD_MEMORY_GUARD'
const process_guard_limit_env = 'VTEST_CHILD_MAX_MEMORY'
const process_guard_limit_mb_env = 'VTEST_CHILD_MAX_MEMORY_MB'
const process_guard_output_limit_env = 'VTEST_CHILD_OUTPUT_LIMIT'
const process_guard_spawn_wait_env = 'VTEST_MEMORY_BACKPRESSURE_WAIT_MS'
const process_guard_default_limit = u64(2) * process_guard_bytes_per_gib
const process_guard_default_output_limit = 4 * 1024 * 1024
const process_guard_default_spawn_wait_ms = 120_000
const process_guard_host_pressure_exit_code = 102
const process_guard_bytes_per_kib = u64(1024)
const process_guard_bytes_per_mib = u64(1024) * process_guard_bytes_per_kib
const process_guard_bytes_per_gib = u64(1024) * process_guard_bytes_per_mib

struct ProcessGuardOutput {
mut:
	builder   strings.Builder
	len       int
	truncated bool
}

fn execute_test_binary(generated_binary_fpath string, run_js bool, run_cmd string) os.Result {
	if !process_guard_enabled() {
		return process_guard_with_silent_diagnostics(run_cmd, process_singleton_execute(run_cmd))
	}
	executable := process_guard_executable(generated_binary_fpath, run_js) or {
		return os.Result{
			exit_code: -1
			output:    err.msg()
		}
	}
	args := if run_js { [generated_binary_fpath] } else { []string{} }
	return process_guard_with_silent_diagnostics(run_cmd, process_guard_execute(executable, args,
		run_cmd))
}

fn process_guard_enabled() bool {
	mode := os.getenv(process_guard_env).trim_space().to_lower()
	if mode in ['0', 'false', 'off', 'no', 'disabled'] {
		return false
	}
	if mode in ['1', 'true', 'on', 'yes', 'always', 'enabled'] {
		return true
	}
	return os.user_os() == 'windows'
}

fn process_guard_executable(generated_binary_fpath string, run_js bool) !string {
	if !run_js {
		return generated_binary_fpath
	}
	return os.find_abs_path_of_executable('node') or {
		error('node executable not found for JS test run: ${err.msg()}')
	}
}

fn process_guard_execute(executable string, args []string, display_cmd string) os.Result {
	if pressure_result := process_guard_wait_for_host_memory('vtest_run', display_cmd) {
		_ = pressure_result
	} else {
		return os.Result{
			exit_code: process_guard_host_pressure_exit_code
			output:    err.msg()
		}
	}
	mut process := os.new_process(executable)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	if process.status == .not_started || process.err != '' {
		return os.Result{
			exit_code: -1
			output:    process_guard_spawn_error(display_cmd, process.err)
		}
	}
	limit_bytes := process_guard_limit_bytes()
	output_limit := process_guard_output_limit()
	mut output := ProcessGuardOutput{
		builder: strings.new_builder(4096)
	}
	mut peak_bytes := u64(0)
	mut killed := false
	for process.is_alive() {
		process_guard_drain(mut process, mut output, output_limit)
		used_bytes := child_process_memory_bytes(process.pid)
		if used_bytes > peak_bytes {
			peak_bytes = used_bytes
		}
		if limit_bytes > 0 && used_bytes > limit_bytes {
			killed = true
			process.signal_kill()
			break
		}
		time.sleep(50 * time.millisecond)
	}
	process.wait()
	process_guard_drain(mut process, mut output, output_limit)
	mut result_output := process_guard_output(output.builder.str(), output.truncated, killed,
		display_cmd, process.pid, peak_bytes, limit_bytes)
	exit_code := if killed { -1 } else { process.code }
	if exit_code != 0 && result_output.trim_space() == '' {
		result_output = process_guard_silent_failure_message(display_cmd, exit_code)
	}
	process.close()
	return os.Result{
		exit_code: exit_code
		output:    result_output
	}
}

fn process_guard_execute_command(cmd string) os.Result {
	args := vflags.tokenize_to_args(cmd)
	if args.len == 0 {
		return os.Result{
			exit_code: -1
			output:    process_guard_spawn_error(cmd, 'empty command')
		}
	}
	if process_singleton_enabled() && !process_singleton_held() {
		mut gate := process_singleton_acquire_for_command(cmd) or {
			return os.Result{
				exit_code: -1
				output:    err.msg()
			}
		}
		old_held := os.getenv(process_singleton_held_env)
		os.setenv(process_singleton_held_env, '1', true)
		defer {
			gate.release()
			process_singleton_restore_env(process_singleton_held_env, old_held)
		}
		return process_guard_execute(args[0], args[1..], cmd)
	}
	return process_guard_execute(args[0], args[1..], cmd)
}

fn process_guard_wait_for_host_memory(phase string, display_cmd string) !string {
	wait_limit_ms := process_guard_spawn_wait_ms()
	mut waited_ms := 0
	mut last_plan := util.MemoryBackpressurePlan{}
	for {
		plan := util.memory_backpressure_plan(phase, runtime.nr_jobs())
		last_plan = plan
		if !plan.decision.should_defer_new_work {
			util.memory_backpressure_apply_plan(plan)
			if waited_ms > 0 {
				return process_guard_wait_message(display_cmd, waited_ms, plan)
			}
			return ''
		}
		if waited_ms >= wait_limit_ms {
			return error(process_guard_host_pressure_message(display_cmd, waited_ms, last_plan))
		}
		sleep_ms := process_guard_spawn_sleep_ms(plan)
		time.sleep(i64(sleep_ms) * time.millisecond)
		waited_ms += sleep_ms
	}
	return error(process_guard_host_pressure_message(display_cmd, waited_ms, last_plan))
}

fn process_guard_with_silent_diagnostics(display_cmd string, result os.Result) os.Result {
	if result.exit_code == 0 || result.output.trim_space() != '' {
		return result
	}
	return os.Result{
		exit_code: result.exit_code
		output:    process_guard_silent_failure_message(display_cmd, result.exit_code)
	}
}

fn process_guard_silent_failure_message(display_cmd string, exit_code int) string {
	snapshot := runtime.collect_host_telemetry(os.getwd())
	return [
		'vtest.process.exit_without_output=true',
		'vtest.process.exit_code=${exit_code}',
		'vtest.process.command=${display_cmd}',
		'vtest.process.advice=The child process failed without stderr/stdout. Check the memory and virtual-memory telemetry below; rerun with VTEST_SHOW_CMD=1, VTEST_CHILD_MEMORY_GUARD=1, or lower VTEST_CHILD_MAX_MEMORY_MB to isolate runaway allocations.',
		snapshot.report(),
	].join('\n')
}

fn process_guard_wait_message(display_cmd string, waited_ms int, plan util.MemoryBackpressurePlan) string {
	return [
		'vtest.resource.waited_for_host_memory=true',
		'vtest.resource.wait_ms=${waited_ms}',
		'vtest.resource.command=${display_cmd}',
		plan.report(),
	].join('\n')
}

fn process_guard_host_pressure_message(display_cmd string, waited_ms int, plan util.MemoryBackpressurePlan) string {
	return [
		'vtest.resource.blocked=true',
		'vtest.resource.reason=host_memory_pressure',
		'vtest.resource.wait_ms=${waited_ms}',
		'vtest.resource.command=${display_cmd}',
		'vtest.resource.advice=V did not start another compiler/test process because Windows memory or commit headroom stayed critical. Redesign the workload to stream, chunk, cap allocations, reuse data, or lower VJOBS; set VMEM_BACKPRESSURE=strict for more conservative scheduling or VTEST_MEMORY_BACKPRESSURE_WAIT_MS to tune the wait window.',
		plan.report(),
	].join('\n')
}

fn process_guard_drain(mut process os.Process, mut output ProcessGuardOutput, output_limit int) {
	for {
		mut drained := false
		if chunk := process.pipe_read(.stdout) {
			process_guard_append(mut output, chunk, output_limit)
			drained = true
		}
		if chunk := process.pipe_read(.stderr) {
			process_guard_append(mut output, chunk, output_limit)
			drained = true
		}
		if !drained {
			break
		}
	}
}

fn process_guard_append(mut output ProcessGuardOutput, chunk string, output_limit int) {
	if chunk == '' {
		return
	}
	if output_limit <= 0 {
		output.builder.write_string(chunk)
		output.len += chunk.len
		return
	}
	if output.len >= output_limit {
		output.truncated = true
		return
	}
	remaining := output_limit - output.len
	if chunk.len <= remaining {
		output.builder.write_string(chunk)
		output.len += chunk.len
		return
	}
	output.builder.write_string(chunk[..remaining])
	output.len = output_limit
	output.truncated = true
}

fn process_guard_output(output string, truncated bool, killed bool, display_cmd string, pid int, peak_bytes u64, limit_bytes u64) string {
	mut lines := []string{}
	if output != '' {
		lines << output
	}
	if truncated {
		lines << 'vtest.resource.output_truncated=true'
	}
	if killed {
		lines << process_guard_kill_message(display_cmd, pid, peak_bytes, limit_bytes)
	}
	return lines.join('\n')
}

fn process_guard_spawn_error(display_cmd string, message string) string {
	detail := if message.trim_space() == '' { 'unknown spawn error' } else { message }
	return 'vtest.resource.spawn_error=true\nvtest.resource.command=${display_cmd}\nvtest.resource.error=${detail}'
}

fn process_guard_kill_message(display_cmd string, pid int, peak_bytes u64, limit_bytes u64) string {
	return [
		'vtest.resource.killed=true',
		'vtest.resource.reason=child_memory_limit',
		'vtest.resource.pid=${pid}',
		'vtest.resource.peak_private_bytes=${peak_bytes}',
		'vtest.resource.limit_bytes=${limit_bytes}',
		'vtest.resource.command=${display_cmd}',
		'vtest.resource.advice=The generated test process was stopped before it could exhaust Windows commit/pagefile. Redesign the test or runtime path to stream, chunk, cap allocations, or reuse data; set VTEST_CHILD_MAX_MEMORY_MB to tune the limit or VTEST_CHILD_MEMORY_GUARD=0 only for trusted diagnostics.',
	].join('\n')
}

fn process_guard_limit_bytes() u64 {
	if raw := os.getenv_opt(process_guard_limit_env) {
		return process_guard_parse_size(raw)
	}
	if raw_mb := os.getenv_opt(process_guard_limit_mb_env) {
		return process_guard_parse_size(raw_mb + 'm')
	}
	return process_guard_default_limit
}

fn process_guard_output_limit() int {
	if raw := os.getenv_opt(process_guard_output_limit_env) {
		limit := process_guard_parse_size(raw)
		if limit > u64(max_int) {
			return max_int
		}
		return int(limit)
	}
	return process_guard_default_output_limit
}

fn process_guard_spawn_wait_ms() int {
	raw := os.getenv(process_guard_spawn_wait_env).trim_space()
	if raw == '' {
		return process_guard_default_spawn_wait_ms
	}
	value := raw.int()
	if value < 0 {
		return process_guard_default_spawn_wait_ms
	}
	return value
}

fn process_guard_spawn_sleep_ms(plan util.MemoryBackpressurePlan) int {
	if plan.sleep_ms > 0 {
		return plan.sleep_ms
	}
	return 250
}

fn process_guard_parse_size(raw string) u64 {
	mut text := raw.trim_space().to_lower().replace('_', '')
	if text == '' {
		return 0
	}
	mut multiplier := u64(1)
	if text.ends_with('kib') {
		text = text[..text.len - 3]
		multiplier = process_guard_bytes_per_kib
	} else if text.ends_with('kb') {
		text = text[..text.len - 2]
		multiplier = process_guard_bytes_per_kib
	} else if text.ends_with('k') {
		text = text[..text.len - 1]
		multiplier = process_guard_bytes_per_kib
	} else if text.ends_with('mib') {
		text = text[..text.len - 3]
		multiplier = process_guard_bytes_per_mib
	} else if text.ends_with('mb') {
		text = text[..text.len - 2]
		multiplier = process_guard_bytes_per_mib
	} else if text.ends_with('m') {
		text = text[..text.len - 1]
		multiplier = process_guard_bytes_per_mib
	} else if text.ends_with('gib') {
		text = text[..text.len - 3]
		multiplier = process_guard_bytes_per_gib
	} else if text.ends_with('gb') {
		text = text[..text.len - 2]
		multiplier = process_guard_bytes_per_gib
	} else if text.ends_with('g') {
		text = text[..text.len - 1]
		multiplier = process_guard_bytes_per_gib
	}
	value := text.u64()
	if value == 0 {
		return 0
	}
	if multiplier > 1 && value > max_u64 / multiplier {
		return max_u64
	}
	return value * multiplier
}
