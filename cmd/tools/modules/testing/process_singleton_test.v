module testing

import os
import os.filelock
import time

fn test_process_singleton_default_policy_matches_host() {
	old_mode := os.getenv(process_singleton_env)
	os.unsetenv(process_singleton_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
	}
	$if windows {
		assert process_singleton_enabled()
	} $else {
		assert !process_singleton_enabled()
	}
}

fn test_process_singleton_env_overrides_default_policy() {
	old_mode := os.getenv(process_singleton_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
	}

	for value in ['1', 'true', 'on', 'yes', 'always', 'enabled'] {
		os.setenv(process_singleton_env, value, true)
		assert process_singleton_enabled()
	}
	for value in ['0', 'false', 'off', 'no', 'disabled'] {
		os.setenv(process_singleton_env, value, true)
		assert !process_singleton_enabled()
	}
}

fn test_process_singleton_reduces_session_jobs_when_enabled() {
	old_mode := os.getenv(process_singleton_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
	}

	os.setenv(process_singleton_env, '1', true)
	assert process_singleton_jobs(8) == 1
	assert process_singleton_jobs(1) == 1
	assert process_singleton_jobs(0) == 0

	os.setenv(process_singleton_env, '0', true)
	assert process_singleton_jobs(8) == 8
}

fn test_process_singleton_busy_lock_fails_closed() {
	lock_path := process_singleton_test_lock_path('busy')
	process_singleton_prepare_lock(lock_path)
	old_mode := os.getenv(process_singleton_env)
	old_lock := os.getenv(process_singleton_lock_env)
	old_wait := os.getenv(process_singleton_wait_env)
	old_held := os.getenv(process_singleton_held_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
		process_singleton_restore_env(process_singleton_lock_env, old_lock)
		process_singleton_restore_env(process_singleton_wait_env, old_wait)
		process_singleton_restore_env(process_singleton_held_env, old_held)
		process_singleton_remove_lock(lock_path)
	}

	os.setenv(process_singleton_env, '1', true)
	os.setenv(process_singleton_lock_env, lock_path, true)
	os.setenv(process_singleton_wait_env, '25', true)
	os.unsetenv(process_singleton_held_env)
	mut gate := filelock.new(lock_path)
	assert gate.wait_acquire(100 * time.millisecond)
	defer {
		gate.release()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == os.system_spawn_failed_exit_code
	assert res.output.contains('timed out after 25ms waiting for V test process singleton')
}

fn test_process_singleton_system_busy_lock_fails_closed() {
	lock_path := process_singleton_test_lock_path('system_busy')
	process_singleton_prepare_lock(lock_path)
	old_mode := os.getenv(process_singleton_env)
	old_lock := os.getenv(process_singleton_lock_env)
	old_wait := os.getenv(process_singleton_wait_env)
	old_held := os.getenv(process_singleton_held_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
		process_singleton_restore_env(process_singleton_lock_env, old_lock)
		process_singleton_restore_env(process_singleton_wait_env, old_wait)
		process_singleton_restore_env(process_singleton_held_env, old_held)
		process_singleton_remove_lock(lock_path)
	}

	os.setenv(process_singleton_env, '1', true)
	os.setenv(process_singleton_lock_env, lock_path, true)
	os.setenv(process_singleton_wait_env, '25', true)
	os.unsetenv(process_singleton_held_env)
	mut gate := filelock.new(lock_path)
	assert gate.wait_acquire(100 * time.millisecond)
	defer {
		gate.release()
	}

	assert process_singleton_system('${os.quoted_path(@VEXE)} version') == os.system_spawn_failed_exit_code
}

fn test_process_singleton_held_flag_keeps_nested_execute_reentrant() {
	lock_path := process_singleton_test_lock_path('held')
	process_singleton_prepare_lock(lock_path)
	old_mode := os.getenv(process_singleton_env)
	old_lock := os.getenv(process_singleton_lock_env)
	old_wait := os.getenv(process_singleton_wait_env)
	old_held := os.getenv(process_singleton_held_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
		process_singleton_restore_env(process_singleton_lock_env, old_lock)
		process_singleton_restore_env(process_singleton_wait_env, old_wait)
		process_singleton_restore_env(process_singleton_held_env, old_held)
		process_singleton_remove_lock(lock_path)
	}

	os.setenv(process_singleton_env, '1', true)
	os.setenv(process_singleton_lock_env, lock_path, true)
	os.setenv(process_singleton_wait_env, '25', true)
	os.setenv(process_singleton_held_env, '1', true)
	mut gate := filelock.new(lock_path)
	assert gate.wait_acquire(100 * time.millisecond)
	defer {
		gate.release()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.output
	assert res.output.to_lower().contains('v ')
}

fn test_process_singleton_can_be_disabled_even_when_lock_is_busy() {
	lock_path := process_singleton_test_lock_path('disabled')
	process_singleton_prepare_lock(lock_path)
	old_mode := os.getenv(process_singleton_env)
	old_lock := os.getenv(process_singleton_lock_env)
	old_wait := os.getenv(process_singleton_wait_env)
	defer {
		process_singleton_restore_env(process_singleton_env, old_mode)
		process_singleton_restore_env(process_singleton_lock_env, old_lock)
		process_singleton_restore_env(process_singleton_wait_env, old_wait)
		process_singleton_remove_lock(lock_path)
	}

	os.setenv(process_singleton_env, '0', true)
	os.setenv(process_singleton_lock_env, lock_path, true)
	os.setenv(process_singleton_wait_env, '25', true)
	mut gate := filelock.new(lock_path)
	assert gate.wait_acquire(100 * time.millisecond)
	defer {
		gate.release()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.output
	assert res.output.to_lower().contains('v ')
}

fn process_singleton_test_lock_path(tag string) string {
	return os.join_path(os.vtmp_dir(), 'vtest_process_singleton_${tag}_${os.getpid()}.lock')
}

fn process_singleton_prepare_lock(path string) {
	os.mkdir_all(os.dir(path)) or { panic('could not create ${os.dir(path)}: ${err}') }
	if os.exists(path) {
		os.rm(path) or { panic('could not remove stale lock ${path}: ${err}') }
	}
}

fn process_singleton_remove_lock(path string) {
	if os.exists(path) {
		os.rm(path) or {}
	}
}
