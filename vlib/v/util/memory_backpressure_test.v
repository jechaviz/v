module util

import os
import runtime

fn test_parse_memory_backpressure_size_accepts_common_units() {
	assert parse_memory_backpressure_size('1024') == 1024
	assert parse_memory_backpressure_size('2k') == 2 * memory_backpressure_bytes_per_kib
	assert parse_memory_backpressure_size('3MB') == 3 * memory_backpressure_bytes_per_mib
	assert parse_memory_backpressure_size('4_gib') == 4 * memory_backpressure_bytes_per_gib
}

fn test_parse_memory_backpressure_size_saturates_overflow() {
	assert parse_memory_backpressure_size('18446744073709551615g') == max_u64
}

fn test_memory_backpressure_limit_prefers_bytes_env() {
	with_memory_env({
		'VMEM_LIMIT_BYTES': '1234'
		'VMEM_LIMIT':       '8g'
		'VMEM_LIMIT_MB':    '64'
	}, fn () {
		assert memory_backpressure_limit_from_env() == 1234
	})
}

fn test_memory_backpressure_policy_uses_mb_env() {
	with_memory_env({
		'VMEM_LIMIT_MB': '64'
		'VMEM_MIN_JOBS': '2'
	}, fn () {
		policy := memory_backpressure_policy(8)
		assert policy.max_memory_bytes == 64 * memory_backpressure_bytes_per_mib
		assert policy.min_jobs == 2
		assert policy.max_jobs == 8
	})
}

fn test_memory_backpressure_jobs_can_be_disabled() {
	with_memory_env({
		'VMEM_BACKPRESSURE': 'off'
		'VMEM_LIMIT_MB':     '1'
	}, fn () {
		assert memory_backpressure_jobs('unit', 7) == 7
	})
}

fn test_memory_backpressure_plan_disabled_keeps_requested_jobs() {
	with_memory_env({
		'VMEM_BACKPRESSURE': 'off'
		'VMEM_LIMIT_MB':     '1'
	}, fn () {
		plan := memory_backpressure_plan('unit', 7)
		assert plan.phase == 'unit'
		assert plan.mode == 'off'
		assert plan.requested_jobs == 7
		assert plan.jobs == 7
		assert plan.sleep_ms == 0
		assert plan.decision.pressure == .unknown
	})
}

fn test_memory_backpressure_warn_samples_without_throttling() {
	with_memory_env({
		'VMEM_BACKPRESSURE': 'warn'
		'VMEM_LIMIT_MB':     '1'
	}, fn () {
		plan := memory_backpressure_plan('unit', 4)
		assert plan.mode == 'warn'
		assert plan.requested_jobs == 4
		assert plan.jobs == 4
		assert plan.sleep_ms == 0
		assert plan.report().contains('v.memory_backpressure.phase=unit')
		assert plan.report().contains('runtime.backpressure.')
	})
}

fn test_memory_backpressure_plan_with_jobs_rescopes_without_resampling() {
	plan := MemoryBackpressurePlan{
		phase:          'unit'
		requested_jobs: 8
		jobs:           6
		sleep_ms:       75
	}
	rescoped := memory_backpressure_plan_with_jobs(plan, 3)
	zero := memory_backpressure_plan_with_jobs(plan, 0)
	oversized := memory_backpressure_plan_with_jobs(plan, 16)
	assert rescoped.jobs == 3
	assert rescoped.sleep_ms == 75
	assert zero.jobs == 0
	assert oversized.jobs == 8
}

fn test_memory_backpressure_strict_uses_min_jobs_under_pressure() {
	decision := runtime.MemoryBackpressureDecision{
		pressure:         .pressure
		recommended_jobs: 6
	}
	policy := runtime.MemoryBackpressurePolicy{
		min_jobs: 2
	}
	assert memory_backpressure_jobs_for_decision('strict', decision, policy, 8) == 2
	assert memory_backpressure_jobs_for_decision('adaptive', decision, policy, 8) == 6
}

fn test_memory_backpressure_unknown_keeps_requested_jobs() {
	decision := runtime.MemoryBackpressureDecision{
		pressure:         .unknown
		recommended_jobs: 1
	}
	assert memory_backpressure_jobs_for_decision('adaptive', decision, runtime.MemoryBackpressurePolicy{},
		9) == 9
}

fn test_memory_backpressure_sleep_only_under_pressure() {
	normal := runtime.MemoryBackpressureDecision{
		pressure: .normal
		sleep_ms: 100
	}
	pressure := runtime.MemoryBackpressureDecision{
		pressure: .pressure
		sleep_ms: 75
	}
	critical := runtime.MemoryBackpressureDecision{
		pressure: .critical
		sleep_ms: 250
	}
	assert memory_backpressure_sleep_ms_for_decision('adaptive', normal) == 0
	assert memory_backpressure_sleep_ms_for_decision('warn', pressure) == 0
	assert memory_backpressure_sleep_ms_for_decision('adaptive', pressure) == 75
	assert memory_backpressure_sleep_ms_for_decision('strict', critical) == 250
}

fn with_memory_env(values map[string]string, body fn ()) {
	names := [
		'VMEM_BACKPRESSURE',
		'VMEM_LIMIT_BYTES',
		'VMEM_LIMIT',
		'VMEM_LIMIT_MB',
		'VMEM_TARGET_PERCENT',
		'VMEM_WARN_PERCENT',
		'VMEM_HARD_PERCENT',
		'VMEM_MIN_JOBS',
		'VMEM_BASE_SLEEP_MS',
		'VMEM_MAX_SLEEP_MS',
	]
	mut old := map[string]string{}
	for name in names {
		old[name] = os.getenv(name)
		os.unsetenv(name)
	}
	for name, value in values {
		os.setenv(name, value, true)
	}
	body()
	for name in names {
		if old[name] == '' {
			os.unsetenv(name)
		} else {
			os.setenv(name, old[name], true)
		}
	}
}
