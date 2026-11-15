# shellcheck shell=sh
# softwary: artifact front matter, `trace` and `status`. Sourced by
# bin/softwary. POSIX sh.
#
# Front matter: the file starts with a `---` line, then `key: value` lines,
# then a closing `---` line. List values are comma-separated.

SW_SPEC_FIELDS="id title status risk model contracts"
SW_SPEC_NONEMPTY="id title status risk"
SW_SPEC_STATUSES="draft approved done"
SW_SLICE_FIELDS="id spec goal acs depends_on touches status"
SW_SLICE_NONEMPTY="id spec goal acs status"
SW_SLICE_STATUSES="planned in-progress review done"
SW_TIERS="R1 R2 R3"
SW_SPEC_MAX_WORDS=600

# sw_fm_read FILE: sets _fm to "F<TAB>key<TAB>value" and "E<TAB>problem" lines.
sw_fm_read() {
	_fm=$(awk '
		NR == 1 {
			if ($0 != "---") { print "E\tmissing front matter (the first line must be ---)"; bad = 1; exit }
			next
		}
		$0 == "---" { closed = 1; exit }
		{
			if (match($0, /^[a-z_]+:/)) {
				k = substr($0, 1, RLENGTH - 1)
				v = substr($0, RLENGTH + 1)
				gsub(/^[ \t]+|[ \t]+$/, "", v)
				if (k in seen) print "E\t" k ": duplicate field"
				else { seen[k] = 1; print "F\t" k "\t" v }
			} else print "E\tfront matter line " NR ": expected \"key: value\""
		}
		END {
			if (NR == 0) print "E\tmissing front matter (the first line must be ---)"
			else if (!bad && !closed) print "E\tfront matter is not closed with ---"
		}' "$1")
}

# sw_fm_has KEY / sw_fm_get KEY: read the front matter loaded by sw_fm_read.
sw_fm_has() {
	printf '%s\n' "$_fm" | awk -F '\t' -v k="$1" '$1 == "F" && $2 == k { f = 1 } END { exit !f }'
}

sw_fm_get() {
	printf '%s\n' "$_fm" | awk -F '\t' -v k="$1" '$1 == "F" && $2 == k { print $3; exit }'
}

# sw_fm_errors: prints the structural problems found by sw_fm_read.
sw_fm_errors() {
	printf '%s\n' "$_fm" | awk -F '\t' '$1 == "E" { print $2 }'
}

# sw_list VALUE: prints the comma-separated items of VALUE, one per line.
sw_list() {
	printf '%s\n' "$1" | tr ',' '\n' | while IFS= read -r _item; do
		_item=$(sw_trim "$_item")
		[ -z "$_item" ] || printf '%s\n' "$_item"
	done
}

# sw_tr_problem REL MESSAGE: records a trace problem.
sw_tr_problem() {
	_tr_probs="${_tr_probs}$1: $2
"
	_tr_n=$((_tr_n + 1))
}

# sw_tr_fields REL FIELDS NONEMPTY: checks the loaded front matter: structural
# problems, unknown, missing, empty and UNSET fields.
sw_tr_fields() {
	_ferrs=$(sw_fm_errors)
	if [ -n "$_ferrs" ]; then
		while IFS= read -r _e; do
			sw_tr_problem "$1" "$_e"
		done <<ERRS
$_ferrs
ERRS
	fi
	case $_ferrs in "missing front matter"*) return 0 ;; esac
	for _k in $(printf '%s\n' "$_fm" | awk -F '\t' '$1 == "F" { print $2 }'); do
		sw_in_list "$_k" "$2" || sw_tr_problem "$1" "unknown field '$_k'"
	done
	for _k in $2; do
		if ! sw_fm_has "$_k"; then
			sw_tr_problem "$1" "$_k: missing"
			continue
		fi
		_v=$(sw_fm_get "$_k")
		if [ "$_v" = UNSET ]; then
			sw_tr_problem "$1" "$_k: is UNSET"
		elif [ -z "$_v" ] && sw_in_list "$_k" "$3"; then
			sw_tr_problem "$1" "$_k: is empty"
		fi
	done
}

