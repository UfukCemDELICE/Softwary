#!/bin/sh
# Tests for ./softwary eval prepare and eval score, and the shipped cases (V3).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

CASES=$PKG_ROOT/src/eval/cases
RECORD=specs/002-tip/reviews/S1.md
JOB=002-S1

# case_count: the number of cases the package ships.
case_count() {
	find "$CASES" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

# kind_of NAME / expect_of NAME: the package's answer for a case.
kind_of() { cat "$CASES/$1/kind"; }

# prepare_cases: setup_repo and a prepared evaluation in $T/ev.
prepare_cases() {
	setup_repo
	sw eval prepare "$T/ev"
	assert_eq "$RC" 0 "eval prepare"
}

# write_record ID DECISION: the reviewer's record of a prepared case.
write_record() {
	mkdir -p "$T/ev/$1/specs/002-tip/reviews"
	printf -- '---\nslice: S1\ndecision: %s\n---\n\n# Review of S1\n' "$2" >"$T/ev/$1/$RECORD"
}

# map_name ID: the package name of a prepared case.
map_name() {
	sed -n "s/^$1 //p" "$REPO/.softwary/state/eval/map"
}

# AC-V3-09: one repository per case, the sample and the installed softwary on
# main, the change on review; nothing in the case says what is expected, and
# the mapping is in the main repository only.
test_ac_v3_09_prepare_layout() {
	setup_repo
	printf 'caught = 1\n' >"$REPO/.softwary/config/eval.conf"
	mkdir -p "$REPO/.softwary/state/eval"
	printf 'old\n' >"$REPO/.softwary/state/eval/map"
	printf 'note\n' >"$REPO/.softwary/state/note"
	sw eval prepare "$T/ev"
	assert_eq "$RC" 0 "eval prepare"
	n=$(case_count)
	assert_eq "$(find "$T/ev" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "$n" "number of case directories"
	assert_eq "$(wc -l <"$REPO/.softwary/state/eval/map" | tr -d ' ')" "$n" "map lines"
	assert_eq "$(cat "$REPO/.softwary/state/eval/dir")" "$(cd "$T/ev" && pwd -P)" "recorded directory"
	i=0
	while [ "$i" -lt "$n" ]; do
		i=$((i + 1))
		id=$(printf 'case-%02d' "$i")
		c=$T/ev/$id
		[ -d "$c/.git" ] || fail "$id is not a git repository"
		git -C "$c" rev-parse -q --verify refs/heads/main >/dev/null || fail "$id has no main"
		git -C "$c" rev-parse -q --verify refs/heads/review >/dev/null || fail "$id has no review"
		[ -f "$c/src/split.sh" ] && [ -x "$c/softwary" ] && [ -f "$c/.softwary/bin/softwary" ] || fail "$id lacks the sample or softwary"
		[ ! -e "$c/.softwary/config/eval.conf" ] && [ ! -e "$c/.softwary/state/note" ] && [ ! -e "$c/.softwary/state/eval" ] || fail "$id carries the evaluation of the main repository"
		[ -z "$(find "$c" -path "$c/.git" -prune -o \( -name expect -o -name kind -o -name diff.patch \) -print)" ] || fail "$id carries the answer"
		assert_eq "$(git -C "$c" log --format=%s main)" "Initial import" "$id main log"
		assert_eq "$(git -C "$c" log --format=%s main..review)" "Implement slice S1" "$id review log"
		assert_eq "$(git -C "$c" branch --show-current)" review "$id checked-out branch"
		(cd "$c" && ./softwary guard $JOB --base main) >/dev/null 2>&1
		[ $? -le 1 ] || fail "$id: guard cannot run in the case"
	done
	# deterministic, and the names do not tell the kind
	cp "$REPO/.softwary/state/eval/map" "$T/map1"
	sw eval prepare "$T/ev2"
	assert_eq "$RC" 0 "second prepare"
	cmp -s "$REPO/.softwary/state/eval/map" "$T/map1" || fail "the order of the cases changed between two prepares"
	assert_no_match "$REPO/.softwary/state/eval/map" "clean|guard|review"
}

# AC-V3-09: a directory that is not empty is refused (2); so is a missing one.
test_ac_v3_09_prepare_needs_an_empty_directory() {
	setup_repo
	mkdir "$T/full"
	touch "$T/full/x"
	sw eval prepare "$T/full"
	assert_eq "$RC" 2 "directory that is not empty"
	[ ! -e "$REPO/.softwary/state/eval/map" ] || fail "a map was written"
	sw eval prepare
	assert_eq "$RC" 2 "no directory"
	sw eval
	assert_eq "$RC" 2 "no subcommand"
	sw eval nonsense x
	assert_eq "$RC" 2 "unknown subcommand"
	sw eval prepare "$T/new/nested"
	assert_eq "$RC" 0 "a directory that does not exist yet is made"
}

# AC-V3-10: at least ten cases, two clean, five that guard catches (each of
# the five kinds), three that only a review can catch; every diff applies;
# guard catches its own kinds and nothing else; the sample's tests pass in
# every case that is not a guard case.
test_ac_v3_10_corpus_shape() {
	clean=0 guard=0 review=0
	for d in "$CASES"/*/; do
		name=${d%/}
		name=${name##*/}
		case $(kind_of "$name") in
		clean) clean=$((clean + 1)); assert_eq "$(cat "$d/expect")" approve "expect of $name" ;;
		guard) guard=$((guard + 1)); assert_eq "$(cat "$d/expect")" changes "expect of $name" ;;
		review) review=$((review + 1)); assert_eq "$(cat "$d/expect")" changes "expect of $name" ;;
		*) fail "unknown kind in $name" ;;
		esac
	done
	[ "$((clean + guard + review))" -ge 10 ] || fail "fewer than ten cases"
	[ "$clean" -ge 2 ] || fail "fewer than two clean cases ($clean)"
	[ "$guard" -ge 5 ] || fail "fewer than five guard cases ($guard)"
	[ "$review" -ge 3 ] || fail "fewer than three review cases ($review)"
	prepare_cases
	: >"$T/kinds"
	while read -r id name; do
		kind=$(kind_of "$name")
		c=$T/ev/$id
		RC=0
		(cd "$c" && ./softwary guard $JOB --base main) >"$T/guard.out" 2>&1 || RC=$?
		OUT=$T/guard.out
		case $kind in
		guard)
			assert_eq "$RC" 1 "guard on $name"
			sed -n 's/^guard: \([a-z ]*\): .*/\1/p' "$T/guard.out" >>"$T/kinds"
			;;
		*)
			assert_eq "$RC" 0 "guard on $name"
			RC=0
			(cd "$c" && sh tests/run.sh) >"$T/sample.out" 2>&1 || RC=$?
			OUT=$T/sample.out
			assert_eq "$RC" 0 "the sample's tests on $name"
			;;
		esac
	done <"$REPO/.softwary/state/eval/map"
	OUT=$T/kinds
	for k in protected "outside touches" "test deleted" "criterion dropped" "skip marker"; do
		assert_match "$T/kinds" "^$k\$"
	done
}

