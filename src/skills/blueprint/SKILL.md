---
name: blueprint
description: Blueprint stage. Writes the architecture model, the data model, contracts, flows, state machines and their TLA+ specifications with invariants a human can read, records the decisions as proposed ADRs, and has the blueprint-critic try to break it, until ./softwary blueprint check passes. Only a human approves it. Use after the product is approved.
---

# Blueprint

Design the smallest architecture that delivers the approved product. The
model, the data model, the contracts and the specifications change only here,
and only with an ADR. Ask the human where the product leaves a choice open;
never invent a technology, a component or an interface you were not told or
cannot justify from `PRODUCT.md`. Write no specs, slices or code.

1. Run `./softwary status`: the product approval must be `approved`; if not,
   send the human back to `define`. Read the open ADRs and `CONTEXT.md`.
2. Model: start from `.softwary/templates/system.calm.json` into
   `architecture/model/system.calm.json`. Give each component its `paths`,
   `risk`, `status` and `metadata.features` (the product features it
   delivers). Every feature must be delivered by a component and no component
   may name a feature the product does not have. Run
   `./softwary model validate` and `./softwary views` until both pass; never
   edit a view by hand.
3. Data model: `.softwary/templates/data-model.json` into
   `architecture/data/model.json`: entities, fields, relations. Only what the
   features need.
4. Contracts: where two components meet, the interface under
   `architecture/contracts/`. Keep them minimal: the approval binds them.
5. Flows: a feature that several components deliver needs
   `architecture/flows/<id>.json` (`.softwary/templates/flow.json`):
   participants, steps, the entities involved. Add `traits` (`concurrency`,
   `retry`, `crash`) when they apply; such a flow needs a specification.
6. State machines: each entity with a lifecycle gets
   `architecture/states/<entity>.json` (`.softwary/templates/states.json`):
   states, initial, final, transitions. Each needs a specification.
7. Specifications, one per state machine or risky flow, in
   `architecture/formal/`: `<name>.tla` (an action named exactly like each
   event), `<name>.cfg` (the model as it should be), one
   `<name>-<variant>.cfg` per invariant that breaks exactly it, and
   `<name>.md` from `.softwary/templates/formal.md`. Write every invariant as
   one plain sentence a human can approve, with the harm if it breaks.
   Without Java: `./softwary formal install` and install a Java runtime.
   Run `./softwary formal check`. A failing good model is a finding: print its
   path to the human; fix the design or ask, never weaken the invariant so
   that it passes.
8. Decisions: for each choice a human might later question, an ADR from
   `.softwary/templates/adr.md` in `architecture/decisions/` with
   `status: proposed` and `affects` naming what it changes. Never set
   `accepted`: only a human does.
9. Run `./softwary blueprint check` and fix every line until it passes.
10. Call the `blueprint-critic` subagent (clean context; on a tool without
    subagents, hand it to a fresh session with its instructions). It writes
    `architecture/critique.md` and replies `pass` or `changes`. On `changes`,
    fix what it proved and call it again: its record names one exact version.
11. Give the human the blueprint, the invariant sentences and the critique, and
    say what to read. **Only a human approves the blueprint:** the human runs
    `./softwary approve blueprint` (it needs a current product approval and the
    critic's pass). You never run `./softwary approve`.
12. Next stage: `plan`.
