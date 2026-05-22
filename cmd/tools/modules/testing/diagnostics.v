module testing

import os
import runtime
import time

const diagnostics_bytes_per_mib = u64(1024 * 1024)

fn command_failure_context(phase string, file string, cmd string, exit_code int, elapsed time.Duration) string {
	mut lines := []string{cap: 6}
	lines << 'vtest diagnostic: ${phase} command failed; exit_code=${exit_code}'
	if file != '' {
		lines << 'file: ${file}'
	}
	lines << 'cmd: ${cmd}'
	lines << 'elapsed: ${elapsed}'
	lines << host_resource_context()
	return lines.join('\n')
}

fn command_output_or_diagnostic(phase string, file string, cmd string, exit_code int, output string, elapsed time.Duration) string {
	trimmed := output.trim_space()
	if trimmed != '' {
		return trimmed
	}
	return command_failure_context(phase, file, cmd, exit_code, elapsed) +
		'\nno stdout/stderr captured'
}

fn host_resource_context() string {
	snapshot := runtime.collect_host_telemetry(os.getwd())
	return 'host: pid=${os.getpid()} os=${snapshot.os_name} jobs=${runtime.nr_jobs()} free_ram_mb=${bytes_to_mib(snapshot.free_memory_bytes)} free_virtual_mb=${bytes_to_mib(snapshot.free_virtual_memory_bytes)} disk_free_mb=${bytes_to_mib(snapshot.disk_free_bytes)}'
}

fn bytes_to_mib(value u64) u64 {
	return value / diagnostics_bytes_per_mib
}
