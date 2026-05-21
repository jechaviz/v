# Mojo/V Ownership And Memory Convergence

This note records the code-level comparison that gates any Mojo-inspired
memory work in V. It deliberately separates public, inspectable Mojo artifacts
from claims that depend on compiler internals that are not yet public.

## Public Mojo Surface Reviewed

- Repository: https://github.com/modular/modular
- Mojo directory: https://github.com/modular/modular/tree/main/mojo
- Mojo stdlib: https://github.com/modular/modular/tree/main/mojo/stdlib/std
- MAX kernels: https://github.com/modular/modular/tree/main/max/kernels
- Stdlib README: https://github.com/modular/modular/blob/main/mojo/stdlib/README.md
- Contributing scope: https://github.com/modular/modular/blob/main/CONTRIBUTING.md
- Path to Mojo 1.0: https://www.modular.com/blog/the-path-to-mojo-1-0
- Mojo 1.0 beta release notes: https://mojolang.org/releases/v1.0.0b1/
- Ownership docs: https://mojolang.org/docs/manual/values/ownership/
- Lifetime/origin docs: https://mojolang.org/docs/manual/values/lifetimes/
- Pointer docs: https://mojolang.org/docs/manual/pointers/
- GPU tutorial: https://mojolang.org/docs/manual/gpu/intro-tutorial/

The public repository exposes Mojo stdlib, docs, examples, and kernels. It does
not expose the full language compiler implementation today, so V changes should
not assume implementation details of Mojo passes that we cannot inspect.

The repository README and contribution guides make stdlib, kernels, examples,
docs, Python APIs, serving, and pipelines the public contribution surface. They
also mention internal compiler bugs and synchronization with Modular's internal
repository. Therefore, claims about the exact borrow checker, optimizer,
monomorphization, MLIR lowering sequence, ABI, caching, or diagnostics are
documentation claims or API inferences unless the compiler source is later
opened.

## Mojo Coding Patterns That Matter

### Ownership and Origins

Mojo uses value ownership, argument conventions, and origins as explicit API
surface. Public docs define `read`, `mut`, `var`, `ref`, `out`, and `deinit`
styles around a lifetime checker. `origin_of(value)` and origin parameters let
APIs return references tied to the lifetime of input storage.

The important coding pattern is not a Rust-like syntax clone. It is the
separation of four facts:

- who owns the value
- whether a reference can mutate it
- whether a call consumes the value
- which source lifetime keeps a returned reference valid

### Smart Pointers and Unsafe Boundaries

`OwnedPointer[T]` is a safe owning pointer. It restricts mutable access through
the origin system, supports `take(deinit self)`, and makes raw pointer escape an
explicit operation through APIs such as `steal_data(deinit self)`.

`UnsafePointer` is deliberately non-null in the 1.0 beta model. Nullable pointer
state is expressed as `Optional[UnsafePointer[...]]`, with the release notes
describing this as layout-compatible and zero overhead. Unsafe pointer APIs also
separate initialized memory from uninitialized memory with explicit init,
destroy, load, store, and free operations.

### Parametric and Comptime Code

Mojo uses compile-time parameters for specialization. Public examples show
`comptime` constants, typed layouts, type/size parameters on SIMD values, and
`comptime for` loops. This gives the compiler strong static facts without
requiring every call site to carry verbose syntax.

### GPU and Device Memory

Open examples use `DeviceContext`, device buffers, `LayoutTensor`/`TileTensor`,
`MutAnyOrigin`, `enqueue_function`, explicit grid/block dimensions, and scoped
host mapping. The GPU tutorial states that when device context, buffers, host
buffers, and tensors are no longer used, destructors are invoked automatically.

For V, the transferable idea is not "add MLIR everywhere". It is to model host
memory, device memory, layouts, and kernel launch contracts as typed resources
with explicit lifetime boundaries.

### What Not To Copy Blindly

Mojo has convenience escape hatches like broad origins. Public docs warn that
`MutAnyOrigin` can extend lifetimes too widely. V should avoid broad "any
lifetime" defaults because they make early destruction and precise autofree
harder. Broad origins should be limited to FFI, low-level GPU APIs, and
diagnostic-only transition paths.

Mojo also has a large MAX/runtime context that V does not have. GPU and kernel
support in V should start as a narrow stdlib/compiler-hook experiment, not a
compiler rewrite.

## Current V Surface

### Main Compiler Autofree

V's current `-autofree` is mostly a C backend cleanup system. It inserts frees
from CGen using scope information and type-specific rules. Important files:

