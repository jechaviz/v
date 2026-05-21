module util

import os
import runtime

const memory_backpressure_bytes_per_kib = u64(1024)
const memory_backpressure_bytes_per_mib = u64(1024 * 1024)
const memory_backpressure_bytes_per_gib = u64(1024 * 1024 * 1024)

pub fn memory_backpressure_jobs(_phase string, requested_jobs int) int {
	max_jobs := if requested_jobs > 0 { requested_jobs } else { runtime.nr_jobs() }
	if max_jobs <= 1 || !memory_backpressure_enabled() {
		return max_jobs
	}
	mode := memory_backpressure_mode()
	if mode == 'warn' {
		return max_jobs
	}
	snapshot := runtime.collect_host_telemetry(os.getwd())
	policy := memory_backpressure_policy(max_jobs)
	decision := runtime.decide_runtime_backpressure(snapshot, policy)
	return memory_backpressure_jobs_for_decision(mode, decision, policy, max_jobs)
}

pub fn memory_backpressure_decision(max_jobs int) runtime.MemoryBackpressureDecision {
	snapshot := runtime.collect_host_telemetry(os.getwd())
	return runtime.decide_runtime_backpressure(snapshot, memory_backpressure_policy(max_jobs))
}

pub fn memory_backpressure_policy(max_jobs int) runtime.MemoryBackpressurePolicy {
	return runtime.MemoryBackpressurePolicy{
		max_memory_bytes: memory_backpressure_limit_from_env()
		target_percent:   memory_backpressure_env_int('VMEM_TARGET_PERCENT',
			runtime_default_memory_target_percent())
		warn_percent:     memory_backpressure_env_int('VMEM_WARN_PERCENT',
			runtime_default_memory_warn_percent())
		hard_percent:     memory_backpressure_env_int('VMEM_HARD_PERCENT',
			runtime_default_memory_hard_percent())
		min_jobs:         memory_backpressure_env_int('VMEM_MIN_JOBS', 1)
		max_jobs:         max_jobs
		base_sleep_ms:    memory_backpressure_env_int('VMEM_BASE_SLEEP_MS', 25)
		max_sleep_ms:     memory_backpressure_env_int('VMEM_MAX_SLEEP_MS', 1000)
	}
}

pub fn memory_backpressure_enabled() bool {
	mode := memory_backpressure_mode()
	if mode in ['off', '0', 'false', 'no', 'disabled'] {
		return false
	}
	if mode in ['on', '1', 'true', 'yes', 'adaptive', 'strict', 'warn'] {
		return true
	}
	if memory_backpressure_limit_from_env() > 0 {
		return true
	}
	return os.user_os() == 'windows'
}

fn memory_backpressure_mode() string {
	return os.getenv('VMEM_BACKPRESSURE').trim_space().to_lower()
}

fn memory_backpressure_limit_from_env() u64 {
	limit_bytes := os.getenv('VMEM_LIMIT_BYTES').trim_space()
	if limit_bytes != '' {
		return parse_memory_backpressure_size(limit_bytes)
	}
	limit := os.getenv('VMEM_LIMIT').trim_space()
	if limit != '' {
		return parse_memory_backpressure_size(limit)
	}
	limit_mb := os.getenv('VMEM_LIMIT_MB').trim_space()
	if limit_mb != '' {
		return parse_memory_backpressure_size(limit_mb + 'm')
	}
	return 0
}

fn parse_memory_backpressure_size(raw string) u64 {
	mut text := raw.trim_space().to_lower().replace('_', '')
	if text == '' {
		return 0
	}
	mut multiplier := u64(1)
	if text.ends_with('kib') {
		text = text[..text.len - 3]
		multiplier = memory_backpressure_bytes_per_kib
	} else if text.ends_with('kb') {
		text = text[..text.len - 2]
		multiplier = memory_backpressure_bytes_per_kib
	} else if text.ends_with('k') {
		text = text[..text.len - 1]
		multiplier = memory_backpressure_bytes_per_kib
	} else if text.ends_with('mib') {
		text = text[..text.len - 3]
		multiplier = memory_backpressure_bytes_per_mib
	} else if text.ends_with('mb') {
		text = text[..text.len - 2]
		multiplier = memory_backpressure_bytes_per_mib
	} else if text.ends_with('m') {
		text = text[..text.len - 1]
		multiplier = memory_backpressure_bytes_per_mib
	} else if text.ends_with('gib') {
		text = text[..text.len - 3]
		multiplier = memory_backpressure_bytes_per_gib
	} else if text.ends_with('gb') {
		text = text[..text.len - 2]
		multiplier = memory_backpressure_bytes_per_gib
	} else if text.ends_with('g') {
		text = text[..text.len - 1]
		multiplier = memory_backpressure_bytes_per_gib
	}
	value := text.u64()
	if value == 0 {
		return 0
	}
	if multiplier > 1 && value > max_u64 / multiplier {
		return max_u64
	}
	return value * multiplier
}

fn memory_backpressure_jobs_for_decision(mode string, decision runtime.MemoryBackpressureDecision, policy runtime.MemoryBackpressurePolicy, max_jobs int) int {
	if decision.pressure == .unknown {
		return max_jobs
	}
	if mode == 'strict' && (decision.pressure == .pressure || decision.pressure == .critical) {
		return clamp_memory_jobs(policy.min_jobs, 1, max_jobs)
	}
	return clamp_memory_jobs(decision.recommended_jobs, 1, max_jobs)
}

fn memory_backpressure_env_int(name string, fallback int) int {
	value := os.getenv(name).trim_space().int()
	if value <= 0 {
		return fallback
	}
	return value
}

fn runtime_default_memory_target_percent() int {
	return 70
}

fn runtime_default_memory_warn_percent() int {
	return 85
}

fn runtime_default_memory_hard_percent() int {
	return 95
}

fn clamp_memory_jobs(value int, min_value int, max_value int) int {
	if value < min_value {
		return min_value
	}
	if value > max_value {
		return max_value
	}
	return value
}
