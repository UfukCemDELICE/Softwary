---
name: diagnose
description: Bug stage. Reproduces a reported bug with a test first, finds the root cause with evidence, and puts the fix into the plan as a spec bound to the product example the bug breaks and a slice with a repro. Never fixes code itself. Use when the human reports a bug.
---

# Diagnose

A bug is fixed in the loop like any other change: a spec, a slice, a job. Your
part is to catch the bug in a test, to find why it happens, and to plan the
fix. You write no code that fixes it.

1. Ask what was expected, what happened and how to trigger it, one question at
   a time, until you can trigger it yourself.
2. Reproduce first. Write the smallest test, under `test_paths`, that fails
   because of the bug, and run it: you must see it red for the reason in the
   report. A test that passes does not reproduce the bug: change it, or ask.
3. Find the root cause with evidence: the file and the line, and the output or
   the trace that shows it. A guess does not go into a spec.
4. Find the example in `product/PRODUCT.md` (`EX-F<n>-NN`) that the bug
   breaks. If no example describes this behaviour, the report is a product
   change, not a bug: stop, tell the human, and send them to `define`.
5. Plan the fix as the `plan` skill does, and nothing more:
   - a spec with one criterion `AC-NNN-NN` that names that example, and a
     slice whose `touches` cover the code to change and the test;
   - in the slice's front matter `repro: <test file>`; the test files must be
     under `test_paths` and in `touches`, and `test_files` in `commands.conf`
     must be the command that runs given tests (`./softwary doctor` says);
   - put the text of your test in the slice, under `## Reproduction`, with the
     output that showed it red, and the root cause under `## Cause`;
   - `./softwary plan check`, the `spec-analyst`, `./softwary plan approve`.
6. Take your test out of the tree again. A red test must not reach the
   integration branch: the job adds it together with the fix, and the gate
   proves it: it must fail on the base and pass on the job
   (`./softwary repro <job>` shows it).
7. Tell the human the spec and the slice; the loop (`run`) does the rest.

You never edit the code that is wrong, a protected path or a check.

## Excuses

| Excuse | Reply |
| --- | --- |
| "The fix is one line; I will just change it." | The fix goes through a spec, a slice and the gate. |
| "I know the cause; no need to see the test fail." | A test you have not seen red proves nothing. |
| "The test passes, but the bug is real." | Then the test is not the bug. Reproduce it first. |
| "No example covers this; I will link the nearest one." | The behaviour is new: it is the human's, through `define`. |
| "I will commit the red test so it is not lost." | A red test breaks the integration branch. Keep it in the slice. |
