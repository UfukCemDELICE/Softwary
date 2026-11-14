#!/bin/sh
# Tests for ./softwary risk (M2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# setup_risk: a repo with the sample model and spec committed on main, and a
# feature branch checked out.
setup_risk() {
	setup_repo
	git -C "$REPO" symbolic-ref HEAD refs/heads/main
	conf_all true
	add_specs
	commit_all base
	git -C "$REPO" checkout -qb feature
}

# AC-M2-08: without changes: the spec and its model components decide.
test_ac_m2_08_spec_and_components() {
	setup_risk
	sw risk 001
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^spec +R1 \(specs/001-login/spec\.md\)$"
	assert_match "$OUT" "^paths +none \(no changed paths\)$"
	assert_match "$OUT" "^components +R2 \(api R2\)$"
	assert_eq "$(tail -n 1 "$OUT")" "risk            R2" "last line"
}

# AC-M2-08: committed, uncommitted and untracked changes since --base count;
# components whose paths cover a change are affected.
test_ac_m2_08_changed_paths() {
	setup_risk
	risk_set 'src/auth/*' R3
	mkdir -p "$REPO/src/auth"
	: >"$REPO/src/auth/a.py"
	commit_all feature
	sw risk 001
	assert_match "$OUT" "^paths +R3 \(src/auth/a\.py: src/auth/\*\)$"
	assert_eq "$(tail -n 1 "$OUT")" "risk            R3" "committed change"
	risk_set 'src/auth/*' R1
	commit_all lower
	mkdir -p "$REPO/db"
	: >"$REPO/db/x.sql"
	sw risk 001
	assert_match "$OUT" "^components +R3 \(api R2, db R3\)$"
	assert_eq "$(tail -n 1 "$OUT")" "risk            R3" "untracked change"
	rm "$REPO/db/x.sql"
	risk_set 'tests/*' R2
	printf 'x\n' >>"$REPO/tests/test_login.py"
	sw risk 001
	assert_match "$OUT" "^paths +R2 \(tests/test_login\.py: tests/\*\)$"
}

# AC-M2-08: a path takes the highest matching pattern; default only if none match.
test_ac_m2_08_highest_pattern_and_default() {
	setup_risk
	risk_set default R2
	risk_set 'src/*' R1
	risk_set 'src/pay/*' R3
	risk_set 'src/pay/*.py' R1
	commit_all config
	mkdir -p "$REPO/src/pay"
	: >"$REPO/src/pay/p.py"
	: >"$REPO/src/ok.py"
	sw risk 001 --base feature
	assert_match "$OUT" "^paths +R3 \(src/pay/p\.py: src/pay/\*\)$"
	rm "$REPO/src/pay/p.py"
	sw risk 001 --base feature
	assert_match "$OUT" "^paths +R1 \(src/ok\.py: src/\*\)$"
}

# AC-M2-08: the spec is named by id or by directory; --base selects the base.
test_ac_m2_08_spec_forms_and_base() {
	setup_risk
	: >"$REPO/new.txt"
	commit_all feature
	sw risk specs/001-login
	assert_eq "$RC" 0 "exit code with a directory"
	assert_match "$OUT" "^paths +R1 \(new\.txt: default\)$"
	sw risk 001 --base feature
	assert_eq "$RC" 0 "exit code with --base"
	assert_match "$OUT" "^paths +none \(no changed paths\)$"
}

# AC-M2-08: configuration and argument problems exit 2.
test_ac_m2_08_errors_exit_2() {
	setup_risk
	sw risk 009
	assert_eq "$RC" 2 "unknown spec"
	assert_match "$OUT" "spec '009' not found"
	sw risk 001 --base nope
	assert_eq "$RC" 2 "unknown base"
	assert_match "$OUT" "base 'nope' not found"
	sw risk
	assert_eq "$RC" 2 "no spec"
	risk_set default UNSET
	sw risk 001
	assert_eq "$RC" 2 "UNSET default"
	assert_match "$OUT" "risk\.conf:[0-9]+: 'default' is UNSET"
	risk_set default R1
	risk_set 'src/*' R5
	printf 'garbage\n' >>"$REPO/.softwary/config/risk.conf"
	sw risk 001
	assert_eq "$RC" 2 "bad tier and malformed line"
	assert_match "$OUT" "risk\.conf:[0-9]+: invalid tier 'R5' for 'src/\*'"
	assert_match "$OUT" "risk\.conf:[0-9]+: malformed line"
	printf '# empty\n' >"$REPO/.softwary/config/risk.conf"
	sw risk 001
	assert_eq "$RC" 2 "missing default"
	assert_match "$OUT" "'default' is missing"
}

# AC-M2-08: a spec whose risk is not a tier is a configuration error.
test_ac_m2_08_invalid_spec_risk() {
	setup_risk
	fm_set "$REPO/specs/001-login/spec.md" risk UNSET
	sw risk 001
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "specs/001-login/spec\.md: risk: 'UNSET' must be one of R1, R2, R3"
}

run_tests "$0"