# sw_tr_enum REL KEY ALLOWED: KEY must be one of ALLOWED (absent, empty and
# UNSET values are reported by sw_tr_fields).
sw_tr_enum() {
	_v=$(sw_fm_get "$2")
	case $_v in '' | UNSET) return 0 ;; esac
	sw_in_list "$_v" "$3" ||
		sw_tr_problem "$1" "$2: '$_v' must be one of $(printf '%s' "$3" | sed 's/ /, /g')"
}

# sw_spec_criteria FILE ID: prints the distinct criterion ids AC-ID-NN found in
# the spec's body (after the front matter), sorted.
sw_spec_criteria() {
	awk -v pre="AC-$2-" '
		NR == 1 && $0 == "---" { infm = 1; next }
		infm { if ($0 == "---") infm = 0; next }
		{
			line = $0
			while ((i = index(line, pre)) > 0) {
				rest = substr(line, i + length(pre))
				if (rest ~ /^[0-9][0-9]([^0-9]|$)/) print pre substr(rest, 1, 2)
				line = rest
			}
		}' "$1" | sort -u
}

# sw_spec_open_questions FILE: true if "## Open questions" has a list item.
sw_spec_open_questions() {
	awk '
		/^## / { on = ($0 ~ /^## Open questions[ \t]*$/); next }
		on && /^[ \t]*([-*+]|[0-9]+\.)[ \t]/ { found = 1 }
		END { exit !found }' "$1"
}

# sw_model_ids: prints the unique-ids of the model's nodes (nothing if the
# model is missing or unreadable).
sw_model_ids() {
	[ -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ] || return 0
	jq -r '.nodes[]? | objects | ."unique-id" | strings' "$SOFTWARY_ROOT/$SW_MODEL_REL" 2>/dev/null
}

# sw_count TEXT: the number of non-empty lines in TEXT.
sw_count() {
	printf '%s\n' "$1" | grep -c . || :
}

# sw_trace_slice SPECDIR FILE: checks one slice of the spec in SPECDIR.
# Uses _drel, _sid, _status and _acs of the spec; adds to _owners and _tr_need.
sw_trace_slice() {
	_tr_slices=$((_tr_slices + 1))
	_lrel=$_drel/slices/$2
	_lname=${2%.md}
	printf '%s\n' "$_lname" | grep -Eq '^S[1-9][0-9]*$' ||
		sw_tr_problem "$_lrel" "file name must be S<n>.md"
	sw_fm_read "$1/slices/$2"
	sw_tr_fields "$_lrel" "$SW_SLICE_FIELDS" "$SW_SLICE_NONEMPTY"
	_v=$(sw_fm_get id)
	case $_v in '' | UNSET | "$_lname") ;; *) sw_tr_problem "$_lrel" "id: '$_v' does not match the file name $2" ;; esac
	_v=$(sw_fm_get spec)
	case $_v in '' | UNSET | "$_sid") ;; *) sw_tr_problem "$_lrel" "spec: '$_v' is not this slice's spec ($_sid)" ;; esac
	sw_tr_enum "$_lrel" status "$SW_SLICE_STATUSES"
	case $_status in approved | done) ;; *) sw_tr_problem "$_lrel" "spec $_sid is not approved" ;; esac
	_lstatus=$(sw_fm_get status)
	for _a in $(sw_list "$(sw_fm_get acs)"); do
		if ! printf '%s\n' "$_a" | grep -Eq "^AC-$_sid-[0-9][0-9]\$"; then
			sw_tr_problem "$_lrel" "acs: '$_a' is not a criterion id of spec $_sid"
		elif ! printf '%s\n' "$_acs" | grep -Fqx -e "$_a"; then
			sw_tr_problem "$_lrel" "acs: $_a is not in the spec"
		else
			_owners="$_owners$_a $_lname
"
			case $_lstatus in review | done) _tr_need="$_tr_need$_lrel $_a
" ;;
			esac
		fi
	done
	for _d in $(sw_list "$(sw_fm_get depends_on)"); do
		if [ "$_d" = "$_lname" ]; then
			sw_tr_problem "$_lrel" "depends_on: a slice cannot depend on itself"
		elif [ ! -f "$1/slices/$_d.md" ]; then
			sw_tr_problem "$_lrel" "depends_on: unknown slice '$_d'"
		fi
	done
}

