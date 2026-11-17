# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_SHIP_* globals are read across this file's functions
# softwary: `ship` (V7). Sourced by bin/softwary. POSIX sh.
#
# `ship` prepares the proposal to take the integration branch to production;
# it never merges it and never deploys (design principle 10: the step that
# cannot be undone is the human's).
#   prepare  the integration branch's tip goes through the gate and the drift
#            is decided; the release note is written to
#            .softwary/state/releases/<sha7>.md
#   check    the note is of today's tip and its three written sections are
#            filled in
#   pr       the note is the body of a pull request from the integration
#            branch to the production branch (ship pr, below)
# The note is the pull request's body and a copy of it in the state. Its
# computed sections are written again by every `prepare`; the three that a
# person writes (Observability, Rollout, Rollback) are carried over.

SW_RELEASES_REL=.softwary/state/releases
SW_SHIP_WRITTEN="Observability Rollout Rollback"

sw_ship_usage() {
	printf 'usage: ./softwary ship prepare|check\n' >&2
}

# sw_ship_resolve NAME: the ref of the branch NAME: origin's when it has it,
# else the local one (nothing when neither is there).
sw_ship_resolve() {
	if git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/remotes/origin/$1^{commit}" >/dev/null 2>&1; then
		printf 'origin/%s\n' "$1"
	elif git -C "$SW_STATE_ROOT" rev-parse -q --verify "refs/heads/$1^{commit}" >/dev/null 2>&1; then
		printf '%s\n' "$1"
	else
		return 1
	fi
}

# sw_ship_refs: the two branches. Sets SW_SHIP_INT and SW_SHIP_PROD (the
# names), SW_SHIP_INT_SHA and SW_SHIP_PROD_SHA and the short forms
# SW_SHIP_INT_7 and SW_SHIP_PROD_7. Fetches origin first when there is one.
# Returns 2, with the reason printed, when a branch is not set or not there.
sw_ship_refs() {
	sw_conf_load "$SW_STATE_ROOT/$SW_CONF_REL"
	if [ "$SW_CONF_FOUND" -eq 0 ]; then
		printf 'ship: %s not found; run install.sh or ./softwary doctor\n' "$SW_CONF_REL"
		return 2
	fi
	if [ -n "$SW_CONF_ERRORS" ]; then
		printf '%s' "$SW_CONF_ERRORS"
		return 2
	fi
	for _sr_k in integration_branch production_branch; do
		if sw_conf_is_unset "$_sr_k"; then
			printf 'ship: %s is not set in %s\n' "$_sr_k" "$SW_CONF_REL"
			return 2
		fi
	done
	SW_SHIP_INT=$(sw_conf_get integration_branch)
	SW_SHIP_PROD=$(sw_conf_get production_branch)
	if sw_wt_origin; then
		if ! _sr_o=$(git -C "$SW_STATE_ROOT" fetch -q origin 2>&1); then
			printf 'ship: could not fetch origin: %s\n' "$_sr_o"
			return 2
		fi
	fi
	for _sr_w in integration production; do
		case $_sr_w in
		integration) _sr_n=$SW_SHIP_INT ;;
		production) _sr_n=$SW_SHIP_PROD ;;
		esac
		if ! _sr_ref=$(sw_ship_resolve "$_sr_n"); then
			printf "ship: the %s branch '%s' is not there (locally or on origin)\n" "$_sr_w" "$_sr_n"
			return 2
		fi
		_sr_sha=$(git -C "$SW_STATE_ROOT" rev-parse "$_sr_ref^{commit}") || return 2
		_sr_7=$(git -C "$SW_STATE_ROOT" rev-parse --short=7 "$_sr_sha") || return 2
		case $_sr_w in
		integration)
			SW_SHIP_INT_SHA=$_sr_sha
			SW_SHIP_INT_7=$_sr_7
			;;
		production)
			SW_SHIP_PROD_SHA=$_sr_sha
			SW_SHIP_PROD_7=$_sr_7
			;;
		esac
	done
}

# sw_ship_range: production must be behind the integration branch on the same
# line: everything on it is in the integration branch, and the integration
# branch has something more. Sets SW_SHIP_N, the commits more. 1 when not.
sw_ship_range() {
	if ! git -C "$SW_STATE_ROOT" merge-base --is-ancestor "$SW_SHIP_PROD_SHA" "$SW_SHIP_INT_SHA"; then
		printf 'ship: %s has commits that %s does not have; bring them into %s first\n' "$SW_SHIP_PROD" "$SW_SHIP_INT" "$SW_SHIP_INT"
		return 1
	fi
	SW_SHIP_N=$(git -C "$SW_STATE_ROOT" rev-list --count "$SW_SHIP_PROD_SHA..$SW_SHIP_INT_SHA")
	if [ "$SW_SHIP_N" -eq 0 ]; then
		printf 'ship: nothing to ship\n'
		return 1
	fi
}

