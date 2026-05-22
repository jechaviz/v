module util

import os
import os.filelock
import runtime
import time

const process_gate_env = 'V_PROCESS_GATE'
const process_gate_slots_env = 'V_PROCESS_GATE_SLOTS'
const process_gate_max_slots_env = 'V_PROCESS_GATE_MAX_SLOTS'
const process_gate_wait_env = 'V_PROCESS_GATE_WAIT_MS'
const process_gate_lock_dir_env = 'V_PROCESS_GATE_LOCK_DIR'
const process_gate_held_env = 'V_PROCESS_GATE_HELD'
const process_gate_trace_env = 'V_PROCESS_GATE_TRACE'
const process_gate_ram_per_slot_mb_env = 'V_PROCESS_GATE_RAM_PER_SLOT_MB'
const process_gate_virtual_per_slot_mb_env = 'V_PROCESS_GATE_VIRTUAL_PER_SLOT_MB'
const process_gate_reserve_ram_mb_env = 'V_PROCESS_GATE_RESERVE_RAM_MB'
const process_gate_reserve_virtual_mb_env = 'V_PROCESS_GATE_RESERVE_VIRTUAL_MB'
const process_gate_default_wait_ms = 600_000
const process_gate_bytes_per_mib = u64(1024 * 1024)
const process_gate_default_ram_per_slot_mb = 4096
const process_gate_default_virtual_per_slot_mb = 16384
const process_gate_default_reserve_ram_mb = 4096
const process_gate_default_reserve_virtual_mb = 16384
const process_gate_default_max_slots = 4

@[params]
pub struct ProcessGateConfig {
pub:
	phase    string
	path     string
	out_name string
}

pub struct ProcessGate {
pub:
	path string
	slot int
pub mut:
	held bool
mut:
	gate     filelock.FileLock
	old_held string
}

pub fn acquire_process_gate(config ProcessGateConfig) !ProcessGate {
	if !process_gate_enabled() || os.getenv(process_gate_held_env) == '1' {
		return ProcessGate{
			slot: -1
			gate: filelock.new('')
		}
	}
	slots := process_gate_slots()
	wait_ms := process_gate_wait_ms()
	lock_dir := process_gate_lock_dir()
	os.mkdir_all(lock_dir) or {
		return error('could not create V process gate lock directory `${lock_dir}`: ${err}')
	}
	deadline := time.now().add(wait_ms * time.millisecond)
	mut last_path := ''
	for time.now() < deadline {
		for slot in 0 .. slots {
			lock_path := os.join_path(lock_dir, 'v_process_gate_${slot}.lock')
			mut gate := filelock.new(lock_path)
			if gate.try_acquire() {
				old_held := os.getenv(process_gate_held_env)
				os.setenv(process_gate_held_env, '1', true)
				process_gate_trace('acquired slot=${slot} path=${lock_path} ${config.phase} ${config.path} ${config.out_name}')
				return ProcessGate{
					path:     lock_path
					slot:     slot
					held:     true
					gate:     gate
					old_held: old_held
				}
			}
			last_path = lock_path
		}
		time.sleep(25 * time.millisecond)
	}
	return error('timed out after ${wait_ms}ms waiting for V process gate (${slots} slot(s)); last lock `${last_path}`')
}

pub fn (mut gate ProcessGate) release() bool {
	if !gate.held {
		return false
	}
	gate.held = false
	process_gate_restore_env(process_gate_held_env, gate.old_held)
	process_gate_trace('released slot=${gate.slot} path=${gate.path}')
	return gate.gate.release()
}

fn process_gate_enabled() bool {
	mode := os.getenv(process_gate_env).trim_space().to_lower()
	if mode in ['0', 'false', 'off', 'no', 'disabled'] {
		return false
	}
	if mode in ['1', 'true', 'on', 'yes', 'always', 'enabled', 'adaptive'] {
		return true
	}
	return os.user_os() == 'windows'
}

fn process_gate_slots() int {
	env_slots := os.getenv(process_gate_slots_env).trim_space().int()
	if env_slots > 0 {
		return env_slots
	}
	if os.user_os() != 'windows' {
		return 1
	}
	snapshot := runtime.collect_host_telemetry(os.getwd())
	ram_headroom := process_gate_headroom(snapshot.free_memory_bytes, process_gate_env_mb(process_gate_reserve_ram_mb_env,
		process_gate_default_reserve_ram_mb))
	virtual_headroom := process_gate_headroom(snapshot.free_virtual_memory_bytes, process_gate_env_mb(process_gate_reserve_virtual_mb_env,
		process_gate_default_reserve_virtual_mb))
	ram_slots := process_gate_slots_for_headroom(ram_headroom, process_gate_env_mb(process_gate_ram_per_slot_mb_env,
		process_gate_default_ram_per_slot_mb))
	virtual_slots := process_gate_slots_for_headroom(virtual_headroom, process_gate_env_mb(process_gate_virtual_per_slot_mb_env,
		process_gate_default_virtual_per_slot_mb))
	resource_slots := int_min(ram_slots, virtual_slots)
	max_slots := process_gate_env_int(process_gate_max_slots_env, process_gate_default_max_slots)
	return int_max(1, int_min(resource_slots, max_slots))
}

fn process_gate_wait_ms() int {
	return process_gate_env_int(process_gate_wait_env, process_gate_default_wait_ms)
}

fn process_gate_lock_dir() string {
	env_dir := os.getenv(process_gate_lock_dir_env).trim_space()
	if env_dir != '' {
		return os.norm_path(env_dir)
	}
	return os.join_path(os.vtmp_dir(), 'v_process_gate')
}

fn process_gate_restore_env(name string, value string) {
	if value == '' {
		os.unsetenv(name)
		return
	}
	os.setenv(name, value, true)
}

fn process_gate_trace(message string) {
	if os.getenv(process_gate_trace_env) == '1' {
		eprintln('v.process_gate: ${message}')
	}
}

fn process_gate_headroom(free_bytes u64, reserve_bytes u64) u64 {
	if free_bytes <= reserve_bytes {
		return 0
	}
	return free_bytes - reserve_bytes
}

fn process_gate_slots_for_headroom(headroom_bytes u64, bytes_per_slot u64) int {
	if bytes_per_slot == 0 {
		return 1
	}
	slots := int(headroom_bytes / bytes_per_slot)
	return int_max(1, slots)
}

fn process_gate_env_mb(name string, fallback int) u64 {
	value := process_gate_env_int(name, fallback)
	return u64(value) * process_gate_bytes_per_mib
}

fn process_gate_env_int(name string, fallback int) int {
	value := os.getenv(name).trim_space().int()
	if value <= 0 {
		return fallback
	}
	return value
}
