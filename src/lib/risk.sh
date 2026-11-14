# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_RISK_* globals are read by doctor.sh
# softwary: risk.conf and the `risk` command. Sourced by bin/softwary. POSIX sh.
#
# risk.conf: one `<glob> = R1|R2|R3` per line and a required `default`. A glob
# is a shell pattern matched against repo-relative paths ('*' matches '/').

SW_RISK_REL=.softwary/config/risk.conf

# sw_tier_num TIER: 1, 2 or 3 for R1..R3; 0 otherwise.
sw_tier_num() {
	case $1 in R1) echo 1 ;; R2) echo 2 ;; R3) echo 3 ;; *) echo 0 ;; esac
}

# sw_risk_load: parses risk.conf. Sets SW_RISK_RULES ("TIER<TAB>GLOB" lines in
# file order), SW_RISK_DEFAULT and SW_RISK_ERRORS ("REL:LINE: message" lines).
sw_risk_load() {
	SW_RISK_RULES='' SW_RISK_DEFAULT='' SW_RISK_ERRORS=''
	_rf=$SOFTWARY_ROOT/$SW_RISK_REL
	if [ ! -f "$_rf" ]; then
		SW_RISK_ERRORS="$SW_RISK_REL: not found; rerun install.sh
"
		return 0
	fi
	_n=0 _seen='' _default_line=''
	while IFS= read -r _line || [ -n "$_line" ]; do
		_n=$((_n + 1))
		_line=$(sw_trim "$_line")
		case $_line in '' | '#'*) continue ;; esac
		_key=$(sw_trim "${_line%%=*}")
		_value=$(sw_trim "${_line#*=}")
		case $_line in *=*) ;; *) _key= ;; esac
		case $_key in
		'' | *[[:space:]]*)
			sw_risk_error "$_n" "malformed line: expected '<glob> = R1|R2|R3'"
			continue
			;;
		esac
		if printf '%s\n' "$_seen" | grep -Fqx -e "$_key"; then
			sw_risk_error "$_n" "duplicate '$_key'"
			continue
		fi
		_seen="$_seen$_key
"
		if [ "$_key" = default ] && [ "$_value" = UNSET ]; then
			sw_risk_error "$_n" "'default' is UNSET (set it to R1, R2 or R3)"
			_default_line=$_n
			continue
		fi
		if [ "$(sw_tier_num "$_value")" -eq 0 ]; then
			sw_risk_error "$_n" "invalid tier '$_value' for '$_key' (use R1, R2 or R3)"
			[ "$_key" != default ] || _default_line=$_n
			continue
		fi
		if [ "$_key" = default ]; then
			SW_RISK_DEFAULT=$_value
			_default_line=$_n
		else
			SW_RISK_RULES="$SW_RISK_RULES$_value	$_key
"
		fi
	done <"$_rf"
	[ -n "$_default_line" ] || SW_RISK_ERRORS="$SW_RISK_ERRORS$SW_RISK_REL: 'default' is missing
"
}

sw_risk_error() {
	SW_RISK_ERRORS="$SW_RISK_ERRORS$SW_RISK_REL:$1: $2
"
}

# sw_path_tier PATH: prints "TIER<TAB>LABEL": the highest tier of the globs
# that match PATH (LABEL is the glob), or the default (LABEL "default").
sw_path_tier() {
	_best=0 _blabel=
	while IFS='	' read -r _t _g; do
		[ -n "$_g" ] || continue
		# shellcheck disable=SC2254 # the glob is a pattern on purpose
		case $1 in $_g)
			_tn=$(sw_tier_num "$_t")
			if [ "$_tn" -gt "$_best" ]; then _best=$_tn _blabel=$_g; fi
			;;
		esac
	done <<RULES
$SW_RISK_RULES
RULES
	if [ "$_best" -eq 0 ]; then
		printf '%s\tdefault\n' "$SW_RISK_DEFAULT"
	else
		printf 'R%s\t%s\n' "$_best" "$_blabel"
	fi
}

