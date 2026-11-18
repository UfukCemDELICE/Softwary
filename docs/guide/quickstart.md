# Quickstart: your first project

You describe a product; softwary and your tool build it. This page is the
shortest path from an installed package to the first merged slice. Terms are
explained in [concepts](concepts.md), commands in [commands](commands.md).

## 1. Install and set up

Install softwary into your repository ([install](install.md)). Then:

```sh
./softwary doctor
```

Every `FAIL` line is something left to do. Ask your tool to run the `setup`
skill: it asks you for the commands of your project (format, lint, type check,
test, build, security), the two branches, the tools you use and the limits of
the loop, and it places the CI workflow. It finishes when `doctor` passes.

Two files need your attention:

- `.softwary/config/tools.conf`: set each of `claude-code`, `codex` and
  `cursor` to `on` or `off`, then run `./softwary sync`. It writes the skills,
  the subagents and the rules into the folders each tool reads.
- `.softwary/config/models.conf`: when Cursor or Codex is on, give each model
  class the model id of your account there. See [tools](tools.md).

Commit what `sync` generated.

## 2. Define the product

Ask your tool to run the `define` skill. It interviews you one question at a
time, with a recommended answer, until every branch is closed, and writes
`product/PRODUCT.md`: the problem, the users, the features and, for each
feature, examples (`EX-<feature>-NN`) that say what must happen. Check it and
approve it yourself:

```sh
./softwary product check
./softwary approve product
```

Only a human runs `approve`. It records a digest of the files, so a change
after the approval is noticed.

## 3. Draw the blueprint

The `blueprint` skill writes the architecture model (components), the data
model, the flows that cross components, the state machines of the entities that
have states and, for the risky ones, a TLA+ specification with invariants in
plain sentences. A critic subagent tries to break it. Then:

```sh
./softwary blueprint check
./softwary approve blueprint
```

`./softwary next` always tells you, in one line, what the project needs next.

## 4. Plan

The `plan` skill turns the blueprint into one spec per feature and thin,
ordered slices of work. Every criterion of a spec is bound to one of your
product examples. A subagent checks each spec; then:

```sh
./softwary plan check
./softwary plan approve 001
```

## 5. Run the loop

```sh
./softwary run start
```

and ask your tool to run the `run` skill. It starts a job for each ready slice:
a worktree and a branch of its own, the `implementer` writes the test first and
the code, the gate runs `./softwary verify`, a pull request is opened, CI must
be green, the `reviewer` reads it in a clean context, and the `approver` merges
it through a script that recomputes every condition, or hands it to you with
one concrete question. `./softwary status` shows the jobs and the questions
waiting for you. You answer with `./softwary job resume <job> "<answer>"`.

## 6. Ship

When the integration branch holds what you want, run the `ship` skill. It
prepares a pull request from the integration branch to the production branch
with a release note. You write what to watch, how to roll out and how to roll
back; you merge it; softwary never deploys.

## Afterwards

- `maintain`: `./softwary drift` shows where the code and the blueprint differ;
  you decide about each difference.
- `diagnose`: a reported bug is first reproduced by a test, then fixed as a slice.
- `handoff`: writes `.softwary/state/handoff.md` for the next session.
- `evaluate`: measures how many deliberately broken changes the reviewer catches.
