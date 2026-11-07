@[has_globals]
module trace_calls

import sync

@[markused]
__global g_stack_base &u8

// These are set before _vinit; runtime initializers would reset the trace.
@[markused]
__global g_start_time u64

@[markused]
__global g_value_mutex &sync.Mutex

@[markused]
__global g_last_values map[string]string

fn init() {
	g_value_mutex = sync.new_mutex()
	g_last_values = map[string]string{}
}

@[markused]
pub fn on_call(fname string) {
	mut volatile pfbase := &u8(unsafe { nil })
	volatile fbase := u8(0)
	ns := current_time() - g_start_time
	mut ssize := u64(0)
	mut tid := u32(0)
	unsafe {
		$if windows {
			tid = C.GetCurrentThreadId()
		} $else $if no_gettid ? {
			tid = u32(C.pthread_self())
		} $else $if linux && !musl ? {
			tid = C.gettid()
		} $else {
			tid = u32(C.pthread_self())
		}
		pfbase = &fbase
		ssize = u64(g_stack_base) - u64(pfbase)
	}
	$if x64 {
		C.fprintf(C.stderr, c'> trace %8u %8ld %8ld %s\n', tid, ns, ssize, fname.str)
	} $else {
		C.fprintf(C.stderr, c'> trace %8u %8lld %8lld %s\n', tid, ns, ssize, fname.str)
	}
	C.fflush(C.stderr)
}

// on_line writes an executed V source statement to stderr.
@[markused]
pub fn on_line(file string, line string, source string, fname string) {
	ns := current_time() - g_start_time
	tid := current_thread_id()
	$if x64 {
		C.fprintf(C.stderr, c'> snoop %8u %8ld %s:%s %s | %s\n', tid, ns, file.str,
			line.str, fname.str, source.str)
	} $else {
		C.fprintf(C.stderr, c'> snoop %8u %8lld %s:%s %s | %s\n', tid, ns, file.str,
			line.str, fname.str, source.str)
	}
	C.fflush(C.stderr)
}

// on_value logs first observations and changes to compiler-captured locals.
@[markused]
pub fn on_value(name string, value string) {
	tid := current_thread_id()
	key := '${tid}:${name}'
	g_value_mutex.lock()
	defer {
		g_value_mutex.unlock()
	}
	if previous := g_last_values[key] {
		if previous == value {
			return
		}
		C.fprintf(C.stderr, c'> value %8u %s: %s -> %s\n', tid, name.str,
			limited_debug_value(previous).str, limited_debug_value(value).str)
	} else {
		C.fprintf(C.stderr, c'> value %8u %s = %s\n', tid, name.str,
			limited_debug_value(value).str)
	}
	g_last_values[key] = value
	C.fflush(C.stderr)
}

fn current_thread_id() u32 {
	mut tid := u32(0)
	unsafe {
		$if windows {
			tid = C.GetCurrentThreadId()
		} $else $if no_gettid ? {
			tid = u32(C.pthread_self())
		} $else $if linux && !musl ? {
			tid = C.gettid()
		} $else {
			tid = u32(C.pthread_self())
		}
	}
	return tid
}

fn limited_debug_value(value string) string {
	runes := value.runes()
	if runes.len > 500 {
		return runes[..500].string() + '…'
	}
	return value
}

@[inline]
fn current_time() u64 {
	unsafe {
		$if windows {
			tm := u64(0)
			C.QueryPerformanceCounter(&tm)
			return tm
		} $else {
			ts := C.timespec{}
			C.clock_gettime(C.CLOCK_MONOTONIC, &ts)
			return u64(ts.tv_sec) * 1000000000 + u64(ts.tv_nsec)
		}
	}
}

@[markused]
pub fn on_c_main(should_trace_c_main bool) {
	g_start_time = current_time()
	//                    > trace  2128896   714640    28148 fn
	C.fprintf(C.stderr, c'#          tid       ns      ssize name\n')
	C.fflush(C.stderr)
	if should_trace_c_main {
		on_call('C.main')
	}
}
