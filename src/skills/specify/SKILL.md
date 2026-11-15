---
name: specify
description: Spec stage. Writes specs/NNN-name/spec.md with numbered acceptance criteria, has it checked by the spec-analyst subagent in a clean context, and leaves it as a draft for the human to approve.
---

# Specify

Every change, however small, has a spec. A spec fits on one page.

1. Copy `.softwary/templates/spec.md` to `specs/NNN-<name>/spec.md` with the
   next free number. Keep `status: draft`.
2. Fill in `title`, `risk` (R1, R2 or R3; ask when unsure), `model` (the
   component ids it touches) and `contracts` (contract files, if any).
3. Write the scope, what is out of scope and the acceptance criteria. Each
   criterion is `AC-NNN-NN`, observable and testable on its own.
4. Put everything you do not know under `## Open questions`. A spec with an
   open question cannot be approved.
5. Run `./softwary trace` until it passes.
6. Have the `spec-analyst` subagent check the spec in a clean context. On a
   tool without subagents, hand the spec to a fresh session with the
   spec-analyst instructions. Address its findings or turn them into open
   questions.

Never set a spec to `approved` yourself: only a human does.

Gate: the human approved the spec. Then continue with `slice`.
