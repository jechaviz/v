module util

import os
import os.filelock
import time

fn test_process_gate_default_lock_dir_is_shared_across_sessions() {
	old_lock_dir := os.getenv(process_gate_lock_dir_env)
	defer {
		process_gate_restore_env(process_gate_lock_dir_env, old_lock_dir)
	}
	os.unsetenv(process_gate_lock_dir_env)

	assert process_gate_lock_dir() == os.join_path(os.temp_dir(), 'v_process_gate')
	assert !process_gate_lock_dir().starts_with(os.vtmp_dir())
}

fn test_process_gate_disabled_returns_inactive_guard() {
	old_mode := os.getenv(process_gate_env)
	defer {
		process_gate_restore_env(process_gate_env, old_mode)
	}
	os.setenv(process_gate_env, '0', true)

	mut gate := acquire_process_gate(phase: 'test')!
	defer {
		gate.release()
	}
	assert !gate.held
	assert gate.slot == -1
}

fn test_process_gate_held_env_keeps_nested_processes_reentrant() {
	old_mode := os.getenv(process_gate_env)
	old_held := os.getenv(process_gate_held_env)
	defer {
		process_gate_restore_env(process_gate_env, old_mode)
		process_gate_restore_env(process_gate_held_env, old_held)
	}
	os.setenv(process_gate_env, '1', true)
	os.setenv(process_gate_held_env, '1', true)

	mut gate := acquire_process_gate(phase: 'nested')!
	defer {
		gate.release()
	}
	assert !gate.held
	assert gate.slot == -1
}

fn test_process_gate_busy_slot_reports_timeout() {
	lock_dir := os.join_path(os.vtmp_dir(), 'process_gate_test_${os.getpid()}')
	os.rmdir_all(lock_dir) or {}
	os.mkdir_all(lock_dir)!
	old_mode := os.getenv(process_gate_env)
	old_slots := os.getenv(process_gate_slots_env)
	old_wait := os.getenv(process_gate_wait_env)
	old_lock_dir := os.getenv(process_gate_lock_dir_env)
	old_held := os.getenv(process_gate_held_env)
	old_reserve_ram := os.getenv(process_gate_reserve_ram_mb_env)
	old_reserve_virtual := os.getenv(process_gate_reserve_virtual_mb_env)
	defer {
		process_gate_restore_env(process_gate_env, old_mode)
		process_gate_restore_env(process_gate_slots_env, old_slots)
		process_gate_restore_env(process_gate_wait_env, old_wait)
		process_gate_restore_env(process_gate_lock_dir_env, old_lock_dir)
		process_gate_restore_env(process_gate_held_env, old_held)
		process_gate_restore_env(process_gate_reserve_ram_mb_env, old_reserve_ram)
		process_gate_restore_env(process_gate_reserve_virtual_mb_env, old_reserve_virtual)
		os.rmdir_all(lock_dir) or {}
	}

	os.setenv(process_gate_env, '1', true)
	os.setenv(process_gate_slots_env, '1', true)
	os.setenv(process_gate_wait_env, '25', true)
	os.setenv(process_gate_lock_dir_env, lock_dir, true)
	os.setenv(process_gate_reserve_ram_mb_env, '1', true)
	os.setenv(process_gate_reserve_virtual_mb_env, '1', true)
	os.unsetenv(process_gate_held_env)
	lock_path := os.join_path(lock_dir, 'v_process_gate_0.lock')
	mut held_gate := filelock.new(lock_path)
	assert held_gate.wait_acquire(100 * time.millisecond)
	defer {
		held_gate.release()
	}

	acquire_process_gate(phase: 'busy', path: 'x.v') or {
		assert err.msg().contains('timed out after 25ms'), err.msg()
		assert err.msg().contains(lock_path), err.msg()
		return
	}
	assert false
}

fn test_process_gate_slot_math_keeps_at_least_one_slot() {
	assert process_gate_headroom(u64(10) * process_gate_bytes_per_mib,
		u64(20) * process_gate_bytes_per_mib) == 0
	assert process_gate_slots_for_headroom(0, u64(4) * process_gate_bytes_per_mib) == 1
	assert process_gate_slots_for_headroom(u64(9) * process_gate_bytes_per_mib,
		u64(4) * process_gate_bytes_per_mib) == 2
}
