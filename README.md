# softwary

softwary helps an engineer who describes a product to define it together,
design it, cut it into independent blocks of work, build the blocks test first
in parallel, pass them through gates and an independent review, merge them, and
keep going through delivery, operation and maintenance.

It is a package of shell scripts, rules, skills and subagent definitions that
you install into a git repository. It works with Claude Code, Cursor and Codex,
for any language or stack. It has no server, no daemon and no runtime of its
own.

What you do: approve the product definition and the blueprint, answer the
questions the loop escalates, decide about drift, and take the integration
branch to production. The rest flows through scripts that check, instead of
instructions that ask.

## What you need

- A POSIX `sh`, `git` and `jq`.
- `gh` (the GitHub command line tool), logged in: every job is a pull request
  and the loop merges with `gh pr merge`.
- Java, only if the project has TLA+ specifications (`./softwary formal install`
  downloads the model checker).
- One of Claude Code, Cursor or Codex.

## Install

Pick one channel. Both end in the same files: `softwary` and `.softwary/` in
your repository.

**From a tag.** Clone the repository at a release tag and run its installer:

```sh
git clone --branch v0.2.0 <softwary-repository-url> softwary
sh softwary/install.sh /path/to/your/repo
```

**From a release archive.** Download `softwary-0.2.0.tar.gz` and `SHA256SUMS`
from the release page, then install the archive with its digest:

```sh
sha256sum -c SHA256SUMS
tar -xzf softwary-0.2.0.tar.gz
sh softwary-0.2.0/install.sh --archive softwary-0.2.0.tar.gz \
  --sha256 "$(cut -d' ' -f1 SHA256SUMS)" /path/to/your/repo
```

There is no `curl | sh` installer. Details, upgrades and removal are in
[docs/guide/install.md](docs/guide/install.md).

## First project

```sh
cd /path/to/your/repo
./softwary doctor        # what is missing
```

Then ask your tool to run the `setup` skill: it fills in the configuration and
the branches and places the CI workflow. After that the stages are skills too:
`define`, `blueprint`, `plan`, `run`, `ship`. The walk-through is in
[docs/guide/quickstart.md](docs/guide/quickstart.md).

## Map of the documentation

| Read | For |
| --- | --- |
| [docs/guide/install.md](docs/guide/install.md) | Install, upgrade, uninstall, versions, releasing |
| [docs/guide/quickstart.md](docs/guide/quickstart.md) | Your first project, step by step |
| [docs/guide/commands.md](docs/guide/commands.md) | Every `./softwary` command |
| [docs/guide/concepts.md](docs/guide/concepts.md) | Artifacts, gates, the loop, approvals, risk tiers |
| [docs/guide/tools.md](docs/guide/tools.md) | Claude Code, Cursor and Codex: model names and tool notes |
| [CHANGELOG.md](CHANGELOG.md) | What each version changed |

The design record of the package itself (`docs/design.md`, `docs/decisions.md`,
the specifications and plans of each milestone) is written in Turkish.

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright 2026
Ufuk Cem Delice. Version 0.1.0 was released under the MIT License.

## Telemetry

softwary has no telemetry: it collects and sends nothing. The package reaches
the network only through `git` (fetch, push, clone), `gh`, and one download:
`./softwary formal install` fetches the pinned TLA+ model checker from a fixed
address and checks its SHA-256. A test of the package keeps it so.

## Versions

softwary follows [semantic versioning](https://semver.org). `./softwary
version` prints the installed one.
