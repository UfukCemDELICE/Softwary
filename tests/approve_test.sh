#!/bin/sh
# Tests for ./softwary approve and the approval lines of status (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

APPROVALS_REL=.softwary/config/approvals.conf
EVENTS_REL=.softwary/state/events.log

# ready: a repo with a product and a blueprint that both pass their checks.
ready() {
	setup_repo
	add_product
	add_blueprint
}

# digest_of KIND: the digest recorded for KIND in approvals.conf.
digest_of() {
	sed -n "s/^$1 = //p" "$REPO/$APPROVALS_REL"
}

# state_is KIND STATE: status reports STATE for KIND's approval.
state_is() {
	sw status
	assert_eq "$RC" 0 "status exit code"
	assert_match "$OUT" "^approval $1: $2$"
}

# AC-V2-03: approving the product records its digest and an event.
test_ac_v2_03_approve_product_writes_digest() {
	ready
	sw approve product
	assert_eq "$RC" 0 "exit code"
	assert_match "$REPO/$APPROVALS_REL" "^product = [0-9a-f]{40,64}$"
	assert_no_match "$REPO/$APPROVALS_REL" "^blueprint"
	assert_eq "$(wc -l <"$REPO/$EVENTS_REL" | tr -d ' ')" 1 "event lines"
	assert_eq "$(jq -r .event "$REPO/$EVENTS_REL")" approve_product "event"
	assert_eq "$(jq -r .job "$REPO/$EVENTS_REL")" - "job"
	assert_eq "$(jq -r .detail "$REPO/$EVENTS_REL")" "$(digest_of product)" "detail"
	sw approve blueprint
	assert_eq "$RC" 0 "blueprint exit code"
	assert_match "$REPO/$APPROVALS_REL" "^blueprint = [0-9a-f]{40,64}$"
	assert_eq "$(jq -r .event "$REPO/$EVENTS_REL" | tail -n 1)" approve_blueprint "last event"
}

# AC-V2-03: a failing check writes nothing: no record, no event.
test_ac_v2_03_failing_check_writes_nothing() {
	ready
	sed 's/^Small teams lose track of who does what\.$/UNSET/' "$REPO/product/PRODUCT.md" >"$T/p" && mv "$T/p" "$REPO/product/PRODUCT.md"
	sw approve product
	assert_eq "$RC" 1 "exit code"
	[ ! -e "$REPO/$APPROVALS_REL" ] || fail "approvals.conf was written"
	[ ! -e "$REPO/$EVENTS_REL" ] || fail "an event was written"
	add_product
	sw approve product
	assert_eq "$RC" 0 "product exit code"
	before=$(cat "$REPO/$APPROVALS_REL")
	jq '.entities[0].id = "Not Valid"' "$REPO/architecture/data/model.json" >"$T/d" && mv "$T/d" "$REPO/architecture/data/model.json"
	sw approve blueprint
	assert_eq "$RC" 1 "blueprint exit code"
	assert_eq "$(cat "$REPO/$APPROVALS_REL")" "$before" "approvals.conf"
	assert_eq "$(wc -l <"$REPO/$EVENTS_REL" | tr -d ' ')" 1 "event lines"
}

# AC-V2-03: the blueprint is approved only on top of a current product approval.
test_ac_v2_03_blueprint_requires_current_product() {
	ready
	sw approve blueprint
	assert_eq "$RC" 1 "exit code without a product approval"
	assert_contains "$OUT" "product approval is missing"
	[ ! -e "$REPO/$APPROVALS_REL" ] || fail "approvals.conf was written"
	sw approve product
	printf '\n' >>"$REPO/product/PRODUCT.md"
	sw approve blueprint
	assert_eq "$RC" 1 "exit code with a stale product approval"
	assert_contains "$OUT" "product approval is stale"
	assert_no_match "$REPO/$APPROVALS_REL" "^blueprint"
}

