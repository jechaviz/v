module snoop

import json2
import runtime
import time

// ProgressState stores bounded profile-mode state for one named phase.
struct ProgressState {
mut:
	started_us   i64
	last_emit_us i64
	completed    i64
	total        i64
	detail       string
}

// phase_start records the beginning of a named unit of work. Profile events
// are flushed immediately so a separate process monitor can detect a stall.
pub fn (mut t Tracer) phase_start(name string, total i64, detail string) {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return
	}
	now_us := time.now().unix_micro()
	state := ProgressState{
		started_us:   now_us
		last_emit_us: now_us
		total:        total
		detail:       detail
	}
	t.progress_states[name] = state
	t.emit_profile_locked('phase_start', name, 0, total, 0, detail, true)
}

// progress records the latest count while writing at most one heartbeat per
// progress_interval_ms, plus the initial and terminal events. A zero total
// means that work is unbounded or its final count is not known in advance.
pub fn (mut t Tracer) progress(name string, completed i64, total i64, detail string) {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return
	}
	now_us := time.now().unix_micro()
	mut state := t.progress_states[name] or {
		ProgressState{
			started_us: now_us
			total:      total
		}
	}
	if state.started_us == 0 {
		state.started_us = now_us
	}
	finished := total > 0 && completed >= total
	interval_us := t.config.progress_interval_ms * 1000
	should_emit := state.last_emit_us == 0 || interval_us <= 0
		|| now_us - state.last_emit_us >= interval_us || finished
	if should_emit {
		t.emit_profile_locked('progress', name, completed, total, now_us - state.started_us,
			detail, state.last_emit_us == 0)
		state.last_emit_us = now_us
	}
	state.completed = completed
	state.total = total
	state.detail = detail
	t.progress_states[name] = state
}

// phase_end writes a final summary and duration for a named phase.
pub fn (mut t Tracer) phase_end(name string, detail string) {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return
	}
	now_us := time.now().unix_micro()
	state := t.progress_states[name] or {
		ProgressState{
			started_us: now_us
		}
	}
	t.emit_profile_locked('phase_end', name, state.completed, state.total,
		now_us - state.started_us, if detail == '' { state.detail } else { detail }, false)
	t.progress_states.delete(name)
}

fn (mut t Tracer) emit_profile_locked(kind string, name string, completed i64, total i64,
	phase_elapsed_us i64, detail string, first bool) {
	t.sequence++
	timestamp_us := time.now().unix_micro()
	elapsed_us := timestamp_us - t.started_at
	memory_bytes := runtime.used_memory() or { u64(0) }
	prefix := if t.config.prefix == '' { 'SNOOP' } else { t.config.prefix }
	message := '${name} ${completed}/${total} +${phase_elapsed_us}us memory=${memory_bytes}B ${detail}'.trim_space()
	output_line := if t.config.output_format == .jsonl {
		'{"seq":${t.sequence},"timestamp_us":${timestamp_us},"elapsed_us":${elapsed_us},"kind":${json2.encode(kind)},"name":${json2.encode(name)},"completed":${completed},"total":${total},"phase_elapsed_us":${phase_elapsed_us},"memory_bytes":${memory_bytes},"detail":${json2.encode(detail)},"first":${first}}'
	} else {
		'${prefix} +${elapsed_us}us ${kind}: ${message}'
	}
	_ := t.output.writeln(output_line) or {
		eprintln('${prefix}: could not write profile output')
		return
	}
	t.output.flush()
}
