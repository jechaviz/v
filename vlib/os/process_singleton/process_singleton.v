module process_singleton

import os
import os.filelock
import time

pub const default_wait_ms = 0

@[params]
pub struct Options {
pub:
	name      string
	lock_path string
	wait_ms   int = default_wait_ms
}

pub struct Guard {
pub:
	name string
	path string
mut:
	lock   filelock.FileLock
	handle voidptr
	held   bool
}

pub fn acquire(name string) !Guard {
	return acquire_with_options(name: name)
}

pub fn acquire_with_options(options Options) !Guard {
	name := options.name.trim_space()
	if name == '' {
		return error('process singleton name cannot be empty')
	}
	path := process_singleton_path(name, options.lock_path)
	wait_ms := if options.wait_ms > 0 { options.wait_ms } else { 0 }
	$if windows {
		return acquire_windows_mutex(name, path, wait_ms)
	}
	return acquire_file_lock(name, path, wait_ms)
}

fn acquire_file_lock(name string, path string, wait_ms int) !Guard {
	os.mkdir_all(os.dir(path)) or {
		return error('could not create process singleton lock directory `${os.dir(path)}`: ${err}')
	}
	mut gate := filelock.new(path)
	acquired := if wait_ms > 0 {
		gate.wait_acquire(wait_ms * time.millisecond)
	} else {
		gate.try_acquire()
	}
	if !acquired {
		return error('process singleton `${name}` is already running')
	}
	return Guard{
		name: name
		path: path
		lock: gate
		held: true
	}
}

pub fn default_lock_path(name string) string {
	return os.join_path(os.vtmp_dir(), 'process_singleton', '${safe_lock_name(name)}.lock')
}

pub fn (mut guard Guard) release() bool {
	if !guard.held {
		return false
	}
	guard.held = false
	$if windows {
		return guard.release_windows_mutex()
	}
	return guard.lock.release()
}

fn process_singleton_path(name string, lock_path string) string {
	if lock_path.trim_space() != '' {
		return os.norm_path(lock_path)
	}
	return default_lock_path(name)
}

fn safe_lock_name(name string) string {
	mut safe := []u8{cap: name.len}
	for ch in name.bytes() {
		if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch in [`_`, `-`, `.`] {
			safe << ch
			continue
		}
		safe << `_`
	}
	res := safe.bytestr().trim('_')
	if res == '' {
		return 'process'
	}
	return res
}
