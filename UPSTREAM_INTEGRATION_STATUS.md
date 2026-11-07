# Upstream integration candidate status

Date: 2026-11-07

## Candidate

- Repository: `jechaviz/v`
- Target: `master`
- Candidate branch: `integration/upstream-base-2026-11-07`
- Upstream: `vlang/v:master`
- Upstream commit incorporated: `d6e2e5f2fb76d7e551b4336c367c4e8b663a5a89`
- Candidate merge commit: `98bbc191ca341e5af841c897e98113b82a3136a9`

## Integration work completed

The candidate branch is now based on the latest upstream master and includes the fork's 197 changed paths from the common ancestor:

- 185 fork-only paths copied onto the upstream base, including runtime telemetry, compiler memory backpressure, process/resource guards, diagnostics, `snoop`, test merging, Windows fallback-cache behavior, compiler changes, and their tests/docs.
- 12 paths changed on both sides reconciled. Eleven were merged from the common ancestor with non-overlapping three-way edits. `cmd/v/launcher_test.v` had two independent test additions at EOF; both were retained alongside upstream's launcher changes.
- Latest upstream follow-up commit `d6e2e5f` was included as a second parent of the candidate merge commit; its Windows Clang/vfmt test adjustment was also copied into the candidate tree.

## Git ancestry check

GitHub compare against `vlang/v:master` reports:
- Candidate ahead: 200 commits
- Candidate behind: 0 commits
- Changed paths: 197

This establishes that the candidate contains the current upstream commit in its ancestry and retains the fork's changed paths. It does not establish that the code compiles or that tests pass.

## Important validation status

- No build or test suite has been run.
- No local Windows/Linux/macOS execution was available in this workflow.
- No GitHub Actions result is being claimed.
- The candidate is not merged into `master`.
- `master` remains unchanged.

## Required before merge

1. Build the compiler/bootstrap on the user's supported host.
2. Run formatter and focused compiler/runtime tests for array semantics, tracing/`snoop`, process memory guard, telemetry, backpressure, diagnostics, process singleton, test merging, and Windows fallback cache.
3. Run the broader test suite on Windows and at least one Unix platform.
4. Review the final PR diff for accidental generated files, test assumptions, API changes and platform-specific regressions.
5. Only then merge the PR into `master`.
