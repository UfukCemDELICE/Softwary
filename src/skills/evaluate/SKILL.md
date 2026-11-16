---
name: evaluate
description: Measures how many deliberately broken changes the reviewer catches. Prepares the evaluation cases, has the reviewer subagent review each one in a clean context, scores them and leaves the result to the human. Use before turning on merges without a human, and again when the reviewer or its model changes.
---

# Evaluate

The loop merges by itself only when the reviewer is shown to catch enough
broken changes (`min_catch_percent` in `.softwary/config/loop.conf`).
`./softwary status` shows the state: `evaluation: missing`, `stale`,
`below <percent>` or `ok <percent>`. Run this skill when it is not `ok`.

1. Pick an empty directory outside the repository (a temporary one) and run
   `./softwary eval prepare <dir>`. It lists one directory per case:
   `case-01`, `case-02`, and so on. Each is a small repository with the base on
   `main` and the change under review on `review`.
2. For each case, call the `reviewer` subagent in a **clean context**, one case
   per call, with only that directory as its workspace: base `main`, slice
   `S1`, the review record `specs/002-tip/reviews/S1.md`. It replies
   `approve` or `changes`. Give it nothing else: not the other cases, not this
   repository, and never `.softwary/eval/` or `.softwary/state/eval/`; they hold
   the answers.
3. Run `./softwary eval score <dir>`. If it lists cases with a missing or
   invalid record, call the reviewer again for those cases and score again;
   nothing is written until every case has a record.
4. Show the human the table, the counts and `.softwary/config/eval.conf`.
   Do not commit the file or change anything else: it is in a protected
   path, and what the numbers mean is for the human to decide. Leave the
   commit, and the question of whether the threshold is high enough, to
   them.

Never edit a record to change a result, and never run the reviewer on a case
twice to get a better one: score what it said the first time.

## Excuses

| Excuse | Reply |
| --- | --- |
| "I know which case is broken; I will point the reviewer at it." | Then the measure is worthless. Give no hint. |
| "One case has no record; I will write it myself." | Only the reviewer writes a record. Call it again. |
| "The score is a little low; I will run it again." | Score what it said. Tell the human the number. |
