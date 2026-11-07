// The comparator of `.sort()` may call global functions on `a` and `b`; it still may not capture
// local variables (see vlib/v/checker/tests for the diagnostics).
struct Item {
	name string
	n    int
}

fn key(s string) int {
	return s.len
}

fn weight(i Item) int {
	return i.n * 10 + i.name.len
}

fn test_sort_with_calls_to_global_functions() {
	mut xs := ['ccc', 'a', 'bb']
	xs.sort(key(a) < key(b))
	assert xs == ['a', 'bb', 'ccc']
	xs.sort(key(a) > key(b))
	assert xs == ['ccc', 'bb', 'a']
}

fn test_sort_with_calls_on_struct_values() {
	mut items := [Item{'x', 3}, Item{'yy', 1}, Item{'z', 2}]
	items.sort(weight(a) < weight(b))
	assert items.map(it.name) == ['yy', 'z', 'x']
	items.sort(weight(a) > weight(b))
	assert items.map(it.name) == ['x', 'z', 'yy']
}

fn test_sort_with_calls_mixed_with_selectors() {
	mut items := [Item{'x', 3}, Item{'yy', 1}, Item{'z', 2}]
	items.sort(key(a.name) < key(b.name))
	assert items[2].name == 'yy'
}
