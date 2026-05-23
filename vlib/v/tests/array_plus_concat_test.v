type Numbers = []int

fn test_array_plus_concatenates_without_mutating_operands() {
	left := [1, 2]
	right := [3, 4]
	joined := left + right
	assert joined == [1, 2, 3, 4]
	assert left == [1, 2]
	assert right == [3, 4]
}

fn test_array_plus_chains_and_accepts_empty_right_literal() {
	base := [1]
	joined := base + [2, 3] + []int{} + [4]
	assert joined == [1, 2, 3, 4]
}

fn test_array_alias_plus_concatenates() {
	a := Numbers([1, 2])
	b := Numbers([3])
	c := a + b
	assert c == Numbers([1, 2, 3])
	assert typeof(c).name == 'Numbers'
}
