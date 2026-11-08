# Upstream integration audit

Date: 2026-11-07

## Scope

- Fork: `jechaviz/v`
- Upstream: `vlang/v`
- Fork baseline: `fb309a9c506de1f30630d1163565e113dd0e487a`
- Candidate's original upstream base: `1f87cae6cdb56e86a1446f507acada5707b1232b`
- Latest upstream head inspected: `e48d9c1f0623520b3a3434d64c0b088635274e13`
- Common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`
- Active candidate: `integration/upstream-base-2026-11-07`

## Exact tree divergence

A recursive Git tree/blob comparison (rather than the REST compare file listing, which is capped) gives:

- Fork changed blob paths: 197
- Upstream changed blob paths: 2,645
- True overlaps: 52
- Fork-only paths: 145

All 145 fork-only paths are represented in the candidate.

## Reconciliation progress

Of the 52 overlaps:
- 25 contain both fork and upstream changes after three-way or targeted manual reconciliation.
- One file, `vlib/v/transform/transform.v`, is empty on both sides.
- 26 still contain the fork's exact blob and require upstream changes to be merged.

The 25 reconciled paths include the test runner and CI diagnostics, V launcher, docs, ARM64 linker, selected OS/filelock tests and selected runtime memory helpers. The 26 unresolved paths are concentrated in builtins, OS/runtime, C/ARM64 compiler generation, scanner, transform and type-checker code. Their exact list and per-path status are maintained in `UPSTREAM_INTEGRATION_STATUS.md` on the active candidate branch.

## Latest upstream delta

Upstream advanced 12 commits and changed 27 files after the original candidate base. Twenty-four non-overlapping files were copied from upstream. Three overlapping files received targeted upstream additions while preserving fork behavior:
- `cmd/v/v.v`: project test dispatch and project backend selection.
- `doc/docs.md`: FastC project backend and MSVC/clang-cl 128-bit ABI documentation.
- `vlib/v/driver/driver.v`: generated-source recognition for inline and stdin compilation.

The file contents are updated, but the candidate does not yet contain current upstream head in its Git ancestry.

## Candidate features preserved

Fork-specific additions include runtime telemetry and memory accounting, compiler memory backpressure, process singleton/resource guards, structured process diagnostics, `snoop` tracing/profiling, test-runner merge/output improvements, Windows fallback-cache support, compiler changes, tests and research documentation.

## Validation gate

- No compiler build, formatter run, or test suite has been executed.
- No GitHub Actions result is claimed.
- No local Windows/Linux/macOS runtime validation has been performed.
- Fork `master` is unchanged.
- A real Git merge/rebase and the 26 remaining overlap reconciliations are required before validation and promotion.

This is a structural/content-preservation report, not a claim that the fork is fully integrated or buildable.
