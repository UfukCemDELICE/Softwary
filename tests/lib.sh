# shellcheck shell=sh
# shellcheck disable=SC2034 # T, OUT, RC, REPO are read by the *_test.sh files
# Shared helpers for softwary tests. Sourced by every *_test.sh file.
#
# Each test is a function named test_<something>() and runs in its own
# subshell with a fresh temporary directory $T. $OUT holds the captured
# output of the last `sw` call and $RC its exit code.

PKG_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
REQUIRED_KEYS="format_check lint typecheck test build security"
T=
OUT=
RC=
REPO=

fail() {
	printf '    assertion failed: %s\n' "$*"
	if [ -n "$OUT" ] && [ -f "$OUT" ]; then
		printf '    --- last output ---\n'
		sed 's/^/    | /' "$OUT"
	fi
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "${3:-value}: expected [$2], got [$1]"
}

# assert_match FILE ERE
assert_match() {
	grep -E -e "$2" "$1" >/dev/null || fail "no line matches /$2/ in ${1##*/}"
}

# assert_no_match FILE ERE
assert_no_match() {
	! grep -E -e "$2" "$1" >/dev/null || fail "unexpected line matches /$2/ in ${1##*/}"
}

# assert_contains FILE TEXT
assert_contains() {
	grep -F -e "$2" "$1" >/dev/null || fail "${1##*/} does not contain [$2]"
}

# setup_repo [--no-git] [--no-sync] [--no-model]: creates $T/repo, initialises
# git and installs softwary. Unless --no-sync is given, every tool is set to
# off, ./softwary sync runs, risk.conf gets a default and, unless --no-model is
# given, the sample model and its view are added: the repo starts complete.
setup_repo() {
	_git=1
	_sync=1
	_model=1
	for _a in "$@"; do
		case $_a in
		--no-git) _git=0 ;;
		--no-sync) _sync=0 ;;
		--no-model) _model=0 ;;
		*) fail "setup_repo: unknown option $_a" ;;
		esac
	done
	REPO=$T/repo
	mkdir -p "$REPO/src"
	: >"$REPO/src/.gitkeep"
	if [ "$_git" -eq 1 ]; then
		git -C "$REPO" init -q || fail "git init failed"
		git -C "$REPO" symbolic-ref HEAD refs/heads/main
	fi
	sh "$PKG_ROOT/install.sh" "$REPO" >"$T/install.out" 2>&1 || fail "install.sh failed: $(cat "$T/install.out")"
	loop_conf
	skip_conf
	add_bootstrap
	if [ "$_sync" -eq 1 ]; then
		tools_all off
		(cd "$REPO" && ./softwary sync) >"$T/sync.out" 2>&1 || fail "sync failed: $(cat "$T/sync.out")"
		risk_set default R1
		add_ci
		[ "$_model" -eq 0 ] || add_model
	fi
}

FIXTURES=$PKG_ROOT/tests/fixtures/artifacts
MODEL_REL=architecture/model/system.calm.json

