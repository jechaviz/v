@[has_globals]
module builtin

$if windows {
	#define PSAPI_VERSION 2
	#include <windows.h>
	#include <psapi.h>

	@[typedef]
	struct C.PROCESS_MEMORY_COUNTERS {
		cb                         u32
		PageFaultCount             u32
		PeakWorkingSetSize         usize
		WorkingSetSize             usize
		QuotaPeakPagedPoolUsage    usize
		QuotaPagedPoolUsage        usize
		QuotaPeakNonPagedPoolUsage usize
		QuotaNonPagedPoolUsage     usize
		PagefileUsage              usize
		PeakPagefileUsage          usize
	}

	fn C.GetCurrentProcess() voidptr
	fn C.K32GetProcessMemoryInfo(voidptr, &C.PROCESS_MEMORY_COUNTERS, u32) bool
}

const auto_process_memory_guard_bytes_per_mib = u64(1024 * 1024)
const auto_process_memory_guard_default_limit_mb = 2048
const auto_process_memory_guard_default_sample_mb = 16
const auto_process_memory_guard_exit_code = 103

__global v_auto_process_memory_guard_configured = false
__global v_auto_process_memory_guard_enabled = false
__global v_auto_process_memory_guard_limit_bytes = u64(0)
__global v_auto_process_memory_guard_sample_bytes = u64(0)
// cumulative bytes of sub-sample allocations since the last used-bytes sample; lets many small
// allocations trigger a check before they can silently exhaust memory (see before_alloc).
__global v_auto_process_memory_guard_since_check = u64(0)

@[markused]
fn auto_process_memory_guard_init() {
	$if no_auto_process_memory_guard ? {
		v_auto_process_memory_guard_configured = true
		v_auto_process_memory_guard_enabled = false
		return
	}
	$if freestanding || vinix {
		v_auto_process_memory_guard_configured = true
		v_auto_process_memory_guard_enabled = false
		return
	}
	v_auto_process_memory_guard_configured = true
	if auto_process_memory_guard_env_off(c'V_PROCESS_MEMORY_GUARD')
		|| auto_process_memory_guard_env_off(c'V_AUTO_PROCESS_MEMORY_GUARD') {
		v_auto_process_memory_guard_enabled = false
		return
	}
	guard_requested := auto_process_memory_guard_env_on(c'V_PROCESS_MEMORY_GUARD')
		|| auto_process_memory_guard_env_on(c'V_AUTO_PROCESS_MEMORY_GUARD')
	mut limit_mb := auto_process_memory_guard_env_int(c'V_PROCESS_MEMORY_LIMIT_MB', 0)
	if limit_mb <= 0 && guard_requested {
		limit_mb = auto_process_memory_guard_default_limit_mb
	}
	if limit_mb <= 0 {
		v_auto_process_memory_guard_enabled = false
		return
	}
	sample_mb := auto_process_memory_guard_env_int(c'V_PROCESS_MEMORY_SAMPLE_MB',
		auto_process_memory_guard_default_sample_mb)
	v_auto_process_memory_guard_limit_bytes = u64(limit_mb) * auto_process_memory_guard_bytes_per_mib
	v_auto_process_memory_guard_sample_bytes = u64(if sample_mb <= 0 { 1 } else { sample_mb }) * auto_process_memory_guard_bytes_per_mib
	v_auto_process_memory_guard_enabled = true
}

fn auto_process_memory_guard_before_alloc(size isize) {
	$if no_auto_process_memory_guard ? {
		return
	}
	$if freestanding || vinix {
		return
	}
	if size <= 0 {
		return
	}
	if !v_auto_process_memory_guard_configured {
		auto_process_memory_guard_init()
	}
	if !v_auto_process_memory_guard_enabled {
		return
	}
	request_bytes := u64(size)
	limit := v_auto_process_memory_guard_limit_bytes
	if limit > 0 && request_bytes >= limit {
		auto_process_memory_guard_fail(0, limit, request_bytes)
	}
	if request_bytes < v_auto_process_memory_guard_sample_bytes {
		// Accumulate small allocations and only pay for the (costly) used-bytes sample once the
		// cumulative small-alloc volume crosses the sample threshold. Without this, a workload
		// made of many sub-sample allocations could exhaust memory unchecked.
		v_auto_process_memory_guard_since_check += request_bytes
		if v_auto_process_memory_guard_since_check < v_auto_process_memory_guard_sample_bytes {
			return
		}
		v_auto_process_memory_guard_since_check = 0
	}
	used := auto_process_memory_guard_used_bytes()
	if used == 0 || limit == 0 {
		return
	}
	if used >= limit || request_bytes >= limit - used {
		auto_process_memory_guard_fail(used, limit, request_bytes)
	}
}

fn auto_process_memory_guard_env_int(name &char, fallback int) int {
	value := C.getenv(name)
	if value == unsafe { nil } {
		return fallback
	}
	unsafe {
		mut p := &u8(value)
		for *p == ` ` || *p == `\t` {
			p++
		}
		mut sign := 1
		if *p == `-` {
			sign = -1
			p++
		} else if *p == `+` {
			p++
		}
		mut n := 0
		for *p >= `0` && *p <= `9` {
			n = n * 10 + int(*p - `0`)
			p++
		}
		return sign * n
	}
}

