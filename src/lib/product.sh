# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: `product check`, `blueprint check`, approvals. Sourced by
# bin/softwary. POSIX sh.
#
# The product definition is product/PRODUCT.md; the blueprint is the CALM
# model, the data model architecture/data/model.json and the contracts.

SW_PRODUCT_REL=product/PRODUCT.md
SW_DATA_REL=architecture/data/model.json
SW_PRODUCT_MISSING="$SW_PRODUCT_REL not found; start from .softwary/templates/PRODUCT.md"
SW_DATA_MISSING="$SW_DATA_REL not found; start from .softwary/templates/data-model.json"

# sw_product_check: prints one "<file>: <problem>" line per problem. Returns
# 0 valid, 1 problems, 2 no PRODUCT.md.
sw_product_check() {
	_pf=$SOFTWARY_ROOT/$SW_PRODUCT_REL
	[ -f "$_pf" ] || return 2
	_pout=$(awk -v P="$SW_PRODUCT_REL: " -v Q="'" '
		function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
		BEGIN {
			nreq = split("Problem|Users|Scope|Out of scope|Features|Non-functional requirements|Constraints|Success metrics|Open questions", req, "|")
		}
		{
			sub(/\r$/, "")
			line = $0
			if (line ~ /UNSET/) print P "line " NR ": UNSET"
			if (incomment) {
				if ((j = index(line, "-->")) > 0) { line = substr(line, j + 3); incomment = 0 } else line = ""
			}
			while ((i = index(line, "<!--")) > 0) {
				rest = substr(line, i + 4)
				if ((j = index(rest, "-->")) > 0) line = substr(line, 1, i - 1) substr(rest, j + 3)
				else { line = substr(line, 1, i - 1); incomment = 1 }
			}
			if (line ~ /^## /) {
				sec = trim(substr(line, 4)); seen[sec] = 1; cur = ""
				next
			}
			if (line ~ /^### / && sec == "Features") {
				h = substr(line, 5); k = index(h, ":")
				id = (k > 0) ? trim(substr(h, 1, k - 1)) : ""
				if (id !~ /^F[1-9][0-9]*$/ || trim(substr(h, k + 1)) == "") {
					print P "line " NR ": feature heading must be " Q "### F<n>: <name>" Q
					cur = ""
				} else if (id in feat) {
					print P "line " NR ": duplicate feature " id
					cur = ""
				} else { feat[id] = 1; order[++nfeat] = id; cur = id }
				next
			}
			if (line ~ /^[ \t]*[-*+][ \t]+\*\*EX-F[0-9][0-9]*-[0-9][0-9]:\*\*/) {
				match(line, /EX-F[0-9][0-9]*-[0-9][0-9]/)
				eid = substr(line, RSTART, RLENGTH)
				split(eid, b, "-"); fn = b[2]
				if (cur == "") print P "line " NR ": example " eid " is not under a feature"
				else if (fn != cur) print P "line " NR ": example " eid " is under feature " cur " (its id must start with EX-" cur "-)"
				else good[cur]++
				if (eid in ids) print P "line " NR ": duplicate example id " eid
				else { ids[eid] = 1; nex++ }
				next
			}
			if (sec == "Open questions" && line ~ /^[ \t]*([-*+]|[0-9]+\.)[ \t]/) {
				q = line; sub(/^[ \t]*([-*+]|[0-9]+\.)[ \t]+/, "", q)
				print P "line " NR ": open question: " trim(q)
			}
		}
		END {
			for (i = 1; i <= nreq; i++)
				if (!(req[i] in seen)) print P "missing section " Q "## " req[i] Q
			if (("Features" in seen) && nfeat == 0) print P "no feature (" Q "### F<n>: <name>" Q ") under " Q "## Features" Q
			for (i = 1; i <= nfeat; i++)
				if (!(order[i] in good)) print P order[i] ": feature has no example (" Q "- **EX-" order[i] "-NN:** ..." Q ")"
		}' "$_pf")
	[ -n "$_pout" ] || return 0
	printf '%s\n' "$_pout"
	return 1
}

# sw_product_features / sw_product_examples: the feature ids (F1) and the
# example ids (EX-F1-01) defined in PRODUCT.md, sorted, one per line.
sw_product_features() {
	[ -f "$SOFTWARY_ROOT/$SW_PRODUCT_REL" ] || return 0
	tr -d '\r' <"$SOFTWARY_ROOT/$SW_PRODUCT_REL" | sed -n 's/^### \(F[1-9][0-9]*\):.*/\1/p' | sort -u
}

sw_product_examples() {
	[ -f "$SOFTWARY_ROOT/$SW_PRODUCT_REL" ] || return 0
	tr -d '\r' <"$SOFTWARY_ROOT/$SW_PRODUCT_REL" |
		sed -n 's/^[[:space:]]*[-*+][[:space:]][[:space:]]*\*\*\(EX-F[1-9][0-9]*-[0-9][0-9]\):\*\*.*/\1/p' | sort -u
}

# sw_product [check]
sw_product() {
	if [ $# -ne 1 ] || [ "$1" != check ]; then
		printf 'usage: ./softwary product check\n' >&2
		return 2
	fi
	_rc=0
	_probs=$(sw_product_check) || _rc=$?
	case $_rc in
	0)
		printf 'product: valid (%s features, %s examples)\n' "$(sw_count "$(sw_product_features)")" "$(sw_count "$(sw_product_examples)")"
		return 0
		;;
	2)
		printf 'product: %s\n' "$SW_PRODUCT_MISSING"
		return 2
		;;
	esac
	printf '%s\n' "$_probs"
	printf 'product: %s problem(s)\n' "$(printf '%s\n' "$_probs" | wc -l | tr -d ' ')"
	return 1
}

