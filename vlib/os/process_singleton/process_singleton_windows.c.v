module process_singleton

fn C.CreateMutexA(voidptr, bool, &char) voidptr

const wait_object_0 = 0
const wait_abandoned = 0x00000080
const wait_timeout = 0x00000102

fn acquire_windows_mutex(name string, path string, wait_ms int) !Guard {
	mutex_name := windows_mutex_name(path)
	handle := C.CreateMutexA(unsafe { nil }, false, &char(mutex_name.str))
	if handle == unsafe { nil } {
		return error('could not create process singleton mutex `${mutex_name}` (GetLastError=${C.GetLastError()})')
	}
	wait_result := C.WaitForSingleObject(handle, wait_ms)
	if wait_result == wait_object_0 || wait_result == wait_abandoned {
		return Guard{
			name:   name
			path:   path
			handle: handle
			held:   true
		}
	}
	C.CloseHandle(handle)
	if wait_result == wait_timeout {
		return error('process singleton `${name}` is already running')
	}
	return error('could not wait for process singleton `${name}` mutex `${mutex_name}` (wait_result=${wait_result}, GetLastError=${C.GetLastError()})')
}

fn (mut guard Guard) release_windows_mutex() bool {
	if guard.handle == unsafe { nil } {
		return false
	}
	C.ReleaseMutex(guard.handle)
	C.CloseHandle(guard.handle)
	guard.handle = unsafe { nil }
	return true
}

fn windows_mutex_name(path string) string {
	mut tail := safe_lock_name(path)
	if tail.len > 64 {
		tail = tail[tail.len - 64..]
	}
	return 'v_process_singleton_${stable_lock_hash(path).hex()}_${tail}'
}

fn stable_lock_hash(text string) u64 {
	mut hash := u64(14695981039346656037)
	for ch in text.bytes() {
		hash ^= u64(ch)
		hash *= u64(1099511628211)
	}
	return hash
}
