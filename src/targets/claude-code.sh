#!/bin/sh
# softwary target: Claude Code.
#   CLAUDE.md block imports AGENTS.md; skills in .claude/skills/,
#   agents in .claude/agents/. See lib/target.sh for the contract.
set -eu
# shellcheck source=src/lib/target.sh
. "$SOFTWARY_HOME/lib/target.sh"

printf '@AGENTS.md\n' >"$3/CLAUDE.md"
sw_copy_skills "$1" "$2/.claude/skills"
sw_copy_agents "$1" "$2/.claude/agents"
