# shellcheck shell=sh
# softwary: ADR checks. Sourced by bin/softwary. POSIX sh.
#
# `trace` validates every architecture decision record (sw_trace_adrs).
# ADR front matter: id title status affects. `affects` lists repo paths inside
# architecture/, comma-separated; a directory covers everything below it.

SW_ADR_REL=architecture/decisions
SW_ADR_FIELDS="id title status affects"
SW_ADR_STATUSES="proposed accepted superseded rejected"

# sw_adr_entry_scope ENTRY: true if ENTRY is a path below architecture/ with
# no '..', '.' or empty segment and no leading '/'.
sw_adr_entry_scope() {
	case $1 in
	architecture/?*) ;;
	*) return 1 ;;
	esac
	case /$1/ in
	*/../* | */./* | *//*) return 1 ;;
	esac
	return 0
}

# sw_trace_adrs: checks every file under architecture/decisions/ (called by
# sw_trace; adds to _tr_probs through sw_tr_problem and counts _tr_adrs).
sw_trace_adrs() {
	for _af in "$SOFTWARY_ROOT/$SW_ADR_REL"/*.md; do
		[ -f "$_af" ] || continue
		_tr_adrs=$((_tr_adrs + 1))
		_ab=${_af##*/}
		_arel=$SW_ADR_REL/$_ab
		sw_fm_read "$_af"
		sw_tr_fields "$_arel" "$SW_ADR_FIELDS" "$SW_ADR_FIELDS"
		if printf '%s\n' "$_ab" | grep -Eq '^[0-9]{4}-[a-z0-9][a-z0-9-]*\.md$'; then
			_v=$(sw_fm_get id)
			case $_v in '' | UNSET | "${_ab%%-*}") ;; *) sw_tr_problem "$_arel" "id: '$_v' does not match the file name $_ab" ;; esac
		else
			sw_tr_problem "$_arel" "file name must be NNNN-<name>.md"
		fi
		sw_tr_enum "$_arel" status "$SW_ADR_STATUSES"
		_aff=$(sw_list "$(sw_fm_get affects)")
		[ -n "$_aff" ] || continue
		while IFS= read -r _ae; do
			if ! sw_adr_entry_scope "$_ae"; then
				sw_tr_problem "$_arel" "affects: '$_ae' is outside architecture/"
			elif [ ! -e "$SOFTWARY_ROOT/$_ae" ]; then
				sw_tr_problem "$_arel" "affects: '$_ae' not found"
			fi
		done <<AFFECTS
$_aff
AFFECTS
	done
}

# --- the `adr` gate ---------------------------------------------------------

SW_CONTRACTS_REL=architecture/contracts

# sw_base_commit REF [NAME]: sets SW_BASE_COMMIT to the merge-base of REF and
# HEAD. Prints the reason (prefixed with NAME, default adr) and returns 2 when
# REF cannot be used.
sw_base_commit() {
	SW_BASE_COMMIT=
	_bn=${2:-adr}
	case $1 in
	-*)
		printf "%s: base '%s' not found (use --base <ref>)\n" "$_bn" "$1"
		return 2
		;;
	esac
	if ! git -C "$SOFTWARY_ROOT" rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1; then
		printf "%s: base '%s' not found (use --base <ref>)\n" "$_bn" "$1"
		return 2
	fi
	if ! SW_BASE_COMMIT=$(git -C "$SOFTWARY_ROOT" merge-base "$1" HEAD 2>/dev/null); then
		printf "%s: no common commit between '%s' and HEAD\n" "$_bn" "$1"
		return 2
	fi
}

# sw_changed_since COMMIT: the paths changed since COMMIT (committed,
# uncommitted and untracked), sorted and unique. Renames are not collapsed:
# both the old and the new path are listed. Non-ASCII names stay unquoted.
sw_changed_since() {
	(cd "$SOFTWARY_ROOT" && {
		git -c core.quotePath=false diff --no-renames --name-only "$1" --
		git -c core.quotePath=false ls-files --others --exclude-standard
	} | sort -u)
}

