---
name: handoff
description: Session handoff. Writes .softwary/state/handoff.md from the project's files, adds the notes only this session knows, and tells the next session to start by reading it. Use when a session ends or its context is full.
---

# Handoff

A new session knows nothing but the files. Leave it what the files do not
say.

1. Run `./softwary handoff`. It writes `.softwary/state/handoff.md` (time,
   branch and commit, the working tree, the next step, the approvals, the
   jobs and their questions, the last ten events) and prints the path. Do not
   edit anything above `## Notes`: the next run rewrites it.
2. Read the file. Under `## Notes`, write what a fresh session cannot read
   from the repository:
   - decisions the human made in this conversation that are not in
     `CONTEXT.md`, an ADR or `PRODUCT.md` yet (and put them there too);
   - what you tried and dropped, and why;
   - a question that is waiting for the human, one concrete question each;
   - anything half done and where it stands.
   Notes are kept when `./softwary handoff` runs again, so keep them short and
   delete what has become true in the files.
3. Never write a secret, a token or a credential in the notes. Do not commit
   the file: it lives under `.softwary/state/`, which is local.
4. End your last message with one line for the human: `Start the next session
   by reading .softwary/state/handoff.md.` The new session reads that file
   first, then runs `./softwary next` to see the step.

A handoff does not approve, merge or change anything in the project.
