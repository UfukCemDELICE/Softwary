# shellcheck shell=sh
# softwary: `doctor` command. Sourced by bin/softwary. POSIX sh.
#
# Reports installation and configuration problems, one line each.
# Exit: 0 no problem, 2 at least one problem.

sw_doctor_fail() {
	sw_line "$1" "FAIL ($2)"
	_problems=$((_problems + 1))
}

# sw_doctor_hooks: core.hooksPath must point at the managed hooks.
sw_doctor_hooks() {
	_cur=$(git -C "$SOFTWARY_ROOT" config --get core.hooksPath 2>/dev/null) || _cur=
	if [ "$_cur" = .softwary/hooks ]; then
		for _h in pre-commit pre-push; do
			if [ ! -x "$SOFTWARY_ROOT/.softwary/hooks/$_h" ]; then
				sw_doctor_fail hooks ".softwary/hooks/$_h is missing or not executable; rerun install.sh"
				return 0
			fi
		done
		sw_line hooks PASS
	elif [ -n "$_cur" ]; then
		sw_doctor_fail hooks "core.hooksPath is '$_cur', not .softwary/hooks"
	else
		_shown=$(cd "$SOFTWARY_ROOT" && git rev-parse --git-path hooks 2>/dev/null)
		case $_shown in
		/*) _hdir=$_shown ;;
		*) _hdir=$SOFTWARY_ROOT/$_shown ;;
		esac
		_custom=
		for _f in "$_hdir"/*; do
			[ -f "$_f" ] || continue
			case ${_f##*/} in *.sample) ;; *) _custom="$_custom $_shown/${_f##*/}" ;; esac
		done
		_why=
		[ -z "$_custom" ] || _why=" ($_custom is not a sample, so install.sh left it)"
		sw_doctor_fail hooks "core.hooksPath is not set; run: git config core.hooksPath .softwary/hooks$_why"
	fi
}

# sw_doctor_branches: both branch settings must be set; once the repository
# has commits, the integration branch must exist (verify compares with it).
sw_doctor_branches() {
	for _bk in $SW_BRANCH_KEYS; do
		if sw_conf_is_unset "$_bk"; then
			sw_doctor_fail "$_bk" "not set in $SW_CONF_REL"
		elif [ "$_bk" = integration_branch ] && sw_has_commits &&
			! git -C "$SOFTWARY_ROOT" rev-parse -q --verify "$(sw_conf_get "$_bk")^{commit}" >/dev/null 2>&1; then
			sw_doctor_fail "$_bk" "branch '$(sw_conf_get "$_bk")' not found"
		else
			sw_line "$_bk" PASS
		fi
	done
}

# sw_doctor_waivers: each waiver on its own line; an expired one is a problem.
sw_doctor_waivers() {
	sw_waivers_load
	if [ -n "$SW_WAIVERS_ERRORS" ]; then
		while IFS= read -r _err; do
			[ -n "$_err" ] && sw_doctor_fail waivers "$_err"
		done <<EOF
$SW_WAIVERS_ERRORS
EOF
	fi
	if [ -z "$SW_WAIVERS" ]; then
		[ -n "$SW_WAIVERS_ERRORS" ] || sw_line waivers "PASS (none)"
		return 0
	fi
	for _wk in $SW_WAIVERS; do
		sw_waiver "$_wk"
		if [ "$SW_WAIVER_EXPIRED" -eq 1 ]; then
			sw_doctor_fail "waiver $_wk" "expired $SW_WAIVER_DATE: $SW_WAIVER_REASON"
		else
			sw_line "waiver $_wk" "WAIVED ($SW_WAIVER_REASON, until $SW_WAIVER_DATE)"
		fi
	done
}

