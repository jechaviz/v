module testing

import os
import runtime
import strings
import time

const process_guard_env = 'VTEST_CHILD_MEMORY_GUARD'
const process_guard_limit_env = 'VTEST_CHILD_MAX_MEMORY'
const process_guard_limit_mb_env = 'VTEST_CHILD_MAX_MEMORY_MB'
const process_guard_output_limit_env = 'VTEST_CHILD_OUTPUT_LIMIT'
const process_guard_default_limit = u64(2) * process_guard_bytes_per_gib
const process_guard_default_output_limit = 4 * 1024 * 1024
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
