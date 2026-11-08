# Upstream integration candidate status

Date: 2026-11-07

## Candidate and immutable references

- Repository: `jechaviz/v`
- Upstream: `vlang/v`
- Fork baseline: `fb309a9c506de1f30630d1163565e113dd0e487a`
- Upstream base used for this candidate: `1f87cae6cdb56e86a1446f507acada5707b1232b`
- Original common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`
- Working branch: `integration/upstream-base-2026-11-07`
- Working branch head at this update: `790b32189297bbefd3e31a270361aa6ac1e3e095`
- Fork `master` has not been modified.

## What has been preserved

A path-set comparison from the common ancestor identifies 197 fork-changed paths, of which 12 are also changed upstream and 185 are fork-only paths.

All 185 fork-only paths are now represented in the upstream-based candidate. A tree/blob comparison against fork `master` verified 184 identical Git blob IDs; the remaining path, `vlib/v/transform/transform.v`, is empty on both sides (the Git blob IDs differ, but both fetched contents are zero bytes). This preserves the fork's path-level additions and changes outside the 12 true overlaps.

Preserved groups include:
- Runtime telemetry and memory accounting.
- Compiler memory backpressure.
- Process singleton coordination and process-resource guards.
- Structured process/exit diagnostics.
- `snoop` tracing and profiling.
- Test-runner merge/output improvements.
- Windows V1 fallback-cache helpers.
- Fork-specific compiler, builtin, OS/runtime changes, tests and documentation.

## What remains unresolved

The 12 overlapping paths have not yet been semantically reconciled. They are:
- `TESTS.md`
- `ci/common/runner.v`
- `cmd/tools/test_if_v_test_system_works.v`
- `cmd/tools/testing/common.v`
- `cmd/tools/vfmt_test.v`
- `cmd/tools/vtest-all.v`
- `cmd/tools/vtest.v`
- `cmd/tools/vup.v`
- `cmd/tools/vwatch.v`
- `cmd/v/launcher_test.v`
- `cmd/v/v.v`
- `doc/docs.md`

These require three-way review of the common ancestor, upstream version and fork version. In particular, compiler/test-runner behavior and launcher changes must not be resolved by blindly choosing one side.

## Git history and validation

- The candidate was created from upstream commit `1f87cae6cdb56e86a1446f507acada5707b1232b`, then updated through GitHub file operations to preserve fork-only paths.
- Those file operations create many individual commits; they do not constitute a real Git merge/rebase of the fork history.
- The candidate has not been built, formatted, or tested.
- No GitHub Actions result is claimed.
- No claim is made that the fork is fully synchronized with the current upstream head beyond the inspected base commit.

## Next sequence

1. Reconcile the 12 overlapping paths with explicit three-way patches.
2. Review compiler and runtime integration groups, especially `vlib/v/gen/c`, `vlib/v/types`, `vlib/v/transform`, `vlib/runtime`, and `vlib/os`.
3. Compare against the latest upstream head again and incorporate newer upstream commits.
4. Perform a real Git merge/rebase or equivalent history-preserving integration when a Git-capable environment is available.
5. Build and run focused and broad tests locally on supported platforms.
6. Only after validation, propose promotion to `master`.

Current status: fork-only path preservation is complete; semantic overlap reconciliation, history synchronization and validation are still pending.
