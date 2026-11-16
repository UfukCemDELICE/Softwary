---
name: plan
description: Planning stage. Turns the approved product and blueprint into one spec per feature with criteria bound to product examples, and ordered slices; the spec-analyst checks each spec and ./softwary plan approve approves it. Use after the blueprint is approved.
---

# Plan

Cut the approved product into specs and slices that the loop can run. Do not
change `PRODUCT.md`, the model or a contract here: if the plan needs that, stop
and send the human back to `define` or `blueprint`.

1. Run `./softwary status`: both approvals must be `approved`.
2. One spec per feature, or per group of features that cannot be built apart:
   copy `.softwary/templates/spec.md` to `specs/NNN-<name>/spec.md`
   (`status: draft`). List the model components it touches in `model`. Write
   criteria `- **AC-NNN-NN:** <one observable behaviour> (EX-F<n>-NN)`, each
   naming the product example it makes testable. At most 600 words, and no
   open questions: ask the human instead.
3. Slices: copy `.softwary/templates/slice.md` to
   `specs/NNN-<name>/slices/S<n>.md`, one end-to-end behaviour each, with
   `acs`, `touches` and `depends_on`. A dependency is `S<n>` (same spec) or
   `NNN-S<n>` (a slice of another spec); order them so work that others rest on
   comes first. Every criterion belongs to exactly one slice.
4. Run `./softwary trace` and `./softwary plan check` and fix every line:
   a criterion without an example, an unknown example, an unknown dependency,
   a dependency cycle, a stale approval.
5. For each draft spec, call the `spec-analyst` subagent (clean context). It
   writes `specs/NNN-<name>/analysis.md` and replies `pass` or `fail`. On
   `fail`, read the findings, fix the spec or slices, and call it again; the
   analysis is of one exact version of the spec.
6. On `pass`, run `./softwary plan approve NNN`. It approves the spec only if
   the plan check is clean and the analysis is current; otherwise it says why.
7. Finish with the foundation: the product, the blueprint, the ADRs and the
   plan go into one pull request that the human merges. The loop starts from
   the integration branch once it is merged and the human has accepted the
   ADRs. Tell the human what to read and what to run next: `run`.

Do not write code. Do not set a spec to `approved` by editing it.
