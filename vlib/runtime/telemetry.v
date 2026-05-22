module runtime

import os
import time

pub enum MemoryPressure {
	unknown
	normal
	pressure
	critical
}

pub enum BackpressureAction {
	unknown
	run
	throttle
	serial
	pause
}

const default_memory_target_percent = 70
const default_memory_warn_percent = 85
const default_memory_hard_percent = 95
const default_memory_sleep_ms = 25
const default_memory_max_sleep_ms = 1000

pub struct HostTelemetry {
pub:
	os_name                    string
	arch                       string
	logical_cpus               int
	total_memory_bytes         u64
	free_memory_bytes          u64
	used_memory_bytes          u64
	memory_complete            bool
	total_virtual_memory_bytes u64
	free_virtual_memory_bytes  u64
	used_virtual_memory_bytes  u64
	available_memory_bytes     u64
	virtual_memory_complete    bool
	disk_path                  string
	disk_total_bytes           u64
	disk_free_bytes            u64
	disk_used_bytes            u64
	disk_complete              bool
	sampled_unix_ms            i64
}

pub struct ResourceBudget {
pub:
	max_memory_bytes u64
	reserve_percent  int
	max_jobs         int
}

pub struct ResourceDecision {
pub:
	target_memory_bytes u64
	used_memory_bytes   u64
	free_memory_bytes   u64
	pressure            MemoryPressure
	within_budget       bool
	suggested_jobs      int
}

pub struct MemoryBackpressurePolicy {
pub:
	max_memory_bytes  u64
	job_reserve_bytes u64
	target_percent    int
	warn_percent      int
	hard_percent      int
	min_jobs          int
	max_jobs          int
	base_sleep_ms     int
	max_sleep_ms      int
}

pub struct MemoryBackpressureDecision {
pub:
	observed_memory_bytes u64
	target_memory_bytes   u64
	warn_memory_bytes     u64
	hard_memory_bytes     u64
	free_memory_bytes     u64
	headroom_bytes        u64
	headroom_jobs         int
	pressure              MemoryPressure
	action                BackpressureAction
	within_budget         bool
	should_collect        bool
	should_defer_new_work bool
	recommended_jobs      int
	sleep_ms              int
}

pub struct PerformanceSample {
pub:
	label             string
	elapsed_ms        i64
	used_memory_bytes u64
	free_memory_bytes u64
	disk_free_bytes   u64
	logical_cpus      int
}

pub struct MetricGate {
pub:
	metric    string
	baseline  i64
	candidate i64
	ratio     f64
	pass      bool
}

pub fn collect_host_telemetry(path string) HostTelemetry {
	total_memory, total_ok := read_total_memory()
	free_memory, free_ok := read_free_memory()
	used_memory, used_ok := read_used_memory()
	total_virtual, total_virtual_ok := read_total_virtual_memory()
	free_virtual, free_virtual_ok := read_free_virtual_memory()
	disk_path := telemetry_disk_path(path)
	disk, disk_ok := read_disk_usage(disk_path)
	return HostTelemetry{
		os_name:                    os.user_os()
		arch:                       host_arch()
		logical_cpus:               nr_cpus()
		total_memory_bytes:         total_memory
		free_memory_bytes:          free_memory
		used_memory_bytes:          used_memory
		memory_complete:            total_ok && free_ok && used_ok
		total_virtual_memory_bytes: total_virtual
		free_virtual_memory_bytes:  free_virtual
		used_virtual_memory_bytes:  used_virtual_memory(total_virtual, free_virtual)
		available_memory_bytes:     available_memory(free_memory, free_virtual)
		virtual_memory_complete:    total_virtual_ok && free_virtual_ok
		disk_path:                  disk_path
		disk_total_bytes:           disk.total
		disk_free_bytes:            disk.available
		disk_used_bytes:            disk.used
		disk_complete:              disk_ok
		sampled_unix_ms:            time.now().unix_milli()
	}
}

