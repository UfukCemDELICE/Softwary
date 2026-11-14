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

run_tests "$0"
