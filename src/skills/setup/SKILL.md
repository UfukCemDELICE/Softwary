---
name: setup
description: Set up softwary in this repository. Fills the configuration and the branches, asks the human to fix or waive every project check that is red in existing code, places the CI template, and finishes when doctor passes. Use right after install.sh or when ./softwary doctor reports problems.
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
   `concurrency` (1 to 3, default 3) is how many jobs run at once. Also ask for
   `bootstrap` in `commands.conf`: the command that prepares a fresh worktree
   (install dependencies), or `NONE: <reason>`; the loop will not start with it `UNSET`.
   `.softwary/config/models.conf` names the model of each subagent; keep it
   unless the human wants another.
6. `.softwary/config/risk.conf`: ask for the `default` tier (R1, R2 or R3) and
   which paths deserve a higher one.
7. An empty repository (no code yet): do not draft a model. Create each
   `src_paths` directory with a `.gitkeep` file so it exists. The `model` line
   of `doctor` stays FAIL until the model is written; tell the human the next
   steps are `define` (the product) and then `blueprint` (the model).
8. A repository with code: do not draw the model and do not write a baseline
   ADR here: `blueprint` does both, from the code (its ADR is
   `.softwary/templates/adr.md`, `status: proposed`). Find the checks that
   fail with `./softwary verify --base <integration branch>`; without a model
   it stops at `model` (exit 2), so then run `./softwary verify --fast` and the
   command of every other key in `commands.conf` yourself, from the
   repository root. Every project check that fails was debt before softwary
   came. Ask the human, for each one: fix it now, or
   waive it. A waiver is a line `<key> = <YYYY-MM-DD>: <reason>` in
   `.softwary/config/waivers.conf`; after the date the check fails again. A
   waived check also runs on the files of every change, so ask for
   `<key>_files` in `commands.conf`: the same check with `{files}` where the
   changed files go (the linter on given files), or `NONE: <reason>` when it
   cannot run on files. The date, the reason and the command are the
   human's; never invent them. Run `verify` again until each failing check
   is fixed or waived.
9. Copy `.softwary/templates/softwary.yml` to `.github/workflows/softwary.yml`.
   Replace `branches: [UNSET, UNSET]` (`pull_request`) with
   the integration branch and the production branch, `branches: [UNSET]`
   (`push`) with the integration branch, and the `Install tools` step with the
   commands that install what `commands.conf` needs on the CI machine (ask
   the human). An existing workflow stays the project's own: tell the human to
   add the production branch to its `pull_request` branches.
10. `.github/CODEOWNERS` is optional. Copy `.softwary/templates/CODEOWNERS`
   only if the human wants owners; then ask for them and replace every
   `UNSET`.
11. Run `./softwary sync`, then `./softwary doctor`. Repeat from the failing
    line until it reports no problems (until only `model` is left, when the
    repository has no model yet).
12. Tell the human what is left for them: commit the result, and protect the
    integration branch: require pull requests and
    require the `softwary` status check to pass;
    do not require a human review, since merges are gated by the checks.
    The next steps are `define` (what the product does today) and then
    `blueprint` (the model, from the code).

Do not edit generated files, and do not weaken a check to get `doctor` to pass.
