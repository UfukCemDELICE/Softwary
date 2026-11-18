# Commands

Every command is `./softwary <command>`. Exit codes: `0` passed, `1` failed
(something to fix in the work), `2` the configuration is missing or invalid, or
the command was used wrongly. `./softwary help` prints the list below in short.

## Checks

| Command | What it does |
| --- | --- |
| `./softwary verify [--fast] [--base <ref>]` | Runs the project's checks from `.softwary/config/commands.conf`, cheap to expensive, one `PASS`, `FAIL` or `SKIP` line each. `--fast` runs only format, lint and type checks. `adr` and `changes` run against the integration branch, or against `<ref>` |
| `./softwary doctor` | Reports installation and configuration problems, one line per check; it does not run your project's commands |
| `./softwary trace` | Checks that specs, slices, ADRs and tests trace to each other (every criterion has a test that names it) |
| `./softwary adr [--base <ref>]` | A changed model or contract needs an accepted ADR in the same change |
| `./softwary changes [--base <ref>]` | A change under `src_paths` needs an active slice of an approved spec in the same change |
| `./softwary risk <spec> [--base <ref>]` | Prints the review tier (R1, R2, R3) of a change |
| `./softwary guard <job> [--base <ref>]` | Reports protected paths, paths outside the slice's `touches` and loosened tests in a job's diff |
| `./softwary repro <job> [--base <ref>]` | For a slice with a `repro`: its tests fail on the base and pass on the job |

## Generated files

| Command | What it does |
| --- | --- |
| `./softwary sync [--check]` | Generates the files each tool reads from the sources in `.softwary/`; `--check` only reports what is out of date |
| `./softwary views [--check]` | Generates `architecture/views/system.mmd` from the model |

## Product and blueprint

| Command | What it does |
| --- | --- |
| `./softwary product check` | Checks `product/PRODUCT.md`: sections, features, examples |
| `./softwary model validate` | Checks the architecture model `architecture/model/system.calm.json` |
| `./softwary blueprint check` | Checks the model, the data model, the flows, the state machines, the specifications and that every product feature is delivered by a component |
| `./softwary blueprint digest` | Prints the digest the blueprint approval binds |
| `./softwary approve product\|blueprint` | Records your approval of the product definition or the blueprint. Only a human runs it |
| `./softwary formal check [<spec>]` | Runs the TLA+ model checker on `architecture/formal/`: the model passes and every variant fails the invariant it should; coverage and staleness are checked too |
| `./softwary formal verified <spec> compatible\|updated` | Records the verdict on a specification after the code it covers changed |
| `./softwary formal trace <spec> <invariant>` | Prints the counter-example of a finding as steps in plain sentences |
| `./softwary formal install` | Downloads the pinned model checker and checks its SHA-256 |
| `./softwary states tests [<entity>]` | Lists the tests a state machine owes: one per state and event |

## Plan

| Command | What it does |
| --- | --- |
| `./softwary plan check` | Checks approvals, criterion-to-example links and the order of slices; includes `trace` |
| `./softwary plan approve <spec>` | Approves a draft spec when `plan check` is clean and the analyst's record passes |
| `./softwary next` | Prints, in one line, what the project needs next; writes nothing |
| `./softwary status` | Summarises approvals, specs, slices, proposed ADRs and jobs |
| `./softwary handoff` | Writes `.softwary/state/handoff.md` for the next session |

## The loop

| Command | What it does |
| --- | --- |
| `./softwary run start\|next\|stop` | Opens the run (after its checks), prints what to do next, closes the run |
| `./softwary job start <job>` | Admits a planned slice, opens its worktree and branch `softwary/<job>` and takes it into its first round |
| `./softwary job gate <job>` | Runs the full `verify` on the job's worktree |
| `./softwary job pr <job>`, `job ci <job>` | Pushes the branch and opens the pull request; checks the pull request's head and CI. `job ci` waits for the checks to appear and to finish (at most `max_ci_minutes`); red checks start a new round, and CI that cannot be read (no check appeared, still pending after the limit, `gh` failing) is handed to you with a question |
| `./softwary job review <job>` | Reads the reviewer's record |
| `./softwary job merged <job>` | Records a merge you did by hand |
| `./softwary job show <job>` | Prints the job |
| `./softwary job escalate <job> <question>` | Hands the job to you with one concrete question |
| `./softwary job resume <job> <answer>`, `job abandon <job> <reason>` | Continues an escalated job in a new round; gives it up |
| `./softwary job event <job> <event> [detail]` | Applies one transition of the job's state table |
| `./softwary job tokens <job> <n>` | Adds tokens to the job's and the run's totals |
| `./softwary merge <job>` | Queues the approved job and drains the queue: every condition is recomputed on the commit to merge |
| `./softwary queue [drain]` | Prints the merge queue; drains it when nobody does |
| `./softwary eval prepare <dir>`, `eval score <dir>` | Builds one repository per evaluation case; reads the reviewer's record of each and writes `.softwary/config/eval.conf` |

## Delivery and maintenance

| Command | What it does |
| --- | --- |
| `./softwary ship prepare\|check\|pr` | Takes the integration branch to the production branch as a pull request you merge: `prepare` writes the release note, `check` verifies it is current and filled in, `pr` opens the pull request. It never merges and never deploys |
| `./softwary drift` | Lists where the code and the blueprint differ and the decision you took for each in `architecture/drift.md`; `1` while one is undecided or expired |

## The package itself

| Command | What it does |
| --- | --- |
| `./softwary upgrade <package-path>` | Replaces the managed files with those of a newer package, then runs `sync` |
| `./softwary upgrade <archive.tar.gz> --sha256 <digest>` | The same from a release archive whose SHA-256 is the digest given |
| `./softwary version` | Prints `softwary <version>` |
| `./softwary uninstall [--yes]` | Lists what removes the package from the project; `--yes` removes it. Your own files, `.softwary/config`, `local` and `state` stay |

See [install](install.md) for upgrading and removing, and [concepts](concepts.md)
for the words used here.
