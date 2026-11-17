# UNSET

<!-- The record of one TLA+ specification: architecture/formal/<name>.md next
to <name>.tla (the model), <name>.cfg (the model as it should be) and
<name>-<variant>.cfg (one broken variant for each invariant). Keep the six
section headings. A state machine's every event is an action below, named
exactly like the TLA+ action. The Invariants table is bound by the blueprint
approval: a human reads those sentences.

Coverage names the files and functions of the code the model describes (a
path that is there, each function a word of it); `planned` while the code does
not exist. Last verified is never edited by hand: `./softwary formal verified
<name> compatible|updated` writes "<commit> <verdict>" once the model checks
against the code as committed. Until then, and after the covered files, the
model or the Coverage table change, `formal check` reports the model as stale.

Optional: when the code this model describes already breaks an invariant, do
not weaken the invariant or the model. Add a section "## Findings" to the
record, a table with the columns | Invariant | Until | Reason | and a row for
each invariant. The date is YYYY-MM-DD; the finding is reported until then and fails after it.
The table is bound by the blueprint approval too. -->

## Invariants

| Name | Statement | Harm |
| --- | --- | --- |
| `UNSET` | UNSET (one plain sentence a human can approve) | UNSET (what goes wrong for the user if it is broken) |

## Actions

| Action | Statement |
| --- | --- |
| `Init` | UNSET (the initial state, in one sentence) |
| `UNSET` | UNSET (one sentence for each TLA+ action) |

## Coverage

| Path | Functions |
| --- | --- |
| planned | - |

## Bounds and assumptions

- UNSET (the size of the model, what it leaves out, what it assumes)

## Last verified

never

## Variants

| File | Breaks |
| --- | --- |
| `UNSET-<variant>.cfg` | `UNSET` |
