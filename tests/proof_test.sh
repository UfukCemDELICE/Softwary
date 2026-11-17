#!/bin/sh
# Tests for proof_check (V8): the command that checks the Lean proofs of
# architecture/proofs/, optional like model_check, required as soon as a proof
# is there.
# shellcheck disable=SC2329,SC2119,SC2016 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

REQUIRED='required: architecture/proofs has proofs'

# proof_repo: a repo whose checks all pass; no proof yet.
proof_repo() {
	setup_repo
	conf_all true
}

# add_proof: a proof file under architecture/proofs/.
add_proof() {
	mkdir -p "$REPO/architecture/proofs"
	printf 'theorem t : True := trivial\n' >"$REPO/architecture/proofs/sum.lean"
}

# AC-V8-10: without a proof and without the key, verify has nothing to say
# about proofs and doctor stays quiet.
test_ac_v8_10_no_proof_no_key() {
	proof_repo
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_no_match "$OUT" "proof_check"
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_no_match "$OUT" "proof_check"
}

# AC-V8-10: a proof and no command (missing, UNSET or NONE) fails both, with
# the reason, as model_check does for a specification.
test_ac_v8_10_proof_needs_the_command() {
	proof_repo
	add_proof
	sw verify
	assert_eq "$RC" 1 "verify exit code without the key"
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code without the key"
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
	conf_set proof_check UNSET
	sw verify
	assert_eq "$RC" 1 "verify exit code with UNSET"
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
	conf_set proof_check "NONE: not now"
	sw verify
	assert_eq "$RC" 1 "verify exit code with NONE"
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
	sw doctor
	assert_eq "$RC" 2 "doctor exit code with NONE"
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
}

# AC-V8-10: a proof that is tracked counts, wherever the working tree stands.
test_ac_v8_10_a_tracked_proof_counts() {
	proof_repo
	add_proof
	commit_all "a proof"
	rm "$REPO/architecture/proofs/sum.lean"
	sw verify
	assert_match "$OUT" "^proof_check +FAIL \\($REQUIRED\\)$"
	git -C "$REPO" rm -q --cached architecture/proofs/sum.lean
	commit_all "no proof"
	sw verify
	assert_no_match "$OUT" "proof_check"
}

# AC-V8-10: the command is run when it is set, and its exit code decides.
test_ac_v8_10_command_runs() {
	proof_repo
	add_proof
	conf_set proof_check 'test -f architecture/proofs/sum.lean'
	sw verify
	assert_eq "$RC" 0 "verify exit code"
	assert_match "$OUT" "^proof_check +PASS "
	sw doctor
	assert_eq "$RC" 0 "doctor exit code"
	assert_match "$OUT" "^proof_check +PASS \\(configured, not run\\)$"
	conf_set proof_check 'echo the proof does not check; exit 3'
	sw verify
	assert_eq "$RC" 1 "verify exit code with a failing command"
	assert_match "$OUT" "^proof_check +FAIL "
	assert_contains "$OUT" "the proof does not check"
	[ -s "$REPO/.softwary/state/logs/verify-proof_check.log" ] || fail "no log"
}

# AC-V8-10: a command without a proof is still run (it is configured); NONE
# without a proof is a skip with its reason; --fast runs neither.
test_ac_v8_10_command_without_a_proof_and_fast() {
	proof_repo
	conf_set proof_check 'true'
	sw verify
	assert_match "$OUT" "^proof_check +PASS "
	conf_set proof_check "NONE: no proofs yet"
	sw verify
	assert_eq "$RC" 0 "verify exit code with NONE and no proof"
	assert_match "$OUT" "^proof_check +SKIP \\(no proofs yet\\)$"
	conf_set proof_check 'exit 1'
	sw verify --fast
	assert_eq "$RC" 0 "verify --fast exit code"
	assert_no_match "$OUT" "proof_check"
}

# AC-V8-10: it is not waivable and has no scoped command: the key
# proof_check_files, and a waiver for proof_check, are not known.
test_ac_v8_10_no_waiver_and_no_scoped_command() {
	proof_repo
	add_proof
	conf_set proof_check true
	conf_set proof_check_files 'true {files}'
	sw doctor
	assert_eq "$RC" 2 "doctor exit code"
	assert_match "$OUT" "^proof_check_files +FAIL \\(unknown key, line [0-9]+\\)$"
	assert_no_match "$OUT" "^proof_check +FAIL"
	sw verify
	assert_eq "$RC" 2 "verify exit code"
	assert_match "$OUT" "^UNKNOWN +proof_check_files "
	conf_del proof_check_files
	printf 'proof_check = 2999-12-31: not yet\n' >"$REPO/.softwary/config/waivers.conf"
	sw verify
	assert_eq "$RC" 2 "verify exit code with a waiver"
	assert_contains "$OUT" "unknown key 'proof_check'"
}

# AC-V8-10: the commands template names the key, as a comment.
test_ac_v8_10_template() {
	assert_contains "$PKG_ROOT/src/templates/commands.conf" "# proof_check = <command that checks architecture/proofs/>"
}

run_tests "$0"
