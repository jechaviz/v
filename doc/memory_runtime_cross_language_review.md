# Memory Runtime Cross-Language Review

This note keeps V's memory/runtime roadmap grounded in primary sources and
implementation evidence. It complements `doc/mojo_v_ownership_convergence.md`.

## Review Standard

Each external idea is treated as:

- source-backed: official docs, release notes, accepted proposals, or public
  compiler/runtime source
- scoped: what is actually implemented versus what is claimed
- portable: what can fit V without breaking source compatibility
- testable: what evidence V must produce before claiming improvement

## Executive Direction For V

V should not jump directly to a mandatory Rust-style borrow checker. The lower
risk, higher signal path is:

1. Observability first: allocation, scheduler, process-memory, channel/thread
   leak, and artifact-size metrics.
2. Compatibility-preserving memory wins: streaming writers, stack/escape
   diagnostics, adaptive jobs, allocator-aware APIs, and lightweight spans.
3. Opt-in ownership: Swift-like consume/borrow/no-copy for resources, then
   Polonius-like strict checking for advanced mode.
4. Better autofree: consume semantic facts from ownership/escape analysis rather
   than guessing in CGen only.

## Go

Primary sources:

- GC guide: https://go.dev/doc/gc-guide
- Runtime debug memory limit: https://go.dev/pkg/runtime/debug/#SetMemoryLimit
- Escape analysis source: https://go.dev/src/cmd/compile/internal/escape/escape.go
- Go 1.14 async preemption notes: https://go.dev/doc/go1.14
- Go 1.26 release notes: https://go.dev/doc/go1.26

Real implementation/design:

- Go has a soft memory limit through `GOMEMLIMIT` and `debug.SetMemoryLimit`.
  The limit guides GC behavior; it is not a hard process cap.
- Escape analysis decides stack versus heap placement by conservative data-flow.
- Recent Go work adds more GC/scheduler profiling and stack allocation cases.

Do not over-claim:

- GC overhead reductions apply mainly to GC-heavy workloads.
- A soft limit can trade memory for CPU and can thrash if set too low.
- Escape analysis is conservative and can move values to heap for safety.

V adaptation:

- Keep `VMEM_*` backpressure as soft policy, not kill switch.
- Add `-mem-report` style diagnostics: stack, heap, escaped, C-escaped,
  closure-captured, global-escaped.
- Add goroutine/thread/channel leak profile equivalent for `spawn` and channel
  ownership in long-running V apps.

Required tests:

- Allocation-pressure tests with expected job reduction.
- Escape diagnostics on returned refs, captured vars, global stores, and C
  interop.
- Scheduler leak fixtures for blocked workers and orphaned channels.

## PyPy

Primary sources:

- GC docs: https://doc.pypy.org/en/default/gc_info.html
- PyPy 7.3.18 release: https://doc.pypy.org/en/latest/release-v7.3.18.html
- PyPy blog/releases: https://pypy.org/blog/

Real implementation/design:

- PyPy's incminimark is incremental, generational, and moving.
- Young objects are allocated in a nursery using bump-pointer allocation; minor
  collections copy survivors to older generations.
- Recent PyPy releases reduce JIT memory and improve profiling visibility.

Do not over-claim:

- A moving nursery conflicts with raw pointers and C interop unless pinned or
  hidden behind handles.
- JIT wins do not apply directly to V's static compiler.

V adaptation:

- Use nursery/arena concepts only for managed/owned internal compiler data or
  explicit runtime modes.
- Add allocation sampling to V tooling before inventing large GC changes.
- Prefer V-native fast paths for JSON/artifact writing where data shape is known.

Required tests:

- Pinned/FFI object tests before any moving nursery.
- Allocation sampling fixtures with stable labels and negligible overhead.
- Pause-time and peak-memory reports.

## Rust

Primary sources:

- Rust 2024/1.85 notes: https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/
- Strict provenance notes: https://blog.rust-lang.org/2025/01/09/Rust-1.84.0/
- Edition guide: https://doc.rust-lang.org/edition-guide/rust-2024/
- Polonius status: https://rust-lang.github.io/polonius/current_status.html
- Polonius rules: https://rust-lang.github.io/polonius/rules.html

Real implementation/design:

- Rust's current borrow checker is production-grade; Polonius is provisionally
  integrated through nightly flags and is not yet the default.
- Strict provenance APIs make pointer reasoning more explicit.
- Async closures improve captures/borrowing expressiveness.

Do not over-claim:

- "Fearless concurrency" does not prevent deadlocks, starvation, or wrong
  protocols.
- A full Rust-style checker would be a semantic rewrite for V.

V adaptation:

- Add unsafe pointer provenance diagnostics and wrappers before changing pointer
  semantics.
- Build a small ownership IR: move, consume, borrow shared, borrow mut, drop,
  escape.
- Use Polonius-like analysis only in opt-in strict ownership mode after local
  ownership tests pass.

Required tests:

- Use-after-move, branch merge, loop, early return, field borrow, closure escape.
- Unsafe pointer null/provenance diagnostics.
- Compile-time regression budget for large codebases.

## Zig

Primary sources:

- Zig language reference, memory: https://ziglang.org/documentation/0.14.0/
- Zig 0.14 release notes: https://ziglang.org/download/0.14.0/release-notes.html
- Zig 0.15.1 release notes: https://ziglang.org/download/0.15.1/release-notes.html

Real implementation/design:

