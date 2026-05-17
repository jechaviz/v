module testing

import os
import os.filelock
import time

const process_singleton_env = 'VTEST_PROCESS_SINGLETON'
const process_singleton_lock_env = 'VTEST_PROCESS_SINGLETON_LOCK'
const process_singleton_wait_env = 'VTEST_PROCESS_SINGLETON_WAIT_MS'
const process_singleton_held_env = 'VTEST_PROCESS_SINGLETON_HELD'
const process_singleton_default_wait_ms = 600_000

fn process_singleton_enabled() bool {
	mode := os.getenv(process_singleton_env).trim_space().to_lower()
	if mode in ['0', 'false', 'off', 'no', 'disabled'] {
		return false
	}
	if mode in ['1', 'true', 'on', 'yes', 'always', 'enabled'] {
		return true
	}
	return os.user_os() == 'windows'
}

fn process_singleton_jobs(requested int) int {
	if requested <= 1 || !process_singleton_enabled() {
		return requested
	}
	return 1
}

fn process_singleton_execute(cmd string) os.Result {
	if !process_singleton_enabled() || process_singleton_held() {
		return os.execute(cmd)
	}
	mut gate := process_singleton_acquire() or {
		return os.Result{
			exit_code: -1
			output:    err.msg()
		}
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	res := os.execute(cmd)
	gate.release()
	process_singleton_restore_env(process_singleton_held_env, old_held)
	return res
}

fn process_singleton_system(cmd string) int {
	if !process_singleton_enabled() || process_singleton_held() {
		return os.system(cmd)
	}
	mut gate := process_singleton_acquire() or {
		eprintln(err.msg())
		return -1
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	code := os.system(cmd)
	gate.release()
	process_singleton_restore_env(process_singleton_held_env, old_held)
	return code
}

fn process_singleton_held() bool {
	return os.getenv(process_singleton_held_env) == '1'
}

fn process_singleton_acquire() !filelock.FileLock {
	lock_path := process_singleton_lock_path()
	os.mkdir_all(os.dir(lock_path)) or {
		return error('could not create V test process singleton lock directory ${os.dir(lock_path)}: ${err}')
	}
	mut gate := filelock.new(lock_path)
	wait_ms := process_singleton_wait_ms()
	if !gate.wait_acquire(wait_ms * time.millisecond) {
		return error('timed out after ${wait_ms}ms waiting for V test process singleton ${lock_path}')
	}
	return gate
}

fn process_singleton_lock_path() string {
	env_path := os.getenv(process_singleton_lock_env).trim_space()
	if env_path != '' {
		return os.norm_path(env_path)
	}
	return os.join_path(os.vtmp_dir(), 'vtest_process_singleton.lock')
}

fn process_singleton_wait_ms() int {
	env_ms := os.getenv(process_singleton_wait_env).trim_space()
	if env_ms == '' {
		return process_singleton_default_wait_ms
	}
	parsed := env_ms.int()
	if parsed <= 0 {
		return process_singleton_default_wait_ms
	}
	return parsed
}

fn process_singleton_restore_env(name string, value string) {
	if value == '' {
		os.unsetenv(name)
		return
	}
	os.setenv(name, value, true)
}
