---
name: ship
description: Delivery stage. Prepares the pull request that takes the integration branch to production, with a release note that says what to watch, how to roll out and how to roll back, and opens it for a human to merge. Use when ./softwary next says ship, or when the human asks to release.
---

# Ship

Taking work to production cannot be undone, so it is the human's. You prepare
the proposal and open the pull request. You never merge it and you never run
`deploy`.

1. `./softwary next`. It says `ship (<n> commits ahead of <production>)` when
   there is something to take to production. If it says anything else, stop
   and tell the human what it says.
2. `./softwary ship prepare`. It refuses with one line that names what must
   come first; report that line and do not work around it:
   - a branch that is not set or not there: the human sets it;
   - the production branch has commits the integration branch lacks: the human
     brings them into the integration branch;
   - the tip does not pass the gate: see the log it names; the loop fixes it;
   - `drift has undecided or expired items`: hand over to `maintain`.
3. It prints the path of the note, `.softwary/state/releases/<sha>.md`. Read
   it. The computed sections (`Range`, `Specs`, `Decisions`, `Risk`,
   `Waivers and findings`, `Drift`) are facts; do not edit them. Say to the
   human which paths are R3 and which waivers and findings go with the release.
4. Write the three sections that are for a person, from what the repository
   shows and what the human tells you; ask for the rest, never invent it:
   - `Observability`: the signals to watch after the release (logs, metrics,
     alerts), where they are seen and the value that means trouble;
   - `Rollout`: the steps, their order, the share of users at each step and
     what is checked before the next one;
   - `Rollback`: how to undo the release, who does it, how long it takes and
     the point after which it cannot be undone.
5. `./softwary ship check`. Every line is a problem to fix. If the integration
   branch moved, run `./softwary ship prepare` again: it keeps what you wrote.
6. `./softwary ship pr`. It opens the pull request with the note as its body.
   Give the human its address, and tell them that merging it and deploying are
   theirs: you do neither.

Never edit the integration or the production branch, a configuration file or
the drift decisions to get a step through.

## Excuses

| Excuse | Reply |
| --- | --- |
| "Everything is merged, so I can merge the release too." | Taking work to production is the human's decision. |
| "The note's sections can say `n/a`." | Say what is watched, how it rolls out and how it is undone, or ask the human. |
| "Drift is old; I will decide it." | Decisions about drift are the human's. Use `maintain`. |
| "The gate is red for a reason unrelated to the release." | The tip must pass; report the log and stop. |
| "I will run deploy to check that it works." | You never run deploy. |
