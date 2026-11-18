#!/bin/sh
# softwary target: Cursor. Reads AGENTS.md (written by sync itself);
#   skills in .cursor/skills/, agents in .cursor/agents/ (with the
#   model of models.conf for Cursor).
set -eu
# shellcheck source=src/lib/target.sh
. "$SOFTWARY_HOME/lib/target.sh"

sw_copy_skills "$1" "$2/.cursor/skills"
sw_copy_agents_tool "$1" "$2/.cursor/agents" cursor
