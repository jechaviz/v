// `a + b` on two dynamic arrays of the same type is a new array with the elements of `a` followed
// by those of `b`, allocated once (the chain `a + b + c + d` too). `a += b` appends in place, like
// `a << b`.
struct Point {
	x int
}

struct Box {
mut:
	items []int
}

fn join[T](a []T, b []T) []T {
	return a + b
}

fn grow(mut s []int) {
	s += [9]
}

fn (mut b Box) add(v []int) {
	b.items += v
}

fn test_plus_concatenates_and_does_not_modify_its_operands() {
	a := [1, 2]
	b := [3, 4]
	c := a + b
	assert c == [1, 2, 3, 4]
	assert a == [1, 2]
	assert b == [3, 4]
}

fn test_plus_result_is_independent_of_its_operands() {
	mut a := []int{cap: 8}
	a << 1
	a << 2
	mut c := a + [3]
	c[0] = 100
	assert a == [1, 2]
	mut t := []int{cap: 10}
	t << 1
	t << 2
	t << 3
	mut u := t
	t = t + [4]
	u << 99
	assert t == [1, 2, 3, 4]
	assert u == [1, 2, 3, 99]
}

fn test_plus_chains_in_any_length() {
	assert [1] + [2] + [3] == [1, 2, 3]
	assert [1] + [2] + [3] + [4] == [1, 2, 3, 4]
	assert [1] + [2] + [3] + [4] + [5] == [1, 2, 3, 4, 5]
	assert [1] + [2] + [3] + [4] + [5] + [6] + [7] + [8] == [1, 2, 3, 4, 5, 6, 7, 8]
}

fn test_plus_with_empty_arrays() {
	empty := []int{}
	a := [1, 2]
	assert (empty + a) == [1, 2]
	assert (a + empty) == [1, 2]
	assert (empty + empty).len == 0
	assert (empty + a + empty + a) == [1, 2, 1, 2]
}

fn test_plus_on_strings_structs_and_fields() {
	assert ['x'] + ['y', 'z'] == ['x', 'y', 'z']
	points := [Point{1}] + [Point{2}, Point{3}]
	assert points.len == 3
	assert points[2].x == 3
	box := Box{
		items: [1]
	}
	assert (box.items + [2, 3]).len == 3
}

fn test_plus_in_generic_functions() {
	assert join([1], [2, 3]) == [1, 2, 3]
	assert join(['a'], ['b']).len == 2
}

fn test_plus_assign_appends_in_place() {
	mut s := []string{}
	s += ['x']
	s += ['y', 'z']
	assert s == ['x', 'y', 'z']
	mut total := []int{}
	for i in 0 .. 1000 {
		total += [i]
	}
	assert total.len == 1000
	assert total[999] == 999
	total += total
	assert total.len == 2000
}

fn test_plus_assign_on_mut_parameters_receivers_and_map_values() {
	mut xs := [1]
	grow(mut xs)
	assert xs == [1, 9]
	mut b := Box{}
	b.add([4])
	b.add([5, 6])
	assert b.items == [4, 5, 6]
	mut m := map[string][]int{}
	m['k'] = [1]
	m['k'] += [2]
	assert m['k'] == [1, 2]
}
