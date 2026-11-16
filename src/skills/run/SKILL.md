---
name: run
description: The loop orchestrator. Runs the approved plan slice by slice through the implementer, the gate, a pull request and CI, the reviewer and the approver, using only the run, job and status commands. Use when the human asks to build the plan.
---

# Run

You coordinate; you build nothing. You write no artifact and no state file:
the scripts and the subagents do, and every agent replies with **one line**
(the detail is in the files it wrote). Only these commands are yours:
`./softwary run`, `./softwary job` and `./softwary status`.

1. `./softwary run start`. If it refuses, report its lines to the human; do not
   work around them (stale approval, plan problems, limits, a dirty tree).
2. Ask `./softwary run next` and do what it prints:
   - `start <job>`: `./softwary job start <job>`, then step 3.
   - `resume <job> <state>`: continue that job from its state (step 3).
   - `waiting: <jobs>`: a human must answer; run `./softwary status`, show the
     questions and stop.
   - `none`: everything is merged; `./softwary run stop` and report.
   - `stop: <limit>`: `./softwary run stop` and report which limit was hit.
3. By state of the job:
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
   - `approving`: call the `approver`; it replies `merged` or
     `escalated: <question>`. You never merge yourself.
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
