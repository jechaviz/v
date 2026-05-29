module testing

struct ProcessGuardJob {
mut:
	handle       voidptr
	enabled      bool
	assigned     bool
	create_error u32
	assign_error u32
}

fn child_process_memory_bytes(pid int) u64 {
	$if windows {
		return child_process_memory_bytes_windows(pid)
	}
	_ := pid
	return 0
}

fn process_guard_job_create(limit_bytes u64) ProcessGuardJob {
	$if windows {
		return process_guard_job_create_windows(limit_bytes)
	}
	_ := limit_bytes
	return ProcessGuardJob{}
}

fn process_guard_job_assign(mut job ProcessGuardJob, pid int) {
	$if windows {
		process_guard_job_assign_windows(mut job, pid)
	}
	_ = pid
}

fn process_guard_job_close(mut job ProcessGuardJob) {
	$if windows {
		process_guard_job_close_windows(mut job)
	}
}
