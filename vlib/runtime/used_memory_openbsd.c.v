module runtime

#include <sys/resource.h>

struct C.rusage {
	ru_maxrss int
}

fn C.getrusage(who i32, usage &C.rusage) i32

// used_memory retrieves the current physical memory usage of the process.
pub fn used_memory() !u64 {
	page_size := usize(C.sysconf(C._SC_PAGESIZE))
	c_errno_1 := C.errno
	if page_size == usize(-1) {
		return error(runtime_errno_report('used_memory', 'C.sysconf(C._SC_PAGESIZE)',
			'sysconf_pagesize_failed', 'return_error_to_caller', c_errno_1))
	}

	mut usage := C.rusage{}
	ret := C.getrusage(C.RUSAGE_SELF, &usage)
	if ret == -1 {
		c_errno_2 := C.errno
		return error(runtime_errno_report('used_memory', 'C.getrusage(C.RUSAGE_SELF)',
			'getrusage_failed', 'return_error_to_caller', c_errno_2))
	}
	return u64(int_max(1, usage.ru_maxrss)) * 1024
}
