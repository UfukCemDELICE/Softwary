# Concepts

Each idea is explained once, here. The other pages link to it.

## The idea

A rule written in a prompt is a request; a rule checked by a script is a gate.
softwary keeps the critical rules in scripts: a check that is not configured
fails, a known debt is a waiver with a date, and nothing counts as passed
because an agent says so. Agents write the work; scripts decide whether it may
go on.

## The stages

| Stage | Skill | What comes out |
| --- | --- | --- |
| Set up | `setup` | A configuration that makes `doctor` pass |
| Define | `define` | `product/PRODUCT.md`, `CONTEXT.md` (the shared vocabulary) |
| Blueprint | `blueprint` | The architecture model, data model, flows, state machines, TLA+ specifications, decisions |
| Plan | `plan` | A spec per feature, thin ordered slices |
| Build | `run`, `implement`, `review` | Merged pull requests |
| Ship | `ship` | A pull request from the integration branch to production, with a release note |
| Maintain | `maintain`, `diagnose` | Decisions about drift; bugs reproduced by a test first |

## Artifacts

| Artifact | Where | Approval |
| --- | --- | --- |
| Product definition | `product/PRODUCT.md`: problem, users, features, examples `EX-<feature>-NN` | You: `approve product` |
| Blueprint | `architecture/model/`, `architecture/data/`, `architecture/contracts/` | You: `approve blueprint` |
| Flows and state machines | `architecture/flows/`, `architecture/states/` | None; the loop may update them |
| Formal specifications | `architecture/formal/<name>.tla` and `<name>.md` | The plain sentence of each invariant is yours to approve |
| Decisions | `architecture/decisions/NNNN-name.md` (ADRs) | You, when one changes a binding part |
| Specs and slices | `specs/NNN-name/spec.md`, `slices/Sx.md` | Automatic, when each criterion is bound to a product example |
| Drift decisions | `architecture/drift.md` | You |

A criterion is an `AC-NNN-NN` identifier in a spec. A test that names it
(`AC-001-02`) is what `trace` looks for.

## The loop

One orchestrator session drains the plan. For each ready slice a **job** starts
in its own git worktree and branch (`softwary/<job>`):

1. the `implementer` writes the test first, then the code (`verify --fast`);
2. the **gate**: the full `verify` on the job's worktree;
3. a pull request and CI;
4. the `reviewer`, in a clean context, with evidence for every finding;
5. the `approver`: asks the merge script to merge, or escalates with a question;
6. the **merge queue**: one merge at a time; the script recomputes the gate on
   the commit to merge and merges the pull request bound to that commit.

State lives in files (`.softwary/state/`) and every transition is applied by a
script from a table and written to an event log, so a dead session resumes from
the files. The limits are in `loop.conf`: rounds, minutes and tokens.

You are asked in four places: the approvals, a job escalated with a question,
drift decisions, and taking the integration branch to production.

## What a merge needs

The merge script refuses unless, on the commit it merges: the gate and CI are
green; the diff is inside the slice's `touches`; no test was deleted, skipped
or loosened; no criterion identifier was removed; no protected path changed
(`.softwary/`, CI, `CODEOWNERS`, the product definition, the binding parts of
the blueprint); the risk tier is below R3; and the limits are not exceeded.
R3 changes and protected-path changes always come to you.

## Risk tiers

`.softwary/config/risk.conf` maps path patterns to R1 (low), R2 (normal) and R3
(critical). A change takes the highest tier of the paths it touches.

## Waivers

An existing project may fail some of its own checks on day one. A waiver
(`.softwary/config/waivers.conf`: `<check> = <date>: <reason>`) makes a failing
check yellow until the date and requires a scoped command that runs the check
on the changed files, so the debt does not grow. After the date the check
fails again. Package checks cannot be waived.

## Roles and models

| Role | Does |
| --- | --- |
| `spec-analyst`, `blueprint-critic` | Check a spec or the blueprint before you approve it |
| `implementer` | Implements one slice |
| `advisor` | Answers the implementer's question; reads, never writes code |
| `reviewer`, `approver` | Review and decide; they must run on a different model than the implementer |

`.softwary/config/models.conf` gives each role a model class, and each tool a
model id for each class. The rule that the reviewer and the approver do not
share the implementer's model is checked by `doctor` and `run start` in every
tool that is on. See [tools](tools.md).

## Generated files

The sources are in `.softwary/` (rules, skills, agents). `./softwary sync`
writes them into the folders each tool reads and records a checksum of each in
`.softwary/generated`. A generated file edited by hand is reported, and
`sync` does not touch a file it did not generate. Files from `local/` override
same-named package files. Commit the generated files; `verify` checks that they
are current.

## Formal specifications

For state machines and flows with concurrency, retries or crashes, the
blueprint holds a TLA+ model whose invariants are written as plain sentences.
`./softwary formal check` runs the model checker; every invariant must also
fail on a deliberately broken variant, or the check proves nothing. The
checker proves the model, not the code: counter-examples are replayed against
the code as tests, and a model older than the code it covers fails the check
until someone records a verdict (`formal verified`).
