#!/bin/sh
# Tests for ADR checks: `trace` (M3) and `adr` (M3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

ADR_DIR=architecture/decisions

# AC-M3-03: a well-formed ADR passes and is counted.
test_ac_m3_03_valid_adr_passes() {
	setup_repo
	conf_all true
	write_adr 0001 accepted architecture/model/system.calm.json
	sw trace
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "1 ADR\(s\)"
}

# AC-M3-03: missing, empty, UNSET and invalid fields are each reported.
test_ac_m3_03_missing_and_invalid_fields() {
	setup_repo
	conf_all true
	mkdir -p "$REPO/$ADR_DIR"
	printf -- '---\nid:\ntitle: UNSET\nstatus: maybe\n---\n\n# x\n' >"$REPO/$ADR_DIR/0001-x.md"
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$ADR_DIR/0001-x\.md: affects: missing$"
	assert_match "$OUT" "^$ADR_DIR/0001-x\.md: id: is empty$"
	assert_match "$OUT" "^$ADR_DIR/0001-x\.md: title: is UNSET$"
	assert_match "$OUT" "^$ADR_DIR/0001-x\.md: status: 'maybe' must be one of proposed, accepted, superseded, rejected$"
}

# AC-M3-03: the id must equal the file name's number; the name must be NNNN-<name>.md.
test_ac_m3_03_id_must_match_file_name() {
	setup_repo
	conf_all true
	write_adr 0002 accepted architecture/model
	sed 's/^id: 0002$/id: 0003/' "$REPO/$ADR_DIR/0002-x.md" >"$T/a" && mv "$T/a" "$REPO/$ADR_DIR/0002-x.md"
	write_adr 0004 accepted architecture/model
	mv "$REPO/$ADR_DIR/0004-x.md" "$REPO/$ADR_DIR/adr.md"
	sw trace
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$ADR_DIR/0002-x\.md: id: '0003' does not match the file name 0002-x\.md$"
	assert_match "$OUT" "^$ADR_DIR/adr\.md: file name must be NNNN-<name>\.md$"
}

# AC-M3-03: every affects entry must be an existing path inside architecture/.
test_ac_m3_03_affects_paths() {
	setup_repo
	conf_all true
	write_adr 0001 accepted "architecture/model, specs/001-login/spec.md, architecture/../specs, /etc/passwd, architecture/, architecture/contracts/nope.yaml"
	sw trace
	assert_eq "$RC" 1 "exit code"
	for e in specs/001-login/spec.md architecture/../specs /etc/passwd architecture/; do
		assert_match "$OUT" "^$ADR_DIR/0001-x\.md: affects: '$e' is outside architecture/$"
	done
	assert_match "$OUT" "^$ADR_DIR/0001-x\.md: affects: 'architecture/contracts/nope\.yaml' not found$"
	assert_no_match "$OUT" "affects: 'architecture/model'"
}

# setup_adr: a repo on main with a committed contract (old.yaml) and a feature
# branch checked out; every command is `true`.
setup_adr() {
	setup_repo
	conf_all true
	mkdir -p "$REPO/architecture/contracts"
	printf 'openapi: 3.0.0\n' >"$REPO/architecture/contracts/old.yaml"
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
	commit_all base
	git -C "$REPO" checkout -qb feature
}

# change_model: edits the model so it differs from main.
change_model() {
	jq '.nodes[0].description = "changed"' "$REPO/$MODEL_REL" >"$T/m" && mv "$T/m" "$REPO/$MODEL_REL"
}

# add_contract: a new, untracked contract file.
add_contract() {
	printf 'openapi: 3.0.0\n' >"$REPO/architecture/contracts/api.yaml"
}

# AC-M3-04: a change that touches neither the model nor contracts needs no ADR.
test_ac_m3_04_no_gated_change_passes() {
	setup_adr
	printf 'x\n' >"$REPO/code.txt"
	sw adr
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "no model or contract changes"
}

# AC-M3-04: a model change needs an accepted ADR in the change covering the model.
test_ac_m3_04_model_change_needs_accepted_adr() {
	setup_adr
	change_model
	sw adr
	assert_eq "$RC" 1 "exit code without an ADR"
	assert_match "$OUT" "^$MODEL_REL: no accepted ADR in this change covers it$"
	write_adr 0001 accepted "$MODEL_REL"
	sw adr
	assert_eq "$RC" 0 "exit code with an accepted ADR"
	assert_match "$OUT" "^$MODEL_REL: covered by ADR 0001$"
}