- Zig makes allocators explicit and treats `error.OutOfMemory` as normal control
  flow.
- 0.14 replaces `GeneralPurposeAllocator` with `DebugAllocator`, adds
  `SmpAllocator`, `Allocator.remap`, and pushes unmanaged containers.
- 0.15.1 redesigns I/O around concrete reader/writer objects to reduce generic
  bloat and improve hot paths.

Do not over-claim:

- Zig is pre-1.0 and intentionally breaks APIs.
- Fast debug backends are for development loops, not necessarily final code.

V adaptation:

- Add allocator-aware APIs for new stdlib/runtime surfaces while preserving old
  APIs.
- Add debug allocator diagnostics and wrong-allocator/free checks.
- Internally move arrays/maps/builders toward unmanaged cores where possible.
- Prefer streaming I/O helpers over whole-file builders in long-running apps.

Required tests:

- Leak, double-free, wrong allocator, OOM propagation, arena reset, remap/resize.
- Builder versus streaming artifact peak-memory benchmarks.

## Swift

Primary sources:

- Swift 6 announcement: https://www.swift.org/blog/announcing-swift-6/
- Swift 6.2 release: https://www.swift.org/blog/swift-6.2-released/
- SE-0377 borrowing/consuming parameters:
  https://github.com/swiftlang/swift-evolution/blob/main/proposals/0377-parameter-ownership-modifiers.md
- SE-0390 noncopyable structs/enums:
  https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md
- SE-0366 consume operator:
  https://github.com/swiftlang/swift-evolution/blob/main/proposals/0366-move-function.md

Real implementation/design:

- Swift exposes `borrowing` and `consuming` ownership conventions without forcing
  caller syntax for normal copyable types.
- Noncopyable types make resource ownership explicit.
- Swift 6 data-race safety is staged through language modes and migration aids.

Do not over-claim:

- Data-race safety does not solve every concurrency bug.
- Migration can be noisy, hence Swift's gradual modes.

V adaptation:

- Add `consume`/`borrow` and `@[no_copy]` style checks first as opt-in warnings.
- Add `-strict-concurrency` warnings for mutable capture in `spawn`, unsafely
  shared arrays/maps, and unannotated C callbacks.
- Use noncopyable resource wrappers for files, sockets, GPU buffers, and arenas.

Required tests:

- Use-after-consume, double-consume, copy of no-copy resources, conditional
  consume with reinit, and closure capture.
- Spawn mutable capture diagnostics and allowed channel/lock/shared patterns.

## Julia

Primary sources:

- Julia GC internals: https://docs.julialang.org/en/v1/devdocs/gc/
- Julia 1.11 highlights: https://julialang.org/blog/2024/10/julia-1.11-highlights/
- Julia escape analysis docs:
  https://docs.julialang.org/en/v1/devdocs/EscapeAnalysis/
- Julia 1.12 NEWS: https://docs.julialang.org/en/v1/NEWS/

Real implementation/design:

- Julia's GC is non-moving, partially concurrent, parallel, generational, and
  mostly precise.
- Small objects use per-thread pool allocation with page metadata and background
  sweeping.
- Julia 1.11 introduced `Memory` as lower-level storage and selectively enabled
  escape analysis in the compiler pipeline.

Do not over-claim:

- Escape analysis is documented as limited in complex memory operations.
- Dynamic dispatch and C interop reduce precision.

V adaptation:

- Add lower-level storage primitives for arrays/maps/builders.
- Move autofree toward SSA/escape facts: no escape, return escape, global escape,
  C escape.
- Add lock-conflict/task metrics for performance debugging.

Required tests:

- SSA escape fixtures, aliasing through fields, panic/or paths, inlining changes,
  globals, C calls, early free with ASAN/Valgrind style runs.

## CPython

Primary sources:

- PEP 703 no-GIL: https://peps.python.org/pep-0703/
- PEP 779 free-threaded support status: https://peps.python.org/pep-0779/
- CPython memory C API: https://docs.python.org/3/c-api/memory.html
- Free-threading HOWTO: https://docs.python.org/3/howto/free-threading-python.html
- PEP 734 subinterpreters: https://peps.python.org/pep-0734/
- PEP 744 JIT: https://peps.python.org/pep-0744/

Real implementation/design:

- CPython 3.13+ can be built free-threaded; 3.14 moves it toward supported but
  optional status.
- PEP 703 uses biased/deferred reference counting and allocator constraints,
  including mimalloc-related changes.
- The docs distinguish raw, mem, and object allocator domains.

Do not over-claim:

- Free-threaded Python does not make old code scale automatically.
- Extension modules, locks, allocator domains, and object immortality matter.

V adaptation:

- Treat allocator domains as a model: raw C memory, V-managed memory, and
  runtime objects should be visibly separated in diagnostics.
- Consider mimalloc or mimalloc-like page strategies as allocator backend work,
  not as an ownership replacement.
- Add thread-safety annotations for C interop.

Required tests:

- Multi-thread allocation/free stress, C interop ownership transfer, allocator
  domain mismatch, and shared-object races.

## Metrics Required Before Claiming Victory

For every memory/runtime slice, report:

- peak process private bytes or commit before/after
- generated artifact sizes before/after
- allocation count/bytes where instrumentation exists
- wall-clock and compile/test time before/after
- compatibility flags used
- tests and edge cases covered
- residual risks and disabled/opt-in paths

This is the bar for "superior to existing": a measurable improvement, preserved
compatibility, and explicit residual risk.
