// v_recover.h — minimal panic-recovery support for V.
// setjmp MUST appear textually in the frame that stays alive while the guarded code runs,
// so `v_recover_setjmp()` is a MACRO: V emits it inline inside builtin__recover_call(),
// keeping that frame valid for the longjmp back. The jmp_buf lives entirely in C to avoid
// V's array-typedef friction. Single-translation-unit build assumed (V default cc).
#ifndef V_RECOVER_H
#define V_RECOVER_H
#include <setjmp.h>

static jmp_buf v_recover_buf;
static int v_recover_active = 0;
static int v_recover_depth = 0;

// returns 0 on the initial setjmp, 1 when longjmp'd back from a panic.
#define v_recover_setjmp() (v_recover_active = 1, setjmp(v_recover_buf))

static inline int v_recover_is_active(void) { return v_recover_active; }
static inline void v_recover_clear(void) { v_recover_active = 0; }
static inline void v_recover_longjmp(void) {
	v_recover_active = 0;
	longjmp(v_recover_buf, 1);
}
#endif
