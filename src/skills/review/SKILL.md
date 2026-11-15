---
name: review
description: Review stage. Has a slice in review checked by the reviewer subagent in a clean context, records the review and tells the human how closely to look based on the risk tier.
---

# Review

The writer does not review. The review is done by the `reviewer` subagent,
which starts with a clean context; on a tool without subagents, hand the slice
to a fresh session with the reviewer instructions.

1. Pick a slice with `status: review`.
2. Give the reviewer the slice file, its spec and the base to diff against
   (the integration branch, `integration_branch` in
   `.softwary/config/commands.conf`, unless told otherwise). It writes
   `specs/NNN-<name>/reviews/S<n>.md` from `.softwary/templates/review.md`.
3. With `decision: approve`, set the slice to `status: done`. With
   `decision: changes`, set it back to `status: in-progress` and return to
   `implement` with the findings.
4. Run `./softwary trace` and `./softwary verify` (it checks the change
   against the integration branch).
5. Run `./softwary risk <spec>` and tell the human what the tier asks of them:
   - R1: skim the review summary;
   - R2: read the summary and the files the review lists;
   - R3: read every line; no automatic merge.

Gate: the review approves the slice and the human approves the merge as the
risk tier requires.