# add_model: copies the sample model into the repo and generates its view.
add_model() {
	mkdir -p "$REPO/architecture/model"
	cp "$FIXTURES/system.calm.json" "$REPO/$MODEL_REL"
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

V2FIX=$FIXTURES/v2

# add_bootstrap: the loop needs a bootstrap command; tests need nothing run.
add_bootstrap() {
	file_set "$REPO/.softwary/config/commands.conf" bootstrap "NONE: tests"
}

# job_wt JOB: the worktree of a job (the main checkout stays on the integration
# branch; the job's files are here).
job_wt() {
	printf '%s/.softwary/worktrees/%s\n' "$REPO" "$1"
}
LOOP_CONF_REL=.softwary/config/loop.conf

# loop_conf: writes the default loop limits, with the token keys filled in
# (the installed template leaves them UNSET). loop_set KEY VALUE changes one.
loop_conf() {
	mkdir -p "$REPO/.softwary/config"
	cat >"$REPO/$LOOP_CONF_REL" <<'LOOP'
max_rounds = 3
max_job_minutes = 45
max_run_minutes = 240
concurrency = 1
max_job_tokens = NONE: tests do not count tokens
max_run_tokens = NONE: tests do not count tokens
min_catch_percent = 90
LOOP
}

# add_eval [CAUGHT BROKEN]: writes a valid eval.conf for the repo's reviewer
# (the digest is the one `eval score` computes: the reviewer's agent files and
# model). The default is a perfect score, 10 of 10.
add_eval() {
	_ev_f=$REPO/.softwary/config/eval.conf
	mkdir -p "$REPO/.softwary/config"
	{
		printf 'caught = %s\n' "${1:-10}"
		printf 'broken = %s\n' "${2:-10}"
		printf 'false_alarms = 0\nclean = 2\n'
		printf 'digest = %s\n' "$(eval_digest)"
		printf 'date = 2026-11-16\n'
	} >"$_ev_f"
}

# eval_digest: the digest of the reviewer, computed the way eval score does.
eval_digest() {
	{
		for _f in .softwary/agents/reviewer.md .softwary/local/agents/reviewer.md; do
			[ -f "$REPO/$_f" ] || continue
			printf '%s %s\n' "$(git -C "$REPO" hash-object -- "$_f")" "$_f"
		done
		printf 'model %s\n' "$(sed -n 's/^reviewer = //p' "$REPO/.softwary/config/models.conf")"
	} | git -C "$REPO" hash-object --stdin
}

loop_set() {
	file_set "$REPO/$LOOP_CONF_REL" "$1" "$2"
}

# skip_conf: writes a test-skip.conf with two patterns (V3).
skip_conf() {
	mkdir -p "$REPO/.softwary/config"
	cat >"$REPO/.softwary/config/test-skip.conf" <<'SKIP'
\.skip\(
\.only\(
SKIP
}

# add_product: copies the sample product definition into the repo.
add_product() {
	mkdir -p "$REPO/product"
	cp "$V2FIX/PRODUCT.md" "$REPO/product/PRODUCT.md"
}

# core_model PATHS STATUS [EXTRA]: replaces the model with an actor and one
# component, `core`, that owns PATHS (a JSON array) and has STATUS; EXTRA is one
# more node (a JSON object). The view is generated.
core_model() {
	mkdir -p "$REPO/architecture/model"
	cat >"$REPO/$MODEL_REL" <<MODEL
{
  "\$schema": "https://calm.finos.org/release/1.3/meta/calm.json",
  "nodes": [
    { "unique-id": "user", "node-type": "actor", "name": "User", "description": "Uses the product." },
    { "unique-id": "core", "node-type": "service", "name": "Core", "description": "The code.",
      "metadata": { "paths": $1, "risk": "R1", "status": "$2" } }${3:+,
    $3}
  ],
  "relationships": [
    { "unique-id": "user-uses-core", "relationship-type": { "interacts": { "actor": "user", "nodes": ["core"] } } }
  ]
}
MODEL
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

# add_production [REF]: the production branch, master, at REF (default: the
# first commit of main), pushed to origin when there is one.
add_production() {
	_ap=${1:-$(git -C "$REPO" rev-list --max-parents=0 main | tail -n 1)}
	git -C "$REPO" branch -f master "$_ap" || fail "add_production: cannot make master at $_ap"
	if git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
		git -C "$REPO" push -q --no-verify -f origin master >"$T/push.out" 2>&1 || fail "push of master failed: $(cat "$T/push.out")"
		git -C "$REPO" fetch -q origin
	fi
}

# add_repro_slice [PATHS]: slice S1 of the sample plan becomes the fix of a bug:
# repro: PATHS (default tests/test_bug.sh), touches src/api and tests, the
# command that runs given tests (test_files = sh {files}) and a src/api/calc.sh
# whose add is wrong. Committed on the integration branch.
# shellcheck disable=SC2016 # the shell code in the printf formats is not for this shell
add_repro_slice() {
	conf_set test_paths tests
	conf_set test_files 'sh {files}'
	_sl=$REPO/specs/001-login/slices/S1.md
	fm_set "$_sl" touches "src/api, tests"
	fm_set "$_sl" repro "${1:-tests/test_bug.sh}"
	mkdir -p "$REPO/src/api"
	printf 'add() { echo $(($1 - $2)); }\n' >"$REPO/src/api/calc.sh"
	commit_all "a bug and the slice that fixes it"
}

# repro_commit DIR [nofix]: what the job commits in DIR (its worktree, or a
# checkout of its branch): the slice in review, the test that reproduces the
# bug (adding 2 and 3 gives 5) and, unless nofix, the fix.
# shellcheck disable=SC2016 # the shell code in the printf formats is not for this shell
repro_commit() {
	fm_set "$1/specs/001-login/slices/S1.md" status review
	mkdir -p "$1/tests"
	printf '#!/bin/sh\n# covers AC-001-01: adding 2 and 3 gives 5\n. "$(dirname "$0")/../src/api/calc.sh"\n[ "$(add 2 3)" = 5 ]\n' >"$1/tests/test_bug.sh"
	[ "${2-}" = nofix ] || printf 'add() { echo $(($1 + $2)); }\n' >"$1/src/api/calc.sh"
	commit_in "$1" "fix the sum"
}

# add_blueprint: replaces the model with the sample one that names product
# features, regenerates its view and adds the sample data model and the flow
# that F1 (delivered by two components) needs.
add_blueprint() {
	mkdir -p "$REPO/architecture/model" "$REPO/architecture/data" "$REPO/architecture/flows"
	cp "$V2FIX/system.calm.json" "$REPO/$MODEL_REL"
	cp "$V2FIX/data-model.json" "$REPO/architecture/data/model.json"
	cp "$V2FIX/flows/signin.json" "$REPO/architecture/flows/signin.json"
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

FORMALFIX=$PKG_ROOT/tests/fixtures/formal

# add_formal: adds the sample state machine of the order, its TLA+ model with
# two invariants and a variant for each (tests/fixtures/formal), and the order
# entity to the data model, and generates the views. Call it after add_blueprint.
add_formal() {
	mkdir -p "$REPO/architecture"
	cp -R "$FORMALFIX/architecture/." "$REPO/architecture/"
	jq '.entities += [{"id": "order", "name": "Order", "fields": [{"name": "id", "type": "uuid", "required": true}, {"name": "status", "type": "string"}]}]' \
		"$REPO/architecture/data/model.json" >"$T/data.tmp" || fail "jq failed adding the order entity"
	mv "$T/data.tmp" "$REPO/architecture/data/model.json"
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

# need_tlc: TLC can be run (Java and the pinned jar), else the test fails. With
# SW_SKIP_FORMAL=<reason> set the test is skipped, visibly: use it as
# `need_tlc || return 0`.
need_tlc() {
	if [ -n "${SW_SKIP_FORMAL:-}" ]; then
		printf 'SKIP (%s)\n' "$SW_SKIP_FORMAL"
		return 1
	fi
	sh "$PKG_ROOT/tests/tlc.sh" --check >"$OUT" 2>&1 || fail "TLC is not available (set SW_SKIP_FORMAL=<reason> to skip)"
}

EXISTINGFIX=$PKG_ROOT/tests/fixtures/existing

# add_existing: the example existing repository (tests/fixtures/existing): a
# small shop's order scripts, its tests and checks, README.md and AGENTS.md,
# as the project's own commit. Its lint and one of its tests are red. Call it
# after setup_repo; existing_conf sets its commands.
add_existing() {
	for _e in README.md AGENTS.md app checks tests; do
		cp -R "$EXISTINGFIX/$_e" "$REPO/" || fail "add_existing: cannot copy $_e"
	done
	commit_all "the existing shop"
}

# existing_conf: commands.conf of the existing repository: its own scripts,
# the branches, the source and the test directories.
existing_conf() {
	write_conf <<'CONF'
format_check = NONE: plain scripts have no formatter
lint = sh checks/lint.sh
typecheck = for f in app/*.sh; do sh -n "$f" || exit 1; done
test = sh checks/test.sh
build = NONE: nothing to build
security = NONE: no dependencies
model_check = ./softwary formal check
src_paths = app
test_paths = tests
integration_branch = main
production_branch = master
bootstrap = NONE: nothing to install
CONF
}

# add_existing_artifacts: what define, blueprint and plan write for the
# existing repository: the product definition, the model, the data model, the
# state machine of the order with its TLA+ record (which has a finding), the
# ADR, and a draft spec with one slice; the views are generated.
add_existing_artifacts() {
	for _e in product architecture specs; do
		cp -R "$EXISTINGFIX/$_e" "$REPO/" || fail "add_existing_artifacts: cannot copy $_e"
	done
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

CRITIQUE_REL=architecture/critique.md

# add_critique [DECISION]: the blueprint critic's record for the blueprint as
# it is now (decision pass unless DECISION says otherwise).
add_critique() {
	_cq=$(cd "$REPO" && ./softwary blueprint digest) || fail "blueprint digest failed"
	mkdir -p "$REPO/architecture"
	printf -- '---\ndigest: %s\ndecision: %s\n---\n\n# Critique\n' "$_cq" "${1:-pass}" >"$REPO/$CRITIQUE_REL"
}

# approve_blueprint: a passing critique of the current blueprint, then
# `approve blueprint` (sets RC and OUT like sw).
approve_blueprint() {
	add_critique
	sw approve blueprint
}

# add_plan: copies the sample plan (an approved spec 001 with two slices and a
# draft spec 002 whose slice depends on 001-S2) into the repo.
add_plan() {
	cp -R "$V2FIX/specs" "$REPO/"
}

# add_parallel_plan: the sample plan with three slices of spec 001 that can run
# together: S1 (src/a, tests/a) and S2 (src/b, tests/b) cross nothing; S3
# (src/a/deep, tests/c) crosses S1. None depends on another. Spec 002 is gone.
add_parallel_plan() {
	add_plan
	rm -r "$REPO/specs/002-tasks"
	_sl=$REPO/specs/001-login/slices
	fm_set "$_sl/S1.md" touches "src/a, tests/a"
	fm_set "$_sl/S2.md" touches "src/b, tests/b"
	fm_set "$_sl/S2.md" depends_on ""
	cp "$_sl/S1.md" "$_sl/S3.md"
	fm_set "$_sl/S3.md" id S3
	fm_set "$_sl/S3.md" acs AC-001-03
	sed -i.bak 's/^\(- \*\*AC-001-02:\*\* .*\)$/\1\
- **AC-001-03:** Signing in twice is harmless. Covers EX-F1-01./' "$REPO/specs/001-login/spec.md" && rm -f "$REPO/specs/001-login/spec.md.bak"
	fm_set "$_sl/S3.md" touches "src/a/deep, tests/c"
}

# implement_job JOB: what the implementer does in the job's worktree: the slice
# in progress, a test that names the slice's criterion and code, both under the
# slice's touches (its first two entries), the slice in review, one commit.
implement_job() {
	_wt=$(job_wt "$1")
	_s=${1#*-}
	_sf=$_wt/specs/${1%%-*}-login/slices/$_s.md
	_touches=$(sed -n 's/^touches: *//p' "$_sf")
	_src=$(printf '%s' "$_touches" | cut -d, -f1 | tr -d ' ')
	_tst=$(printf '%s' "$_touches" | cut -d, -f2 | tr -d ' ')
	fm_set "$_sf" status in-progress
	mkdir -p "$_wt/$_src" "$_wt/$_tst"
	printf '# covers %s\n' "$(sed -n 's/^acs: *//p' "$_sf")" >"$_wt/$_tst/test_$_s.py"
	printf 'code %s\n' "$_s" >"$_wt/$_src/code_$_s.py"
	fm_set "$_sf" status review
	git -C "$_wt" add -A
	git -C "$_wt" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "implement $_s"
}

# review_job JOB [DECISION]: the reviewer's record in the job's worktree.
review_job() {
	_wt=$(job_wt "$1")
	mkdir -p "$_wt/specs/${1%%-*}-login/reviews"
	printf -- '---\nslice: %s\ndecision: %s\n---\n\n# Review of %s\n' "${1#*-}" "${2:-approve}" "${1#*-}" \
		>"$_wt/specs/${1%%-*}-login/reviews/${1#*-}.md"
}

# write_decision JOB DECISION: the approver's decision file.
write_decision() {
	printf -- '---\ndecision: %s\n---\n\nReady.\n' "$2" >"$REPO/.softwary/state/jobs/$1/decision.md"
}

# approve_job JOB: start, implement and take the job through the gate, the PR,
# CI and the review to the approver's decision to merge.
approve_job() {
	sw job start "$1"
	[ "$RC" -eq 0 ] || fail "job start $1"
	implement_job "$1"
	sw job event "$1" implemented
	for _step in gate pr ci; do
		sw job "$_step" "$1"
		[ "$RC" -eq 0 ] || fail "job $_step $1"
	done
	review_job "$1"
	sw job review "$1"
	[ "$RC" -eq 0 ] || fail "job review $1"
	write_decision "$1" merge
}

# add_origin: commits what the repo has, creates the bare repository
# $T/origin.git as its `origin` and pushes main (setting origin/main).
add_origin() {
	git -C "$REPO" config user.name t
	git -C "$REPO" config user.email t@example.com
	[ -z "$(git -C "$REPO" status --porcelain)" ] || commit_all "base"
	git init -q --bare "$T/origin.git" || fail "git init --bare failed"
	git -C "$T/origin.git" symbolic-ref HEAD refs/heads/main
	git -C "$REPO" remote add origin "$T/origin.git"
	git -C "$REPO" push -q --no-verify origin main >"$T/push.out" 2>&1 || fail "push to origin failed: $(cat "$T/push.out")"
	git -C "$REPO" fetch -q origin
}

# open_run: opens a run the way `run start` does, without its checks.
open_run() {
	mkdir -p "$REPO/.softwary/state"
	printf 'started=%s\ntokens=0\n' "$(date +%s)" >"$REPO/.softwary/state/run"
}

# fake_gh: puts a fake `gh` first in PATH. It logs every call to $T/gh.log and
# works against the repository $T/origin.git: `pr create` prints
# https://github.com/o/r/pull/<n> (n = 1, 2, ...) and records the PR's title,
# base and head branch under $T/gh/; `pr view --json headRefOid` prints
# $T/gh/head when that file exists, else the tip of the PR's branch in origin;
# `pr view --json state` prints $T/gh/state-<n> (else $T/gh/state) or OPEN;
# `pr create` also keeps the body ($T/gh/body-<n>, from --body or --body-file) and
# `pr list --base B --head H --state open --json ...` prints the open PRs of
# that base and head as a JSON array of {number, url}; `pr checks` exits with the
# code in $T/gh/checks (default 0); `pr merge` exits with the code in
# $T/gh/merge when that file exists, else squash-merges the PR's branch into
# its base in origin (refusing a --match-head-commit that is not the tip) and
# marks the PR MERGED. Every merge call logs "start <n>" and "end <n>" to
# $T/gh/merge-log; $T/gh/pre-merge (a script) runs first, $T/gh/merge-sleep
# (seconds) delays, and $T/gh/merge-then-die kills the caller after the merge.
fake_gh() {
	mkdir -p "$T/bin" "$T/gh"
	cat >"$T/bin/gh" <<'GH'
#!/bin/sh
T=@T@
printf '%s\n' "$*" >>"$T/gh.log"
[ "$1" = pr ] || exit 0
sub=$2
shift 2
case $sub in
create)
	n=$(cat "$T/gh/next" 2>/dev/null || echo 1)
	echo $((n + 1)) >"$T/gh/next"
	while [ $# -gt 0 ]; do
		case $1 in
		--title) printf '%s\n' "$2" >"$T/gh/pr-$n"; shift 2 ;;
		--base) printf '%s\n' "$2" >"$T/gh/base-$n"; shift 2 ;;
		--head) printf '%s\n' "$2" >"$T/gh/branch-$n"; shift 2 ;;
		--body) printf '%s\n' "$2" >"$T/gh/body-$n"; shift 2 ;;
		--body-file) cp "$2" "$T/gh/body-$n"; shift 2 ;;
		*) shift ;;
		esac
	done
	printf 'https://github.com/o/r/pull/%s\n' "$n"
	;;
list)
	base= head=
	while [ $# -gt 0 ]; do
		case $1 in
		--base) base=$2; shift 2 ;;
		--head) head=$2; shift 2 ;;
		*) shift ;;
		esac
	done
	out=
	n=1
	while [ -f "$T/gh/pr-$n" ]; do
		st=$(cat "$T/gh/state-$n" 2>/dev/null || cat "$T/gh/state" 2>/dev/null || echo OPEN)
		if [ "$(cat "$T/gh/base-$n")" = "$base" ] && [ "$(cat "$T/gh/branch-$n")" = "$head" ] && [ "$st" = OPEN ]; then
			out="${out:+$out,}{\"number\":$n,\"url\":\"https://github.com/o/r/pull/$n\"}"
		fi
		n=$((n + 1))
	done
	printf '[%s]\n' "$out"
	;;
