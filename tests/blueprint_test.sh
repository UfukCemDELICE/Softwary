#!/bin/sh
# Tests for ./softwary blueprint check (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

DATA_REL=architecture/data/model.json

# data_edit FILTER: rewrites the repo's data model with a jq FILTER.
data_edit() {
	jq "$1" "$REPO/$DATA_REL" >"$T/data.tmp" || fail "jq filter failed: $1"
	mv "$T/data.tmp" "$REPO/$DATA_REL"
}

# model_edit FILTER: rewrites the repo's model with a jq FILTER.
model_edit() {
	jq "$1" "$REPO/$MODEL_REL" >"$T/model.tmp" || fail "jq filter failed: $1"
	mv "$T/model.tmp" "$REPO/$MODEL_REL"
}

# ready: a repo with a product and a blueprint that both pass.
ready() {
	setup_repo
	add_product
	add_blueprint
}

# AC-V2-02: each missing input is a configuration error, named on its own line.
test_ac_v2_02_missing_inputs_exit_2() {
	ready
	rm "$REPO/product/PRODUCT.md"
	sw blueprint check
	assert_eq "$RC" 2 "exit code without the product"
	assert_match "$OUT" "^blueprint: product/PRODUCT.md not found"
	add_product
	rm "$REPO/$MODEL_REL"
	sw blueprint check
	assert_eq "$RC" 2 "exit code without the model"
	assert_match "$OUT" "^blueprint: architecture/model/system.calm.json not found"
	add_blueprint
	rm "$REPO/$DATA_REL"
	sw blueprint check
	assert_eq "$RC" 2 "exit code without the data model"
	assert_match "$OUT" "^blueprint: architecture/data/model.json not found"
	assert_contains "$OUT" ".softwary/templates/data-model.json"
}

# AC-V2-02: a complete blueprint passes.
test_ac_v2_02_valid_blueprint_passes() {
	ready
	sw blueprint check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^blueprint: valid \(3 nodes, 2 entities, 2 features\)$"
}

# AC-V2-02: model validation problems are listed.
test_ac_v2_02_model_problems_listed() {
	ready
	model_edit '.nodes[1]["unique-id"] = ""'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/model/system.calm.json: nodes\[1\]\.unique-id: missing or not a non-empty string$"
}

# AC-V2-02: a failing product check is one line; the rest is still checked.
test_ac_v2_02_failing_product_is_one_line() {
	ready
	sed 's/^## Problem$//' "$REPO/product/PRODUCT.md" >"$T/p" && mv "$T/p" "$REPO/product/PRODUCT.md"
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: product check fails$"
	assert_no_match "$OUT" "missing section"
}

# AC-V2-02: every data model problem is a separate line.
test_ac_v2_02_data_model_problems() {
	ready
	data_edit '.entities += [.entities[0]]
		| .entities[1].fields += [{"name": "id", "type": "uuid"}, {"name": "note"}]
		| .entities[1].relations = [{"to": "ghost", "kind": "one-to-many"}, {"to": "user", "kind": "sideways"}]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/data/model.json: entities\[2\]\.id: duplicate 'user'$"
	assert_match "$OUT" "^architecture/data/model.json: entities\[1\]\.fields\[2\]\.name: duplicate field 'id'$"
	assert_match "$OUT" "^architecture/data/model.json: entities\[1\]\.fields\[3\]\.type: missing or not a non-empty string$"
	assert_match "$OUT" "^architecture/data/model.json: entities\[1\]\.relations\[0\]\.to: unknown entity 'ghost'$"
	assert_match "$OUT" "^architecture/data/model.json: entities\[1\]\.relations\[1\]\.kind: must be one of"
}

# AC-V2-02: an invalid id, invalid JSON and the template's UNSET are reported.
test_ac_v2_02_data_model_shape() {
	ready
	data_edit '.entities[0].id = "User One"'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^architecture/data/model.json: entities\[0\]\.id: must match"
	printf '{ "entities": [ \n' >"$REPO/$DATA_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with invalid JSON"
	assert_match "$OUT" "^architecture/data/model.json: invalid JSON"
	cp "$REPO/.softwary/templates/data-model.json" "$REPO/$DATA_REL"
	sw blueprint check
	assert_eq "$RC" 1 "exit code with the template"
	assert_match "$OUT" "^architecture/data/model.json: entities\[0\]\.name: is UNSET$"
}

# AC-V2-02: a feature no node delivers and a node naming an unknown feature
# are separate lines; model validate rejects a malformed features list.
test_ac_v2_02_feature_coverage() {
	ready
	model_edit '.nodes[2].metadata[1].features = ["F1"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: feature F2 is not delivered by any component$"
	model_edit '.nodes[1].metadata.features = ["F1", "F9"]'
	sw blueprint check
	assert_eq "$RC" 1 "exit code with an unknown feature"
	assert_match "$OUT" "^architecture/model/system.calm.json: component 'api' names feature F9, which is not in the product$"
	model_edit '.nodes[1].metadata.features = ["x"]'
	sw model validate
	assert_eq "$RC" 1 "model validate exit code"
	assert_match "$OUT" "nodes\[1\]\.metadata\.features: must be a non-empty array of feature ids"
	model_edit '.nodes[1].metadata.features = []'
	sw model validate
	assert_eq "$RC" 1 "model validate exit code with an empty list"
}

run_tests "$0"