# AC-V3-11: a case with no record or an invalid one is listed; nothing is
# written; 1.
test_ac_v3_11_score_incomplete() {
	prepare_cases
	n=$(case_count)
	i=0
	while [ "$i" -lt "$n" ]; do
		i=$((i + 1))
		write_record "$(printf 'case-%02d' "$i")" approve
	done
	rm "$T/ev/case-02/$RECORD"
	write_record case-03 maybe
	printf -- '---\nslice: S9\ndecision: approve\n---\n' >"$T/ev/case-04/$RECORD"
	sw eval score "$T/ev"
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^case-02: no review record"
	assert_match "$OUT" "^case-03: the review record is invalid"
	assert_match "$OUT" "^case-04: the review record is invalid"
	assert_no_match "$OUT" "^case-01:"
	[ ! -e "$REPO/.softwary/config/eval.conf" ] || fail "eval.conf was written"
}

# AC-V3-11: guard catches count without the reviewer; a broken case counts as
# caught when its record says changes; a clean case with changes is a false
# alarm; eval.conf has the counts, the reviewer's digest and the date.
test_ac_v3_11_score_writes_conf() {
	prepare_cases
	broken=0 clean=0 missed_one=0
	while read -r id name; do
		case $(kind_of "$name") in
		clean)
			clean=$((clean + 1))
			if [ "$clean" -eq 1 ]; then write_record "$id" changes; else write_record "$id" approve; fi
			;;
		guard)
			broken=$((broken + 1))
			write_record "$id" approve
			;;
		review)
			broken=$((broken + 1))
			if [ "$missed_one" -eq 0 ]; then
				missed_one=1
				write_record "$id" approve
			else
				write_record "$id" changes
			fi
			;;
		esac
	done <"$REPO/.softwary/state/eval/map"
	sw eval score "$T/ev"
	assert_eq "$RC" 0 "exit code"
	conf=$REPO/.softwary/config/eval.conf
	assert_eq "$(sed -n 's/^broken = //p' "$conf")" "$broken" "broken"
	assert_eq "$(sed -n 's/^caught = //p' "$conf")" "$((broken - 1))" "caught: guard cases without a reviewer, one review case missed"
	assert_eq "$(sed -n 's/^clean = //p' "$conf")" "$clean" "clean"
	assert_eq "$(sed -n 's/^false_alarms = //p' "$conf")" 1 "false alarms"
	assert_match "$conf" "^digest = [0-9a-f]{40,64}$"
	assert_match "$conf" "^date = [0-9]{4}-[0-9]{2}-[0-9]{2}$"
	assert_match "$OUT" "caught $((broken - 1)) of $broken"
	before=$(sed -n 's/^digest = //p' "$conf")
	printf '\nA new instruction.\n' >>"$REPO/.softwary/agents/reviewer.md"
	sw eval score "$T/ev"
	assert_eq "$RC" 0 "exit code after the reviewer changed"
	[ "$(sed -n 's/^digest = //p' "$conf")" != "$before" ] || fail "the digest ignores the reviewer's agent file"
	before=$(sed -n 's/^digest = //p' "$conf")
	sed 's/^reviewer = .*/reviewer = haiku/' "$REPO/.softwary/config/models.conf" >"$T/m" && cp "$T/m" "$REPO/.softwary/config/models.conf"
	sw eval score "$T/ev"
	[ "$(sed -n 's/^digest = //p' "$conf")" != "$before" ] || fail "the digest ignores the reviewer's model"
}

