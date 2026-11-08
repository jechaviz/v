module runtime

#flag @VEXEROOT/vlib/runtime/free_memory_openbsd.o

fn C.v_runtime_openbsd_free_memory(&usize) int

fn free_memory_impl() !usize {
	$if cross ? {
		return error('free_memory: not implemented')
	}
	$if !cross ? {
		$if openbsd {
			mut free_bytes := usize(0)
			retval := C.v_runtime_openbsd_free_memory(&free_bytes)
			c_errno := C.errno
			if retval == -1 {
				return error(runtime_errno_report('free_memory', 'C.sysctl(VM_UVMEXP)',
					'sysctl_free_pages_failed', 'return_error_to_caller', c_errno))
			}
			return free_bytes
		}
	}
	return error('free_memory: not implemented')
}
