# Upstream integration audit

Date: 2026-11-07

## Repositories and commits

- Fork: `jechaviz/v`
- Upstream: `vlang/v`
- Fork baseline: `fb309a9c506de1f30630d1163565e113dd0e487a`
- Original upstream base used for the candidate: `1f87cae6cdb56e86a1446f507acada5707b1232b`
- Latest upstream head inspected: `e48d9c1f0623520b3a3434d64c0b088635274e13`
- Common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`
- Active candidate branch: `integration/upstream-base-2026-11-07`

## Exact divergence

The initial REST compare listing was capped at 300 upstream paths, which understated the number of overlaps. A complete recursive Git tree/blob comparison corrected the counts:

- Fork changed blob paths: 197
- Upstream changed blob paths from the common ancestor: 2,632
- True overlaps: 52
- Fork-only paths: 145

All 145 fork-only paths are represented in the active candidate. The candidate has also retained fork versions for the 38 unresolved overlaps, but those paths still need upstream changes merged in. They are not considered integrated.

## Overlap status

Thirteen overlap files have both fork and upstream changes represented:
`TESTS.md`, `ci/common/runner.v`, `cmd/tools/test_if_v_test_system_works.v`,
`cmd/tools/testing/common.v`, `cmd/tools/vfmt_test.v`, `cmd/tools/vtest-all.v`,
`cmd/tools/vtest.v`, `cmd/tools/vup.v`, `cmd/tools/vwatch.v`,
`cmd/v/launcher_test.v`, `cmd/v/v.v`, `doc/docs.md`, and
`vlib/v/driver/driver.v`.

`vlib/v/transform/transform.v` is empty on both sides. Its blob IDs differ, but both fetched contents are zero bytes.

Thirty-eight overlap files still contain the fork's exact blob and need three-way reconciliation. They span builtin arrays/allocation, OS and runtime implementations, database/network libraries, compiler C/ARM64 generation, scanner, transform and type-checker code, plus related tests and build documentation. See `UPSTREAM_INTEGRATION_STATUS.md` on the active candidate branch for the complete path list.

## Latest upstream delta

Upstream advanced 12 commits and changed 27 files after the original candidate base. Twenty-four non-overlapping files were copied from current upstream. Three overlapping files received targeted additions:
- `cmd/v/v.v`: project test dispatch and project backend selection.
- `doc/docs.md`: FastC project backend and MSVC/clang-cl 128-bit ABI documentation.
- `vlib/v/driver/driver.v`: generated-source recognition for inline and stdin compilation.

These file updates do not add upstream commits to the candidate's Git ancestry. Compare against current upstream still reports the candidate as 406 commits ahead and 11 behind; the ahead count is inflated by individual file-edit commits.

## Candidate features retained

The fork-only path set includes:
- Runtime telemetry and memory accounting.
- Compiler memory backpressure.
- Process singleton coordination and process-resource guards.
- Structured process/exit diagnostics.
- `snoop` tracing and profiling.
- Test-runner merge/output improvements.
- Windows V1 fallback-cache support.
- Compiler, builtin, OS/runtime changes, tests and research documentation.

## Validation and promotion gate

- No compiler build or test suite has been run.
- No GitHub Actions result is claimed.
- No local Windows/Linux/macOS runtime validation has been performed.
- The active candidate is not merged into `master`; fork `master` remains unchanged.
- A real Git merge/rebase and three-way reconciliation of the 38 remaining overlaps are required before validation and promotion.

This audit is a structural/content-preservation report, not a claim that the fork is fully integrated or buildable.
