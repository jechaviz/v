module runtime

fn C.sysconf(name i32) i64

fn runtime_report_value(value string) string {
	return value.trim_space().replace('\r', '\\r').replace('\n', '\\n')
}

fn runtime_errno_report(metric string, syscall string, reason string, action string, errno int) string {
	error_text := unsafe { cstring_to_vstring(C.strerror(errno)) }
	return 'runtime.memory.failed=true\nruntime.memory.metric=${metric}\nruntime.memory.reason=${reason}\nruntime.memory.action=${action}\nruntime.memory.message=${syscall} failed while reading host memory information\nruntime.memory.errno=${errno}\nruntime.memory.error=${runtime_report_value(error_text)}'
}

// nr_cpus returns the number of virtual CPU cores found on the system.
pub fn nr_cpus() int {
	mut cpus := int(C.sysconf(C._SC_NPROCESSORS_ONLN))
	if cpus < 1 {
		eprintln('Warning: sysconf(_SC_NPROCESSORS_ONLN) returned -1, returning CPU count as 1')
		cpus = 1
	}
	return cpus
}

// total_memory returns total physical memory found on the system.
pub fn total_memory() !usize {
	page_size := usize(C.sysconf(C._SC_PAGESIZE))
	c_errno_1 := C.errno
	if page_size == usize(-1) {
		return error(runtime_errno_report('total_memory', 'C.sysconf(C._SC_PAGESIZE)',
			'sysconf_pagesize_failed', 'return_error_to_caller', c_errno_1))
	}
	phys_pages := usize(C.sysconf(C._SC_PHYS_PAGES))
	c_errno_2 := C.errno
	if phys_pages == usize(-1) {
		return error(runtime_errno_report('total_memory', 'C.sysconf(C._SC_PHYS_PAGES)',
			'sysconf_physical_pages_failed', 'return_error_to_caller', c_errno_2))
	}
	return page_size * phys_pages
}

// free_memory returns free physical memory found on the system.
// Note: implementation available only on Darwin, FreeBSD, Linux, OpenBSD and
// Windows. Otherwise, returns 'free_memory: not implemented'.
pub fn free_memory() !usize {
	return free_memory_impl()!
}

// total_virtual_memory returns the best portable host memory ceiling.
// On POSIX platforms without a cheap commit-limit API, this falls back to RAM.
pub fn total_virtual_memory() !usize {
	return total_memory()!
}

// free_virtual_memory returns the best portable host allocation headroom.
// On POSIX platforms without a cheap commit-limit API, this falls back to RAM.
pub fn free_virtual_memory() !usize {
	return free_memory()!
}
