import arrays

fn non_empty_upper(value string) ?string {
	if value == '' {
		return none
	}
	return value.to_upper()
}

fn test_filter_map_keeps_transformed_values() {
	values := ['alpha', '', 'beta', '']
	assert arrays.filter_map[string, string](values, non_empty_upper) == ['ALPHA', 'BETA']
}

fn test_filter_map_indexed_keeps_transformed_values() {
	values := ['a', '', 'b', 'c']
	got := arrays.filter_map_indexed[string, string](values, fn (idx int, value string) ?string {
		if value == '' {
			return none
		}
		return '${idx}:${value}'
	})
	assert got == ['0:a', '2:b', '3:c']
}

fn test_filter_map_empty_input() {
	assert arrays.filter_map[int, string]([]int{}, fn (value int) ?string {
		return value.str()
	}) == []string{}
}