# AC-V2-03: a changed, added or removed bound file makes the approval stale,
# a changed-but-uncommitted file included; approving again makes it current.
test_ac_v2_03_stale_on_change_add_remove() {
	ready
	sw approve product
	sw approve blueprint
	state_is product approved
	state_is blueprint approved
	printf '\n' >>"$REPO/product/PRODUCT.md"
	state_is product stale
	state_is blueprint approved
	sw approve product
	state_is product approved
	mkdir -p "$REPO/architecture/contracts"
	printf 'openapi: 3.0.0\n' >"$REPO/architecture/contracts/api.yaml"
	state_is blueprint stale
	sw approve blueprint
	state_is blueprint approved
	printf 'x\n' >"$REPO/architecture/contracts/.hidden"
	state_is blueprint stale
	sw approve blueprint
	printf 'openapi: 3.1.0\n' >"$REPO/architecture/contracts/api.yaml"
	state_is blueprint stale
	sw approve blueprint
	rm "$REPO/architecture/contracts/api.yaml"
	state_is blueprint stale
	sw approve blueprint
	state_is blueprint approved
	jq '.nodes[0].name = "Someone"' "$REPO/$MODEL_REL" >"$T/m" && mv "$T/m" "$REPO/$MODEL_REL"
	state_is blueprint stale
	sw approve blueprint
	jq '.entities[0].name = "Member"' "$REPO/architecture/data/model.json" >"$T/d" && mv "$T/d" "$REPO/architecture/data/model.json"
	state_is blueprint stale
	sw approve blueprint
	rm "$REPO/architecture/data/model.json"
	state_is blueprint stale
	assert_eq "$(wc -l <"$REPO/$APPROVALS_REL" | tr -d ' ')" "$(grep -c . "$REPO/$APPROVALS_REL")" "no blank lines"
}

# AC-V2-03: a malformed approvals.conf exits 2 and is not rewritten.
test_ac_v2_03_bad_approvals_conf_exits_2() {
	ready
	printf 'product = nothex\nblueprint = 0123456789abcdef0123456789abcdef01234567\nblueprint = 0123456789abcdef0123456789abcdef01234567\nbogus = 1\njunk\n' >"$REPO/$APPROVALS_REL"
	cp "$REPO/$APPROVALS_REL" "$T/before"
	sw approve product
	assert_eq "$RC" 2 "exit code"
	assert_match "$OUT" "^\.softwary/config/approvals\.conf:1: invalid digest"
	assert_match "$OUT" "^\.softwary/config/approvals\.conf:3: .*duplicate key 'blueprint'"
	assert_match "$OUT" "^\.softwary/config/approvals\.conf:4: unknown key 'bogus'"
	assert_match "$OUT" "^\.softwary/config/approvals\.conf:5: malformed line"
	cmp -s "$T/before" "$REPO/$APPROVALS_REL" || fail "approvals.conf was rewritten"
	sw status
	assert_eq "$RC" 2 "status exit code"
}

# AC-V2-03: outside a git repository approve exits 2.
test_ac_v2_03_needs_git_repository() {
	setup_repo --no-git
	add_product
	sw approve product
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "not a git repository"
	[ ! -e "$REPO/$APPROVALS_REL" ] || fail "approvals.conf was written"
}

# AC-V2-03: usage errors exit 2.
test_ac_v2_03_usage() {
	ready
	sw approve
	assert_eq "$RC" 2 "exit code"
	sw approve spec
	assert_eq "$RC" 2 "exit code for an unknown kind"
	assert_contains "$OUT" "usage: ./softwary approve product|blueprint"
}

# AC-V2-04: status shows each approval as missing, approved or stale.
test_ac_v2_04_status_shows_approvals() {
	ready
	state_is product missing
	state_is blueprint missing
	sw approve product
	state_is product approved
	state_is blueprint missing
	printf '\n' >>"$REPO/product/PRODUCT.md"
	state_is product stale
}

# AC-V2-04: a repository with no product and no approvals prints no approval lines.
test_ac_v2_04_status_without_product_is_unchanged() {
	setup_repo
	sw status
	assert_eq "$RC" 0 "exit code"
	assert_no_match "$OUT" "^approval"
}

run_tests "$0"
