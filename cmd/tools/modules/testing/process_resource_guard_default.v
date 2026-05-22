module testing

fn child_process_memory_bytes(pid int) u64 {
	$if windows {
		return child_process_memory_bytes_windows(pid)
	}
	_ := pid
	return 0
}
