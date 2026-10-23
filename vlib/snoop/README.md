# Snoop-style tracing for V

`snoop` combines automatic source tracing with explicit value watches. The
compiler's `-snoop` option logs executed statements, source text, function names,
function entries, and changed local values. Use `-trace-fns` to limit the output:

```sh
./v -snoop run main.v
./v -snoop -trace-fns 'main.calculate,math.*' run main.v
```

Tracing uses the C backend and writes to stderr. It adds work to every traced
statement, so filter large applications to the functions being investigated.
Values are sampled after statements and capped at 500 characters in the output.

## Watch values

Use `watch` to record a value the first time and when its rendered value
changes. It returns the value unchanged, so it can wrap an expression:

```v
import snoop

fn calculate() {
	mut trace := snoop.new()
	defer {
		trace.close()
	}

	mut total := 0
	total = trace.watch('calculate.total', total + 3)
	total = trace.watch('calculate.total', total * 2)
}
```

`watch_fields` uses V's compile-time field iteration to record every field of
a struct in one call:

```v
import snoop

struct State {
pub mut:
	count int
	label string
}

fn inspect(mut trace snoop.Tracer, state State) {
	trace.watch_fields('worker.state', state)
}
```

Use a qualified name such as `worker.state` when multiple functions or
goroutines share one tracer. Output writes and remembered values are protected
by a mutex.

## Output

By default, the library writes to stderr. `new_file` starts a fresh log file.
For custom labels, truncation limits, unchanged-value events, or machine-readable
JSON Lines, create a tracer with `new_with_config`:

```v
import snoop

mut trace := snoop.new_with_config(snoop.Config{
	output_path:      'trace.jsonl'
	prefix:           'DEBUG'
	max_value_length: 200
	output_format:    .jsonl
	record_unchanged: false
}) or { panic(err) }
```

JSONL records have a sequence number and elapsed time. `Tracer.line` events
include the file, line, and source description. Watch events include the name,
current value, previous value, and whether the value changed. String values
are JSON escaped.

## Bounded progress profiling

Long-running pipelines can emit phase and progress events without tracing every
statement. Events are flushed as they are written; progress is throttled by
`progress_interval_ms` (250 ms by default), with the initial and final event
always recorded:

```v
mut trace := snoop.new_with_config(snoop.Config{
	output_path:          'profile.jsonl'
	output_format:        .jsonl
	progress_interval_ms: 250
}) or { panic(err) }
defer {
	trace.close()
}

trace.phase_start('lift', 0, 'function=fu904 blocks=160')
trace.progress('lift', 640, 0, 'block=b41 queue=12')
trace.phase_end('lift', 'visits=912 elapsed details are in the event stream')
```

`total: 0` marks work whose total is unknown, such as a CFG worklist with loop
revisits. JSONL progress events expose `completed`, `total`, phase elapsed time,
and the latest detail as separate fields. This mode suits expensive compiler,
decompiler, and backtest phases: it reports useful heartbeats without emitting
one record per instruction or statement.

The runtime API can also mark a selected point with
`trace.line(@FILE, @LINE, 'description')`, or observe selected values with
`watch` and `watch_fields` without enabling compiler-wide tracing.
