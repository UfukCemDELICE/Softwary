# shellcheck shell=sh
# Splitting a bill. Amounts are whole cents.

# split_even TOTAL PEOPLE: prints one share per line, the first person first.
# The shares add up to TOTAL; the cents that do not divide go one each to the
# first people. Fewer than one person is refused with status 2.
split_even() {
	_se_total=$1
	_se_people=$2
	if [ "$_se_people" -lt 1 ]; then
		echo "split: at least one person" >&2
		return 2
	fi
	_se_share=$((_se_total / _se_people))
	_se_rest=$((_se_total % _se_people))
	_se_i=1
	while [ "$_se_i" -le "$_se_people" ]; do
		if [ "$_se_i" -le "$_se_rest" ]; then
			echo $((_se_share + 1))
		else
			echo "$_se_share"
		fi
		_se_i=$((_se_i + 1))
	done
}
