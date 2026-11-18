---
name: run
description: The loop orchestrator. Runs the approved plan slice by slice, several jobs at once, through the implementer, the gate, a pull request and CI, the reviewer and the approver, using only the run, job, queue and status commands. Use when the human asks to build the plan.
---

# Run

You coordinate; you build nothing. You write no artifact and no state file:
the scripts and the subagents do, and every agent replies with **one line**
(the detail is in the files it wrote). Only these commands are yours:
`./softwary run`, `./softwary job`, `./softwary queue` and `./softwary status`.
Every job works in its own worktree, `.softwary/worktrees/<job>`, on branch
`softwary/<job>`; the main checkout stays on the integration branch.

1. `./softwary run start`. If it refuses, report its lines to the human; do not
   work around them (stale approval, plan problems, limits, a dirty tree,
   `bootstrap` UNSET, an integration branch that is still red).
2. Ask `./softwary run next`. It prints **one line for each thing to do**; do
   all of them (at most `concurrency` jobs run at once; the scripts refuse
   more, and a slice that crosses a running one waits):
   - `start <job>`: `./softwary job start <job>`, then step 3.
   - `resume <job> <state>`: continue that job from its state (step 3). A job
     that already has an agent working on it is not started a second time.
   - `drain`: the merge queue has jobs and nobody merges them:
     `./softwary queue drain`.
   - `merging: <jobs>`: someone is merging them; do nothing for those jobs.
   - `waiting: <jobs>`: a human must answer; run `./softwary status`, show the
     questions, and go on with the other lines.
   - `none`: everything is merged; `./softwary run stop` and report. Say that
     the integration branch can now go to production with the `ship` skill, if
     the human wants it: that pull request and its merge are theirs, never yours.
   - `stop: <why>` alone: do not call `run stop`. Report `./softwary status`
     and the reason: after a red merge the human decides about the revert PR,
     then `./softwary run start` goes on; for a run limit `./softwary run stop`.
3. By state of the job (each job on its own; call an agent by its name, and run
   agents and long commands such as `job gate` and `job ci` in the background
   if the tool can; when one finishes ask `./softwary run next` again):
   - `implementing`: call the `implementer` with the job id. It replies
     `done`, `blocked: <reason>` or `advice: <question>`.
     `done`: `./softwary job event <job> implemented`, then
     `./softwary job gate <job>`. `blocked`: `./softwary job escalate <job>
     "<question for the human>"`. `advice`: **you** call the `advisor`
     yourself (a subagent cannot call another) with the question; it replies
     `advice written`; call the implementer again and tell it to read
     `.softwary/state/jobs/<job>/advice.md`.
   - `pr`: `./softwary job pr <job>`. `ci`: `./softwary job ci <job>`.
   - `reviewing`: call the `reviewer` (clean context; it replies `approve` or
     `changes`), then `./softwary job review <job>`.
   - `approving`: call the `approver`; it replies `merged`, `queued` or
     `escalated: <question>`. You never merge yourself: the approver's
     decision is queued and `./softwary queue drain` runs the script that
     recomputes every condition.
   - `queued`: the job is in the merge queue; `drain` or `merging:` covers it.
   - `escalated`: stop for this job and tell the human the question.
4. After each agent call add its token use with
   `./softwary job tokens <job> <n>` when the tool reports it.
5. A failed gate, red CI or requested changes return the job to
   `implementing` in a new round; the scripts count the rounds and escalate at
   the limit. Never retry a step that a script refused.
6. When the human answers a question: `./softwary job resume <job> "<answer>"`
   (or `./softwary job abandon <job> "<reason>"`), then continue with
   `./softwary run next`. After the human merges a PR by hand:
   `./softwary job merged <job>`.

Never edit a spec, slice, review, config or state file yourself, and never
weaken a check.

## Excuses

| Excuse | Reply |
| --- | --- |
| "The script refused; I will try it again." | Never retry a refused step. Report the refusal to the human. |
| "CI is green, so I can merge by hand." | You never merge. The approver and the script decide. |
| "The reviewer is slow; I will write the review." | Only the reviewer writes it, in a clean context. |
| "Auto-merge is off, but the change is small." | Leave the PR to the human; say what `./softwary status` shows. |
| "The slice crosses a running job; start it anyway." | The script refuses it; wait for `run next` to print `start`. |
