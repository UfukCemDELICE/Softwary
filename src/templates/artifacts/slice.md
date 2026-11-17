---
id: S1
spec: NNN
goal: UNSET
acs: AC-NNN-01
depends_on:
touches:
status: planned
---

# S1

<!-- One end-to-end observable behaviour, finished in one session. The slice
lives in specs/NNN-<name>/slices/S<n>.md and id matches the file name.
acs: the criteria it delivers, comma-separated; each criterion belongs to
exactly one slice. depends_on: slice ids. touches: paths it changes.
status: planned, in-progress, review or done.
repro (optional, a line like "repro: tests/test_bug.sh"): for a slice that
fixes a bug, the test files that reproduce it, separated by spaces, each under
test_paths and in touches. The gate proves each fails on the base and passes
on the job. -->

## Notes
