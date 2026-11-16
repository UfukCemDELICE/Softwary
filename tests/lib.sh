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
	if [ "$_git" -eq 1 ]; then
		git -C "$REPO" init -q || fail "git init failed"
		git -C "$REPO" symbolic-ref HEAD refs/heads/main
	fi
	sh "$PKG_ROOT/install.sh" "$REPO" >"$T/install.out" 2>&1 || fail "install.sh failed: $(cat "$T/install.out")"
	loop_conf
	skip_conf
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

# add_blueprint: replaces the model with the sample one that names product
# features, regenerates its view and adds the sample data model.
add_blueprint() {
	mkdir -p "$REPO/architecture/model" "$REPO/architecture/data"
	cp "$V2FIX/system.calm.json" "$REPO/$MODEL_REL"
	cp "$V2FIX/data-model.json" "$REPO/architecture/data/model.json"
	(cd "$REPO" && ./softwary views) >"$T/views.out" 2>&1 || fail "views failed: $(cat "$T/views.out")"
}

# add_plan: copies the sample plan (an approved spec 001 with two slices and a
# draft spec 002 whose slice depends on 001-S2) into the repo.
add_plan() {
	cp -R "$V2FIX/specs" "$REPO/"
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
# `pr view --json state` prints $T/gh/state or OPEN; `pr checks` exits with the
# code in $T/gh/checks (default 0); `pr merge` exits with the code in
# $T/gh/merge when that file exists, else squash-merges the PR's branch into
# its base in origin (refusing a --match-head-commit that is not the tip).
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
		*) shift ;;
		esac
	done
	printf 'https://github.com/o/r/pull/%s\n' "$n"
	;;
view)
	n=$1
	case "$*" in
	*headRefOid*)
		if [ -f "$T/gh/head" ]; then cat "$T/gh/head"
		else git --git-dir="$T/origin.git" rev-parse "refs/heads/$(cat "$T/gh/branch-$n")"; fi
		;;
	*state*) cat "$T/gh/state" 2>/dev/null || echo OPEN ;;
	esac
	;;
checks)
	exit "$(cat "$T/gh/checks" 2>/dev/null || echo 0)"
	;;
merge)
	n=$1
	shift
	[ ! -f "$T/gh/merge" ] || exit "$(cat "$T/gh/merge")"
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
	sed 's/^\( *run: \)UNSET.*$/\1true/; s/branches: \[UNSET\]/branches: [main]/' "$REPO/.softwary/templates/softwary.yml" >"$REPO/.github/workflows/softwary.yml"
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
