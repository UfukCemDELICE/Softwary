#!/bin/sh
# Tests for the flow files of ./softwary blueprint check (V5).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

FLOW_REL=architecture/flows/signin.json
P=architecture/flows/signin.json

# ready: a repo with a product and a blueprint (with its one flow) that pass.
ready() {
	setup_repo
	add_product
	add_blueprint
}

# flow_edit FILTER: rewrites the repo's flow with a jq FILTER.
flow_edit() {
	jq "$1" "$REPO/$FLOW_REL" >"$T/flow.tmp" || fail "jq filter failed: $1"
	mv "$T/flow.tmp" "$REPO/$FLOW_REL"
}

# AC-V5-01: a valid flow passes and is counted.
test_ac_v5_01_valid_flow_passes() {
	ready
	sw blueprint check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^blueprint: valid \(3 nodes, 2 entities, 2 features\)$"
	assert_match "$OUT" "^blueprint: 1 flow\(s\)"
}

# AC-V5-01: invalid JSON and a flow that is not an object.
test_ac_v5_01_json_shape() {
	ready
	printf '{ "id": \n' >"$REPO/$FLOW_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with invalid JSON"
	assert_match "$OUT" "^$P: invalid JSON"
	printf '[1]\n' >"$REPO/$FLOW_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with an array"
	assert_match "$OUT" "^$P: \(root\): must be a JSON object$"
}

# AC-V5-01: every required field is its own line; the id must be the file name.
test_ac_v5_01_required_fields() {
	ready
	flow_edit 'del(.name, .features, .participants, .steps) | .id = "other"'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: id: 'other' must be the file name 'signin'$"
	assert_match "$OUT" "^$P: name: missing or not a non-empty string$"
	assert_match "$OUT" "^$P: features: must be a non-empty array of feature ids"
	assert_match "$OUT" "^$P: participants: must be a non-empty array of component ids$"
	assert_match "$OUT" "^$P: steps: must be a non-empty array$"
	flow_edit '.id = "Bad Id"'
	sw blueprint check
	assert_match "$OUT" "^$P: id: must match \^\[a-z\]\[a-z0-9-\]\*"
}

# AC-V5-01: references to a component, an entity or a feature that does not exist.
test_ac_v5_01_unknown_references() {
	ready
	flow_edit '.participants += ["ghost"] | .entities += ["phantom"] | .features += ["F9"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: participants\[3\]: unknown component 'ghost'$"
	assert_match "$OUT" "^$P: entities\[1\]: unknown entity 'phantom'$"
	assert_match "$OUT" "^$P: features\[1\]: feature F9 is not in the product$"
}

# AC-V5-01: a step end that is not a participant, and a step without an action.
test_ac_v5_01_step_ends() {
	ready
	flow_edit '.participants = ["user", "api"] | .steps[1].action = ""'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: steps\[1\]\.to: 'db' is not a participant of this flow$"
	assert_match "$OUT" "^$P: steps\[2\]\.from: 'db' is not a participant of this flow$"
	assert_match "$OUT" "^$P: steps\[1\]\.action: missing or not a non-empty string$"
	assert_no_match "$OUT" "steps\[0\]"
}

# AC-V5-01: an unknown trait; a trait without a formal field; a valid pair.
test_ac_v5_01_traits_and_formal() {
	ready
	flow_edit '.traits = ["concurrency", "teleport"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: traits\[1\]: unknown trait 'teleport' \(use concurrency, retry, crash\)$"
	assert_match "$OUT" "^$P: formal: missing; a flow with traits needs a formal specification$"
	flow_edit '.traits = ["retry"] | .formal = "signin"'
	sw blueprint check
	assert_no_match "$OUT" "traits\["
	assert_no_match "$OUT" "formal: missing"
}

# AC-V5-01: a feature that two components deliver needs a flow that carries it;
# a feature of one component does not.
test_ac_v5_01_feature_needs_a_flow() {
	ready
	rm "$REPO/$FLOW_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/flows: feature F1 is delivered by 2 components \(api, db\) and no flow carries it$"
	assert_no_match "$OUT" "feature F2"
	flow_edit_new
	sw blueprint check
	assert_eq "$RC" 0 "exit code with the flow back"
}

flow_edit_new() {
	mkdir -p "$REPO/architecture/flows"
	cp "$V2FIX/flows/signin.json" "$REPO/$FLOW_REL"
}

# AC-V5-01: a flow that carries another feature does not satisfy F1; a file
# that is not .json is ignored.
test_ac_v5_01_flow_must_carry_the_feature() {
	ready
	flow_edit '.features = ["F2"]'
	printf 'notes\n' >"$REPO/architecture/flows/README.md"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/flows: feature F1 is delivered by 2 components"
	assert_no_match "$OUT" "README"
}

# AC-V5-01: the template's UNSET is reported, and the template is installed.
test_ac_v5_01_template() {
	ready
	[ -f "$REPO/.softwary/templates/flow.json" ] || fail "flow.json template is not installed"
	cp "$REPO/.softwary/templates/flow.json" "$REPO/architecture/flows/signin.json"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$P: .*is UNSET$"
}

run_tests "$0"
