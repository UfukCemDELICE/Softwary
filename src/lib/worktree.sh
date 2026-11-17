# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: the worktree of a job. Sourced by bin/softwary. POSIX sh.
#
# Every job works in .softwary/worktrees/<job> of the main checkout, on its
# own branch softwary/<job>; the main checkout stays on the integration
# branch. `git worktree add|remove|prune` run under the state lock; the job's
# `bootstrap` command does not. Checks (guard, risk, verify) run with the main
# checkout's scripts on the job's tree: SOFTWARY_ROOT=<worktree>.

SW_WT_REL=.softwary/worktrees
SW_LOGS_REL=.softwary/state/logs

# sw_wt_path JOB: the worktree directory of JOB.
sw_wt_path() {
	printf '%s/%s/%s' "$SW_STATE_ROOT" "$SW_WT_REL" "$1"
}

sw_wt_origin() {
	git -C "$SW_STATE_ROOT" remote get-url origin >/dev/null 2>&1
}

# sw_wt_start_ref BASE: where a new job branch starts: the tip of the
# integration branch on origin when there is one, else the local branch.
sw_wt_start_ref() {
	if git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null 2>&1; then
		printf 'origin/%s\n' "$1"
	else
		printf '%s\n' "$1"
	fi
}

# sw_wt_exists JOB: true when the worktree directory is there.
sw_wt_exists() {
	[ -e "$(sw_wt_path "$1")/.git" ]
}

# sw_wt_add JOB BASE: opens softwary/<job> at the integration tip in a new
# worktree (state lock held by the caller). Prints git's complaint on failure.
sw_wt_add() {
	mkdir -p "$SW_STATE_ROOT/$SW_WT_REL" || return 2
	_wa_o=$(git -C "$SW_STATE_ROOT" worktree add -q --no-track -b "softwary/$1" "$(sw_wt_path "$1")" "$(sw_wt_start_ref "$2")" 2>&1) ||
		{ printf '%s\n' "$_wa_o"; return 2; }
}

# sw_wt_ensure JOB: the worktree of JOB is there; it is rebuilt from the local
# branch, or from origin/softwary/<job>, when its directory is gone. 2 when
# there is nothing to build it from.
sw_wt_ensure() {
	sw_wt_exists "$1" && return 0
	sw_state_locked sw_wt_rebuild "$1"
}

sw_wt_rebuild() {
	sw_wt_exists "$1" && return 0
	_wb_wt=$(sw_wt_path "$1")
	_wb_br=softwary/$1
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	mkdir -p "$SW_STATE_ROOT/$SW_WT_REL" || return 2
	if git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/heads/$_wb_br" >/dev/null 2>&1; then
		_wb_o=$(git -C "$SW_STATE_ROOT" worktree add -q "$_wb_wt" "$_wb_br" 2>&1) ||
			{ printf 'job %s: %s\n' "$1" "$_wb_o"; return 2; }
		return 0
	fi
	if sw_wt_origin && git -C "$SW_STATE_ROOT" fetch -q origin "+refs/heads/$_wb_br:refs/remotes/origin/$_wb_br" >/dev/null 2>&1 &&
		git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/remotes/origin/$_wb_br" >/dev/null 2>&1; then
		_wb_o=$(git -C "$SW_STATE_ROOT" worktree add -q --no-track -b "$_wb_br" "$_wb_wt" "origin/$_wb_br" 2>&1) ||
			{ printf 'job %s: %s\n' "$1" "$_wb_o"; return 2; }
		return 0
	fi
	printf 'job %s: no worktree and no branch %s\n' "$1" "$_wb_br"
	return 2
}

# sw_wt_resume JOB BASE: the worktree of a job that was left in `ready`: what is
# there is kept, the local branch is used if it exists, else a new one is
# opened at the integration tip.
sw_wt_resume() {
	sw_state_locked sw_wt_resume_locked "$@"
}

sw_wt_resume_locked() {
	sw_wt_exists "$1" && return 0
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	if git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/heads/softwary/$1" >/dev/null 2>&1; then
		sw_wt_rebuild "$1"
	else
		sw_wt_add "$1" "$2"
	fi
}

# sw_wt_remove JOB [branch]: removes the worktree; with `branch` the local
# branch too (a merged job). A job that has no worktree is not an error.
sw_wt_remove() {
	sw_state_locked sw_wt_remove_locked "$@"
}

