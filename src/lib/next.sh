# shellcheck shell=sh
# shellcheck disable=SC2034,SC2119,SC2120 # SW_* globals are read by the other libs; sw_next takes no argument but checks for one
# softwary: `next` and `handoff` (V5). Sourced by bin/softwary. POSIX sh.
#
# `next` says in one line what the project needs next, worked out from its
# files; it reads, writes nothing and never runs TLC. `handoff` writes
# .softwary/state/handoff.md for the session that takes over.

SW_HANDOFF_REL=.softwary/state/handoff.md

# sw_next_first TEXT: the first line of TEXT.
sw_next_first() {
	printf '%s\n' "$1" | head -n 1
}

# sw_next_set STEP WHY: the answer of sw_next_compute.
sw_next_set() {
	_nx_step=$1
	_nx_why=$2
}

# sw_next_analysis_ok SPECDIR: true when the spec-analyst's record of the
# draft spec passes for this very version of it.
sw_next_analysis_ok() {
	_na_f=$SOFTWARY_ROOT/specs/$1/analysis.md
	[ -f "$_na_f" ] || return 1
	sw_fm_read "$_na_f"
	[ "$(sw_fm_get spec)" = "${1%%-*}" ] &&
		[ "$(sw_fm_get decision)" = pass ] &&
		[ "$(sw_fm_get digest)" = "$(git -C "$SOFTWARY_ROOT" hash-object -- "specs/$1/spec.md")" ]
}

