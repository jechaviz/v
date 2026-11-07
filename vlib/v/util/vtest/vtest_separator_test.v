module vtest

import os

fn test_filter_vtest_only_ignores_the_kind_of_path_separator() {
	previous := os.getenv_opt('VTEST_ONLY')
	defer {
		if value := previous {
			os.setenv('VTEST_ONLY', value, true)
		} else {
			os.unsetenv('VTEST_ONLY')
		}
	}
	// a pattern with `/` must find a path that the OS spelled with `\`, and the other way round,
	// and the path that is returned is the one that was given
	os.setenv('VTEST_ONLY', 'tests/array', true)
	assert filter_vtest_only(['vlib\\v\\tests\\array_test.v', 'vlib\\v\\tests\\map_test.v'],
		fix_slashes: false) == ['vlib\\v\\tests\\array_test.v']
	os.setenv('VTEST_ONLY', 'tests\\array', true)
	assert filter_vtest_only(['vlib/v/tests/array_test.v', 'vlib/v/tests/map_test.v'],
		fix_slashes: false) == ['vlib/v/tests/array_test.v']
	os.setenv('VTEST_ONLY', 'tests/map,tests/array', true)
	assert filter_vtest_only(['vlib\\v\\tests\\array_test.v', 'vlib\\v\\tests\\map_test.v',
		'vlib\\v\\tests\\other_test.v'], fix_slashes: false).len == 2
}
