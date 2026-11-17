# shellcheck shell=sh
# shellcheck disable=SC2034 # SW_* globals are read by the other libs
# softwary: the flow and state machine files of the blueprint (V5). Sourced
# by bin/softwary. POSIX sh.
#
# architecture/flows/<id>.json describes how components work together for a
# product feature; architecture/states/<entity>.json is the state machine of
# a stateful entity. lib/flows.jq and lib/states.jq hold the checks; the
# formal specifications they name are checked in formal.sh.

SW_FLOWS_DIR=architecture/flows
SW_STATES_DIR=architecture/states

# sw_ids_json KIND: the ids of the model's components (nodes) or of the data
# model's entities as a JSON array; [] when the file cannot be read.
sw_ids_json() {
	case $1 in
	nodes) jq -c '[.nodes[]? | objects | ."unique-id" | strings]' "$SOFTWARY_ROOT/$SW_MODEL_REL" 2>/dev/null || printf '[]\n' ;;
	entities) jq -c '[.entities[]? | objects | .id | strings]' "$SOFTWARY_ROOT/$SW_DATA_REL" 2>/dev/null || printf '[]\n' ;;
	esac
}

# sw_json_files DIR: the .json files of DIR (repo-relative), one per line.
sw_json_files() {
	for _jf in "$SOFTWARY_ROOT/$1"/*.json; do
		[ -f "$_jf" ] || continue
		printf '%s/%s\n' "$1" "${_jf##*/}"
	done
}

# sw_flows_check: prints one "<file>: <problem>" line per problem of the flow
# files and of the rule that a feature several components deliver has a flow.
# Returns 0 clean, 1 problems.
sw_flows_check() {
	_fl_out=
	_fl_nodes=$(sw_ids_json nodes)
	_fl_ents=$(sw_ids_json entities)
	_fl_list=$(sw_product_features | tr '\n' ' ')
	_fl_feats=$(printf '%s\n' "$_fl_list" | tr ' ' '\n' | jq -R . | jq -sc 'map(select(length > 0))')
	_fl_have=
	for _fl_rel in $(sw_json_files "$SW_FLOWS_DIR"); do
		_fl_f=$SOFTWARY_ROOT/$_fl_rel
		_fl_id=${_fl_rel##*/}
		_fl_id=${_fl_id%.json}
		if ! _fl_err=$(jq empty "$_fl_f" 2>&1); then
			_fl_out="${_fl_out}$_fl_rel: invalid JSON: $(printf '%s\n' "$_fl_err" | head -n 1)
"
			continue
		fi
		_fl_p=$(jq -r --arg id "$_fl_id" --argjson nodes "$_fl_nodes" --argjson entities "$_fl_ents" --argjson features "$_fl_feats" \
			-f "$SOFTWARY_HOME/lib/flows.jq" "$_fl_f") || _fl_p="(root): could not be checked (jq failed)"
		[ -z "$_fl_p" ] || _fl_out="${_fl_out}$(printf '%s\n' "$_fl_p" | sed "s|^|$_fl_rel: |")
"
		_fl_have="$_fl_have $(jq -r '.features? | if type == "array" then .[] | strings else empty end' "$_fl_f" 2>/dev/null | paste -sd' ' -)"
	done
	# A feature that two or more components deliver crosses a boundary: a flow
	# has to say how.
	_fl_pairs=$(sw_model_features)
	for _fl_ft in $(printf '%s\n' "$_fl_pairs" | awk 'NF == 2 { print $2 }' | sort -u); do
		sw_in_list "$_fl_ft" "$_fl_list" || continue
		_fl_who=$(printf '%s\n' "$_fl_pairs" | awk -v f="$_fl_ft" '$2 == f { printf "%s%s", sep, $1; sep = ", " }')
		_fl_n=$(printf '%s\n' "$_fl_pairs" | awk -v f="$_fl_ft" '$2 == f { n++ } END { print n + 0 }')
		[ "$_fl_n" -ge 2 ] || continue
		sw_in_list "$_fl_ft" "$_fl_have" && continue
		_fl_out="${_fl_out}$SW_FLOWS_DIR: feature $_fl_ft is delivered by $_fl_n components ($_fl_who) and no flow carries it
"
	done
	[ -z "$_fl_out" ] || printf '%s' "$_fl_out"
	[ -z "$_fl_out" ]
}

# sw_states_check: prints one "<file>: <problem>" line per problem of the
# state machine files. Returns 0 clean, 1 problems.
sw_states_check() {
	_st_out=
	_st_ents=$(sw_ids_json entities)
	for _st_rel in $(sw_json_files "$SW_STATES_DIR"); do
		_st_f=$SOFTWARY_ROOT/$_st_rel
		_st_id=${_st_rel##*/}
		_st_id=${_st_id%.json}
		if ! _st_err=$(jq empty "$_st_f" 2>&1); then
			_st_out="${_st_out}$_st_rel: invalid JSON: $(printf '%s\n' "$_st_err" | head -n 1)
"
			continue
		fi
		_st_p=$(jq -r --arg id "$_st_id" --argjson entities "$_st_ents" -f "$SOFTWARY_HOME/lib/states.jq" "$_st_f") ||
			_st_p="(root): could not be checked (jq failed)"
		[ -z "$_st_p" ] || _st_out="${_st_out}$(printf '%s\n' "$_st_p" | sed "s|^|$_st_rel: |")
"
	done
	[ -z "$_st_out" ] || printf '%s' "$_st_out"
	[ -z "$_st_out" ]
}
