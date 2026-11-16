#!/bin/sh
# Tests for ./softwary product check (V2).
# shellcheck disable=SC2329,SC2119 # tests are called by run_tests; setup_repo takes optional flags
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

PRODUCT_REL=product/PRODUCT.md
SECTIONS="Problem|Users|Scope|Out of scope|Features|Non-functional requirements|Constraints|Success metrics|Open questions"

# product_edit SED...: edits the repo's PRODUCT.md with sed.
product_edit() {
	sed "$@" "$REPO/$PRODUCT_REL" >"$T/product.tmp" || fail "sed failed: $*"
	mv "$T/product.tmp" "$REPO/$PRODUCT_REL"
}

# AC-V2-01: no PRODUCT.md is a configuration error.
test_ac_v2_01_missing_product_exits_2() {
	setup_repo
	sw product check
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "product/PRODUCT.md not found"
	assert_contains "$OUT" ".softwary/templates/PRODUCT.md"
}

# AC-V2-01: a complete definition passes.
test_ac_v2_01_valid_product_passes() {
	setup_repo
	add_product
	sw product check
	assert_eq "$RC" 0 "exit code"
	assert_match "$OUT" "^product: valid \(2 features, 3 examples\)$"
}

# AC-V2-01: each missing required section is reported by name, on its own line.
test_ac_v2_01_each_missing_section() {
	setup_repo
	old_ifs=$IFS
	IFS='|'
	# shellcheck disable=SC2086 # split the section list on '|' on purpose
	set -- $SECTIONS
	IFS=$old_ifs
	for s in "$@"; do
		add_product
		product_edit "/^## $s\$/d"
		sw product check
		assert_eq "$RC" 1 "exit code without $s"
		assert_match "$OUT" "^product/PRODUCT.md: missing section '## $s'$"
		[ "$(grep -c 'missing section' "$OUT")" -eq 1 ] || fail "more than one missing section reported without $s"
	done
}

# AC-V2-01: a feature without an example is reported with its id.
test_ac_v2_01_feature_without_example() {
	setup_repo
	add_product
	product_edit '/EX-F2-01/d'
	sw product check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: F2: feature has no example"
	assert_no_match "$OUT" "F1: feature has no example"
}

# AC-V2-01: an example carrying another feature's prefix, a duplicate id and
# an example outside any feature are separate lines.
test_ac_v2_01_wrong_prefix_and_duplicate() {
	setup_repo
	add_product
	product_edit 's/EX-F2-01/EX-F1-01/'
	sw product check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: example EX-F1-01 is under feature F2 \(its id must start with EX-F2-\)$"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: duplicate example id EX-F1-01$"
	assert_match "$OUT" "^product/PRODUCT.md: F2: feature has no example"
}

# AC-V2-01: UNSET lines and open questions are reported, one line each.
test_ac_v2_01_unset_and_open_questions() {
	setup_repo
	add_product
	product_edit 's/^Team members and their lead\.$/UNSET/; s/^None\.$/- Who pays?\n- Which hosting?/'
	sw product check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: UNSET$"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: open question: Who pays\?$"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: open question: Which hosting\?$"
	[ "$(grep -c 'open question' "$OUT")" -eq 2 ] || fail "expected two open-question lines"
}

# AC-V2-01: a CRLF file checks like an LF one (D-48).
test_ac_v2_01_crlf_product() {
	setup_repo
	add_product
	sed 's/$/\r/' "$REPO/$PRODUCT_REL" >"$T/crlf" && mv "$T/crlf" "$REPO/$PRODUCT_REL"
	sw product check
	assert_eq "$RC" 0 "exit code"
}

# AC-V2-01: the template itself fails, because of its UNSET placeholders.
test_ac_v2_01_template_fails() {
	setup_repo
	mkdir -p "$REPO/product"
	cp "$REPO/.softwary/templates/PRODUCT.md" "$REPO/$PRODUCT_REL"
	sw product check
	assert_eq "$RC" 1 "exit code"
	assert_match "$OUT" "^product/PRODUCT.md: line [0-9]+: UNSET$"
	assert_no_match "$OUT" "missing section"
	assert_no_match "$OUT" "has no example"
}

# AC-V2-01: usage errors exit 2.
test_ac_v2_01_usage() {
	setup_repo
	sw product
	assert_eq "$RC" 2 "exit code"
	assert_contains "$OUT" "usage: ./softwary product check"
}

run_tests "$0"
