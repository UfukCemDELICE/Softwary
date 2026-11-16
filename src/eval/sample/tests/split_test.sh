# shellcheck shell=sh
# shellcheck disable=SC2154,SC2329 # root and assert_eq come from run.sh; tests are called by it
# shellcheck source=/dev/null
. "$root/src/split.sh"

# AC-001-01
test_shares_add_up() {
	sum=0
	for s in $(split_even 1001 4); do
		sum=$((sum + s))
	done
	assert_eq "$sum" 1001
}

# AC-001-02
test_remainder_goes_to_first() {
	assert_eq "$(split_even 100 3 | paste -sd' ' -)" "34 33 33"
}

# AC-001-03
test_zero_people_refused() {
	split_even 100 0 2>/dev/null
	assert_eq "$?" 2
}
