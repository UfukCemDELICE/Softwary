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

# sw_doctor_ci: the CI workflow and CODEOWNERS must be placed and filled in.
# Comment lines (#) are ignored.
sw_doctor_ci() {
	_wf=.github/workflows/softwary.yml
	if [ ! -f "$SOFTWARY_ROOT/$_wf" ]; then
		sw_doctor_fail workflow "$_wf not found; copy .softwary/templates/softwary.yml"
	else
		_ln=$(awk '/^[ \t]*#/ { next } /UNSET/ { print NR; exit }' "$SOFTWARY_ROOT/$_wf")
		if [ -n "$_ln" ]; then
			sw_doctor_fail workflow "$_wf still contains UNSET (line $_ln)"
		else
			sw_line workflow PASS
		fi
	fi
	_co=.github/CODEOWNERS
	if [ ! -f "$SOFTWARY_ROOT/$_co" ]; then
		sw_doctor_fail CODEOWNERS "$_co not found; copy .softwary/templates/CODEOWNERS"
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
		for _k in $SW_REQUIRED_KEYS; do
			if sw_conf_is_unset "$_k"; then
				sw_doctor_fail "$_k" UNSET
			else
				sw_line "$_k" PASS
			fi
		done
		for _k in $(sw_conf_unknown_keys); do
			sw_doctor_fail "$_k" "unknown key, line $(sw_conf_line "$_k")"
		done
	fi

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