pub fn decide_resource_budget(snapshot HostTelemetry, budget ResourceBudget) ResourceDecision {
	max_memory := if budget.max_memory_bytes > 0 {
		budget.max_memory_bytes
	} else {
		snapshot.total_memory_bytes
	}
	reserve := clamp_percent(budget.reserve_percent)
	reserve_bytes := max_memory * u64(reserve) / 100
	target := if max_memory > reserve_bytes { max_memory - reserve_bytes } else { max_memory }
	pressure := classify_memory_pressure(snapshot.used_memory_bytes, target, max_memory)
	mut jobs := suggested_jobs_for_pressure(pressure, budget.max_jobs)
	if jobs < 1 {
		jobs = 1
	}
	return ResourceDecision{
		target_memory_bytes: target
		used_memory_bytes:   snapshot.used_memory_bytes
		free_memory_bytes:   snapshot.free_memory_bytes
		pressure:            pressure
		within_budget:       target == 0 || snapshot.used_memory_bytes <= target
		suggested_jobs:      jobs
	}
}

pub fn decide_memory_backpressure(used_bytes u64, free_bytes u64, policy MemoryBackpressurePolicy) MemoryBackpressureDecision {
	target := memory_target_bytes(policy)
	warn := memory_warn_bytes(policy)
	hard := memory_hard_bytes(policy)
	used_pressure := classify_memory_backpressure(used_bytes, warn, hard)
	free_pressure := classify_free_memory_backpressure(free_bytes, warn, hard,
		policy.max_memory_bytes)
	pressure := strongest_memory_pressure(used_pressure, free_pressure)
	action := backpressure_action_for(pressure)
	headroom := memory_effective_headroom(used_bytes, free_bytes, hard, policy.max_memory_bytes)
	headroom_jobs := memory_headroom_jobs(headroom, policy)
	return MemoryBackpressureDecision{
		observed_memory_bytes: used_bytes
		target_memory_bytes:   target
		warn_memory_bytes:     warn
		hard_memory_bytes:     hard
		free_memory_bytes:     free_bytes
		headroom_bytes:        headroom
		headroom_jobs:         headroom_jobs
		pressure:              pressure
		action:                action
		within_budget:         (hard == 0 || used_bytes < hard) && free_pressure != .critical
		should_collect:        target > 0 && used_bytes >= target
		should_defer_new_work: action == .serial || action == .pause
		recommended_jobs:      memory_jobs_for_pressure(used_bytes, warn, hard, pressure,
			headroom_jobs, policy)
		sleep_ms:              memory_sleep_ms_for_pressure(used_bytes, warn, hard, pressure,
			policy)
	}
}

pub fn decide_runtime_backpressure(snapshot HostTelemetry, policy MemoryBackpressurePolicy) MemoryBackpressureDecision {
	max_memory := runtime_backpressure_max_memory(snapshot, policy)
	effective_policy := if policy.max_memory_bytes > 0 {
		policy
	} else {
		MemoryBackpressurePolicy{
			...policy
			max_memory_bytes: max_memory
		}
	}
	return decide_memory_backpressure(snapshot.used_memory_bytes,
		runtime_available_memory(snapshot), effective_policy)
}

pub fn performance_sample(label string, started_unix_ms i64, snapshot HostTelemetry) PerformanceSample {
	now := time.now().unix_milli()
	return PerformanceSample{
		label:             label
		elapsed_ms:        normalized_duration_ms(started_unix_ms, now)
		used_memory_bytes: snapshot.used_memory_bytes
		free_memory_bytes: snapshot.free_memory_bytes
		disk_free_bytes:   snapshot.disk_free_bytes
		logical_cpus:      snapshot.logical_cpus
	}
}

