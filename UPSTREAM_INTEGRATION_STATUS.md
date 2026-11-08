# Upstream integration candidate status

Date: 2026-11-07

## Candidate and immutable references

- Repository: `jechaviz/v`
- Upstream: `vlang/v`
- Fork baseline: `fb309a9c506de1f30630d1163565e113dd0e487a`
- Upstream base used to create the candidate: `1f87cae6cdb56e86a1446f507acada5707b1232b`
- Latest upstream head inspected: `e48d9c1f0623520b3a3434d64c0b088635274e13`
- Original common ancestor: `d1df2de5377098c11f7326c1155f3ce32cfa0340`
- Working branch: `integration/upstream-base-2026-11-07`
- Candidate head at this update: `6fc172a652097fa9d87918e67607cd399806200e`
- Fork `master` has not been modified.

## Exact path divergence

A recursive Git tree/blob comparison against the common ancestor avoids the GitHub compare API's 300-file listing limit.

- Fork changed blob paths: 197
- Upstream changed blob paths: 2,645
- True overlaps: 52
- Fork-only paths: 145

All 145 fork-only paths are represented in the candidate. The 52 overlapping paths have been classified by comparing the candidate, fork and upstream blob IDs.

## Overlap reconciliation status

Of the 52 true overlaps:

- 25 now contain both sides' changes, based on three-way, non-overlapping patch application or targeted manual reconciliation.
- `vlib/v/transform/transform.v` is empty on both sides. Its Git blob IDs differ, but both fetched contents are zero bytes.
- 26 still contain the fork's exact blob; their upstream-side changes remain to be merged.

The 25 reconciled paths are:
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
- `vlib/os/command_test.v`
- `vlib/os/filelock/filelock_test.v`
- `vlib/runtime/free_memory_impl_freebsd.c.v`
- `vlib/runtime/free_memory_impl_linux.c.v`
- `vlib/runtime/free_memory_impl_openbsd.c.v`
- `vlib/runtime/used_memory_freebsd.c.v`
- `vlib/runtime/used_memory_openbsd.c.v`
- `vlib/v/driver/driver.v`
- `vlib/v/gen/arm64/linker.v`
- `vlib/v/help/build/build.txt`
- `vlib/v/tests/builtin_overflow_test.v`
- `vlib/v/tests/concurrency/shared_nested_lock_runtime_test.v`
- `vlib/v/tests/shared_library_system_link_test.v`

The 26 unresolved overlap paths are:
- Builtins: `vlib/builtin/allocation.c.v`, `array.v`, `builtin_windows.c.v`, `cfns.c.v`, `panicing.c.v`, `recover.c.v`
- Libraries: `vlib/db/pg/pg.c.v`, `vlib/fasthttp/fasthttp_linux.v`, `vlib/hash/crc64/interop/crc64_interop.vsh`
- OS: `vlib/os/os.c.v`, `os.v`, `os_nix.c.v`, `os_windows.c.v`
- Runtime: `vlib/runtime/runtime_nix.c.v`, `runtime_windows.c.v`, `used_memory_windows.c.v`
- Compiler: `vlib/v/gen/c/cleanc.v`, `fn_parallel_notd_v3_no_parallel.v`, `stmt.v`, `vlib/v/scanner/scanner.v`, `vlib/v/transform/expr.v`, `map.v`, `vlib/v/types/checker.v`, `checker_comptime.v`, `checker_tail.v`, `checker_tail_stmt.v`

These are high-risk merge targets. In particular, compiler, builtin, OS and runtime files must not be replaced wholesale by either side.

## Latest upstream delta

Upstream advanced from the original base to `e48d9c1f0623520b3a3434d64c0b088635274e13` (12 commits, 27 changed files).

- 24 upstream-only changed files were copied into the candidate.
- Three overlapping files received explicit upstream additions while retaining fork behavior:
  - `cmd/v/v.v`: project test dispatch and project backend selection.
  - `doc/docs.md`: FastC project backend and MSVC/clang-cl 128-bit ABI documentation.
  - `vlib/v/driver/driver.v`: generated-source recognition for inline and stdin compilation.
- These file changes are present, but the candidate does not yet contain the upstream head in its Git ancestry.

## Git history and validation

- GitHub file operations created individual commits; this is not a real Git merge/rebase.
- Compare against current upstream reports 419 commits ahead and 11 behind. The ahead count is inflated by file-by-file commits and must not be interpreted as 419 independent fork features.
- No compiler build, formatter run, or test suite has been executed.
- No GitHub Actions result is claimed.
- No local Windows/Linux/macOS runtime validation has been performed.

## Next sequence

1. Three-way merge the 26 unresolved overlap paths using common ancestor, fork and latest upstream versions.
2. Recompute tree/blob coverage after each group and inspect the complete candidate diff.
3. Perform a real Git merge/rebase so upstream's current head is in the candidate ancestry.
4. Build the compiler/bootstrap and run focused tests for compiler, builtin, OS/runtime, telemetry, memory backpressure, diagnostics, process coordination, `snoop`, test merging and Windows fallback cache.
5. Run broader tests on Windows and at least one Unix platform.
6. Promote to `master` only after review and validation.

Current status: 145 fork-only paths preserved; 25 overlap paths reconciled, one empty overlap confirmed content-identical, and 26 overlap paths still require three-way reconciliation. Latest upstream file changes are represented, but Git ancestry and all tests remain pending.
