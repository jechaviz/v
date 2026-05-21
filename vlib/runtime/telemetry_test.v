module runtime

fn test_classify_memory_pressure() {
	assert classify_memory_pressure(10, 100, 200) == .normal
	assert classify_memory_pressure(95, 100, 200) == .pressure
	assert classify_memory_pressure(195, 100, 200) == .critical
	assert classify_memory_pressure(0, 100, 200) == .unknown
}

fn test_decide_resource_budget_reduces_jobs_under_pressure() {
	snapshot := HostTelemetry{
		logical_cpus:       8
		total_memory_bytes: 1000
		free_memory_bytes:  100
		used_memory_bytes:  920
		memory_complete:    true
	}
	decision := decide_resource_budget(snapshot, ResourceBudget{
		max_memory_bytes: 1000
		reserve_percent:  10
		max_jobs:         8
	})
	assert decision.pressure == .pressure
	assert !decision.within_budget
	assert decision.suggested_jobs >= 1
	assert decision.suggested_jobs <= 4
	assert decision.report().contains('runtime.budget.pressure=pressure')
}

fn test_decide_resource_budget_detects_critical_pressure() {
	snapshot := HostTelemetry{
		total_memory_bytes: 1000
		free_memory_bytes:  10
		used_memory_bytes:  990
		memory_complete:    true
	}
	decision := decide_resource_budget(snapshot, ResourceBudget{
		max_memory_bytes: 1000
		max_jobs:         16
	})
	assert decision.pressure == .critical
	assert decision.suggested_jobs == 1
}

fn test_decide_memory_backpressure_throttles_before_hard_limit() {
	decision := decide_memory_backpressure(900, 100, MemoryBackpressurePolicy{
		max_memory_bytes: 1000
		target_percent:   70
		warn_percent:     80
		hard_percent:     95
		min_jobs:         2
		max_jobs:         10
		base_sleep_ms:    20
		max_sleep_ms:     200
	})
	assert decision.pressure == .pressure
	assert decision.action == .throttle
	assert decision.within_budget
	assert decision.should_collect
	assert !decision.should_defer_new_work
	assert decision.recommended_jobs == 5
	assert decision.sleep_ms > 20
	assert decision.sleep_ms < 200
	assert decision.headroom_bytes == 50
	assert decision.report().contains('runtime.backpressure.action=throttle')
}

fn test_decide_memory_backpressure_pauses_at_hard_limit() {
	decision := decide_memory_backpressure(960, 40, MemoryBackpressurePolicy{
		max_memory_bytes: 1000
		warn_percent:     80
		hard_percent:     95
		min_jobs:         3
		max_jobs:         12
		base_sleep_ms:    50
		max_sleep_ms:     120
	})
	assert decision.pressure == .critical
	assert decision.action == .pause
	assert !decision.within_budget
	assert decision.should_collect
	assert decision.should_defer_new_work
	assert decision.recommended_jobs == 3
	assert decision.sleep_ms == 120
	assert decision.headroom_bytes == 0
}

fn test_decide_runtime_backpressure_uses_total_memory_as_default_limit() {
	snapshot := HostTelemetry{
		total_memory_bytes: 1000
		free_memory_bytes:  100
		used_memory_bytes:  900
	}
	decision := decide_runtime_backpressure(snapshot, MemoryBackpressurePolicy{
		warn_percent: 80
		hard_percent: 95
		max_jobs:     8
	})
	assert decision.hard_memory_bytes == 950
	assert decision.pressure == .pressure
	assert decision.recommended_jobs == 4
}

fn test_lower_is_better_gate() {
	pass := lower_is_better_gate('elapsed_ms', 200, 50, 2.0)
	assert pass.pass
	assert pass.ratio == 4.0

	fail := lower_is_better_gate('elapsed_ms', 200, 150, 2.0)
	assert !fail.pass
}

fn test_collect_host_telemetry_report_shape() {
	snapshot := collect_host_telemetry('.')
	report := snapshot.report()
	assert snapshot.logical_cpus > 0
	assert report.contains('runtime.telemetry.cpus=')
	assert report.contains('runtime.telemetry.memory.')
	assert report.contains('runtime.telemetry.disk.')
}
