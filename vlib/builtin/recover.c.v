module builtin

#include "@VEXEROOT/vlib/builtin/v_recover.h"

fn C.v_recover_setjmp() int
fn C.v_recover_is_active() int
fn C.v_recover_clear()

@[noreturn]
fn C.v_recover_longjmp()

// g_recover_msg holds the message of the most recently recovered panic.
__global g_recover_msg = ''

// recover_call runs `cb` and returns true if it completed normally, or false if it panicked
// (array index out of range, integer divide by zero, an explicit panic(), an unhandled
// option/result, etc.). On a panic the process is NOT aborted: control returns here with
// false, and recover_message() holds the panic text. This lets a host run many independent
// units of work (plugins / solvers / per-task jobs) where any one may fault, without a single
// fault killing the whole process.
//
// Limits: not re-entrant (one shared jmp_buf — do not nest recover_call inside recover_call);
// a recovered panic skips deferred statements and manual frees on the unwound frames, so run
// it with the GC enabled (the default) where leaked allocations are reclaimed; assumes a
// single-translation-unit build (V default).
pub fn recover_call(cb fn ()) bool {
	if C.v_recover_setjmp() == 0 {
		cb()
		C.v_recover_clear()
		return true
	}
	C.v_recover_clear()
	return false
}

// recover_message returns the text of the most recently recovered panic ('' if none yet).
pub fn recover_message() string {
	return g_recover_msg
}

// recover_active reports whether execution is currently inside a recover_call guard.
pub fn recover_active() bool {
	return C.v_recover_is_active() != 0
}
