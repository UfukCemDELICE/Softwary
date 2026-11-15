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
4. Run `./softwary verify` and fix what it reports. Show its output.
5. Add short notes to the slice: what changed, what was surprising.
6. Set the slice to `status: review` and continue with `review`.

Three things are forbidden:

- weaken a test, a check or a gate to get it to pass;
- change `.softwary/config/` files;
- change the model or a contract; that belongs to the `architect` stage. Stop
  and say so when the slice needs it.

If the same failure is still there after three attempts, stop, describe what
you tried and ask the human.

Gate: `./softwary verify` passes.
