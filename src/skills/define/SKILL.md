---
name: define
description: Definition stage. Interviews the human one question at a time and writes the product definition (product/PRODUCT.md) and the shared vocabulary (CONTEXT.md), until ./softwary product check passes. Only a human approves it. Use at the start of a project or when the product changes.
---

# Define

Turn the human's idea into `product/PRODUCT.md`. You ask; the human decides.
Never invent a user, a feature, a number or a constraint: ask.

1. Copy `.softwary/templates/PRODUCT.md` to `product/PRODUCT.md` if it does
   not exist. Keep its nine section headings.
2. Interview the human **one question at a time**, each with your own
   recommended answer, until every branch is settled: the problem, the users,
   the scope and what is out of it, the non-functional requirements, the
   constraints and the success metrics. Prefer the answer the code or
   `CONTEXT.md` already gives over asking.
3. Write each feature as `### F<n>: <name>` under `## Features`, with at
   least one acceptance example per feature, as a list item:
   `- **EX-F<n>-NN:** Given ..., when ..., then ...`. An example is one
   observable behaviour; its id starts with its own feature's number.
   Examples are what the plan later binds every criterion to, so state
   them precisely enough to test.
4. Keep `CONTEXT.md` (`.softwary/templates/CONTEXT.md`) up to date with each
   term as it is settled; use those terms in `PRODUCT.md`.
5. Anything still open goes in `## Open questions`, one list item each. The
   product cannot be approved while any is left: ask until none remain.
6. Run `./softwary product check`. Fix every line it prints (a missing
   section, a feature without an example, a bad or duplicate example id, a
   remaining `UNSET`, an open question) and run it again until it passes.
7. Give the human the file and the passing check, and say what to read.
   **Only a human approves the product:** the human runs
   `./softwary approve product`. You never run `./softwary approve`.
8. Next stage: `blueprint`. If the human changes `PRODUCT.md` after the
   approval, the approval turns stale (`./softwary status` shows it) and the
   human approves again.

Do not write code, a model, a spec or a slice in this stage.