# AC-V3-11: the case's own softwary runs guard; the main repository's root
# does not leak into it.
test_ac_v3_11_score_uses_the_cases_own_guard() {
	prepare_cases
	while read -r id _name; do
		write_record "$id" approve
	done <"$REPO/.softwary/state/eval/map"
	conf_del test_paths
	sw eval score "$T/ev"
	assert_eq "$RC" 0 "exit code with the main repository's test_paths unset"
	assert_match "$OUT" "caught [0-9]+ of"
}

# AC-V3-11: score wants a prepared evaluation and the directory it made.
test_ac_v3_11_score_needs_prepare() {
	setup_repo
	mkdir "$T/ev"
	sw eval score "$T/ev"
	assert_eq "$RC" 2 "nothing prepared"
	sw eval prepare "$T/prepared"
	sw eval score "$T/ev"
	assert_eq "$RC" 2 "another directory"
	sw eval score "$T/missing"
	assert_eq "$RC" 2 "no such directory"
	sw eval score
	assert_eq "$RC" 2 "no directory"
}

# make_pkg DIR VERSION: a copy of the package with the given version.
make_pkg() {
	mkdir -p "$1"
	cp -R "$PKG_ROOT/install.sh" "$PKG_ROOT/VERSION" "$PKG_ROOT/src" "$1/"
	printf '%s\n' "$2" >"$1/VERSION"
}

# AC-V3-10: install puts the sample and the cases under .softwary/eval; upgrade
# replaces them and removes what the new version no longer ships.
test_ac_v3_10_install_and_upgrade_ship_eval() {
	setup_repo
	first=$(find "$CASES" -mindepth 1 -maxdepth 1 -type d | sort | sed -n 1p)
	name=${first##*/}
	[ -f "$REPO/.softwary/eval/cases/$name/diff.patch" ] || fail "cases are not installed"
	[ -f "$REPO/.softwary/eval/sample/.softwary-config/commands.conf" ] || fail "the sample is not installed"
	[ -f "$REPO/.softwary/eval/sample/tests/run.sh" ] || fail "the sample's tests are not installed"
	make_pkg "$T/pkg" 0.1.0
	rm -r "$T/pkg/src/eval/cases/$name"
	printf '# changed\n' >>"$T/pkg/src/eval/sample/CONTEXT.md"
	sw upgrade "$T/pkg"
	assert_eq "$RC" 0 "upgrade exit code"
	[ ! -e "$REPO/.softwary/eval/cases/$name" ] || fail "a case the new version lacks was kept"
	assert_contains "$REPO/.softwary/eval/sample/CONTEXT.md" "# changed"
	sw sync --check
	assert_eq "$RC" 0 "sync --check after the upgrade"
}

run_tests "$0"
