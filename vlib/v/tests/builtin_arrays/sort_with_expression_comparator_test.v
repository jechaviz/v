// Verifies that `.sort()` / `.sorted()` accept arbitrary expressions over the magic `a`/`b`
// element variables in the comparison (not only bare ident/selector/index/call operands):
// arithmetic on fields, free function calls (on a deref or a pointer), and descending order.

struct Vec {
	x int
	y int
}

fn sq(v int) int {
	return v * v
}

fn keyf(p &Vec) int {
	return -(p.x + p.y)
}

fn test_arithmetic_on_fields_ascending() {
	mut a := [Vec{1, 5}, Vec{2, 1}, Vec{0, 0}]
	a.sort(a.x + a.y < b.x + b.y)
	assert a.map(it.x + it.y) == [0, 3, 6]
}

fn test_arithmetic_on_fields_descending() {
	mut a := [Vec{1, 5}, Vec{2, 1}, Vec{9, 9}]
	a.sort(a.x + a.y > b.x + b.y)
	assert a.map(it.x + it.y) == [18, 6, 3]
}

fn test_free_fn_call_on_deref() {
	mut a := [3, -1, 2, -4]
	a.sort(sq(*a) < sq(*b)) // sort by square ascending
	assert a == [-1, 2, 3, -4]
}

fn test_free_fn_call_on_pointer() {
	mut a := [Vec{1, 0}, Vec{3, 0}, Vec{2, 0}]
	a.sort(keyf(a) < keyf(b)) // keyf negates, so this sorts by x descending
	assert a.map(it.x) == [3, 2, 1]
}

fn test_sorted_returns_new_with_expression() {
	a := [3, 1, 2]
	c := a.sorted(sq(*a) < sq(*b))
	assert c == [1, 2, 3]
	assert a == [3, 1, 2] // original unchanged
}
