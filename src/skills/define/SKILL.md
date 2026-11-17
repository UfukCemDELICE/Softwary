---
name: define
description: Definition stage. Interviews the human one question at a time, with a recommended answer, until every branch of the decision tree is closed, and writes the product definition (product/PRODUCT.md), the shared vocabulary (CONTEXT.md) and the decisions, until ./softwary product check passes. Only a human approves it. Use at the start of a project or when the product changes.
---

# Define

Turn the human's idea into `product/PRODUCT.md`. You ask; the human decides.
Never invent a user, a feature, a number or a constraint: ask. Write no code,
model, spec or slice in this stage.

1. Read what exists first: `./softwary next`, `CONTEXT.md` (start from
   `.softwary/templates/CONTEXT.md`), `product/PRODUCT.md`, the architecture
   model, the specs and the code. Prefer the answer they already give over a
   question.
2. Copy `.softwary/templates/PRODUCT.md` to `product/PRODUCT.md` if it does
   not exist. Keep its nine section headings.
3. Interview the human **one question at a time**. Each question is a single
   question with your own **recommended answer** and the reason for it; the
   human may just say yes. Do not stack questions and do not offer a menu
   without a recommendation.
4. Walk the decision tree: the problem, who the users are, what each of them
   does (short user stories: who, what, why), the scope and what is out of it,
   the non-functional requirements, the constraints, the success metrics. A
   branch is closed only when its answer is written down. **Keep asking until
   every branch is closed**; an answer that opens a new branch gets its own
   questions before you move on.
5. Write each answer **in the conversation, as it is given**: the product
   facts into `PRODUCT.md`; every domain term into `CONTEXT.md` (one
   definition, the words to avoid) and use that word from then on. A choice
   that is hard to reverse, surprising without its context or a real
   trade-off also gets an ADR: copy `.softwary/templates/adr.md` to
   `architecture/decisions/NNNN-<name>.md`, `status: proposed`, `affects`
   naming the file it changes. Never set an ADR to `accepted`; only a human
   does.
6. Write each feature as `### F<n>: <name>` under `## Features`, with at
   least one acceptance example per feature, as a list item:
   `- **EX-F<n>-NN:** Given ..., when ..., then ...`. An example is one
   observable behaviour; its id starts with its own feature's number.
   Examples are what the plan later binds every criterion to, so state
   them precisely enough to test.
7. The open questions, whatever you cannot close yet, go in
   `## Open questions`, one list item each. The product cannot be approved while any is left: ask until
   none remain.
8. Run `./softwary product check`. Fix every line it prints (a missing
   section, a feature without an example, a bad or duplicate example id, a
   remaining `UNSET`, an open question) and run it again until it passes.
9. Give the human the file and the passing check, and say what to read.
   **Only a human approves the product:** the human runs
   `./softwary approve product`. You never run `./softwary approve`.
10. Next stage: `blueprint`. If the human changes `PRODUCT.md` after the
   approval, the approval turns stale (`./softwary status` shows it) and the
   human approves again.
