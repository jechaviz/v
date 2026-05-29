module testing

import os
import os.process_singleton
import time

const process_singleton_helper_mode_env = 'VTEST_PROCESS_SINGLETON_TEST_HELPER_MODE'
const process_singleton_helper_lock_env = 'VTEST_PROCESS_SINGLETON_TEST_HELPER_LOCK'

fn testsuite_begin() {
	if os.getenv(process_singleton_helper_mode_env) != '' {
		process_singleton_run_helper()
	}
}

fn process_singleton_run_helper() {
	match os.getenv(process_singleton_helper_mode_env) {
		'hold' {
			mut gate := process_singleton_hold_gate(os.getenv(process_singleton_helper_lock_env)) or {
				eprintln(err.msg())
				exit(2)
			}
			println('locked')
			os.flush()
			time.sleep(500 * time.millisecond)
			gate.release()
			exit(0)
		}
		else {
			exit(3)
		}
	}
}

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
	mut helper := process_singleton_start_hold_helper(lock_path)
	process_singleton_wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == -1, res.exit_code_diagnostics('-1', label: @FN)
	assert res.output.contains('vtest.process.queue=timeout')
	assert res.output.contains('process-instance-queue-timeout')
	assert res.output.contains('vtest.process.action=abort_before_child_start')
	assert res.output.contains('vtest.process.message=')
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
	mut helper := process_singleton_start_hold_helper(lock_path)
	process_singleton_wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}

	assert process_singleton_system('${os.quoted_path(@VEXE)} version') == -1
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
	mut helper := process_singleton_start_hold_helper(lock_path)
	process_singleton_wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
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
	mut helper := process_singleton_start_hold_helper(lock_path)
	process_singleton_wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}

	res := process_singleton_execute('${os.quoted_path(@VEXE)} version')
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
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

fn process_singleton_hold_gate(lock_path string) !process_singleton.Guard {
	return process_singleton.acquire_with_options(
		name:      'vtest'
		lock_path: lock_path
		wait_ms:   100
	)
}

fn process_singleton_start_hold_helper(lock_path string) &os.Process {
	mut p := os.new_process(os.executable())
	mut env := os.environ()
	env[process_singleton_helper_mode_env] = 'hold'
	env[process_singleton_helper_lock_env] = lock_path
	p.set_environment(env)
	p.set_redirect_stdio()
	p.run()
	return p
}

fn process_singleton_wait_for_helper(mut p os.Process) {
	mut output := ''
	for _ in 0 .. 50 {
		if p.is_pending(.stdout) {
			output += p.stdout_read()
			if output.contains('locked') {
				return
			}
		}
		if !p.is_alive() {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	p.wait()
	stderr := p.stderr_slurp().trim_space()
	assert false, os.process_exit_code_diagnostics(p.code, '0',
		label:  @FN
		stdout: output
		stderr: stderr
	)
}
