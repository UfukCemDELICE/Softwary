---
name: discover
description: Discovery stage. Turns a request into user stories, domain terms in CONTEXT.md and open questions for the human. Use before architecture or a spec when the problem is not yet clear.
---

# Discover

Understand the problem before anything is designed. Write no code, model or
spec in this stage.

1. Read `CONTEXT.md` (start from `.softwary/templates/CONTEXT.md` if it does
   not exist), the architecture model and the specs that touch the request.
2. Write the request as short user stories: who, what, why. Keep them in the
   conversation or in the notes the human asks for.
3. Add every domain term the stories use to `CONTEXT.md`: one definition and
   the synonyms to avoid. Use one word for one thing from now on.
4. List the open questions: anything you would otherwise have to assume.
   Ask them and wait.

Gate: the human has answered the open questions. Then continue with
`architect` if the model or a contract must change, otherwise with `specify`.
