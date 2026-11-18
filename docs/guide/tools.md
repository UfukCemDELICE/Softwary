# Claude Code, Cursor and Codex

softwary writes the same skills and subagents for each tool you turn on in
`.softwary/config/tools.conf`, in the folders that tool reads. The skills and
agents themselves do not name a tool: they say "call the `reviewer`" and run
long steps in the background "if the tool can". What is specific to a tool is
on this page.

```
claude-code = on
cursor = on
codex = off
```

Run `./softwary sync` after changing it. A tool set to `off` gets no files, and
files generated earlier for it are removed.

| | Claude Code | Cursor | Codex |
| --- | --- | --- | --- |
| Rules entry | `CLAUDE.md` (imports `AGENTS.md`) | `AGENTS.md` | `AGENTS.md` |
| Skills | `.claude/skills/softwary-<name>/` | `.cursor/skills/softwary-<name>/` | `.agents/skills/softwary-<name>/` |
| Subagents | `.claude/agents/<name>.md` | `.cursor/agents/<name>.md` | `.codex/agents/<name>.toml` |

## Models

Each subagent has a **class** in `.softwary/config/models.conf`:

```
implementer = sonnet
reviewer = opus
approver = opus
```

A class is a short name for a kind of model. What it is called in a tool is a
second kind of line, one per tool and class:

```
cursor: opus = claude-opus-5[effort=high]
cursor: sonnet = gpt-5.6-sol
codex: opus = <model id of your Codex account>
codex: sonnet = <model id of your Codex account>
```

`./softwary sync` writes the id into each subagent file of that tool. These
are examples: the ids available to you depend on your plan and tool, so use the
ones your tool lists. softwary checks the shape of an id (not empty, not
`UNSET`, no spaces or quotes) and does not know whether it exists.

- **Claude Code** reads the class as the model name. With no line for a class,
  the class name is written as it is; give a line (`claude-code: opus = <id>`)
  to use another name.
- **Cursor** needs a line for each class while it is on. The `model:` line of
  the subagent header takes `inherit` or a model id; options go in brackets
  after the id. Cursor falls back to a compatible model when an administrator
  has blocked the model or your plan does not include it.
- **Codex** needs a line for each class while it is on. The id is written as
  `model = "<id>"` in the subagent's TOML file, and it takes precedence over
  the model of the session that calls the agent.

If a tool is on and a class has no id, `./softwary doctor` fails and
`./softwary run start` refuses to open a run, with a line saying which tool and
class. A tool that is off needs none. If `models.conf` is missing or has an
invalid line, `sync` writes no model into any file, and `doctor` says why.

### The reviewer is not the implementer

A model reviewing its own kind of work agrees too easily. For every tool that is
on, `doctor` and `run start` compare the model ids after the translation, and
fail when the `reviewer` or the `approver` ends up with the `implementer`'s:

```
.softwary/config/models.conf:7: reviewer uses the implementer's model in cursor (gpt-5.6-sol)
```

Two classes mapped to the same id are caught as well as the same class. Claude
Code is compared by class name, as before, and by id when its classes are
translated.

## Claude Code

Nothing else is needed. Subagents are started by name, and the `run` skill runs
the gate and CI in the background.

## Cursor

- Cursor also reads `.claude/skills` and `.agents/skills`. With several tools on,
  the same skill can be listed more than once; this is expected.
- Subagent files in `.cursor/agents/` win over same-named files from other folders.

## Codex

- Codex reads `AGENTS.md` from the root down to the working directory, up to a
  size limit (32 KiB by default). The rules block is short, but a very long
  project `AGENTS.md` may push it out.
- Custom agents are TOML files with `name`, `description` and
  `developer_instructions`; softwary adds `model` when `models.conf` gives one.
  They inherit the permissions of the session that starts them.

## What has not been tried

The generated files and the skill texts are checked by tests. Running the whole
loop inside Cursor and Codex is not covered by an automated test; try it on a
small project first and read the subagent files in `.cursor/agents/` or
`.codex/agents/` to see which model each one got.
