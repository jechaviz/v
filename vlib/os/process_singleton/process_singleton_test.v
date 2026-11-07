module process_singleton

import os
import time

const helper_mode_env = 'V_PROCESS_SINGLETON_TEST_MODE'
const helper_name_env = 'V_PROCESS_SINGLETON_TEST_NAME'
const helper_path_env = 'V_PROCESS_SINGLETON_TEST_PATH'
const helper_wait_env = 'V_PROCESS_SINGLETON_TEST_WAIT_MS'

fn testsuite_begin() {
	if os.getenv(helper_mode_env) != '' {
		run_helper_process()
	}
}

fn run_helper_process() {
	mode := os.getenv(helper_mode_env)
	name := os.getenv(helper_name_env)
	path := os.getenv(helper_path_env)
	wait_ms := os.getenv(helper_wait_env).int()
	match mode {
		'hold' {
			mut guard := acquire_with_options(name: name, lock_path: path, wait_ms: wait_ms) or {
				eprintln(err.msg())
				exit(2)
			}
			println('locked')
			os.flush()
			time.sleep(500 * time.millisecond)
			guard.release()
			exit(0)
		}
		'try' {
			mut guard := acquire_with_options(name: name, lock_path: path, wait_ms: wait_ms) or {
				exit(1)
			}
			guard.release()
			exit(0)
		}
		else {
			exit(3)
		}
	}
}

fn test_default_lock_path_sanitizes_names() {
	path := default_lock_path('v app:main/process')
	assert path.ends_with(os.join_path('process_singleton', 'v_app_main_process.lock'))
}

fn test_acquire_blocks_second_instance() {
	lock_path := singleton_test_lock_path('blocks_second')
	cleanup_lock(lock_path)
	defer {
		cleanup_lock(lock_path)
	}
	mut helper := new_helper_process('test-singleton', lock_path, 100, 'hold')
	helper.run()
	wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}
	assert try_acquire_from_helper('test-singleton', lock_path, 0) == 1
}

fn test_release_allows_reacquire() {
	lock_path := singleton_test_lock_path('reacquire')
	cleanup_lock(lock_path)
	defer {
		cleanup_lock(lock_path)
	}
	mut first := acquire_with_options(name: 'test-singleton', lock_path: lock_path)!
	assert first.release()
	mut second := acquire_with_options(name: 'test-singleton', lock_path: lock_path)!
	defer {
		second.release()
	}
	assert second.path == lock_path
}

fn test_windows_mutex_does_not_create_lock_file_artifact() {
	$if !windows {
		return
	}
	lock_path := singleton_test_lock_path('no_lock_file')
	cleanup_lock(lock_path)
	defer {
		cleanup_lock(lock_path)
	}
	mut guard := acquire_with_options(name: 'test-singleton', lock_path: lock_path)!
	defer {
		guard.release()
	}
	assert guard.path == lock_path
	assert !os.exists(lock_path)
}

fn test_wait_timeout_reports_busy_instance() {
	lock_path := singleton_test_lock_path('wait_timeout')
	cleanup_lock(lock_path)
	defer {
		cleanup_lock(lock_path)
	}
	mut helper := new_helper_process('test-singleton', lock_path, 100, 'hold')
	helper.run()
	wait_for_helper(mut helper)
	defer {
		helper.wait()
		assert helper.stderr_slurp().trim_space() == ''
		assert helper.code == 0, os.process_exit_code_diagnostics(helper.code, '0', label: @FN)
		helper.close()
	}
	assert try_acquire_from_helper('test-singleton', lock_path, 5) == 1
}

fn test_lock_path_is_required_when_name_is_empty() {
	acquire_with_options(name: ' ') or {
		assert err.msg().contains('cannot be empty')
		return
	}
	assert false
}

fn singleton_test_lock_path(tag string) string {
	return os.join_path(os.vtmp_dir(), 'process_singleton_tests', '${tag}_${os.getpid()}.lock')
}

fn cleanup_lock(path string) {
	if os.exists(path) {
		os.rm(path) or {}
	}
}

fn new_helper_process(name string, lock_path string, wait_ms int, mode string) &os.Process {
	mut p := os.new_process(os.executable())
	mut env := os.environ()
	env[helper_mode_env] = mode
	env[helper_name_env] = name
	env[helper_path_env] = lock_path
	env[helper_wait_env] = wait_ms.str()
	p.set_environment(env)
	p.set_redirect_stdio()
	return p
}

fn wait_for_helper(mut p os.Process) {
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

fn try_acquire_from_helper(name string, lock_path string, wait_ms int) int {
	mut p := new_helper_process(name, lock_path, wait_ms, 'try')
	p.run()
	p.wait()
	stderr := p.stderr_slurp().trim_space()
	code := p.code
	p.close()
	assert stderr == ''
	return code
}