# sw_trace_spec DIR: checks one spec directory (absolute path, no trailing /).
sw_trace_spec() {
	_dn=${1##*/}
	_drel=specs/$_dn
	_sid=${_dn%%-*}
	_srel=$_drel/spec.md
	if [ ! -f "$1/spec.md" ]; then
		sw_tr_problem "$_drel" "spec.md missing"
		return 0
	fi
	_tr_specs=$((_tr_specs + 1))
	sw_fm_read "$1/spec.md"
	sw_tr_fields "$_srel" "$SW_SPEC_FIELDS" "$SW_SPEC_NONEMPTY"
	_v=$(sw_fm_get id)
	case $_v in '' | UNSET | "$_sid") ;; *) sw_tr_problem "$_srel" "id: '$_v' does not match the directory $_dn" ;; esac
	sw_tr_enum "$_srel" status "$SW_SPEC_STATUSES"
	sw_tr_enum "$_srel" risk "$SW_TIERS"
	_status=$(sw_fm_get status)
	_model_list=$(sw_list "$(sw_fm_get model)")
	_contract_list=$(sw_list "$(sw_fm_get contracts)")
	if [ -n "$_model_list" ] && [ ! -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ]; then
		sw_tr_problem "$_srel" "model: $SW_MODEL_REL not found"
	elif [ -n "$_model_list" ]; then
		for _c in $_model_list; do
			printf '%s\n' "$_tr_ids" | grep -Fqx -e "$_c" || sw_tr_problem "$_srel" "model: unknown component '$_c'"
		done
	fi
	if [ -n "$_contract_list" ]; then
		while IFS= read -r _c; do
			[ -f "$SOFTWARY_ROOT/$_c" ] || sw_tr_problem "$_srel" "contracts: '$_c' not found"
		done <<CONTRACTS
$_contract_list
CONTRACTS
	fi
	case $_status in
	approved | done)
		if sw_spec_open_questions "$1/spec.md"; then
			sw_tr_problem "$_srel" "open questions: an approved spec must have none"
		fi
		_words=$(wc -w <"$1/spec.md" | tr -d ' ')
		[ "$_words" -le "$SW_SPEC_MAX_WORDS" ] ||
			sw_tr_problem "$_srel" "$_words words; an approved spec must be at most $SW_SPEC_MAX_WORDS"
		;;
	esac

	_acs=$(sw_spec_criteria "$1/spec.md" "$_sid")
	_tr_criteria=$((_tr_criteria + $(sw_count "$_acs")))
	_slices=
	[ ! -d "$1/slices" ] || _slices=$(cd "$1/slices" && find . -type f -name '*.md' | sed 's|^\./||' | sort)
	[ -n "$_slices" ] || return 0
	_owners=
	for _f in $_slices; do
		sw_trace_slice "$1" "$_f"
	done
	# Coverage: every criterion belongs to exactly one slice.
	for _a in $_acs; do
		_who=$(printf '%s' "$_owners" | awk -v a="$_a" '$1 == a { print $2 }' | sort -u)
		_count=$(sw_count "$_who")
		if [ "$_count" -eq 0 ]; then
			sw_tr_problem "$_srel" "$_a: in no slice"
		elif [ "$_count" -gt 1 ]; then
			sw_tr_problem "$_srel" "$_a: in more than one slice ($(printf '%s\n' "$_who" | paste -sd, - | sed 's/,/, /g'))"
		fi
	done
}

# sw_trace_tests: every criterion of a review or done slice (in _tr_need) must
# appear in a file under test_paths. Sets _cfg_err when test_paths is unusable.
sw_trace_tests() {
	sw_conf_load "$SOFTWARY_ROOT/$SW_CONF_REL"
	_tp=
	! sw_conf_has test_paths || _tp=$(sw_conf_get test_paths)
	case $_tp in '' | UNSET | NONE*)
		_cfg_err="trace: test_paths is not set in $SW_CONF_REL (needed for slices in review or done)"
		return 0
		;;
	esac
	for _p in $_tp; do
		[ -e "$SOFTWARY_ROOT/$_p" ] || _cfg_err="${_cfg_err:+$_cfg_err
}trace: test_paths: '$_p' not found"
	done
	[ -z "$_cfg_err" ] || return 0
	while read -r _lrel _a; do
		[ -n "$_a" ] || continue
		# shellcheck disable=SC2086 # test_paths is a space-separated list of paths
		_hit=$(cd "$SOFTWARY_ROOT" && find $_tp -type f -exec grep -lE -e "$_a([^0-9]|\$)" {} + 2>/dev/null | head -n 1)
		[ -n "$_hit" ] || sw_tr_problem "$_lrel" "$_a: not found under test_paths ($_tp)"
	done <<NEED
