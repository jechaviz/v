# Upstream integration audit

Date: 2026-11-07

## Scope and immutable references

- Fork: `jechaviz/v`
- Upstream: `vlang/v`
- Fork baseline: `fb309a9c506de1f30630d1163565e113dd0e487a`
- Upstream head inspected: `1f87cae6cdb56e86a1446f507acada5707b1232b`
- Common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`
- Preservation branch: `integration/upstream-2026-11-07`

## Divergence

GitHub compare reports the fork as 108 commits behind upstream and upstream as 670 commits ahead of the fork. The fork-side comparison from the common ancestor contains 108 commits and a net tree delta of 197 paths: 9,183 additions and 350 deletions. These are not 108 independent features: the history includes upstream merge commits, local merge commits, and explicit revert commits.

The fork-side changes cluster in:
- `vlib/`: 146 changed paths
- `cmd/tools/`: 35 changed paths
- `cmd/v/`: 5 changed paths
- `doc/`: 5 changed paths
- Other root, CI, examples and third-party paths: 6 changed paths

## Fork-specific functionality confirmed absent from current upstream

The following paths exist on the fork's `master` but return 404 on upstream `master`:
- `vlib/runtime/telemetry.v`, `telemetry_memory.v`, `telemetry_test.v`: runtime memory/pressure telemetry.
- `vlib/v/util/memory_backpressure.v` and its tests: dynamic compiler-job backpressure.
- `vlib/os/process_singleton/`: process singleton/coordination primitives.
- `vlib/os/result_diagnostics.v` and tests: structured command/process failure diagnostics.
- `vlib/snoop/`: statement/value tracing and bounded profiling.
- `cmd/tools/testing/process_resource_guard.v` and related files: test child-process resource guard.
- `doc/qes_compiler_regression_audit_2026-10-01.md`: fork-specific regression audit.

These are preservation candidates, not automatic merge conflicts. Their callers, APIs and assumptions must be reconciled with upstream changes before moving them.

## High-risk overlapping files

The fork and upstream have different blob SHAs for several central compiler/runtime files:
- `vlib/v/gen/c/trace_calls.v` (fork 6,983 bytes; upstream 2,946 bytes): fork extends tracing code; likely overlaps the recent `snoop` work.
- `vlib/v/gen/c/stmt.v` (fork 369,141 bytes; upstream 384,024 bytes): central code-generation path.
- `cmd/v/v.v` (fork 51,812 bytes; upstream 54,000 bytes): CLI/bootstrap integration.
- `vlib/v/types/checker_tail.v` (fork 832,796 bytes; upstream 871,282 bytes): type checker.
- `vlib/builtin/array.v` (fork 57,988 bytes; upstream 53,024 bytes): array semantics/performance changes.

The fork's recent `snoop` implementation touches runtime helpers, C generation and CLI wiring. It must be integrated as a coherent feature, not cherry-picked as unrelated files.

## Suggested integration order

1. Reconcile upstream compiler/type-checker and builtin changes first, keeping the fork's semantic changes and regression tests visible.
2. Integrate runtime/process coordination and memory backpressure as a separate layer; re-check upstream process, memory and test-runner behavior.
3. Integrate diagnostics and test-runner changes, preserving platform-specific Windows behavior.
4. Integrate `snoop` last as a coherent feature across CLI, transform/codegen, runtime helpers, docs and tests.
5. Re-run the compare, inspect the final diff, then validate locally before promoting anything to `master`.

## Current status

This audit is committed only to `integration/upstream-2026-11-07`. No upstream source files have been merged or overwritten. No build or test suite has been run. The fork's `master` remains unchanged.
