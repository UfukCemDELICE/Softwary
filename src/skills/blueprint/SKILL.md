---
name: blueprint
description: Blueprint stage. Writes the architecture model with the product features each component delivers, the data model, contracts where components meet, and a proposed ADR, until ./softwary blueprint check passes. Only a human approves it. Use after the product is approved.
---

# Blueprint

Design the smallest architecture that delivers the approved product. Ask the
human where the product leaves a choice open; never invent a technology, a
component or an interface you were not told or cannot justify from
`PRODUCT.md`.

1. Run `./softwary status`: the product approval must be `approved`. If it is
   not, stop and send the human back to `define`.
2. Model: start from `.softwary/templates/system.calm.json` into
   `architecture/model/system.calm.json`. Give each component its `paths`,
   `risk`, `status` and `metadata.features`, the list of product features
   (`F1`, `F2`, ...) it delivers. Every feature of `PRODUCT.md` must be
   delivered by at least one component, and no component may name a feature
   the product does not have. Run `./softwary model validate` and
   `./softwary views` until both pass.
3. Data model: start from `.softwary/templates/data-model.json` into
   `architecture/data/model.json`: entities (`id`, `name`, `fields` with
   `type`, `relations` with `to` and `kind`). Only what the features need.
4. Contracts: where two components meet, write the interface under
   `architecture/contracts/` (an OpenAPI or schema file, whatever the stack
   uses). Their content is bound by the approval, so keep them minimal.
5. Decisions: for each choice a human might later question, copy
   `.softwary/templates/adr.md` to `architecture/decisions/`, with
   `status: proposed` and `affects` naming the model or contract it changes.
   Never set an ADR to `accepted`; only a human does.
6. Run `./softwary blueprint check`. Fix every line (a model or data model
   problem, a feature no component delivers, an unknown feature) and run it
   again until it passes.
7. Give the human the model, the view, the data model, the contracts and the
   proposed ADRs, and say what to read. **Only a human approves the
   blueprint:** the human runs `./softwary approve blueprint` (it needs the
   product approval to be current). You never run `./softwary approve`.
8. Next stage: `plan`.

Do not write specs, slices or code in this stage.