$_tr_need
NEED
}

# sw_trace: checks every spec under specs/. Exit 0 traced, 1 problems,
# 2 test_paths missing when it is needed.
sw_trace() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary trace\n' >&2
		return 2
	fi
	_tr_probs='' _tr_n=0 _tr_specs=0 _tr_slices=0 _tr_criteria=0 _tr_adrs=0 _tr_need='' _cfg_err=''
	_tr_ids=$(sw_model_ids)
	for _dir in "$SOFTWARY_ROOT"/specs/*/; do
		[ -d "$_dir" ] || continue
		_dir=${_dir%/}
		if printf '%s\n' "${_dir##*/}" | grep -Eq '^[0-9]{3}-[a-z0-9][a-z0-9-]*$'; then
			sw_trace_spec "$_dir"
		else
			sw_tr_problem "specs/${_dir##*/}" "directory name must be NNN-name"
		fi
	done
	sw_trace_adrs
	[ -z "$_tr_need" ] || sw_trace_tests

	printf '%s' "$_tr_probs"
	if [ -n "$_cfg_err" ]; then
		printf '%s\n' "$_cfg_err"
		return 2
	fi
	if [ "$_tr_n" -gt 0 ]; then
		printf 'trace: %s problem(s)\n' "$_tr_n"
		return 1
	fi
	printf 'trace: %s spec(s), %s slice(s), %s criteria\n' "$_tr_specs" "$_tr_slices" "$_tr_criteria"
	[ "$_tr_adrs" -eq 0 ] || printf 'trace: %s ADR(s)\n' "$_tr_adrs"
}

# sw_slice_counts DIR: "1 done, 2 planned" for the slices of a spec directory.
sw_slice_counts() {
	for _f in "$1"/slices/*.md; do
		[ -f "$_f" ] || continue
		sw_fm_read "$_f"
		_s=$(sw_fm_get status)
		printf '%s\n' "${_s:-?}"
	done | awk '
		{ n[$0]++ }
		END {
			split("done review in-progress planned", order, " ")
			for (i = 1; i <= 4; i++)
				if (order[i] in n) { out = out sep n[order[i]] " " order[i]; sep = ", "; delete n[order[i]] }
			for (k in n) { out = out sep n[k] " " k; sep = ", " }
			print out
		}'
}

# sw_status: one line per spec and per proposed ADR. Writes nothing.
sw_status() {
	if [ $# -ne 0 ]; then
		printf 'usage: ./softwary status\n' >&2
		return 2
	fi
	_n=0
	for _dir in "$SOFTWARY_ROOT"/specs/*/; do
		_dir=${_dir%/}
		[ -f "$_dir/spec.md" ] || continue
		_n=$((_n + 1))
		_dn=${_dir##*/}
		_counts=$(sw_slice_counts "$_dir")
		sw_fm_read "$_dir/spec.md"
		_note=
		[ -z "$(sw_fm_errors)" ] || _note=" (run ./softwary trace)"
		_id=$(sw_fm_get id)
		_st=$(sw_fm_get status)
		_rk=$(sw_fm_get risk)
		_ti=$(sw_fm_get title)
		printf '%-4s %-11s %-3s %-24s slices: %s%s\n' "${_id:-${_dn%%-*}}" "${_st:-?}" "${_rk:-?}" "${_ti:-?}" \
			"${_counts:-none}" "$_note"
	done
	[ "$_n" -gt 0 ] || printf 'no specs\n'
	for _f in "$SOFTWARY_ROOT"/architecture/decisions/*.md; do
		[ -f "$_f" ] || continue
		sw_fm_read "$_f"
		[ "$(sw_fm_get status)" = proposed ] || continue
		_id=$(sw_fm_get id)
		_b=${_f##*/}
		printf 'ADR %-4s %-9s %s\n' "${_id:-${_b%%-*}}" proposed "$(sw_fm_get title)"
	done
	return 0
}