fn auto_process_memory_guard_env_off(name &char) bool {
	value := C.getenv(name)
	if value == unsafe { nil } {
		return false
	}
	first := unsafe { (&u8(value))[0] }
	if first == 0 {
		return false
	}
	if first == `0` || first == `f` || first == `F` || first == `n` || first == `N` || first == `u`
		|| first == `U` {
		return true
	}
	if first == `o` || first == `O` {
		second := unsafe { (&u8(value))[1] }
		return second == `f` || second == `F`
	}
	return false
}

fn auto_process_memory_guard_env_on(name &char) bool {
	value := C.getenv(name)
	if value == unsafe { nil } {
		return false
	}
	first := unsafe { (&u8(value))[0] }
	if first == 0 {
		return false
	}
	if first == `1` || first == `t` || first == `T` || first == `y` || first == `Y` || first == `e`
		|| first == `E` {
		return true
	}
	if first == `o` || first == `O` {
		second := unsafe { (&u8(value))[1] }
		return second == `n` || second == `N`
	}
	return false
}

fn auto_process_memory_guard_used_bytes() u64 {
	$if windows {
		mut pmc := C.PROCESS_MEMORY_COUNTERS{}
		pmc.cb = u32(sizeof(pmc))
		if C.K32GetProcessMemoryInfo(C.GetCurrentProcess(), &pmc, pmc.cb) {
			if pmc.PagefileUsage > 0 {
				return u64(pmc.PagefileUsage)
			}
			return u64(pmc.WorkingSetSize)
		}
		return 0
	} $else $if linux {
		buffer := [1024]u8{}
		mut pc := unsafe { &u8(&buffer[0]) }
		f := C.fopen(c'/proc/self/stat', c'r')
		if f == unsafe { nil } {
			return 0
		}
		read := C.fread(pc, 1, buffer.len, f)
		C.fclose(f)
		if read <= 0 {
			return 0
		}
		mut c := 0
		unsafe {
			for c < buffer.len && *pc != `)` {
				pc++
				c++
			}
			mut spaces := 0
			for c < buffer.len && spaces < 22 {
				if *pc == ` ` {
					spaces++
				}
				pc++
				c++
			}
			mut ndigits := 0
			for c < buffer.len && *(pc + ndigits) != ` ` {
				ndigits++
				c++
			}
			if ndigits <= 0 {
				return 0
			}
			mut rss_pages := u64(0)
			for i in 0 .. ndigits {
				ch := *(pc + i)
				if ch < `0` || ch > `9` {
					break
				}
				rss_pages = rss_pages * 10 + u64(ch - `0`)
			}
			page_size := C.sysconf(C._SC_PAGESIZE)
			if page_size <= 0 {
				return 0
			}
			return u64(rss_pages) * u64(page_size)
		}
	} $else {
		return 0
	}
}

@[noreturn]
fn auto_process_memory_guard_fail(used u64, limit u64, request u64) {
	v_memory_panic = true
	$if !freestanding {
		// If we are inside a recover_call() guard, the refused allocation is treated as a
		// recoverable fault: unwind to the guard (skipping the current unit of work) instead
		// of aborting the whole process. This hook runs BEFORE the real malloc, so no
		// allocator lock is held and no partial allocation exists — longjmp is safe here. The
		// message is a string literal (no heap allocation) so it is safe under memory pressure,
		// and we stay quiet (no stderr report) since the fault is being handled.
		if C.v_recover_is_active() != 0 {
			g_recover_msg = 'process memory guard: allocation refused before OOM (limit exceeded)'
			C.v_recover_longjmp()
		}
	}
	C.fprintf(C.stderr, c'v.memory_guard.failed=true\n')
	C.fprintf(C.stderr, c'v.memory_guard.reason=process_memory_limit\n')
	C.fprintf(C.stderr, c'v.memory_guard.action=abort_before_oom\n')
	C.fprintf(C.stderr,
		c'v.memory_guard.message=V auto process memory guard refused an allocation before the process could exhaust memory.\n')
	C.fprintf(C.stderr, c'v.memory_guard.used_bytes=%llu\n', used)
	C.fprintf(C.stderr, c'v.memory_guard.limit_bytes=%llu\n', limit)
	C.fprintf(C.stderr, c'v.memory_guard.request_bytes=%llu\n', request)
	C.fprintf(C.stderr, c'v.memory_guard.exit_code=%d\n', auto_process_memory_guard_exit_code)
	C.fprintf(C.stderr,
		c'v.memory_guard.advice=Redesign the workload to stream/chunk/reuse memory, or raise V_PROCESS_MEMORY_LIMIT_MB when the larger budget is intentional.\n')
	C.fprintf(C.stderr,
		c'v.memory_guard.override=Use V_PROCESS_MEMORY_GUARD=0 or -d no_auto_process_memory_guard only for trusted diagnostics.\n')
	C.exit(auto_process_memory_guard_exit_code)
}
