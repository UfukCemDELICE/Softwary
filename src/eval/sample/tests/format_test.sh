# shellcheck shell=sh
# shellcheck disable=SC2154,SC2329 # root and assert_eq come from run.sh; tests are called by it
# shellcheck source=/dev/null
. "$root/src/format.sh"

test_format_cents() {
	assert_eq "$(format_cents 1234)" "12.34"
}

test_format_small_amounts() {
	assert_eq "$(format_cents 5)" "0.05"
}