# sw_adr_covers ENTRY PATH: true if PATH is ENTRY or below the directory ENTRY.
sw_adr_covers() {
	_cv=${1%/}
	[ "$2" = "$_cv" ] && return 0
	case $2 in "$_cv"/*) return 0 ;; esac
	return 1
}

sw_adr_usage() {
	printf 'usage: ./softwary adr [--base <ref>]\n' >&2
}

# sw_adr [--base REF]: every model or contract file changed since REF
# (default main) needs an accepted ADR in the change whose affects covers it.
# The ADR must be new in the change or not yet accepted on the base.
# Exit: 0 covered, 1 not covered, 2 base missing or usage.
sw_adr() {
	_adr_base=main
	while [ $# -gt 0 ]; do
		case $1 in
		--base)
			[ $# -ge 2 ] || { sw_adr_usage; return 2; }
			_adr_base=$2
			shift 2
			;;
		*) sw_adr_usage; return 2 ;;
		esac
	done
	sw_base_commit "$_adr_base" || return 2
	_changed=$(sw_changed_since "$SW_BASE_COMMIT")

	_gated=
	_cands=
	while IFS= read -r _p; do
		case $_p in
		"$SW_MODEL_REL" | "$SW_CONTRACTS_REL"/?*) _gated="$_gated$_p
" ;;
		# git still quotes names with tabs, newlines or quotes: gate them too
		# (no ADR entry can cover such a name, so they fail closed).
		\"*"$SW_CONTRACTS_REL"/*) _gated="$_gated$_p
" ;;
		"$SW_ADR_REL"/*.md)
			[ -f "$SOFTWARY_ROOT/$_p" ] || continue
			# An ADR already accepted on the base was accepted for another
			# change; reusing it would let a change pass without a human
			# accepting anything in it.
			_bs=
			if git -C "$SOFTWARY_ROOT" cat-file -e "$SW_BASE_COMMIT:$_p" 2>/dev/null; then
				_bf=$(mktemp) || return 2
				git -C "$SOFTWARY_ROOT" show "$SW_BASE_COMMIT:$_p" >"$_bf" 2>/dev/null
				sw_fm_read "$_bf"
				_bs=$(sw_fm_get status)
				rm -f "$_bf"
			fi
			sw_fm_read "$SOFTWARY_ROOT/$_p"
			_cs=$(sw_fm_get status)
			[ "$_cs" != accepted ] || [ "$_bs" != accepted ] || _cs=base-accepted
			_ci=$(sw_fm_get id)
			[ -n "$_ci" ] || _ci=${_p##*/}
			while IFS= read -r _ce; do
				sw_adr_entry_scope "$_ce" || continue
				_cands="$_cands$_cs	$_ci	$_ce
"
			done <<AFFECTS
$(sw_list "$(sw_fm_get affects)")
AFFECTS
			;;
		esac
	done <<CHANGED
$_changed
CHANGED

	if [ -z "$_gated" ]; then
		printf 'adr: no model or contract changes\n'
		return 0
	fi
	_miss=0
	while IFS= read -r _p; do
		[ -n "$_p" ] || continue
		_acc='' _prop='' _based=''
		while IFS='	' read -r _cs _ci _ce; do
			[ -n "$_ce" ] || continue
			sw_adr_covers "$_ce" "$_p" || continue
			case $_cs in
			accepted) [ -n "$_acc" ] || _acc=$_ci ;;
			proposed) [ -n "$_prop" ] || _prop=$_ci ;;
			base-accepted) [ -n "$_based" ] || _based=$_ci ;;
			esac
		done <<CANDS
$_cands
CANDS
		if [ -n "$_acc" ]; then
			printf '%s: covered by ADR %s\n' "$_p" "$_acc"
		elif [ -n "$_prop" ]; then
			printf '%s: awaiting human acceptance (ADR %s is proposed)\n' "$_p" "$_prop"
			_miss=$((_miss + 1))
		elif [ -n "$_based" ]; then
			printf '%s: no accepted ADR in this change covers it (ADR %s was already accepted on the base)\n' "$_p" "$_based"
			_miss=$((_miss + 1))
		else
			printf '%s: no accepted ADR in this change covers it\n' "$_p"
			_miss=$((_miss + 1))
		fi
	done <<GATED
$_gated
GATED
	if [ "$_miss" -gt 0 ]; then
		printf 'adr: %s path(s) need an accepted ADR\n' "$_miss"
		return 1
	fi
	printf 'adr: ok\n'
}
