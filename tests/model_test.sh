#!/bin/sh
# Tests for ./softwary model validate (M2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# model_edit FILTER: rewrites the repo's model with a jq FILTER.
model_edit() {
	jq "$1" "$REPO/$MODEL_REL" >"$T/model.tmp" || fail "jq filter failed: $1"
	mv "$T/model.tmp" "$REPO/$MODEL_REL"
}

# AC-M2-02: a valid model passes.
test_ac_m2_02_valid_model_passes() {
	setup_repo
	sw model validate
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^model: valid \(3 nodes, 2 relationships\)$"
}

# AC-M2-02: a missing model file is a configuration error.
test_ac_m2_02_missing_model_exits_2() {
	setup_repo --no-model
	sw model validate
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "architecture/model/system.calm.json not found"
	assert_contains "$OUT" ".softwary/templates/system.calm.json"
}

# AC-M2-02: invalid JSON is reported.
test_ac_m2_02_invalid_json() {
	setup_repo
	printf '{ "nodes": [ \n' >"$REPO/$MODEL_REL"
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "invalid JSON"
}

# AC-M2-02: a model without nodes fails.
test_ac_m2_02_no_nodes() {
	setup_repo
	printf '{ "nodes": [], "relationships": [] }\n' >"$REPO/$MODEL_REL"
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes: must be a non-empty array$"
}

# AC-M2-02: every problem is reported on its own line with its JSON path.
test_ac_m2_02_each_problem_on_its_own_line() {
	setup_repo
	model_edit '
		del(.nodes[1].name)
		| .relationships[0]["unique-id"] = "api"
		| .relationships[0]["relationship-type"].interacts.nodes = ["ghost"]
		| .relationships[1]["relationship-type"].connects.destination.interfaces = ["nope"]
		| del(.relationships[1]["unique-id"])'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.name: missing or not a non-empty string$"
	assert_match "$OUT" "^$MODEL_REL: relationships\[0\]\.unique-id: duplicate 'api'$"
	assert_match "$OUT" "^$MODEL_REL: relationships\[0\]\.relationship-type\.interacts\.nodes\[0\]: unknown node 'ghost'$"
	assert_match "$OUT" "^$MODEL_REL: relationships\[1\]\.relationship-type\.connects\.destination\.interfaces\[0\]: unknown interface 'nope' on node 'db'$"
	assert_match "$OUT" "^$MODEL_REL: relationships\[1\]\.unique-id: missing or not a non-empty string$"
	assert_match "$OUT" "^model: 5 problem\(s\)$"
}

# AC-M2-02: a relationship must have exactly one known type.
test_ac_m2_02_relationship_type() {
	setup_repo
	model_edit '.relationships[0]["relationship-type"] = {"likes": {}}'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: relationships\[0\]\.relationship-type: must have exactly one of interacts, connects, deployed-in, composed-of, options$"
}

# AC-M2-02: composed-of and deployed-in references are checked.
test_ac_m2_02_container_references() {
	setup_repo
	model_edit '.relationships += [{"unique-id": "c", "relationship-type": {"composed-of": {"container": "box", "nodes": ["api"]}}}]'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: relationships\[2\]\.relationship-type\.composed-of\.container: unknown node 'box'$"
}

# AC-M2-02: invalid paths, risk and status are reported.
test_ac_m2_02_invalid_softwary_fields() {
	setup_repo
	model_edit '.nodes[1].metadata = {"paths": [], "risk": "R4", "status": "live"}'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.paths: must be a non-empty array of non-empty strings$"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.risk: must be R1, R2 or R3$"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.status: must be planned, active or deprecated$"
}

# AC-M2-02 / principle 4: a value left as UNSET is reported.
test_ac_m2_02_unset_values() {
	setup_repo
	model_edit '.nodes[1].metadata.risk = "UNSET" | .nodes[0].description = "UNSET"'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.risk: is UNSET$"
	assert_match "$OUT" "^$MODEL_REL: nodes\[0\]\.description: is UNSET$"
}

# AC-M2-03: metadata is read both as an object and as an array of objects.
test_ac_m2_03_metadata_object_and_array() {
	setup_repo
	model_edit '.nodes[2].metadata = [{"paths": ["db/*"]}, {"risk": "R9", "status": "active"}]'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes\[2\]\.metadata\.risk: must be R1, R2 or R3$"
	model_edit '.nodes[2].metadata = {"paths": ["db/*"], "risk": "R3", "status": "active"}'
	sw model validate
	assert_eq "$RC" 0 "exit code with object metadata"
	model_edit '.nodes[2].metadata = "nope"'
	sw model validate
	assert_eq "$RC" 1 "exit code with string metadata"
	assert_match "$OUT" "^$MODEL_REL: nodes\[2\]\.metadata: must be an object or an array of objects$"
}

# AC-M2-03: a node with paths must also have risk and status.
test_ac_m2_03_paths_need_risk_and_status() {
	setup_repo
	model_edit '.nodes[1].metadata = {"paths": ["src/api/*"]}'
	sw model validate
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.risk: required when paths is set$"
	assert_match "$OUT" "^$MODEL_REL: nodes\[1\]\.metadata\.status: required when paths is set$"
}

# Usage: unknown subcommand.
test_model_usage() {
	setup_repo
	sw model check
	assert_eq "$RC" 2 "exit code"
}

run_tests "$0"