# sw_data_check: prints one "<file>: <path>: <problem>" line per problem.
# Returns 0 valid, 1 problems, 2 no data model.
sw_data_check() {
	_df=$SOFTWARY_ROOT/$SW_DATA_REL
	[ -f "$_df" ] || return 2
	if ! _derr=$(jq empty "$_df" 2>&1); then
		printf '%s: invalid JSON: %s\n' "$SW_DATA_REL" "$(printf '%s\n' "$_derr" | head -n 1)"
		return 1
	fi
	_dout=$(jq -r -f "$SOFTWARY_HOME/lib/data.jq" "$_df") || {
		printf '%s: could not be checked (jq failed)\n' "$SW_DATA_REL"
		return 1
	}
	[ -n "$_dout" ] || return 0
	printf '%s\n' "$_dout" | sed "s|^|$SW_DATA_REL: |"
	return 1
}

# sw_model_features: prints "<node id> <feature>" for every feature the
# model's components name (nothing when the model cannot be read).
sw_model_features() {
	[ -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ] || return 0
	jq -r '.nodes[]? | objects | ."unique-id" as $id
		| (.metadata | if type == "object" then . elif type == "array" then (map(objects) | add // {}) else {} end)
		| (.features // []) | if type == "array" then .[] | strings else empty end
		| "\($id) \(.)"' "$SOFTWARY_ROOT/$SW_MODEL_REL" 2>/dev/null
}

# sw_blueprint_check: prints one problem per line. Returns 0 valid,
# 1 problems, 2 an input is missing (each missing input has its own line).
sw_blueprint_check() {
	_bmiss=0
	if [ ! -f "$SOFTWARY_ROOT/$SW_PRODUCT_REL" ]; then
		printf 'blueprint: %s\n' "$SW_PRODUCT_MISSING"
		_bmiss=1
	fi
	if [ ! -f "$SOFTWARY_ROOT/$SW_MODEL_REL" ]; then
		printf 'blueprint: %s\n' "$SW_MODEL_MISSING"
		_bmiss=1
	fi
	if [ ! -f "$SOFTWARY_ROOT/$SW_DATA_REL" ]; then
		printf 'blueprint: %s\n' "$SW_DATA_MISSING"
		_bmiss=1
	fi
	[ "$_bmiss" -eq 0 ] || return 2
	_bn=0
	_bp=$(sw_product_check) || _bp=fail
	if [ "$_bp" = fail ]; then
		printf '%s: product check fails\n' "$SW_PRODUCT_REL"
		_bn=$((_bn + 1))
	fi
	_bm=$(sw_model_check) || _bn=$((_bn + $(sw_count "$_bm")))
	[ -z "$_bm" ] || printf '%s\n' "$_bm"
	_bd=$(sw_data_check) || _bn=$((_bn + $(sw_count "$_bd")))
	[ -z "$_bd" ] || printf '%s\n' "$_bd"
	if [ "$_bp" != fail ]; then
		_bfeat=$(sw_product_features)
		_bnode=$(sw_model_features)
		for _bf in $_bfeat; do
			printf '%s\n' "$_bnode" | awk -v f="$_bf" '$2 == f { found = 1 } END { exit !found }' && continue
			printf '%s: feature %s is not delivered by any component\n' "$SW_PRODUCT_REL" "$_bf"
			_bn=$((_bn + 1))
		done
		_bref=$(printf '%s\n' "$_bnode" | while read -r _bid _bf; do
			[ -n "$_bf" ] || continue
			printf '%s\n' "$_bf" | grep -Eq '^F[1-9][0-9]*$' || continue
			printf '%s\n' "$_bfeat" | grep -Fqx -e "$_bf" ||
				printf "%s: component '%s' names feature %s, which is not in the product\n" "$SW_MODEL_REL" "$_bid" "$_bf"
		done)
		if [ -n "$_bref" ]; then
			printf '%s\n' "$_bref"
			_bn=$((_bn + $(sw_count "$_bref")))
		fi
	fi
	[ "$_bn" -eq 0 ]
}

# sw_blueprint [check]
sw_blueprint() {
	if [ $# -ne 1 ] || [ "$1" != check ]; then
		printf 'usage: ./softwary blueprint check\n' >&2
		return 2
	fi
	_rc=0
	_probs=$(sw_blueprint_check) || _rc=$?
	case $_rc in
	0)
		printf 'blueprint: valid (%s nodes, %s entities, %s features)\n' \
			"$(jq '.nodes | length' "$SOFTWARY_ROOT/$SW_MODEL_REL")" \
			"$(jq '.entities | length' "$SOFTWARY_ROOT/$SW_DATA_REL")" "$(sw_count "$(sw_product_features)")"
		return 0
		;;
	2)
		printf '%s\n' "$_probs"
		return 2
		;;
	esac
	printf '%s\n' "$_probs"
	printf 'blueprint: %s problem(s)\n' "$(sw_count "$_probs")"
	return 1
}
