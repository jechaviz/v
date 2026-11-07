module process_singleton

fn acquire_windows_mutex(name string, path string, wait_ms int) !Guard {
	return error('process singleton mutex is only available on Windows')
}

fn (mut guard Guard) release_windows_mutex() bool {
	return false
}
