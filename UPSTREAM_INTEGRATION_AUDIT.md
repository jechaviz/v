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

GitHub compare reports 670 upstream-only commits and 108 fork-only commits. From the common ancestor, GitHub exposes 300 changed paths on upstream and 197 changed paths on the fork. The fork-side net delta is 9,183 additions and 350 deletions. The fork's 108 commits are not 108 independent features: the history includes upstream merge commits, local merge commits and explicit revert commits.

The fork-side changed paths cluster in:
- `vlib/`: 146 paths
- `cmd/tools/`: 35 paths
- `cmd/v/`: 5 paths
- `doc/`: 5 paths
- Other root, CI, examples and third-party paths: 6 paths

## True path-level overlaps

Only 12 paths appear in both the upstream and fork changed-path sets from the common ancestor. These are the actual path-level reconciliation hotspots:

- `TESTS.md`: upstream changes test/build guidance; fork adds merged test-file behavior and its constraints.
- `ci/common/runner.v`: upstream resolves compiler invocation through valgrind; fork adds structured command-failure reporting.
- `cmd/tools/test_if_v_test_system_works.v`: upstream streams child output while retaining it; fork adds structured failure diagnostics.
- `cmd/tools/testing/common.v`: upstream adjusts self-build and production compiler selection; fork adds process guard and memory-pressure handling.
- `cmd/tools/vfmt_test.v`: upstream updates formatter expectations; fork adds UTF-8 BOM preservation tests.
- `cmd/tools/vtest-all.v`: upstream adjusts cross-target test behavior; fork adds structured failure reports.
- `cmd/tools/vtest.v`: upstream makes test discovery target-architecture aware; fork adds an explicit successful exit.
- `cmd/tools/vup.v`: upstream changes updater/TCC/cache behavior; fork adds structured failure diagnostics.
- `cmd/tools/vwatch.v`: upstream handles replacement of generated manifests; fork reports failures from before/after commands.
- `cmd/v/launcher_test.v`: upstream updates launcher/fallback expectations; fork adds Windows fallback-cache coverage.
- `cmd/v/v.v`: upstream changes launcher/compiler dispatch; fork adds Windows user-cache fallback selection.
- `doc/docs.md`: upstream changes updater documentation; fork documents array concatenation and `+=`.

These 12 files require deliberate reconciliation. The upstream and fork patches are functionally distinct in several cases; blindly choosing either side would discard useful behavior.

## Fork-only additions and changes to preserve

The fork has 185 changed paths not changed by upstream since the common ancestor. Important feature groups include:

- Runtime memory/pressure telemetry: `vlib/runtime/telemetry.v`, `telemetry_memory.v`, and tests.
- Compiler memory backpressure: `vlib/v/util/memory_backpressure.v` and tests.
- Process coordination: `vlib/os/process_singleton/`.
- Structured process/exit diagnostics: `vlib/os/result_diagnostics.v` and tests.
- Statement/value tracing and bounded profiling: `vlib/snoop/`.
- Test child-process resource guard: `cmd/tools/testing/process_resource_guard*`.
- Test-runner merge optimization: `cmd/tools/testing/merge.v` and tests.
- V1 fallback cache Windows helpers: `cmd/v/v1_fallback_cache_windows*`.
- Regression/architecture research notes: `doc/qes_compiler_regression_audit_2026-10-01.md`, `doc/memory_runtime_cross_language_review.md`, and `doc/mojo_v_ownership_convergence.md`.

These features are not present as path changes in upstream's 300-path delta from the common ancestor. Their APIs, callers and platform assumptions still need compatibility review against the updated upstream tree.

## Fork-only compiler changes

The fork also changes core compiler files that upstream has not changed from the common ancestor in this comparison. These are not path-level merge conflicts, but they are high-impact fork behavior and must be preserved while taking upstream's other compiler improvements:

- `vlib/v/gen/c/trace_calls.v` (fork 6,983 bytes; upstream 2,946 bytes): extended tracing/code generation.
- `vlib/v/gen/c/stmt.v` (fork 369,141 bytes; upstream 384,024 bytes): fork-specific code-generation changes.
- `vlib/v/types/checker_tail.v` (fork 832,796 bytes; upstream 871,282 bytes): fork-specific type-checker changes.
- `vlib/builtin/array.v` (fork 57,988 bytes; upstream 53,024 bytes): array semantics/performance changes.

`cmd/v/v.v` is different: it is one of the 12 true overlaps and contains both upstream launcher changes and the fork's Windows fallback-cache change.

## Latest upstream commit inspected

The upstream head is `1f87cae6cdb56e86a1446f507acada5707b1232b`, titled `ci: fix macOS Brotli module-cache link and vfmt failures`. Its latest commit changes the Brotli MemorySanitizer helper into a separate native C object, adds a module-cache regression test, and formats a Windows Clang test command. This should be included with the upstream update; it is not a fork-specific feature.

## Suggested integration order

1. Reconcile the 12 true overlapping paths, starting with `cmd/tools/testing/common.v`, `cmd/v/v.v`, `cmd/tools/vup.v`, and `doc/docs.md`.
2. Bring in upstream-only paths and compiler/runtime improvements without replacing fork-only compiler files.
3. Reconcile fork-only compiler changes against upstream's current compiler interfaces and tests.
4. Integrate runtime/process coordination, telemetry, memory backpressure, diagnostics and test-runner features as coherent groups.
5. Integrate `snoop` last across CLI, transform/codegen, runtime helpers, docs and tests.
6. Re-run the compare, inspect the complete diff, then validate locally before promoting anything to `master`.

## Current status

This audit is committed only to `integration/upstream-2026-11-07`. No upstream source files have been merged or overwritten. No build or test suite has been run. The fork's `master` remains unchanged.
