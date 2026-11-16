---
name: setup
description: Set up softwary in this repository. Fills the configuration and the branches, drafts a baseline model and ADR for existing code, places the CI template, and finishes when doctor passes. Use right after install.sh or when ./softwary doctor reports problems.
---

# Setup

Get this repository to a state where `./softwary doctor` passes. Never invent
a command, a branch, an owner or a risk tier you do not know: ask the human.

1. Run `./softwary doctor`. Every FAIL line is something left to do.
2. `.softwary/config/commands.conf`: for each `UNSET` key, look at the
   repository's manifests and scripts and propose a command. Ask the human to
   confirm it, and ask outright for any you cannot find. Use `NONE: <reason>`
   only with a reason the human gave you. Set `test_paths` to the test
   directories and `src_paths` to the source directories (every change under
   them needs a spec). Also ask which markers of the test framework skip a
   test or focus a run, and write them as patterns in
   `.softwary/config/test-skip.conf` (or `NONE: <reason>` if there is no
   framework yet); `guard` reports every added line that matches one.
3. Ask for the two branches and set them in `commands.conf`:
   `integration_branch` (where finished work is merged, through pull
   requests; changes are checked against it) and `production_branch` (what
   is released; only a human moves work there).
4. `.softwary/config/tools.conf`: ask which of the tools listed there the
   team uses; set each to `on` or `off`.
5. `.softwary/config/loop.conf`: the limits of the loop. Keep the defaults
   if the human agrees (3 rounds, 45 minutes a job, 240 minutes a run) and ask
   for `max_job_tokens` and `max_run_tokens`: how many tokens a job and a run
   may use, or `NONE: <reason>`. `min_catch_percent` is the share of the
   evaluation's broken changes the reviewer must catch before merges happen
   without a human; propose 90 and ask. They start `UNSET`; `doctor` fails until set.
   `.softwary/config/models.conf` names the model of each subagent; keep it
   unless the human wants another.
6. `.softwary/config/risk.conf`: ask for the `default` tier (R1, R2 or R3) and
   which paths deserve a higher one.
7. An empty repository (no code yet): do not draft a model. Create each
   `src_paths` directory with a `.gitkeep` file so it exists. The `model` line
   of `doctor` stays FAIL until the model is written; tell the human the next
   steps are `define` (the product) and then `blueprint` (the model), or
   `discover` and `architect` to walk the stages by hand.
8. A repository with code, and no `architecture/model/system.calm.json`:
   draft the model from the code. Start from
   `.softwary/templates/system.calm.json`, describe only components you can
   see, set their `paths`, `risk` and `status`, then run
   `./softwary model validate` and `./softwary views` until both pass. Record
   the draft as the baseline: copy `.softwary/templates/adr.md` to
   `architecture/decisions/0001-baseline-model.md`, list in it
   the paths each component is drawn from, set `status: proposed` and
   `affects: architecture/model/system.calm.json`. Never set an ADR to
   `accepted`; only a human does.
9. Copy `.softwary/templates/softwary.yml` to `.github/workflows/softwary.yml`.
   Replace both `branches: [UNSET]` with the integration branch, and the
   `Install tools` step with the commands that install what `commands.conf`
   needs on the CI machine (ask the human for them).
10. `.github/CODEOWNERS` is optional. Copy `.softwary/templates/CODEOWNERS`
   only if the human wants owners; then ask for them and replace every
   `UNSET`.
11. Run `./softwary sync`, then `./softwary doctor`. Repeat from the failing
    line until it reports no problems (in an empty repository, until only
    `model` is left).
12. Tell the human what is left for them: accept the baseline ADR if there is
    one, commit the result, and protect the integration branch: require pull
    requests and require the `softwary` status check to pass;
    do not require a human review, since merges are gated by the checks.

Do not edit generated files, and do not weaken a check to get `doctor` to pass.
