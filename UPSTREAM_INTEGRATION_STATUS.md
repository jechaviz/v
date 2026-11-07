# Upstream integration candidate status

Date: 2026-11-07

## Candidate

- Repository: `jechaviz/v`
- Target branch: `master` (not modified)
- Working branch: `integration/upstream-base-2026-11-07`
- Upstream: `vlang/v:master`
- Upstream head last inspected: `b3e1e85f7062da68a8072c169256951ef9d29760`
- Candidate head before this status update: `ea508bec2a35382e0360660f10b5f9a12364b3c6`
- Original common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`

## Integration work completed

The working branch was assembled on the upstream tree and preserves all 197 paths changed by the fork since the common ancestor:

- 185 fork-only paths copied onto the upstream-based tree. This includes runtime telemetry, memory backpressure, process coordination and resource guards, structured diagnostics, `snoop`, test-runner improvements, Windows fallback-cache support, compiler changes, tests and documentation.
- All 12 path-level overlaps between upstream and fork were reconciled:
  - Three-way, non-overlapping edits were applied to `TESTS.md`, `ci/common/runner.v`, `cmd/tools/test_if_v_test_system_works.v`, `cmd/tools/testing/common.v`, `cmd/tools/vfmt_test.v`, `cmd/tools/vtest-all.v`, `cmd/tools/vtest.v`, `cmd/tools/vup.v`, `cmd/tools/vwatch.v`, and `cmd/v/v.v`.
  - `cmd/v/launcher_test.v`: the fork's Windows fallback-cache test is already identical to the upstream-based copy; no duplicate was added.
  - `doc/docs.md`: the fork's array concatenation, comparator-expression, and `@[hot]`/`@[cold]`/`@[noalloc]` documentation was carried into the upstream version.
- The latest upstream changes inspected after the original base were applied to `vlib/math/bits/div_64_cross_test.v`, `vlib/v/gen/c/headerless_program_test.v`, and `vlib/v/gen/c/literal_output_test.v`.

A path-set check against the common ancestor found all 185 fork-only paths represented in the candidate; none were missing.

## Current upstream relationship

The last compare against `vlang/v:master` (`b3e1e85f7062da68a8072c169256951ef9d29760`) reported:
- Candidate ahead: 254 commits
- Candidate behind: 1 commit
- Changed paths: 200

The latest upstream file changes have been applied to the candidate tree, but the branch still lacks the latest upstream commit in its Git ancestry. This is a Git-history limitation of the available GitHub file-edit workflow; it is not being represented as a completed ancestry merge. A proper Git merge/rebase or merge commit is still required to make the branch fully synchronized by ancestry.

## Validation status and limitations

- No compiler build or test suite has been run.
- No local Windows/Linux/macOS execution was available in this workflow.
- No GitHub Actions result is being claimed.
- Textual three-way reconciliation is not a substitute for compilation, formatting, runtime testing, or a full semantic review.
- The working branch is not merged into `master`; `master` remains unchanged.

## Required before promotion

1. Perform a real Git merge/rebase from the current upstream head so the latest upstream commit is in the candidate's ancestry.
2. Build the compiler/bootstrap on the supported host.
3. Run formatter and focused compiler/runtime tests for array semantics, tracing/`snoop`, process memory guard, telemetry, backpressure, diagnostics, process singleton, test merging, and Windows fallback cache.
4. Run the broader test suite on Windows and at least one Unix platform.
5. Review the final PR diff for generated files, test assumptions, API changes, platform-specific regressions, and any accidental overwrites.
6. Only then promote the candidate into `master`.
