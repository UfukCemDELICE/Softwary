# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by verify.sh, doctor.sh and the other libs
# softwary: `model validate` and `views`. Sourced by bin/softwary. POSIX sh.
#
# The model is architecture/model/system.calm.json (CALM 1.3). lib/model.jq
# holds the checks and lib/views.jq the Mermaid view.

SW_MODEL_REL=architecture/model/system.calm.json
SW_VIEW_REL=architecture/views/system.mmd
SW_MODEL_MISSING="$SW_MODEL_REL not found; start from .softwary/templates/system.calm.json"

# sw_model_check: prints one "<file>: <path>: <problem>" line per problem.
# Returns 0 valid, 1 problems, 2 no model file.
sw_model_check() {
	_mf=$SOFTWARY_ROOT/$SW_MODEL_REL
	[ -f "$_mf" ] || return 2
	if ! _merr=$(jq empty "$_mf" 2>&1); then
		printf '%s: invalid JSON: %s\n' "$SW_MODEL_REL" "$(printf '%s\n' "$_merr" | head -n 1)"
		return 1
	fi
	_mout=$(jq -r -f "$SOFTWARY_HOME/lib/model.jq" "$_mf") || {
		printf '%s: could not be checked (jq failed)\n' "$SW_MODEL_REL"
		return 1
	}
	[ -n "$_mout" ] || return 0
	printf '%s\n' "$_mout" | sed "s|^|$SW_MODEL_REL: |"
	return 1
}

sw_model() {
	if [ $# -ne 1 ] || [ "$1" != validate ]; then
		printf 'usage: ./softwary model validate\n' >&2
		return 2
	fi
	_rc=0
	_probs=$(sw_model_check) || _rc=$?
	case $_rc in
	0)
		printf 'model: valid (%s)\n' "$(jq -r '"\(.nodes | length) nodes, \(.relationships // [] | length) relationships"' \
			"$SOFTWARY_ROOT/$SW_MODEL_REL")"
		return 0
		;;
	2)
		printf 'model: %s\n' "$SW_MODEL_MISSING"
		return 2
		;;
	esac
	printf '%s\n' "$_probs"
	printf 'model: %s problem(s)\n' "$(printf '%s\n' "$_probs" | wc -l | tr -d ' ')"
	return 1
}

# sw_views [--check]: writes architecture/views/system.mmd from the model, or
# with --check reports it as missing or stale without writing.
sw_views() {
	_check=0
	for _a in "$@"; do
		case $_a in
		--check) _check=1 ;;
		*)
			printf 'usage: ./softwary views [--check]\n' >&2
			return 2
			;;
		esac
	done
	_rc=0
	sw_model_check >/dev/null || _rc=$?
	case $_rc in
	2)
		printf 'views: %s\n' "$SW_MODEL_MISSING"
		return 2
		;;
	1)
		printf 'views: the model is invalid; run ./softwary model validate\n'
		return 1
		;;
	esac
	_vtmp=$(mktemp "${TMPDIR:-/tmp}/softwary-view.XXXXXX") || return 2
	if ! jq -r -f "$SOFTWARY_HOME/lib/views.jq" "$SOFTWARY_ROOT/$SW_MODEL_REL" >"$_vtmp"; then
		rm -f "$_vtmp"
		printf 'views: could not render the model (jq failed)\n'
		return 1
	fi
	_view=$SOFTWARY_ROOT/$SW_VIEW_REL
	if [ "$_check" -eq 1 ]; then
		_vrc=0
		if [ ! -f "$_view" ]; then
			printf '%-8s %s\n' missing "$SW_VIEW_REL"
			_vrc=1
		elif ! cmp -s "$_vtmp" "$_view"; then
			printf '%-8s %s\n' stale "$SW_VIEW_REL"
			_vrc=1
		fi
		rm -f "$_vtmp"
		if [ "$_vrc" -eq 0 ]; then
			printf 'views --check: up to date\n'
		else
			printf 'views --check: out of date; run ./softwary views\n'
		fi
		return "$_vrc"
	fi
	if [ -f "$_view" ] && cmp -s "$_vtmp" "$_view"; then
		rm -f "$_vtmp"
		printf 'views: up to date\n'
		return 0
	fi
	_vrc=0
	{ mkdir -p "$(dirname "$_view")" && cp "$_vtmp" "$_view"; } || _vrc=2
	rm -f "$_vtmp"
	[ "$_vrc" -eq 0 ] || return 2
	printf 'views: wrote %s\n' "$SW_VIEW_REL"
}
