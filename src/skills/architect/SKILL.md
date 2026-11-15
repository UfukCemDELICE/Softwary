---
name: architect
description: Architecture stage. Changes the architecture model, the contracts and their views, and records the decision as a proposed ADR for the human to accept. The only stage that may change the model or contracts.
---

# Architect

The model (`architecture/model/system.calm.json`) and the contracts
(`architecture/contracts/`) change only here, and only with an ADR.

1. Read the model, the contracts, the open ADRs (`./softwary status`) and the
   answers from discovery.
2. Write the decision first: copy `.softwary/templates/adr.md` to
   `architecture/decisions/NNNN-<name>.md` with the next number. Fill in the
   context, the options table and the consequences. Set `status: proposed`
   and list in `affects` every model or contract path it changes.
3. Change the model: components keep `paths`, `risk` and `status` in their
   metadata. Run `./softwary model validate` until it passes, then
   `./softwary views` to regenerate the diagram. Never edit the view by hand.
4. Change or add the contracts the decision needs.
5. Run `./softwary trace` and `./softwary adr` to see what is left.

Never set an ADR to `accepted` yourself: only a human does. `adr` keeps
failing until they do.

Gate: the human accepted the ADR. Then continue with `specify`.