# sw_ship_note_rel: the note of the integration branch's tip.
sw_ship_note_rel() {
	printf '%s/%s.md' "$SW_RELEASES_REL" "$SW_SHIP_INT_7"
}

# sw_ship_fm SHA PATH: reads the front matter of PATH as of SHA (sw_fm_get
# reads it); 1 when it is not there.
sw_ship_fm() {
	_sf_t=$(mktemp "${TMPDIR:-/tmp}/softwary-ship.XXXXXX") || return 2
	_sf_rc=1
	if git -C "$SW_STATE_ROOT" show "$1:./$2" >"$_sf_t" 2>/dev/null; then
		sw_fm_read "$_sf_t"
		_sf_rc=0
	fi
	rm -f "$_sf_t"
	return "$_sf_rc"
}

# sw_ship_ls SHA DIR PATTERN: the files below DIR as of SHA whose path matches
# PATTERN (an ERE), one per line.
sw_ship_ls() {
	git -C "$SW_STATE_ROOT" -c core.quotePath=false ls-tree -r --name-only "$1" -- "$2" | grep -E -e "$3" || :
}

# sw_ship_specs: the slices that are done at the integration tip and were not
# at the production tip, with their specs.
sw_ship_specs() {
	while IFS= read -r _ss_p; do
		[ -n "$_ss_p" ] || continue
		sw_ship_fm "$SW_SHIP_INT_SHA" "$_ss_p" || continue
		[ "$(sw_fm_get status)" = "done" ] || continue
		_ss_goal=$(sw_fm_get goal)
		if sw_ship_fm "$SW_SHIP_PROD_SHA" "$_ss_p" && [ "$(sw_fm_get status)" = "done" ]; then
			continue
		fi
		_ss_d=${_ss_p#specs/}
		_ss_d=${_ss_d%%/*}
		_ss_s=${_ss_p##*/}
		_ss_title=
		if sw_ship_fm "$SW_SHIP_INT_SHA" "specs/$_ss_d/spec.md"; then
			_ss_title=$(sw_fm_get title)
		fi
		printf -- '- %s-%s: %s (spec %s: %s)\n' "${_ss_d%%-*}" "${_ss_s%.md}" "$_ss_goal" "${_ss_d%%-*}" "$_ss_title"
	done <<SHIP_SLICES
$(sw_ship_ls "$SW_SHIP_INT_SHA" specs '^specs/[^/]+/slices/S[0-9]+\.md$')
SHIP_SLICES
}

# sw_ship_decisions: the ADRs added in the range and those whose status
# changed in it.
sw_ship_decisions() {
	while IFS= read -r _sd_p; do
		[ -n "$_sd_p" ] || continue
		sw_ship_fm "$SW_SHIP_INT_SHA" "$_sd_p" || continue
		_sd_st=$(sw_fm_get status)
		_sd_title=$(sw_fm_get title)
		if sw_ship_fm "$SW_SHIP_PROD_SHA" "$_sd_p" && [ "$(sw_fm_get status)" = "$_sd_st" ]; then
			continue
		fi
		_sd_b=${_sd_p##*/}
		printf -- '- %s: %s (%s)\n' "${_sd_b%%-*}" "$_sd_title" "$_sd_st"
	done <<SHIP_ADRS
$(sw_ship_ls "$SW_SHIP_INT_SHA" "$SW_ADR_REL" '\.md$')
SHIP_ADRS
}

# sw_ship_risk: the highest tier among the paths changed in the range and the
# paths of tier R3 (risk.conf is read from SOFTWARY_ROOT, the tip's tree).
sw_ship_risk() {
	_sk_best=0
	_sk_r3=
	while IFS= read -r _sk_p; do
		[ -n "$_sk_p" ] || continue
		_sk_t=$(sw_path_tier "$_sk_p")
		_sk_n=$(sw_tier_num "${_sk_t%%	*}")
		[ "$_sk_n" -le "$_sk_best" ] || _sk_best=$_sk_n
		if [ "$_sk_n" -eq 3 ]; then
			_sk_r3="$_sk_r3  - $_sk_p (${_sk_t#*	})
"
		fi
	done <<SHIP_PATHS
$(git -C "$SW_STATE_ROOT" -c core.quotePath=false diff --no-renames --relative --name-only "$SW_SHIP_PROD_SHA" "$SW_SHIP_INT_SHA" --)
SHIP_PATHS
	if [ "$_sk_best" -eq 0 ]; then
		printf -- '- highest tier: none (no path changed)\n'
		return 0
	fi
	printf -- '- highest tier: R%s\n' "$_sk_best"
	if [ -n "$_sk_r3" ]; then
		printf -- '- R3 paths:\n%s' "$_sk_r3"
	else
		printf -- '- R3 paths: none\n'
	fi
}

# sw_ship_list TEXT: TEXT, or (none).
sw_ship_list() {
	if [ -n "$1" ]; then printf '%s\n' "$1"; else printf '(none)\n'; fi
}

# sw_ship_compose NOTE: writes the note: the computed sections from the
# branches and from the tree SOFTWARY_ROOT, then the written ones, which are
# those of the note that is there, else the template's.
sw_ship_compose() {
	_sc_note=$1
	_sc_root=$SOFTWARY_ROOT
	SOFTWARY_ROOT=$SW_SHIP_TREE
	sw_risk_load
	if [ -n "$SW_RISK_ERRORS" ]; then
		SOFTWARY_ROOT=$_sc_root
		printf '%s' "$SW_RISK_ERRORS"
		return 2
	fi
	_sc_specs=$(sw_ship_specs)
	_sc_adrs=$(sw_ship_decisions)
	_sc_risk=$(sw_ship_risk)
	_sc_waivers=$(sw_status_waivers | sed 's/^/- /')
	SOFTWARY_ROOT=$_sc_root
	_sc_tail=$_sc_note.written
	: >"$_sc_tail"
	if [ -f "$_sc_note" ]; then
		awk '/^## Observability[ \t]*$/ { on = 1 } on { print }' "$_sc_note" >"$_sc_tail"
	fi
	if [ ! -s "$_sc_tail" ]; then
		if [ ! -f "$SOFTWARY_HOME/templates/release.md" ]; then
			rm -f "$_sc_tail"
			printf 'ship: %s is missing; rerun install.sh\n' ".softwary/templates/release.md"
			return 2
		fi
		cat "$SOFTWARY_HOME/templates/release.md" >"$_sc_tail"
	fi
	{
		printf '# Release %s\n\n' "$SW_SHIP_INT_7"
		printf 'production: %s\nintegration: %s\n\n' "$SW_SHIP_PROD_SHA" "$SW_SHIP_INT_SHA"
		printf '## Range\n\n- production: %s %s\n- integration: %s %s\n- commits: %s\n\n' \
			"$SW_SHIP_PROD" "$SW_SHIP_PROD_7" "$SW_SHIP_INT" "$SW_SHIP_INT_7" "$SW_SHIP_N"
		printf '## Specs\n\n'
		sw_ship_list "$_sc_specs"
		printf '\n## Decisions\n\n'
		sw_ship_list "$_sc_adrs"
		printf '\n## Risk\n\n%s\n' "$_sc_risk"
		printf '\n## Waivers and findings\n\n'
		sw_ship_list "$_sc_waivers"
		printf '\n## Drift\n\n'
		sw_ship_list "$SW_DRIFT_INFORCE"
		printf '\n'
		cat "$_sc_tail"
	} >"$_sc_note.tmp" || { rm -f "$_sc_tail" "$_sc_note.tmp"; return 2; }
	rm -f "$_sc_tail"
	mv "$_sc_note.tmp" "$_sc_note"
}

# sw_ship_prepare: AC-V7-01 and 02.
sw_ship_prepare() {
	sw_ship_refs || return $?
	sw_ship_range || return $?
	_sp_rc=0
	sw_queue_verify "$SW_SHIP_INT" || _sp_rc=$?
	if [ "$_sp_rc" -ne 0 ]; then
		printf 'ship: the tip of %s does not pass the gate (see %s)\n' "$SW_SHIP_INT" "$SW_INTEGRATION_LOG"
		return 1
	fi
	# the tree of the tip as it is committed: what verify left is cleaned away
	sw_wt_integration "$SW_SHIP_INT" || return 2
	SW_SHIP_TREE=$(sw_wt_path _integration)
	_sp_root=$SOFTWARY_ROOT
	SOFTWARY_ROOT=$SW_SHIP_TREE
	_sp_out=$(mktemp "${TMPDIR:-/tmp}/softwary-ship.XXXXXX") || return 2
	_sp_rc=0
	sw_drift_run >"$_sp_out" 2>&1 || _sp_rc=$?
	SOFTWARY_ROOT=$_sp_root
	if [ "$_sp_rc" -ne 0 ]; then
		printf 'ship: drift could not be worked out: %s\n' "$(head -n 1 "$_sp_out")"
		rm -f "$_sp_out"
		return 2
	fi
	rm -f "$_sp_out"
	if [ "$SW_DRIFT_BAD" -ne 0 ]; then
		printf 'ship: drift has undecided or expired items (./softwary drift)\n'
		return 1
	fi
	mkdir -p "$SW_STATE_ROOT/$SW_RELEASES_REL" || return 2
	_sp_note=$SW_STATE_ROOT/$(sw_ship_note_rel)
	_sp_rc=0
	sw_ship_compose "$_sp_note" || _sp_rc=$?
	[ "$_sp_rc" -eq 0 ] || return "$_sp_rc"
	printf 'ship: release note %s\n' "$(sw_ship_note_rel)"
	printf 'ship: write its Observability, Rollout and Rollback sections, then ./softwary ship check\n'
}

# sw_ship_section_filled FILE NAME: true when the section "## NAME" has a line
# that is not blank, not inside a comment and not UNSET.
sw_ship_section_filled() {
	tr -d '\r' <"$1" | awk -v name="$2" '
		/^## / { on = ($0 ~ "^## " name "[ \t]*$"); incomment = 0; next }
		!on { next }
		{
			line = $0
			if (incomment) {
				i = index(line, "-->")
				if (i == 0) next
				line = substr(line, i + 3)
				incomment = 0
			}
			while ((i = index(line, "<!--")) > 0) {
				rest = substr(line, i + 4)
				j = index(rest, "-->")
				if (j == 0) { line = substr(line, 1, i - 1); incomment = 1; break }
				line = substr(line, 1, i - 1) substr(rest, j + 3)
			}
			gsub(/^[ \t]+|[ \t]+$/, "", line)
			if (line != "" && line != "UNSET") found = 1
		}
		END { exit !found }'
}

# sw_ship_check_problems: prints one `ship: ...` line for each problem of the
# note of today's tip; nothing when the note is ready.
sw_ship_check_problems() {
	_sc_rel=$(sw_ship_note_rel)
	_sc_f=$SW_STATE_ROOT/$_sc_rel
	if [ ! -f "$_sc_f" ]; then
		# shellcheck disable=SC2012 # the names are the package's own: <sha7>.md
		_sc_other=$(ls -t "$SW_STATE_ROOT/$SW_RELEASES_REL" 2>/dev/null | head -n 1)
		if [ -n "$_sc_other" ]; then
			printf 'ship: there is no release note for the tip %s of %s (the note %s is for another tip; run ./softwary ship prepare)\n' \
				"$SW_SHIP_INT_7" "$SW_SHIP_INT" "$_sc_other"
		else
			printf 'ship: there is no release note for the tip %s of %s (run ./softwary ship prepare)\n' "$SW_SHIP_INT_7" "$SW_SHIP_INT"
		fi
		return 0
	fi
	_sc_v=$(sed -n 's/^integration: //p' "$_sc_f" | head -n 1 | tr -d '\r')
	if [ "$_sc_v" != "$SW_SHIP_INT_SHA" ]; then
		printf 'ship: the note is of another tip than %s (run ./softwary ship prepare)\n' "$SW_SHIP_INT_SHA"
	fi
	_sc_v=$(sed -n 's/^production: //p' "$_sc_f" | head -n 1 | tr -d '\r')
	if [ "$_sc_v" != "$SW_SHIP_PROD_SHA" ]; then
		printf 'ship: the note was prepared when %s was at %s (it is at %s now; run ./softwary ship prepare)\n' \
			"$SW_SHIP_PROD" "$(printf '%s' "$_sc_v" | cut -c1-7)" "$SW_SHIP_PROD_7"
	fi
	for _sc_s in $SW_SHIP_WRITTEN; do
		sw_ship_section_filled "$_sc_f" "$_sc_s" || printf 'ship: ## %s is not filled in (replace UNSET with text)\n' "$_sc_s"
	done
}

# sw_ship_check: AC-V7-03. Returns 1 with the problems, one line each.
sw_ship_check() {
	sw_ship_refs || return $?
	sw_ship_range || return $?
	_sc_probs=$(sw_ship_check_problems)
	if [ -n "$_sc_probs" ]; then
		printf '%s\n' "$_sc_probs"
		printf 'ship: %s problem(s) in the release note\n' "$(sw_count "$_sc_probs")"
		return 1
	fi
	printf 'ship: release note %s is ready\n' "$(sw_ship_note_rel)"
}

# sw_ship prepare|check|pr
sw_ship() {
	_sh_cmd=${1:-}
	[ $# -ge 1 ] || { sw_ship_usage; return 2; }
	shift
	[ $# -eq 0 ] || { sw_ship_usage; return 2; }
	case $_sh_cmd in
	prepare) sw_ship_prepare ;;
	check) sw_ship_check ;;
	*)
		sw_ship_usage
		return 2
		;;
	esac
}