view)
	n=$1
	case "$*" in
	*headRefOid*)
		if [ -f "$T/gh/head" ]; then cat "$T/gh/head"
		else git --git-dir="$T/origin.git" rev-parse "refs/heads/$(cat "$T/gh/branch-$n")"; fi
		;;
	*state*) cat "$T/gh/state-$n" 2>/dev/null || cat "$T/gh/state" 2>/dev/null || echo OPEN ;;
	esac
	;;
checks)
	exit "$(cat "$T/gh/checks" 2>/dev/null || echo 0)"
	;;
merge)
	n=$1
	shift
	echo "start $n" >>"$T/gh/merge-log"
	[ ! -f "$T/gh/pre-merge" ] || sh "$T/gh/pre-merge"
	[ ! -f "$T/gh/merge-sleep" ] || sleep "$(cat "$T/gh/merge-sleep")"
	if [ -f "$T/gh/merge" ]; then
		echo "end $n" >>"$T/gh/merge-log"
		exit "$(cat "$T/gh/merge")"
	fi
	br=$(cat "$T/gh/branch-$n")
	base=$(cat "$T/gh/base-$n")
	tip=$(git --git-dir="$T/origin.git" rev-parse "refs/heads/$br")
	while [ $# -gt 0 ]; do
		case $1 in
		--match-head-commit) [ "$2" = "$tip" ] || exit 1; shift 2 ;;
		*) shift ;;
		esac
	done
	w=$(mktemp -d) || exit 1
	git clone -q "$T/origin.git" "$w/c" || exit 1
	cd "$w/c" || exit 1
	git config user.name gh
	git config user.email gh@example.com
	git checkout -q "$base" || exit 1
	git merge -q --squash "origin/$br" >/dev/null 2>&1 || exit 1
	git commit -q -m "squash $br" || exit 1
	git push -q origin "$base" >/dev/null 2>&1 || exit 1
	rm -rf "$w"
	echo MERGED >"$T/gh/state-$n"
	echo "end $n" >>"$T/gh/merge-log"
	[ ! -f "$T/gh/merge-then-die" ] || kill -9 "$PPID"
	;;