# AC-M3-04: a proposed ADR does not pass; the output says a human must accept it.
# superseded and rejected ADRs do not cover anything.
test_ac_m3_04_proposed_adr_awaits_human() {
	setup_adr
	change_model
	write_adr 0001 proposed "$MODEL_REL"
	sw adr
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^$MODEL_REL: awaiting human acceptance \(ADR 0001 is proposed\)$"
	for st in superseded rejected; do
		write_adr 0001 $st "$MODEL_REL"
		sw adr
		assert_eq "$RC" 1 "exit code for $st"
		assert_match "$OUT" "no accepted ADR"
	done
}

# AC-M3-04: the ADR must be part of the change, not merely present on the base.
test_ac_m3_04_adr_must_be_in_the_change() {
	setup_repo
	conf_all true
	write_adr 0001 accepted "$MODEL_REL"
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
	commit_all base
	git -C "$REPO" checkout -qb feature
	change_model
	sw adr
	assert_eq "$RC" 1 "exit code"
}

# AC-M3-04: contracts need an ADR whose affects covers them; a directory covers
# its files; a bare architecture/ covers nothing.
test_ac_m3_04_contracts() {
	setup_adr
	add_contract
	sw adr
	assert_eq "$RC" 1 "new contract without an ADR"
	assert_match "$OUT" "^architecture/contracts/api\.yaml: no accepted ADR"
	write_adr 0001 accepted architecture/model
	sw adr
	assert_eq "$RC" 1 "ADR for another path"
	write_adr 0001 accepted architecture/
	sw adr
	assert_eq "$RC" 1 "bare architecture/ covers nothing"
	write_adr 0001 accepted architecture/contracts
	sw adr
	assert_eq "$RC" 0 "directory entry"
	assert_match "$OUT" "^architecture/contracts/api\.yaml: covered by ADR 0001$"
}

# AC-M3-04: a contract moved out of architecture/contracts/ or deleted still
# needs an ADR, and the old path is reported (renames are not collapsed).
test_ac_m3_04_renamed_or_deleted_contract() {
	setup_adr
	mkdir -p "$REPO/docs"
	git -C "$REPO" mv architecture/contracts/old.yaml docs/old.yaml
	sw adr
	assert_eq "$RC" 1 "renamed contract"
	assert_match "$OUT" "^architecture/contracts/old\.yaml: no accepted ADR"
	git -C "$REPO" mv docs/old.yaml architecture/contracts/old.yaml
	rm "$REPO/architecture/contracts/old.yaml"
	sw adr
	assert_eq "$RC" 1 "deleted contract"
	assert_match "$OUT" "^architecture/contracts/old\.yaml: no accepted ADR"
}

# AC-M3-04: a base that cannot be found is a configuration problem (2).
test_ac_m3_04_base_not_found_exits_2() {
	setup_adr
	sw adr --base nope
	assert_eq "$RC" 2 "unknown base"
	assert_match "$OUT" "base 'nope' not found"
	sw adr --base -x
	assert_eq "$RC" 2 "option-like base"
	git -C "$REPO" branch -qm main trunk
	sw adr
	assert_eq "$RC" 2 "no main branch"
	sw adr --base trunk
	assert_eq "$RC" 0 "explicit base"
	sw adr --bogus
	assert_eq "$RC" 2 "unknown option"
}

# AC-M3-04: verify --base appends the adr check after trace; without --base it
# does not run; --fast cannot be combined with --base; a missing base runs nothing.
test_ac_m3_04_verify_base() {
	setup_adr
	add_contract
	sw verify --base main
	assert_eq "$RC" 1 "exit code without an ADR"
	assert_match "$OUT" "^adr +FAIL"
	[ "$(grep -n '^trace ' "$OUT" | cut -d: -f1)" -lt "$(grep -n '^adr ' "$OUT" | cut -d: -f1)" ] || fail "adr must come after trace"
	write_adr 0001 accepted architecture/contracts
	sw verify --base main
	assert_eq "$RC" 0 "exit code with an ADR"
	assert_match "$OUT" "^adr +PASS"
	sw verify
	assert_eq "$RC" 0 "plain verify"
	assert_no_match "$OUT" "^adr "
	sw verify --fast --base main
	assert_eq "$RC" 2 "--fast with --base"
	sw verify --base nope
	assert_eq "$RC" 2 "missing base"
	assert_no_match "$OUT" "PASS"
}

run_tests "$0"