pub fn lower_is_better_gate(metric string, baseline i64, candidate i64, min_ratio f64) MetricGate {
	if baseline <= 0 || candidate <= 0 {
		return MetricGate{
			metric:    metric
			baseline:  baseline
			candidate: candidate
		}
	}
	target := if min_ratio > 0 { min_ratio } else { 2.0 }
	ratio := f64(baseline) / f64(candidate)
	return MetricGate{
		metric:    metric
		baseline:  baseline
		candidate: candidate
		ratio:     ratio
		pass:      ratio >= target
	}
}

pub fn (snapshot HostTelemetry) report() string {
	return [
		'runtime.telemetry.os=${snapshot.os_name}',
		'runtime.telemetry.arch=${snapshot.arch}',
		'runtime.telemetry.cpus=${snapshot.logical_cpus}',
		'runtime.telemetry.memory.total_bytes=${snapshot.total_memory_bytes}',
		'runtime.telemetry.memory.free_bytes=${snapshot.free_memory_bytes}',
		'runtime.telemetry.memory.used_bytes=${snapshot.used_memory_bytes}',
		'runtime.telemetry.memory.complete=${snapshot.memory_complete}',
		'runtime.telemetry.virtual_memory.total_bytes=${snapshot.total_virtual_memory_bytes}',
		'runtime.telemetry.virtual_memory.free_bytes=${snapshot.free_virtual_memory_bytes}',
		'runtime.telemetry.virtual_memory.used_bytes=${snapshot.used_virtual_memory_bytes}',
		'runtime.telemetry.memory.available_bytes=${runtime_available_memory(snapshot)}',
		'runtime.telemetry.virtual_memory.complete=${snapshot.virtual_memory_complete}',
		'runtime.telemetry.disk.path=${snapshot.disk_path}',
		'runtime.telemetry.disk.total_bytes=${snapshot.disk_total_bytes}',
		'runtime.telemetry.disk.free_bytes=${snapshot.disk_free_bytes}',
		'runtime.telemetry.disk.used_bytes=${snapshot.disk_used_bytes}',
		'runtime.telemetry.disk.complete=${snapshot.disk_complete}',
	].join('\n')
}

pub fn (decision ResourceDecision) report() string {
	return [
		'runtime.budget.target_memory_bytes=${decision.target_memory_bytes}',
		'runtime.budget.used_memory_bytes=${decision.used_memory_bytes}',
		'runtime.budget.free_memory_bytes=${decision.free_memory_bytes}',
		'runtime.budget.pressure=${decision.pressure}',
		'runtime.budget.within=${decision.within_budget}',
		'runtime.budget.suggested_jobs=${decision.suggested_jobs}',
	].join('\n')
}

pub fn (decision MemoryBackpressureDecision) report() string {
	return [
		'runtime.backpressure.memory.used_bytes=${decision.observed_memory_bytes}',
		'runtime.backpressure.memory.target_bytes=${decision.target_memory_bytes}',
		'runtime.backpressure.memory.warn_bytes=${decision.warn_memory_bytes}',
		'runtime.backpressure.memory.hard_bytes=${decision.hard_memory_bytes}',
		'runtime.backpressure.memory.free_bytes=${decision.free_memory_bytes}',
		'runtime.backpressure.memory.headroom_bytes=${decision.headroom_bytes}',
		'runtime.backpressure.memory.headroom_jobs=${decision.headroom_jobs}',
		'runtime.backpressure.pressure=${decision.pressure}',
		'runtime.backpressure.action=${decision.action}',
		'runtime.backpressure.within=${decision.within_budget}',
		'runtime.backpressure.should_collect=${decision.should_collect}',
		'runtime.backpressure.should_defer_new_work=${decision.should_defer_new_work}',
		'runtime.backpressure.recommended_jobs=${decision.recommended_jobs}',
		'runtime.backpressure.sleep_ms=${decision.sleep_ms}',
	].join('\n')
}

pub fn (sample PerformanceSample) report() string {
	return [
		'runtime.sample.label=${sample.label}',
		'runtime.sample.elapsed_ms=${sample.elapsed_ms}',
		'runtime.sample.memory.used_bytes=${sample.used_memory_bytes}',
		'runtime.sample.memory.free_bytes=${sample.free_memory_bytes}',
		'runtime.sample.disk.free_bytes=${sample.disk_free_bytes}',
		'runtime.sample.cpus=${sample.logical_cpus}',
	].join('\n')
}

