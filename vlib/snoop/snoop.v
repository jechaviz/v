module snoop

import os
import json2
import sync
import time

// OutputFormat selects the representation of each trace event.
pub enum OutputFormat {
	text
	jsonl
}

// Config controls the output and size of values recorded by a Tracer.
pub struct Config {
pub:
	output_path          string
	prefix               string = 'SNOOP'
	max_value_length     int    = 500
	output_format        OutputFormat
	append_output        bool
	record_unchanged     bool
	progress_interval_ms i64 = 250
}

// Tracer records explicit execution points and changes to watched values.
@[heap]
pub struct Tracer {
	config Config
mut:
	output          os.File
	owns_output     bool
	closed          bool
	started_at      i64
	sequence        u64
	mutex           &sync.Mutex = sync.new_mutex()
	last_values     map[string]string
	progress_states map[string]ProgressState
}

// new creates a tracer that writes to stderr.
pub fn new() &Tracer {
	return new_with_config(Config{}) or { panic(err) }
}

// new_file creates a tracer that truncates and writes the configured file.
pub fn new_file(output_path string) !&Tracer {
	return new_with_config(Config{
		output_path: output_path
	})
}

// new_with_config creates a tracer with custom output and value limits.
pub fn new_with_config(config Config) !&Tracer {
	mut output := if config.output_path == '' {
		os.stderr()
	} else if config.append_output {
		os.open_append(config.output_path)!
	} else {
		os.create(config.output_path)!
	}
	return &Tracer{
		config:      config
		output:      output
		owns_output: config.output_path != ''
		started_at:  time.now().unix_micro()
	}
}

// line writes a source location and optional description to the trace.
// Pass @FILE and @LINE at the call site to capture its location.
pub fn (mut t Tracer) line(file string, line_number string, source string) {
	location := if file == '' { '<unknown>' } else { file }
	description := source.replace('\n', ' ').replace('\r', ' ').trim_space()
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return
	}
	message := if description == '' {
		'${location}:${line_number}'
	} else {
		'${location}:${line_number}: ${description}'
	}
	t.emit_locked('line', message, location, line_number, description, '', '', '', false, false)
}

// watch records the first value and later changes for name, returning no
// output when the rendered value has not changed.
pub fn (mut t Tracer) watch[T](name string, value T) T {
	current := t.limit_value('${value}')
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return value
	}
	if previous := t.last_values[name] {
		if previous == current {
			if t.config.record_unchanged {
				t.emit_locked('watch', '${name} = ${current}', '', '', '', name, previous,
					current, false, false)
			}
			return value
		}
		t.emit_locked('watch', '${name}: ${previous} -> ${current}', '', '', '', name,
			previous, current, true, false)
	} else {
		t.emit_locked('watch', '${name} = ${current}', '', '', '', name, '', current, true,
			true)
	}
	t.last_values[name] = current
	return value
}

// watch_fields records all fields of a struct under a shared name prefix.
// It uses V's compile-time field iteration, so each field is rendered directly.
pub fn (mut t Tracer) watch_fields[T](name string, value T) {
	$if T is $struct {
		$for field in T.fields {
			t.watch('${name}.${field.name}', value.$(field.name))
		}
	} $else {
		$compile_error('snoop.watch_fields requires a struct value')
	}
}

// reset_forget clears remembered values so the next watch call records them
// as first observations.
pub fn (mut t Tracer) reset_forget() {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	t.last_values.clear()
}

// close closes the output file when the tracer owns it. Calls after close are
// ignored.
pub fn (mut t Tracer) close() {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	if t.closed {
		return
	}
	if t.owns_output {
		t.output.close()
	}
	t.closed = true
}

fn (t &Tracer) limit_value(value string) string {
	limit := t.config.max_value_length
	if limit > 0 {
		runes := value.runes()
		if runes.len > limit {
			return runes[..limit].string() + '…'
		}
	}
	return value
}

fn (mut t Tracer) emit_locked(kind string, message string, file string, line string, source string,
	name string, previous string, value string, changed bool, first bool) {
	t.sequence++
	elapsed_us := time.now().unix_micro() - t.started_at
	prefix := if t.config.prefix == '' { 'SNOOP' } else { t.config.prefix }
	output_line := if t.config.output_format == .jsonl {
		'{"seq":${t.sequence},"elapsed_us":${elapsed_us},"kind":${json2.encode(kind)},"file":${json2.encode(file)},"line":${json2.encode(line)},"source":${json2.encode(source)},"name":${json2.encode(name)},"previous":${json2.encode(previous)},"value":${json2.encode(value)},"changed":${changed},"first":${first}}'
	} else {
		'${prefix} +${elapsed_us}us ${message}'
	}
	_ := t.output.writeln(output_line) or {
		eprintln('${prefix}: could not write trace output')
		return
	}
}
