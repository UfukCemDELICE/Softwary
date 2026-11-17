---
name: maintain
description: Maintenance stage. Runs ./softwary drift and asks the human to decide every difference between the blueprint and the code (accept it, change the blueprint, or fix the code through a spec), writing each decision with a date and a reason to architecture/drift.md. Use when drift reports items, when ship refuses for drift, or as a regular check.
---

# Maintain

The blueprint says what the system is; the code says what it has become.
`./softwary drift` lists where they differ. The loop goes on while items are
open; `ship` stops. Every decision is the human's.

1. Run `./softwary drift`. Each line is `drift: <item>: <state>`; the kinds are
   `uncovered <path>` (code no component owns), `missing <component> <path>`,
   `empty <component>`, `planned-with-code <component>`,
   `unexercised <EX>` (a product example no test names),
   `untested ST-<entity>-<state>-<event>` (a test a state machine owes that no
   test names; `./softwary states tests` lists them all) and
   `unreplayed CE-<spec>-<invariant>` (a finding no test replays;
   `./softwary formal trace <spec> <invariant>` prints its steps).
2. For each item that is `undecided` or `expired`, one at a time: say what you
   found in the code and the blueprint, recommend an answer and why, and ask:
   - `accept`: the code stays as it is and the difference is known;
   - `blueprint`: the blueprint is wrong; it will be changed to match (send the
     human to `blueprint`);
   - `fix <spec number>`: the code is wrong; a spec will change it (`plan`, or
     `diagnose` when it is a bug). For `untested` and `unreplayed` items it is
     the usual answer: a spec whose tests name the identifier.
3. Write the answer as a row of the table in `architecture/drift.md`, copied
   from `.softwary/templates/drift.md` when the file is not there:
   `| <item exactly as drift prints it> | <decision> | <YYYY-MM-DD> | <reason> |`.
   The date, until when the decision holds, and the reason are the human's:
   never invent them.
4. Remove the rows that drift calls `stale decision`: what they decided is no
   longer there.
5. Run `./softwary drift` again until every item is decided and none expired.

Do not change the model, the code or a decision to shrink drift, and do
not decide an item the human has not answered.

## Excuses

| Excuse | Reply |
| --- | --- |
| "The difference is obviously harmless; I will accept it." | Only the human decides. Recommend, then ask. |
| "I will extend the component's paths so nothing is uncovered." | That changes the blueprint, which needs approval. Ask. |
| "The date can be far away; nobody will look." | Ask the human for the date: a decision is taken again by then. |
| "The decision expired yesterday; it still holds." | An expired decision is open again. Ask. |
| "I will delete the unexercised example." | The product definition is the human's. |
