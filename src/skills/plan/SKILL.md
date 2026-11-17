---
name: plan
description: Planning stage. Turns the approved product and blueprint into one spec per feature with criteria bound to product examples, and thin ordered slices; the spec-analyst checks each spec and ./softwary plan approve approves it. Use after the blueprint is approved.
---

# Plan

Cut the approved product into specs and slices that the loop can run. Every
change, however small, has a spec; a spec fits on one page. Do not change
`PRODUCT.md`, the model or a contract here: if the plan needs that, stop and
send the human back to `define` or `blueprint`. Write no code.

1. Run `./softwary status`: both approvals must be `approved`.
2. One spec per feature, or per group of features that cannot be built apart:
   copy `.softwary/templates/spec.md` to `specs/NNN-<name>/spec.md` with the
   next free number, `status: draft`. Fill in `title`, `risk` (R1, R2 or R3;
   ask when unsure), `model` (the component ids it touches) and `contracts`.
   Write the scope, what is out of scope and criteria
   `- **AC-NNN-NN:** <one observable behaviour> (EX-F<n>-NN)`, each testable
   on its own and naming the product example it makes testable. At most 600
   words, and no open questions: ask the human instead.
3. Slices: copy `.softwary/templates/slice.md` to
   `specs/NNN-<name>/slices/S<n>.md`, one end-to-end behaviour each that one
   session can finish; prefer more, thin slices over a few wide ones. Fill in
   `goal`, `acs`, `touches` (the paths it will change; the loop refuses a
   change outside them) and `depends_on`: `S<n>` (same spec) or `NNN-S<n>`
   (another spec); work that others rest on comes first. Keep
   `status: planned`. Every criterion belongs to exactly one slice. A slice
   that fixes a bug carries `repro: <test files>` (each under `test_paths` and
   in `touches`): the gate proves they fail on the base and pass on the job.
   The `diagnose` skill plans those.
4. Run `./softwary trace` and `./softwary plan check` and fix every line:
   a criterion without an example, an unknown example, an unknown dependency,
   a dependency cycle, a stale approval.
5. For each draft spec, call the `spec-analyst` subagent (clean context; on a
   tool without subagents, hand the spec to a fresh session with its
   instructions). It writes `specs/NNN-<name>/analysis.md` and replies `pass`
   or `fail`. On `fail`, fix the spec or slices and call it again; the
   analysis is of one exact version of the spec.
6. On `pass`, run `./softwary plan approve NNN`. It approves the spec only if
   the plan check is clean and the analysis is current; otherwise it says why.
   Never set a spec to `approved` by editing it.
7. Finish with the foundation: the product, the blueprint, the ADRs and the
   plan go into one pull request that the human merges. The loop starts from
   the integration branch once it is merged and the human has accepted the
   ADRs. Tell the human what to read and what to run next: `run`.