esac
GH
	sed -i.bak "s|@T@|$T|" "$T/bin/gh" && rm -f "$T/bin/gh.bak"
	chmod +x "$T/bin/gh"
	: >"$T/gh.log"
	PATH=$T/bin:$PATH
	export PATH
}

# add_specs: copies the sample specs and tests into the repo and points
# test_paths at the tests. Call it after conf_all, which rewrites commands.conf.
add_specs() {
	cp -R "$FIXTURES/specs" "$FIXTURES/tests" "$REPO/"
	conf_set test_paths tests
}

# add_ci: fills in the CI workflow and CODEOWNERS templates under .github/.
add_ci() {
	mkdir -p "$REPO/.github/workflows"
	sed 's/^\( *run: \)UNSET.*$/\1true/; s/branches: \[UNSET, UNSET\]/branches: [main, master]/; s/branches: \[UNSET\]/branches: [main]/' "$REPO/.softwary/templates/softwary.yml" >"$REPO/.github/workflows/softwary.yml"
	sed 's/UNSET/@owner/' "$REPO/.softwary/templates/CODEOWNERS" >"$REPO/.github/CODEOWNERS"
}

# risk_set PATTERN TIER: sets PATTERN in risk.conf.
risk_set() {
	file_set "$REPO/.softwary/config/risk.conf" "$1" "$2"
}