# sw_doctor_ci: the CI workflow must be placed and filled in; CODEOWNERS,
# when present, must cover the protected paths.
# Comment lines (#) are ignored.
sw_doctor_ci() {
	_wf=.github/workflows/softwary.yml
	if [ ! -f "$SOFTWARY_ROOT/$_wf" ]; then
		sw_doctor_fail workflow "$_wf not found; copy .softwary/templates/softwary.yml"
	else
		_lns=$(awk '/^[ \t]*#/ { next } /UNSET/ { print NR }' "$SOFTWARY_ROOT/$_wf")
		for _ln in $_lns; do
			sw_doctor_fail workflow "$_wf still contains UNSET (line $_ln)"
		done
		[ -n "$_lns" ] || sw_line workflow PASS
	fi
	_co=.github/CODEOWNERS
	# CODEOWNERS is optional: a team that wants owners to review uses it; the
	# loop's merges are gated by CI, not by a human review.
	if [ ! -f "$SOFTWARY_ROOT/$_co" ]; then
		sw_line CODEOWNERS "SKIP (optional)"
		return 0
	fi
	_cn=$_problems
	for _p in specs architecture .softwary/config .github; do
		# As on GitHub, the last matching line decides; it must name an owner.
		awk -v p="$_p" '
			/^[ \t]*#/ || NF < 1 { next }
			{ pat = $1; sub(/^\//, "", pat); sub(/\/\*\*$/, "", pat); sub(/\/$/, "", pat)
			  if (pat == p || pat == "*" || pat == "**") owned = (NF >= 2) }
			END { exit !owned }' "$SOFTWARY_ROOT/$_co" || sw_doctor_fail CODEOWNERS "does not cover $_p/"
	done
	# shellcheck disable=SC2013 # the words are line numbers, without whitespace
	for _ln in $(awk '/^[ \t]*#/ { next } { for (i = 2; i <= NF; i++) if ($i == "UNSET") { print NR; break } }' "$SOFTWARY_ROOT/$_co"); do
		sw_doctor_fail CODEOWNERS "owner is UNSET (line $_ln)"
	done
	[ "$_problems" -ne "$_cn" ] || sw_line CODEOWNERS PASS
}

# sw_doctor_conf LABEL ERRORS: PASS, or one FAIL line per problem.
sw_doctor_conf() {
	if [ -z "$2" ]; then
		sw_line "$1" PASS
		return 0
	fi
	while IFS= read -r _err; do
		[ -n "$_err" ] && sw_doctor_fail "$1" "$_err"
	done <<EOF
$2
EOF
}

sw_doctor() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary doctor\n' >&2
		return 2
	fi
	_problems=0

	for _tool in git jq; do
		if command -v "$_tool" >/dev/null 2>&1; then
			sw_line "$_tool" PASS
		else
			sw_doctor_fail "$_tool" "not found in PATH"
		fi
	done

	if ! command -v git >/dev/null 2>&1; then
		sw_doctor_fail "git repository" "cannot check without git"
	elif git -C "$SOFTWARY_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		sw_line "git repository" PASS
		sw_doctor_hooks
	else
		sw_doctor_fail "git repository" "not a git repository"
	fi

	if [ -x "$SOFTWARY_ROOT/softwary" ]; then
		sw_line "wrapper" PASS
	else
		sw_doctor_fail "wrapper" "./softwary missing or not executable; rerun install.sh"
	fi

	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	if [ "$SW_CONF_FOUND" -eq 0 ]; then
		sw_doctor_fail "commands.conf" "$SW_CONF_REL not found; rerun install.sh"
	else
		if [ -z "$SW_CONF_ERRORS" ]; then
			sw_line "commands.conf" PASS
		else
			while IFS= read -r _err; do
				[ -n "$_err" ] && sw_doctor_fail "commands.conf" "$_err"
			done <<EOF
$SW_CONF_ERRORS
EOF
		fi
		# doctor never runs the project's commands: verify does.
		for _k in $SW_REQUIRED_KEYS; do
			if sw_conf_is_unset "$_k"; then
				sw_doctor_fail "$_k" UNSET
			else
				case $(sw_conf_get "$_k") in
				NONE | NONE:*) sw_line "$_k" "SKIP ($(sw_none_reason "$(sw_conf_get "$_k")"))" ;;
				*) sw_line "$_k" "PASS (configured, not run)" ;;
				esac
			fi
		done
		for _k in $(sw_conf_unknown_keys); do
			sw_doctor_fail "$_k" "unknown key, line $(sw_conf_line "$_k")"
		done
		_spp=$(sw_src_paths_problems)
		if [ -n "$_spp" ]; then
			while IFS= read -r _err; do
				sw_doctor_fail src_paths "$_err"
			done <<EOF
$_spp
EOF
		else
			sw_line src_paths PASS
		fi
		sw_doctor_branches
	fi
	sw_doctor_waivers

	SW_PROBLEMS=
	sw_tools_load
	if [ -n "$SW_PROBLEMS" ]; then
		while IFS= read -r _err; do
			[ -n "$_err" ] && sw_doctor_fail "tools.conf" "$_err"
		done <<EOF
$SW_PROBLEMS
EOF
	else
		sw_line "tools.conf" PASS
		_rc=0
		_sync_out=$(sw_sync --check) || _rc=$?
		if [ "$_rc" -eq 0 ]; then
			sw_line "generated" PASS
		else
			while IFS= read -r _err; do
				case $_err in '' | sync*) continue ;; esac
				sw_doctor_fail "generated" "$(printf '%s' "$_err" | tr -s ' ')"
			done <<EOF
$_sync_out
EOF
		fi
	fi

	sw_risk_load
	if [ -n "$SW_RISK_ERRORS" ]; then
		while IFS= read -r _err; do
			[ -n "$_err" ] && sw_doctor_fail "risk.conf" "$_err"
		done <<EOF
$SW_RISK_ERRORS
EOF
	else
		sw_line "risk.conf" PASS
	fi

	sw_doctor_ci

	sw_loop_load || :
	sw_doctor_conf loop.conf "${SW_LOOP_ERRORS-}"
	sw_models_load || :
	sw_doctor_conf models "${SW_MODELS_ERRORS-}"
	sw_testskip_load || :
	sw_doctor_conf test-skip "${SW_TS_ERRORS-}"

	if [ -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ]; then
		sw_line "model" PASS
	else
		sw_doctor_fail "model" "$SW_MODEL_MISSING"
	fi

	if [ "$_problems" -eq 0 ]; then
		printf 'doctor: no problems found\n'
		return 0
	fi
	printf 'doctor: %s problem(s) found\n' "$_problems"
	return 2
}