pub fn classify_memory_pressure(used u64, target u64, max_memory u64) MemoryPressure {
	if used == 0 || target == 0 || max_memory == 0 {
		return .unknown
	}
	if used >= max_memory || used * 100 >= max_memory * 95 {
		return .critical
	}
	if used >= target || used * 100 >= target * 90 {
		return .pressure
	}
	return .normal
}

fn classify_memory_backpressure(used u64, warn u64, hard u64) MemoryPressure {
	if used == 0 || warn == 0 || hard == 0 {
		return .unknown
	}
	if used >= hard {
		return .critical
	}
	if used >= warn {
		return .pressure
	}
	return .normal
}

fn backpressure_action_for(pressure MemoryPressure) BackpressureAction {
	match pressure {
		.critical { return .pause }
		.pressure { return .throttle }
		.normal { return .run }
		.unknown { return .unknown }
	}
}

fn memory_target_bytes(policy MemoryBackpressurePolicy) u64 {
	return percent_of(policy.max_memory_bytes, normalized_memory_target_percent(policy))
}

fn memory_warn_bytes(policy MemoryBackpressurePolicy) u64 {
	return percent_of(policy.max_memory_bytes, normalized_memory_warn_percent(policy))
}

fn memory_hard_bytes(policy MemoryBackpressurePolicy) u64 {
	return percent_of(policy.max_memory_bytes, normalized_memory_hard_percent(policy))
}

fn normalized_memory_target_percent(policy MemoryBackpressurePolicy) int {
	warn := normalized_memory_warn_percent(policy)
	target := if policy.target_percent > 0 {
		policy.target_percent
	} else {
		default_memory_target_percent
	}
	return clamp_int(target, 1, warn)
}

fn normalized_memory_warn_percent(policy MemoryBackpressurePolicy) int {
	hard := normalized_memory_hard_percent(policy)
	warn := if policy.warn_percent > 0 {
		policy.warn_percent
	} else {
		default_memory_warn_percent
	}
	return clamp_int(warn, 1, hard)
}

fn normalized_memory_hard_percent(policy MemoryBackpressurePolicy) int {
	hard := if policy.hard_percent > 0 {
		policy.hard_percent
	} else {
		default_memory_hard_percent
	}
	return clamp_int(hard, 1, 100)
}

fn memory_jobs_for_pressure(used u64, warn u64, hard u64, pressure MemoryPressure, headroom_jobs int, policy MemoryBackpressurePolicy) int {
	min_jobs := normalized_memory_min_jobs(policy)
	max_jobs := normalized_memory_max_jobs(policy)
	pressure_jobs := match pressure {
		.critical {
			min_jobs
		}
		.pressure {
			if max_jobs <= min_jobs {
				max_jobs
			} else if hard <= warn || used <= warn {
				clamp_int(max_jobs - 1, min_jobs, max_jobs)
			} else {
				span := hard - warn
				over := min_u64(used - warn, span)
				reducible_jobs := max_jobs - min_jobs
				mut reduction := int(u64(reducible_jobs) * over / span)
				if reduction < 1 {
					reduction = 1
				}
				clamp_int(max_jobs - reduction, min_jobs, max_jobs)
			}
		}
		.normal {
			max_jobs
		}
		.unknown {
			max_jobs
		}
	}

	if headroom_jobs <= 0 {
		return pressure_jobs
	}
	return clamp_int(min_int(pressure_jobs, headroom_jobs), min_jobs, max_jobs)
}

fn memory_headroom_jobs(headroom u64, policy MemoryBackpressurePolicy) int {
	max_jobs := normalized_memory_max_jobs(policy)
	if policy.job_reserve_bytes == 0 || headroom == 0 {
		return max_jobs
	}
	jobs := int(headroom / policy.job_reserve_bytes)
	return clamp_int(jobs, 1, max_jobs)
}

