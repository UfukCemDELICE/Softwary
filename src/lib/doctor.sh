# shellcheck shell=sh
# softwary: `doctor` command. Sourced by bin/softwary. POSIX sh.
#
# Reports installation and configuration problems, one line each.
# Exit: 0 no problem, 2 at least one problem.

sw_doctor_fail() {
	sw_line "$1" "FAIL ($2)"
	_problems=$((_problems + 1))
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

	if [ "$_problems" -eq 0 ]; then
		printf 'doctor: no problems found\n'
		return 0
	fi
	printf 'doctor: %s problem(s) found\n' "$_problems"
	return 2
}
