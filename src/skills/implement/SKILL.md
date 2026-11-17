---
name: implement
description: Implementation stage. Implements one planned slice of an approved spec test first, then makes ./softwary verify pass and hands the slice to review. Delegates to the implementer subagent where the tool has one.
---

# Implement

One slice per session. Where the tool has subagents, give the slice to the
`implementer` subagent; otherwise follow these steps yourself.

1. Pick a `planned` slice whose `depends_on` slices are done, of a spec whose
   status is `approved`. Set the slice to `status: in-progress`.
2. Write the test first. Each test names the criterion id it covers
   (`AC-NNN-NN`) and fails for the right reason before any code exists.
3. Write the least code that makes the tests pass, inside the slice's
   `touches` where possible.
4. While iterating, run `./softwary verify --fast` (format, lint, types).
   Once, before review, run the full `./softwary verify` and fix what it
   reports; it also checks the change against the integration branch. Show
   its output.
5. The slice changes code that a specification covers (the model is `stale`
   in `./softwary formal check`, and the slice touches its record): check the
   model again against the code you leave. Commit the code first, then record
   the verdict and commit the record:
   - the model still describes the code: `./softwary formal verified <spec> compatible`;
   - the model had to follow the code (`.tla`, `.cfg` and the record's other
     sections only): commit it, then `./softwary formal verified <spec> updated`;
   - the code breaks an invariant (`bug`) or you cannot decide (`blocked`):
     `./softwary job escalate <job> <question>`.
   A counter-example of a finding that does not replay against the code
   (`./softwary formal trace <spec> <invariant>`) means the model is wrong
   before the code is: suspect the model first.
6. Add short notes to the slice: what changed, what was surprising.
7. Set the slice to `status: review` and continue with `review`.

Four things are forbidden:

- weaken a test, a check or a gate to get it to pass;
- change `.softwary/config/` files;
- change the model or a contract; that belongs to the `blueprint` stage. Stop
  and say so when the slice needs it;
- change an invariant's sentence, a finding or the files of
  `architecture/formal/` to get a model through: they bind a human.

If the same failure is still there after three attempts, stop, describe what
you tried and ask the human.

## Excuses

| Excuse | Reply |
| --- | --- |
| "The test is wrong, I will skip it." | Skipping a test is loosening it. Stop and ask the human. |
| "It only fails on the gate; it is flaky." | The gate decides. Fix the cause, or stop and say what you saw. |
| "A small change to a config file will do." | Configuration and the paths softwary protects are not yours. Stop and ask. |
| "This file is outside the slice, but it needs the fix." | The slice's `touches` is the limit. Say what is needed. |
| "The model is stale; I will loosen the invariant." | The invariant is the human's. `bug` or `blocked`: `job escalate`. |

Gate: `./softwary verify` passes.