# fm_set FILE KEY VALUE: sets KEY in FILE's front matter (an empty VALUE
# keeps the key with no value). fm_del FILE KEY removes it.
fm_set() {
	awk -v k="$2" -v v="$3" '
		NR == 1 { print; next }
		!closed && $0 == "---" { if (!done) print k ": " v; closed = 1; print; next }
		!closed && index($0, k ":") == 1 { print k ": " v; done = 1; next }
		{ print }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
	sed 's/: $/:/' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

fm_del() {
	awk -v k="$2" 'NR == 1 || closed || index($0, k ":") != 1 { print } NR > 1 && $0 == "---" { closed = 1 }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# write_conf: replaces the repo's commands.conf with stdin.
write_conf() {
	cat >"$REPO/.softwary/config/commands.conf"
}

# conf_all VALUE: every required key gets VALUE ("%k" is replaced by the key);
# src_paths points at src/, which setup_repo creates; the integration branch
# is main (setup_repo starts on it) and the production branch master.
conf_all() {
	{
		for _k in $REQUIRED_KEYS; do
			printf '%s = %s\n' "$_k" "$(printf '%s' "$1" | sed "s/%k/$_k/g")"
		done
		printf 'src_paths = src\n'
		printf 'integration_branch = main\n'
		printf 'production_branch = master\n'
		printf 'bootstrap = NONE: tests\n'
	} | write_conf
}

# file_set FILE KEY VALUE: replaces KEY's line in FILE, or appends it.
file_set() {
	awk -v k="$2" -v v="$3" '
		$1 == k && $2 == "=" { print k " = " v; done = 1; next }
		{ print }
		END { if (!done) print k " = " v }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

# conf_set KEY VALUE: sets KEY in commands.conf.
conf_set() {
	file_set "$REPO/.softwary/config/commands.conf" "$1" "$2"
}

# conf_del KEY: removes KEY's line from commands.conf.
conf_del() {
	_c=$REPO/.softwary/config/commands.conf
	awk -v k="$1" '!($1 == k && $2 == "=")' "$_c" >"$_c.tmp" && mv "$_c.tmp" "$_c"
}

TOOLS="claude-code codex cursor"

# tools_set TOOL VALUE: sets TOOL in tools.conf.
tools_set() {
	file_set "$REPO/.softwary/config/tools.conf" "$1" "$2"
}

# tools_all VALUE: sets every tool to VALUE.
tools_all() {
	for _t in $TOOLS; do
		tools_set "$_t" "$1"
	done
}

# add_sources: copies the sample skills and agents into the repo's .softwary/.
add_sources() {
	cp -R "$PKG_ROOT/tests/fixtures/sources/skills" "$PKG_ROOT/tests/fixtures/sources/agents" "$REPO/.softwary/"
}

# snapshot: prints "cksum size path" for every file in the repo except .git.
snapshot() {
	(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | while IFS= read -r _f; do
		printf '%s %s\n' "$(cksum <"$_f")" "$_f"
	done)
}

# changed_paths BEFORE AFTER: paths whose snapshot lines differ.
changed_paths() {
	diff "$1" "$2" | sed -n 's/^[<>] [0-9]* [0-9]* \.\///p' | sort -u
}

# block_of FILE: prints the lines between the softwary markers.
block_of() {
	awk '/^<!-- softwary:end -->$/ { on = 0 } on { print } /^<!-- softwary:begin/ { on = 1 }' "$1"
}

# outside_block FILE: prints the lines outside the softwary block.
outside_block() {
	awk '/^<!-- softwary:begin/ { on = 1 } !on { print } /^<!-- softwary:end -->$/ { on = 0 }' "$1"
}

# commit_all MESSAGE: commits every file in the repo. --no-verify: the repo's
# git hooks are installed and would run verify; only hooks_test.sh wants that.
commit_all() {
	git -C "$REPO" add -A || fail "git add failed"
	git -C "$REPO" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "$1" || fail "commit failed"
}

# commit_in DIR MESSAGE: commits every file in DIR (a job's worktree).
commit_in() {
	git -C "$1" add -A || fail "git add failed"
	git -C "$1" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "$2" || fail "commit failed"
}

# write_adr ID STATUS AFFECTS: writes architecture/decisions/ID-x.md.
write_adr() {
	mkdir -p "$REPO/architecture/decisions"
	printf -- '---\nid: %s\ntitle: Decision %s\nstatus: %s\naffects: %s\n---\n\n# %s\n' "$1" "$1" "$2" "$3" "$1" \
		>"$REPO/architecture/decisions/$1-x.md"
}

# sw ARGS...: runs ./softwary ARGS in the repo, capturing output and exit code.
sw() {
	RC=0
	(cd "$REPO" && ./softwary "$@") >"$OUT" 2>&1 || RC=$?
}

# path_without TOOL: prints a directory usable as PATH that has every
# executable from the current PATH except TOOL.
path_without() {
	_d=$T/path-without-$1
	mkdir -p "$_d"
	_old_ifs=$IFS
	IFS=:
	# shellcheck disable=SC2086 # split PATH on ':' on purpose
	set -- "$1" $PATH
	IFS=$_old_ifs
	_tool=$1
	shift
	for _p in "$@"; do
		[ -d "$_p" ] || continue
		for _f in "$_p"/*; do
			_n=${_f##*/}
			[ "$_n" = "$_tool" ] && continue
			[ -x "$_f" ] && [ ! -e "$_d/$_n" ] && ln -s "$_f" "$_d/$_n"
		done
	done
	printf '%s\n' "$_d"
}

# run_tests FILE: runs every test_* function defined in FILE.
run_tests() {
	_failed=0
	_count=0
	# shellcheck disable=SC2013 # test function names contain no whitespace
	for _t in $(sed -n 's/^\(test_[a-z0-9_]*\)() {$/\1/p' "$1"); do
		# SW_TEST_ONLY=<name> runs that one test (the mutation checks use it).
		[ -z "${SW_TEST_ONLY:-}" ] || [ "$_t" = "$SW_TEST_ONLY" ] || continue
		_count=$((_count + 1))
		T=$(mktemp -d "${TMPDIR:-/tmp}/softwary-test.XXXXXX") || exit 1
		OUT=$T/out
		if ("$_t"); then
			printf 'ok    %s\n' "$_t"
		else
			printf 'FAIL  %s\n' "$_t"
			_failed=$((_failed + 1))
		fi
		rm -rf "$T"
	done
	[ "$_count" -gt 0 ] || { printf 'no tests found in %s\n' "$1"; return 1; }
	[ "$_failed" -eq 0 ]
}
