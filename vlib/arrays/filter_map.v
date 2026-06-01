module arrays

// filter_map creates a new array from non-none values returned by transform.
// It is equivalent to mapping into optional values and filtering out `none`, but only scans once.
pub fn filter_map[T, R](array []T, transform fn (elem T) ?R) []R {
	mut result := []R{cap: array.len}
	for elem in array {
		if value := transform(elem) {
			result << value
		}
	}
	return result
}

// filter_map_indexed creates a new array from non-none values returned by transform for each idx,elem pair.
pub fn filter_map_indexed[T, R](array []T, transform fn (idx int, elem T) ?R) []R {
	mut result := []R{cap: array.len}
	for idx, elem in array {
		if value := transform(idx, elem) {
			result << value
		}
	}
	return result
}