fn memory_sleep_ms_for_pressure(used u64, warn u64, hard u64, pressure MemoryPressure, policy MemoryBackpressurePolicy) int {
	if pressure == .unknown || pressure == .normal {
		return 0
	}
	max_sleep := normalized_memory_max_sleep_ms(policy)
	base := clamp_int(if policy.base_sleep_ms > 0 {
		policy.base_sleep_ms
	} else {
		default_memory_sleep_ms
	}, 1, max_sleep)
	if pressure == .critical {
		return max_sleep
	}
	if hard <= warn || used <= warn {
		return base
	}
	span := hard - warn
	over := min_u64(used - warn, span)
	scaled := base + int(u64(max_sleep - base) * over / span)
	return clamp_int(scaled, base, max_sleep)
}

fn normalized_memory_min_jobs(policy MemoryBackpressurePolicy) int {
	return clamp_int(if policy.min_jobs > 0 { policy.min_jobs } else { 1 }, 1,
		normalized_memory_max_jobs(policy))
}

fn normalized_memory_max_jobs(policy MemoryBackpressurePolicy) int {
	if policy.max_jobs > 0 {
		return clamp_int(policy.max_jobs, 1, 1024)
	}
	return nr_jobs()
}

fn normalized_memory_max_sleep_ms(policy MemoryBackpressurePolicy) int {
	return clamp_int(if policy.max_sleep_ms > 0 {
		policy.max_sleep_ms
	} else {
		default_memory_max_sleep_ms
	}, 1, 60000)
}

fn memory_headroom(used u64, hard u64) u64 {
	if hard == 0 || used >= hard {
		return 0
	}
	return hard - used
}

fn percent_of(value u64, percent int) u64 {
	if value == 0 {
		return 0
	}
	return value * u64(percent) / 100
}

fn suggested_jobs_for_pressure(pressure MemoryPressure, max_jobs int) int {
	base := if max_jobs > 0 { min_int(nr_jobs(), max_jobs) } else { nr_jobs() }
	match pressure {
		.critical { return 1 }
		.pressure { return max_int(1, base / 2) }
		else { return base }
	}
}

fn read_total_memory() (u64, bool) {
	value := total_memory() or { return 0, false }
	return u64(value), value > 0
}

fn read_free_memory() (u64, bool) {
	value := free_memory() or { return 0, false }
	return u64(value), true
}

fn read_total_virtual_memory() (u64, bool) {
	value := total_virtual_memory() or { return 0, false }
	return u64(value), value > 0
}

fn read_free_virtual_memory() (u64, bool) {
	value := free_virtual_memory() or { return 0, false }
	return u64(value), true
}

fn read_used_memory() (u64, bool) {
	value := used_memory() or { return 0, false }
	return value, value > 0
}

fn read_disk_usage(path string) (os.DiskUsage, bool) {
	usage := os.disk_usage(path) or { return os.DiskUsage{}, false }
	return usage, usage.total > 0
}

fn telemetry_disk_path(path string) string {
	if path.trim_space() == '' {
		return os.getwd()
	}
	return path
}

fn host_arch() string {
	env_arch := os.getenv('PROCESSOR_ARCHITECTURE')
	if env_arch != '' {
		return env_arch
	}
	return os.uname().machine
}

fn normalized_duration_ms(started_ms i64, finished_ms i64) i64 {
	if finished_ms <= started_ms {
		return 1
	}
	return finished_ms - started_ms
}

fn clamp_percent(value int) int {
	if value < 0 {
		return 0
	}
	if value > 90 {
		return 90
	}
	return value
}

fn clamp_int(value int, min_value int, max_value int) int {
	if value < min_value {
		return min_value
	}
	if value > max_value {
		return max_value
	}
	return value
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

fn min_u64(a u64, b u64) u64 {
	return if a < b { a } else { b }
}
