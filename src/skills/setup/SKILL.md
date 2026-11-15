---
name: setup
description: Set up softwary in this repository. Fills the configuration, drafts a baseline model and ADR for existing code, places the CI and CODEOWNERS templates, and finishes when doctor passes. Use right after install.sh or when ./softwary doctor reports problems.
---

# Setup

Get this repository to a state where `./softwary doctor` passes. Never invent
a command, an owner or a risk tier you do not know: ask the human.

1. Run `./softwary doctor`. Every FAIL line is something left to do.
2. `.softwary/config/commands.conf`: for each `UNSET` key, look at the
   repository's manifests and scripts and propose a command. Ask the human to
   confirm it, and ask outright for any you cannot find. Use `NONE: <reason>`
   only with a reason the human gave you. Set `test_paths` to the test
   directories and `src_paths` to the source directories (every change under
   them needs a spec).
3. `.softwary/config/tools.conf`: ask which of the tools listed there the
   team uses; set each to `on` or `off`.
4. `.softwary/config/risk.conf`: ask for the `default` tier (R1, R2 or R3) and
   which paths deserve a higher one.
5. If the repository has code and `architecture/model/system.calm.json` does
   not exist, draft the model from the code. Start from
   `.softwary/templates/system.calm.json`, describe only components you can
   see, set their `paths`, `risk` and `status`, then run
   `./softwary model validate` and `./softwary views` until both pass.
6. Record that draft as the baseline. Copy `.softwary/templates/adr.md` to
   `architecture/decisions/0001-baseline-model.md`, fill it in, set
   `status: proposed` and `affects: architecture/model/system.calm.json`.
   Never set an ADR to `accepted`; only a human does.
7. Copy `.softwary/templates/softwary.yml` to `.github/workflows/softwary.yml`
   and `.softwary/templates/CODEOWNERS` to `.github/CODEOWNERS`. Ask for the
   GitHub owners and for the commands that install the tools `commands.conf`
   needs, and replace every `UNSET`.
8. Run `./softwary sync`, then `./softwary doctor`. Repeat from the failing
   line until it reports no problems.
9. Tell the human what is left for them: accept the baseline ADR, commit the
   result, and turn on "Require review from Code Owners" in the branch
   protection of `main`.

Do not edit generated files, and do not weaken a check to get `doctor` to pass.
