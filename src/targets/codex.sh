#!/bin/sh
# softwary target: Codex. Reads AGENTS.md (written by sync itself);
#   skills in .agents/skills/, agents as TOML in .codex/agents/.
set -eu
# shellcheck source=src/lib/target.sh
. "$SOFTWARY_HOME/lib/target.sh"

sw_copy_skills "$1" "$2/.agents/skills"
for f in "$1"/agents/*.md; do
	[ -f "$f" ] || continue
	mkdir -p "$2/.codex/agents"
	n=${f##*/}
	sw_agent_toml "$f" >"$2/.codex/agents/${n%.md}.toml"
done
