import os
import time

const process_memory_guard_probe_source = '
fn main() {
	unsafe {
		_ := malloc(2 * 1024 * 1024)
	}
	println("ok")
}
'

fn test_process_memory_guard_is_off_without_explicit_limit() {
	probe := process_memory_guard_build_probe()!
	defer {
		os.rm(probe) or {}
	}
	result := process_memory_guard_run_probe(probe, {})
	assert result.exit_code == 0, result.output
	assert result.output.trim_space() == 'ok'
}

fn test_process_memory_guard_limit_env_fails_before_large_allocation() {
	probe := process_memory_guard_build_probe()!
	defer {
		os.rm(probe) or {}
	}
	result := process_memory_guard_run_probe(probe, {
		'V_PROCESS_MEMORY_LIMIT_MB': '1'
	})
	assert result.exit_code == 103, result.output
	assert result.output.contains('v.memory_guard.failed=true')
	assert result.output.contains('v.memory_guard.reason=process_memory_limit')
	assert result.output.contains('v.memory_guard.action=abort_before_oom')
	assert result.output.contains('v.memory_guard.message=')
	assert result.output.contains('v.memory_guard.limit_bytes=1048576')
	assert result.output.contains('v.memory_guard.request_bytes=2097152')
	assert result.output.contains('v.memory_guard.advice=')
	assert result.output.contains('v.memory_guard.override=')
}

fn process_memory_guard_build_probe() !string {
	source_path := os.join_path(os.vtmp_dir(),
		'process_memory_guard_probe_${os.getpid()}_${time.now().unix_milli()}.v')
	exe_path := os.join_path(os.vtmp_dir(),
		'process_memory_guard_probe_${os.getpid()}_${time.now().unix_milli()}.exe')
	os.write_file(source_path, process_memory_guard_probe_source)!
	defer {
		os.rm(source_path) or {}
	}
	cmd := '${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe_path)} ${os.quoted_path(source_path)}'
	result := os.execute(cmd)
	if result.exit_code != 0 {
		return error('could not build memory guard probe:\n${cmd}\n${result.output}')
	}
	return exe_path
}

fn process_memory_guard_run_probe(exe_path string, values map[string]string) os.Result {
	mut env := os.environ()
	env.delete('V_PROCESS_MEMORY_GUARD')
	env.delete('V_AUTO_PROCESS_MEMORY_GUARD')
	env.delete('V_PROCESS_MEMORY_LIMIT_MB')
	env.delete('V_PROCESS_MEMORY_SAMPLE_MB')
	for key, value in values {
		env[key] = value
	}
	mut process := os.new_process(exe_path)
	process.set_environment(env)
	process.set_redirect_stdio()
	process.run()
	if process.status == .not_started || process.err != '' {
		return os.Result{
			exit_code: -1
			output:    process.err
		}
	}
	process.wait()
	stdout := process.stdout_slurp()
	stderr := process.stderr_slurp()
	exit_code := process.code
	process.close()
	return os.Result{
		exit_code: exit_code
		output:    stdout + stderr
	}
}
