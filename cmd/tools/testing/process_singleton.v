module testing

import os
import os.process_singleton

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
	mut gate := process_singleton_acquire_for_command(cmd) or {
		return os.Result{
			exit_code: -1
			output:    os.process_command_failure_report('vtest.process.execute', -1,
				stage:          'acquire_process_singleton'
				command:        cmd
				reason:         'process_singleton_acquire_failed'
				action:         'inspect_process_singleton_lock_or_disable_singleton'
				message:        'could not acquire process singleton before running command'
				stderr:         err.msg()
				output_capture: 'not_started'
			)
		}
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	defer {
		gate.release()
		process_singleton_restore_env(process_singleton_held_env, old_held)
	}
	return os.execute(cmd)
}

fn process_singleton_exec_args(args []string, cmd string) os.Result {
	if args.len == 0 {
		return os.Result{
			exit_code: -1
			output:    os.process_command_failure_report('vtest.process.exec', -1,
				stage:          'validate_command_arguments'
				command:        cmd
				reason:         'empty_command_arguments'
				action:         'provide_executable_and_arguments'
				message:        'cannot execute an empty argument list'
				output_capture: 'not_started'
			)
		}
	}
	if !process_singleton_enabled() || process_singleton_held() {
		return os.exec(args)
	}
	mut gate := process_singleton_acquire_for_command(cmd) or {
		return os.Result{
			exit_code: -1
			output:    os.process_command_failure_report('vtest.process.exec', -1,
				stage:          'acquire_process_singleton'
				command:        cmd
				reason:         'process_singleton_acquire_failed'
				action:         'inspect_process_singleton_lock_or_disable_singleton'
				message:        'could not acquire process singleton before running command'
				stderr:         err.msg()
				output_capture: 'not_started'
			)
		}
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	defer {
		gate.release()
		process_singleton_restore_env(process_singleton_held_env, old_held)
	}
	return os.exec(args)
}

fn process_singleton_system(cmd string) int {
	if !process_singleton_enabled() || process_singleton_held() {
		return os.system(cmd)
	}
	mut gate := process_singleton_acquire_for_command(cmd) or {
		eprintln(os.process_command_failure_report('vtest.process.system', -1,
			stage:          'acquire_process_singleton'
			command:        cmd
			reason:         'process_singleton_acquire_failed'
			action:         'inspect_process_singleton_lock_or_disable_singleton'
			message:        'could not acquire process singleton before running command'
			stderr:         err.msg()
			output_capture: 'not_started'
		))
		return -1
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	defer {
		gate.release()
		process_singleton_restore_env(process_singleton_held_env, old_held)
	}
	return os.system(cmd)
}

fn process_singleton_system_args(args []string, cmd string) int {
	if args.len == 0 {
		eprintln(os.process_command_failure_report('vtest.process.system', -1,
			stage:          'validate_command_arguments'
			command:        cmd
			reason:         'empty_command_arguments'
			action:         'provide_executable_and_arguments'
			message:        'cannot execute an empty argument list'
			output_capture: 'not_started'
		))
		return -1
	}
	if !process_singleton_enabled() || process_singleton_held() {
		return os.system_args(args)
	}
	mut gate := process_singleton_acquire_for_command(cmd) or {
		eprintln(os.process_command_failure_report('vtest.process.system', -1,
			stage:          'acquire_process_singleton'
			command:        cmd
			reason:         'process_singleton_acquire_failed'
			action:         'inspect_process_singleton_lock_or_disable_singleton'
			message:        'could not acquire process singleton before running command'
			stderr:         err.msg()
			output_capture: 'not_started'
		))
		return -1
	}
	old_held := os.getenv(process_singleton_held_env)
	os.setenv(process_singleton_held_env, '1', true)
	defer {
		gate.release()
		process_singleton_restore_env(process_singleton_held_env, old_held)
	}
	return os.system_args(args)
}

fn process_singleton_held() bool {
	return os.getenv(process_singleton_held_env) == '1'
}

fn process_singleton_acquire() !process_singleton.Guard {
	lock_path := process_singleton_lock_path()
	wait_ms := process_singleton_wait_ms()
	return process_singleton.acquire_with_options(
		name:      'vtest'
		lock_path: lock_path
		wait_ms:   wait_ms
	) or {
		error('timed out after ${wait_ms}ms waiting for V test process singleton ${lock_path}: ${err}')
	}
}

fn process_singleton_acquire_for_command(cmd string) !process_singleton.Guard {
	lock_path := process_singleton_lock_path()
	mut guard := process_singleton.acquire_with_options(
		name:      'vtest'
		lock_path: lock_path
		wait_ms:   0
	) or {
		wait_ms := process_singleton_wait_ms()
		eprintln(process_singleton_queue_wait_message(cmd, lock_path, wait_ms))
		guard_after_wait := process_singleton.acquire_with_options(
			name:      'vtest'
			lock_path: lock_path
			wait_ms:   wait_ms
		) or { return error(process_singleton_queue_timeout_message(cmd, lock_path, wait_ms)) }
		eprintln(process_singleton_queue_start_message(cmd, lock_path))
		return guard_after_wait
	}
	return guard
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

fn process_singleton_queue_wait_message(cmd string, lock_path string, wait_ms int) string {
	return [
		'vtest.process.queue=waiting',
		'vtest.process.reason=process_instance_queue_busy',
		'vtest.process.action=wait_for_singleton_turn',
		'vtest.process.queue_message=otra instancia de V/VTest esta activa o cerrandose; esta ejecucion queda formada y no arrancara hasta obtener turno',
		'vtest.process.message=Another V/VTest instance is active; this command is queued until the singleton lock is available.',
		'vtest.process.queue_timeout_ms=${wait_ms}',
		'vtest.process.lock_path=${lock_path}',
		'vtest.process.command=${cmd}',
		'vtest.process.advice=No lance instancias simultaneas salvo que el flujo declare explicitamente VTEST_PROCESS_SINGLETON=0 y tenga diseno seguro para concurrencia.',
	].join('\n')
}

fn process_singleton_queue_start_message(cmd string, lock_path string) string {
	return [
		'vtest.process.queue=starting',
		'vtest.process.reason=process_instance_queue_released',
		'vtest.process.action=start_queued_command',
		'vtest.process.queue_message=la instancia previa libero el turno; iniciando ahora',
		'vtest.process.message=The previous V/VTest instance released the singleton lock; starting this command now.',
		'vtest.process.lock_path=${lock_path}',
		'vtest.process.command=${cmd}',
	].join('\n')
}

fn process_singleton_queue_timeout_message(cmd string, lock_path string, wait_ms int) string {
	return [
		'vtest.process.queue=timeout',
		'vtest.process.reason=process-instance-queue-timeout',
		'vtest.process.action=abort_before_child_start',
		'vtest.process.message=V did not start another instance because the singleton queue timed out.',
		'vtest.process.exit_code=-1',
		'vtest.process.exit_code_meaning=${os.process_exit_code_meaning(-1)}',
		'vtest.process.queue_timeout_ms=${wait_ms}',
		'vtest.process.lock_path=${lock_path}',
		'vtest.process.command=${cmd}',
		'vtest.process.advice=No se lanzo otra instancia simultanea. Revise si la instancia previa esta colgada, reduzca paralelismo o use VTEST_PROCESS_SINGLETON=0 solo para flujos disenados para multiples instancias.',
	].join('\n')
}