- `vlib/v/gen/c/autofree.v`
- `vlib/v/gen/c/auto_free_methods.v`
- `vlib/v/gen/c/fn.v`
- `vlib/v/checker/fn.v`
- `vlib/v/pref/pref.v`

This is practical and compatible with the C backend, but it is downstream of
semantic analysis. It does not yet have a first-class ownership/origin fact
model comparable to Mojo.

### V2 Ownership Checker

V already has an experimental ownership path in `v2`:

- `doc/ownership.md`
- `cmd/v/v.v`
- `vlib/v2/types/checker_ownership.v`
- `vlib/v2/types/checker_ownership_test.v`
- `vlib/builtin/string_d_ownership.v`

The implementation tracks `owned_vars`, `moved_vars`, and `borrowed_vars`, with
`.to_owned()` currently focused on strings. This is valuable local intent. It
should be evolved, not bypassed.

The current gap versus Mojo is that V2 ownership is name-map based and narrow in
type coverage. Mojo's public API models ownership and origins in signatures and
types, which makes references, smart pointers, and unsafe boundaries composable.

## FODA

Fortalezas:

- V already has `-autofree`, `-manualfree`, GC modes, and an experimental V2
  ownership checker.
- V's C backend and simple compilation model keep implementation cost low.
- Existing AST scope data can drive early cleanup once semantic facts improve.

Oportunidades:

- Promote V2 ownership facts into a reusable semantic layer that CGen/autofree
  can consume.
- Add opt-in ownership for arrays, maps, resource structs, and smart-pointer-like
  stdlib types without changing default V semantics.
- Add non-null pointer wrappers and explicit nullable pointer wrappers at the
  library boundary before changing pointer language semantics.
- Use runtime backpressure to keep long-lived V programs alive under Windows
  commit pressure while ownership/autofree becomes more precise.

Debilidades:

- Current autofree decisions are duplicated across several CGen paths.
- V2 ownership is not yet the default checker and is currently string-centered.
- C interop can hide escaping pointers from static analysis.
- Maps, closures, async work, and generated temporaries can obscure ownership.

Amenazas:

- Over-aggressive autofree can create use-after-free or double-free bugs.
- Pointer nullability changes can break C interop or existing unsafe code.
- MLIR/GPU work can distract from the immediate Windows RAM failure mode.
- A hybrid model can become confusing unless diagnostics explain ownership,
  fallback GC, and manual boundaries precisely.

## Edge Cases That Must Be Solved First

- Branch merge: a value moved in one branch and live in another must be reported
  precisely.
- Early return/or blocks: destructor placement must not skip cleanup or double
  clean.
- Mutable aliasing: a `mut` borrow must exclude other mutable borrows and moves.
- Closures: captured values need origin sets or conservative escape fallback.
- Maps: overwriting/deleting owned values must not leak or double-free.
- C interop: passing a pointer to C must conservatively mark escape unless an
  API is annotated no-escape.
- Unsafe nullability: non-null wrappers must reject null construction while
  optional wrappers preserve FFI layout expectations.
- Device memory: host/device buffers need separate ownership domains.
- Long-lived processes: memory pressure should reduce work, flush caches, or
  delay producers instead of killing the process.

## Implementation Gate For V

No Mojo-inspired feature should land directly in the main compiler without
passing this staged gate:

1. Add characterization tests for current V behavior.
2. Extend V2 ownership facts first, behind `-ownership`.
3. Expose reusable semantic facts: owned, moved, borrowed, escaped, consumed,
   and returned-origin.
4. Teach CGen/autofree to consume those facts for earlier and safer cleanup.
5. Add library-level resource types before changing language-wide pointer rules.
6. Keep C interop conservative until no-escape and ownership transfer attributes
   are proven by tests.

## First Convergence Slices

1. Stabilize memory backpressure in runtime/compiler jobs so Windows survives
   high commit pressure.
2. Fix autofree diagnostics, especially `-print_autofree_vars_in_fn`, so memory
   decisions are inspectable.
3. Extract an autofree cleanup decision helper to remove CGen duplication.
4. Add V2 ownership tests inspired by Mojo origins: returned borrowed references,
   mut exclusivity, consume semantics, and branch merges.
5. Add safe pointer/resource wrappers in stdlib: non-null resource pointer,
   optional nullable pointer, and owned resource with explicit `take`.
6. Only then connect ownership facts to autofree for early post-call temporary
   cleanup.