# sw_risk SPEC [--base REF]: the review tier of a change.
sw_risk() {
	_spec='' _base=main
	while [ $# -gt 0 ]; do
		case $1 in
		--base)
			[ $# -ge 2 ] || { sw_risk_usage; return 2; }
			_base=$2
			shift 2
			;;
		-*) sw_risk_usage; return 2 ;;
		*)
			[ -z "$_spec" ] || { sw_risk_usage; return 2; }
			_spec=$1
			shift
			;;
		esac
	done
	[ -n "$_spec" ] || { sw_risk_usage; return 2; }

	sw_risk_load
	if [ -n "$SW_RISK_ERRORS" ]; then
		printf '%s' "$SW_RISK_ERRORS"
		return 2
	fi

	# The spec: by id (001) or by directory (specs/001-x, with or without spec.md).
	_sdir=
	case $_spec in
	[0-9][0-9][0-9])
		for _d in "$SOFTWARY_ROOT"/specs/"$_spec"-*/; do
			[ -f "$_d/spec.md" ] && _sdir=${_d%/} && break
		done
		;;
	*)
		_s=${_spec%/spec.md}
		_s=${_s%/}
		[ -f "$SOFTWARY_ROOT/$_s/spec.md" ] && _sdir=$SOFTWARY_ROOT/$_s
		;;
	esac
	if [ -z "$_sdir" ]; then
		printf "risk: spec '%s' not found\n" "$_spec"
		return 2
	fi
	_srel=specs/${_sdir##*/}/spec.md
	sw_fm_read "$_sdir/spec.md"
	_srisk=$(sw_fm_get risk)
	if [ "$(sw_tier_num "$_srisk")" -eq 0 ]; then
		printf "%s: risk: '%s' must be one of R1, R2, R3\n" "$_srel" "$_srisk"
		return 2
	fi

	_mrc=0
	sw_model_check >/dev/null || _mrc=$?
	case $_mrc in
	2) printf 'risk: %s\n' "$SW_MODEL_MISSING"; return 2 ;;
	1) printf 'risk: the model is invalid; run ./softwary model validate\n'; return 2 ;;
	esac

	if ! git -C "$SOFTWARY_ROOT" rev-parse -q --verify "$_base^{commit}" >/dev/null 2>&1; then
		printf "risk: base '%s' not found (use --base <ref>)\n" "$_base"
		return 2
	fi
	if ! _mb=$(git -C "$SOFTWARY_ROOT" merge-base "$_base" HEAD 2>/dev/null); then
		printf "risk: no common commit between '%s' and HEAD\n" "$_base"
		return 2
	fi
	_changed=$(cd "$SOFTWARY_ROOT" && {
		git diff --name-only "$_mb" --
		git ls-files --others --exclude-standard
	} | sort -u)

	_max=$(sw_tier_num "$_srisk")
	sw_line spec "$_srisk ($_srel)"

	# Changed paths: the highest tier and the first path that reaches it.
	_pbest=0 _pdesc=
	if [ -n "$_changed" ]; then
		while IFS= read -r _p; do
			_pt=$(sw_path_tier "$_p")
			_tn=$(sw_tier_num "${_pt%%	*}")
			if [ "$_tn" -gt "$_pbest" ]; then _pbest=$_tn _pdesc="$_p: ${_pt#*	}"; fi
		done <<CHANGED
$_changed
CHANGED
		sw_line paths "R$_pbest ($_pdesc)"
		[ "$_pbest" -le "$_max" ] || _max=$_pbest
	else
		sw_line paths "none (no changed paths)"
	fi

	# Components: named in the spec's model field, or whose paths cover a change.
	_named=$(sw_list "$(sw_fm_get model)")
	_cdesc='' _cbest=0
	_nodes=$(jq -r '.nodes[] | (.metadata | if type == "array" then add // {} else . // {} end) as $m
		| select($m.risk | type == "string")
		| [."unique-id", $m.risk] + ($m.paths // []) | join("\t")' "$SOFTWARY_ROOT/$SW_MODEL_REL")
	set -f
	while IFS='	' read -r _cid _crisk _cpaths; do
		[ -n "$_cid" ] || continue
		_hit=0
		if printf '%s\n' "$_named" | grep -Fqx -e "$_cid"; then
			_hit=1
		elif [ -n "$_changed" ]; then
			_old_ifs=$IFS
			IFS='	'
			for _g in $_cpaths; do
				IFS=$_old_ifs
				while IFS= read -r _p; do
					# shellcheck disable=SC2254 # the glob is a pattern on purpose
					case $_p in $_g) _hit=1 ;; esac
				done <<CHANGED
$_changed
CHANGED
			done
			IFS=$_old_ifs
		fi
		[ "$_hit" -eq 1 ] || continue
		_cdesc="${_cdesc:+$_cdesc, }$_cid $_crisk"
		_tn=$(sw_tier_num "$_crisk")
		[ "$_tn" -le "$_cbest" ] || _cbest=$_tn
	done <<NODES
$_nodes
NODES
	set +f
	if [ -n "$_cdesc" ]; then
		sw_line components "R$_cbest ($_cdesc)"
		[ "$_cbest" -le "$_max" ] || _max=$_cbest
	else
		sw_line components none
	fi
	sw_line risk "R$_max"
}

sw_risk_usage() {
	printf 'usage: ./softwary risk <spec> [--base <ref>]   (<spec>: 001 or specs/001-name)\n' >&2
}