sw_wt_remove_locked() {
	_wr_wt=$(sw_wt_path "$1")
	if [ -e "$_wr_wt" ]; then
		git -C "$SW_STATE_ROOT" worktree remove --force "$_wr_wt" >/dev/null 2>&1 || rm -rf "$_wr_wt"
	fi
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	if [ "${2-}" = branch ]; then
		git -C "$SW_STATE_ROOT" branch -D "softwary/$1" >/dev/null 2>&1
	fi
	return 0
}

# sw_wt_bootstrap_cmd: prints the bootstrap command of commands.conf; nothing
# for `NONE: <reason>`. 2 (with the reason) when it is UNSET.
sw_wt_bootstrap_cmd() {
	sw_conf_load "$SW_STATE_ROOT/$SW_CONF_REL"
	if sw_conf_is_unset bootstrap; then
		printf 'bootstrap is UNSET in %s (the command that prepares a fresh worktree, or NONE: <reason>)\n' "$SW_CONF_REL"
		return 2
	fi
	case $(sw_conf_get bootstrap) in
	NONE | NONE:*) ;;
	*) sw_conf_get bootstrap ;;
	esac
}

# sw_wt_bootstrap JOB: runs `bootstrap` in the job's worktree, outside any
# lock; its output goes to .softwary/state/logs/bootstrap-<job>.log.
sw_wt_bootstrap() {
	_wp_cmd=$(sw_wt_bootstrap_cmd) || { printf '%s\n' "$_wp_cmd"; return 2; }
	[ -n "$_wp_cmd" ] || return 0
	mkdir -p "$SW_STATE_ROOT/$SW_LOGS_REL" || return 2
	(cd "$(sw_wt_path "$1")" && sh -c "$_wp_cmd") >"$SW_STATE_ROOT/$SW_LOGS_REL/bootstrap-$1.log" 2>&1
}

# sw_wt_softwary JOB ARGS...: the main checkout's softwary, run on the
# job's worktree (the job's own copy of the scripts is never run).
sw_wt_softwary() {
	_wsw_wt=$(sw_wt_path "$1")
	shift
	SOFTWARY_ROOT=$_wsw_wt sh "$SW_STATE_ROOT/.softwary/bin/softwary" "$@"
}

# sw_wt_branch_now JOB: the branch checked out in the job's worktree.
sw_wt_branch_now() {
	git -C "$(sw_wt_path "$1")" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# sw_wt_check JOB [loose]: the worktree is there (rebuilt if need be), on the
# job's branch and clean (with `loose`, files may be uncommitted: the review
# record is written there before `job review` commits it); 2 with a message
# otherwise.
sw_wt_check() {
	sw_wt_ensure "$1" || return 2
	if [ "$(sw_wt_branch_now "$1")" != "softwary/$1" ]; then
		printf 'job %s: the worktree is not on branch softwary/%s\n' "$1" "$1"
		return 2
	fi
	if [ "${2-}" != loose ] && [ -n "$(git -C "$(sw_wt_path "$1")" status --porcelain 2>/dev/null)" ]; then
		printf 'job %s: working tree is not clean\n' "$1"
		return 2
	fi
}

# sw_wt_integration BASE: the worktree .softwary/worktrees/_integration, with
# a detached HEAD at origin/<BASE> (made, or moved there).
sw_wt_integration() {
	sw_state_locked sw_wt_integration_locked "$1"
}

sw_wt_integration_locked() {
	_wi_wt=$(sw_wt_path _integration)
	if [ -e "$_wi_wt/.git" ]; then
		git -C "$_wi_wt" checkout -q -f --detach "$(sw_wt_start_ref "$1")" >/dev/null 2>&1 || return 2
		git -C "$_wi_wt" clean -fdq >/dev/null 2>&1
		return 0
	fi
	git -C "$SW_STATE_ROOT" worktree prune >/dev/null 2>&1
	mkdir -p "$SW_STATE_ROOT/$SW_WT_REL" || return 2
	git -C "$SW_STATE_ROOT" worktree add -q --detach "$_wi_wt" "$(sw_wt_start_ref "$1")" >/dev/null 2>&1 || return 2
}