# sw_next_compute: sets _nx_step and _nx_why. Returns 2 when approvals.conf is
# malformed (its problems are printed).
sw_next_compute() {
	if [ ! -f "$SOFTWARY_ROOT/$SW_PRODUCT_REL" ]; then
		sw_next_set define "$SW_PRODUCT_REL is missing"
		return 0
	fi
	_nx_rc=0
	_nx_p=$(sw_product_check) || _nx_rc=$?
	if [ "$_nx_rc" -ne 0 ]; then
		sw_next_set define "product check reports $(sw_count "$_nx_p") problem(s): $(sw_next_first "$_nx_p")"
		return 0
	fi
	if ! _nx_ap=$(sw_approvals_problems); then
		printf '%s\n' "$_nx_ap"
		return 2
	fi
	_nx_s=$(sw_approval_state product)
	if [ "$_nx_s" != approved ]; then
		sw_next_set "approve product (human)" "the product approval is $_nx_s"
		return 0
	fi
	# The models are not run here: the structure of the specifications is
	# checked, TLC is left to blueprint check and approve.
	_nx_rc=0
	_nx_b=$(sw_blueprint_check --no-formal) || _nx_rc=$?
	if [ "$_nx_rc" -ne 0 ]; then
		sw_next_set blueprint "blueprint check reports $(sw_count "$_nx_b") problem(s): $(sw_next_first "$_nx_b")"
		return 0
	fi
	_nx_note=
	[ -z "$(sw_formal_names)" ] || _nx_note="; formal check was not run"
	if ! _nx_c=$(sw_critique_problem); then
		sw_next_set critique "$(sw_next_first "$_nx_c" | sed 's/^blueprint: //')$_nx_note"
		return 0
	fi
	_nx_s=$(sw_approval_state blueprint)
	if [ "$_nx_s" != approved ]; then
		sw_next_set "approve blueprint (human)" "the critic passed it; the blueprint approval is $_nx_s$_nx_note"
		return 0
	fi
	_nx_specs=0 _nx_approved=0 _nx_draft=
	for _nx_d in "$SOFTWARY_ROOT"/specs/*/; do
		[ -f "${_nx_d}spec.md" ] || continue
		_nx_specs=$((_nx_specs + 1))
		_nx_dn=$(basename "$_nx_d")
		sw_fm_read "${_nx_d}spec.md"
		case $(sw_fm_get status) in
		approved) _nx_approved=$((_nx_approved + 1)) ;;
		draft) [ -n "$_nx_draft" ] || _nx_draft=$_nx_dn ;;
		esac
	done
	if [ "$_nx_specs" -eq 0 ]; then
		sw_next_set plan "no spec under specs/"
		return 0
	fi
	if ! _nx_pp=$(sw_plan_problems); then
		sw_next_set plan "plan check reports $(sw_count "$_nx_pp") problem(s): $(sw_next_first "$_nx_pp")"
		return 0
	fi
	if [ "$_nx_approved" -eq 0 ]; then
		if [ -n "$_nx_draft" ] && sw_next_analysis_ok "$_nx_draft"; then
			sw_next_set "plan approve ${_nx_draft%%-*}" "the spec-analyst passed this version of spec ${_nx_draft%%-*}"
		elif [ -n "$_nx_draft" ]; then
			sw_next_set plan "spec ${_nx_draft%%-*} has no passing analysis for this version (call the spec-analyst)"
		else
			sw_next_set plan "no approved spec"
		fi
		return 0
	fi
	if sw_run_open; then
		_nx_w=$(sw_job_waiting | paste -sd' ' -)
		if [ -n "$_nx_w" ]; then
			sw_next_set "waiting: $_nx_w" "the loop waits for a human's answer; ./softwary status shows the questions"
			return 0
		fi
	fi
	_nx_planned=0
	for _nx_d in "$SOFTWARY_ROOT"/specs/*/; do
		[ -f "${_nx_d}spec.md" ] || continue
		sw_fm_read "${_nx_d}spec.md"
		[ "$(sw_fm_get status)" = approved ] || continue
		for _nx_f in "${_nx_d}slices"/*.md; do
			[ -f "$_nx_f" ] || continue
			sw_fm_read "$_nx_f"
			[ "$(sw_fm_get status)" != planned ] || _nx_planned=$((_nx_planned + 1))
		done
	done
	if [ "$_nx_planned" -gt 0 ]; then
		sw_next_set run "$_nx_planned slice(s) planned in approved specs"
		return 0
	fi
	sw_next_set none "nothing is left to plan or run"
}

# sw_next: prints `next: <step> (<why>)`. Reads only.
sw_next() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary next\n' >&2
		return 2
	fi
	_nx_step='' _nx_why=''
	sw_next_compute || return $?
	printf 'next: %s (%s)\n' "$_nx_step" "$_nx_why"
}

# sw_handoff: writes .softwary/state/handoff.md (where we are, the working
# tree, what comes next, approvals, jobs and their questions, the last ten
# events) and prints its path. The `## Notes` section of the file that was
# there, and what follows it, is carried over unchanged.
sw_handoff() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary handoff\n' >&2
		return 2
	fi
	_ho_f=$SW_STATE_ROOT/$SW_HANDOFF_REL
	mkdir -p "$(dirname "$_ho_f")" || return 2
	: >"$_ho_f.notes"
	if [ -f "$_ho_f" ]; then
		awk '/^## Notes[ \t]*$/ { on = 1 } on { print }' "$_ho_f" >"$_ho_f.notes"
	fi
	[ -s "$_ho_f.notes" ] || printf '## Notes\n' >"$_ho_f.notes"
	_ho_next=$(sw_next) || _ho_next="next: unknown ($(sw_next_first "$_ho_next"))"
	{
		printf '# Handoff\n\n## Where\n\n'
		printf -- '- time: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		if git -C "$SOFTWARY_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			printf -- '- branch: %s\n' "$(git -C "$SOFTWARY_ROOT" symbolic-ref --short -q HEAD || printf 'detached')"
			if sw_has_commits; then
				printf -- '- commit: %s\n' "$(git -C "$SOFTWARY_ROOT" log -1 --format='%h %s')"
			else
				printf -- '- commit: none yet\n'
			fi
		else
			printf -- '- branch: not a git repository\n'
		fi
		printf '\n## Working tree\n\n'
		_ho_st=$(git -C "$SOFTWARY_ROOT" status --short 2>/dev/null)
		if [ -n "$_ho_st" ]; then printf '%s\n' "$_ho_st"; else printf '(clean)\n'; fi
		printf '\n## Next\n\n%s\n' "$_ho_next"
		printf '\n## Approvals\n\n'
		_ho_ap=$(sw_status_approvals 2>&1)
		if [ -n "$_ho_ap" ]; then printf '%s\n' "$_ho_ap"; else printf '(no product definition yet)\n'; fi
		printf '\n## Jobs\n\n'
		_ho_jobs=$(sw_status_jobs 2>&1)
		if [ -n "$_ho_jobs" ]; then printf '%s\n' "$_ho_jobs"; else printf '(no jobs)\n'; fi
		printf '\n## Recent events\n\n'
		if [ -s "$SW_STATE_ROOT/$SW_EVENTS_REL" ]; then
			tail -n 10 "$SW_STATE_ROOT/$SW_EVENTS_REL" |
				jq -r '"- \(.time) \(.job) \(.event)\(if (.detail // "") != "" then " " + .detail else "" end)"' 2>/dev/null
		else
			printf '(no events)\n'
		fi
		printf '\n'
		cat "$_ho_f.notes"
	} >"$_ho_f.tmp" || { rm -f "$_ho_f.tmp" "$_ho_f.notes"; return 2; }
	rm -f "$_ho_f.notes"
	mv "$_ho_f.tmp" "$_ho_f" || return 2
	printf '%s\n' "$SW_HANDOFF_REL"
}
