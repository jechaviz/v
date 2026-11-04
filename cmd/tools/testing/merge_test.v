module testing

import os

fn merge_test_dir(name string) string {
	dir := os.join_path(os.vtmp_dir(), 'vtest_merge_${name}_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn write_test_file(dir string, name string, content string) string {
	path := os.join_path(dir, name)
	os.write_file(path, content) or { panic(err) }
	return path
}

fn test_a_test_file_of_a_named_module_is_mergeable() {
	dir := merge_test_dir('mod')
	defer { os.rmdir_all(dir) or {} }
	file := write_test_file(dir, 'a_test.v', '// a comment\nmodule foo\n\nfn test_a() {}\n')
	assert module_of_test(file) == 'foo'
}

fn test_main_attributed_and_directive_files_are_not_mergeable() {
	dir := merge_test_dir('not')
	defer { os.rmdir_all(dir) or {} }
	assert module_of_test(write_test_file(dir, 'a_test.v', 'module main\n\nfn test_a() {}\n')) == ''
	assert module_of_test(write_test_file(dir, 'b_test.v', '@[has_globals]\nmodule foo\n')) == ''
	assert module_of_test(write_test_file(dir, 'c_test.v', '// vtest vflags: -d x\nmodule foo\n')) == ''
	assert module_of_test(write_test_file(dir, 'd_test.c.v', 'module foo\n')) == ''
	assert module_of_test(write_test_file(dir, 'e.v', 'module foo\n')) == ''
	assert module_of_test(write_test_file(dir, 'zz_vmerged_foo_test.v', 'module foo\n')) == ''
}

fn test_the_merged_source_hoists_each_import_once_and_keeps_every_body() {
	dir := merge_test_dir('src')
	defer { os.rmdir_all(dir) or {} }
	a := write_test_file(dir, 'a_test.v', 'module foo\n\nimport os\nimport time\n\nfn test_a() {\n\tassert true\n}\n')
	b := write_test_file(dir, 'b_test.v', 'module foo\n\nimport os\n\nfn test_b() {\n\tassert true\n}\n')
	text := merged_source('foo', [a, b]) or { panic(err) }
	assert text.starts_with('module foo\n\nimport os\nimport time\n')
	assert text.count('import os') == 1
	assert text.contains('fn test_a()')
	assert text.contains('fn test_b()')
	assert text.contains('// ---- a_test.v')
	assert text.contains('// ---- b_test.v')
}

fn test_a_directory_below_the_threshold_is_left_alone() {
	dir := merge_test_dir('few')
	defer { os.rmdir_all(dir) or {} }
	mut files := []string{}
	for name in ['a', 'b'] {
		files << write_test_file(dir, '${name}_test.v', 'module foo\n\nfn test_${name}() {}\n')
	}
	out, plan := plan_module_merging(files, [])
	assert plan.is_empty()
	assert out == files
}

fn test_the_files_of_a_module_become_one_merged_file_next_to_them() {
	dir := merge_test_dir('many')
	defer { os.rmdir_all(dir) or {} }
	mut files := []string{}
	for name in ['a', 'b', 'c'] {
		files << write_test_file(dir, '${name}_test.v', 'module foo\n\nfn test_${name}() {}\n')
	}
	other := write_test_file(dir, 'main_test.v', 'module main\n\nfn test_m() {}\n')
	files << other
	out, plan := plan_module_merging(files, [])
	assert !plan.is_empty()
	merged := os.join_path(dir, 'zz_vmerged_foo_test.v')
	assert merged in plan.merged
	assert plan.merged[merged].len == 3
	assert os.exists(merged)
	assert out.len == 2
	assert other in out
	assert merged in out
	plan.remove_merged_files()
	assert !os.exists(merged)
}

fn test_skipped_files_are_not_merged() {
	dir := merge_test_dir('skip')
	defer { os.rmdir_all(dir) or {} }
	mut files := []string{}
	for name in ['a', 'b', 'c', 'd'] {
		files << write_test_file(dir, '${name}_test.v', 'module foo\n\nfn test_${name}() {}\n')
	}
	_, plan := plan_module_merging(files, [os.real_path(files[0])])
	merged := os.join_path(dir, 'zz_vmerged_foo_test.v')
	assert plan.merged[merged].len == 3
	plan.remove_merged_files()
}

fn test_stale_merged_files_from_an_interrupted_run_are_removed() {
	dir := merge_test_dir('stale')
	defer { os.rmdir_all(dir) or {} }
	stale := write_test_file(dir, 'zz_vmerged_old_test.v', 'module old\n')
	a := write_test_file(dir, 'a_test.v', 'module foo\n')
	out, _ := plan_module_merging([a, stale], [])
	assert stale !in out
	assert !os.exists(stale)
}

fn test_a_test_that_waits_on_another_process_is_not_merged() {
	dir := merge_test_dir('heavy')
	defer { os.rmdir_all(dir) or {} }
	mut light := []string{}
	for name in ['a', 'b', 'c'] {
		light << write_test_file(dir, '${name}_test.v', 'module foo\n\nfn test_${name}() {}\n')
	}
	heavy := write_test_file(dir, 'slow_test.v', 'module foo\n\nimport os\n\nfn test_slow() {\n\t_ := os.execute("echo")\n}\n')
	assert test_file_is_heavy(heavy)
	assert !test_file_is_heavy(light[0])
	out, plan := plan_module_merging([heavy, ...light], [])
	merged := os.join_path(dir, 'zz_vmerged_foo_test.v')
	assert plan.merged[merged].len == 3
	assert heavy in out // it still runs, on its own, beside the merged program
	assert heavy !in plan.merged[merged]
	plan.remove_merged_files()
}

fn test_merging_heavy_tests_can_be_asked_for() {
	dir := merge_test_dir('heavyopt')
	defer { os.rmdir_all(dir) or {} }
	heavy := write_test_file(dir, 'slow_test.v', 'module foo\n\nimport os\n\nfn test_slow() {\n\t_ := os.exec(["echo"])\n}\n')
	previous := os.getenv_opt('VTEST_MERGE_HEAVY')
	defer {
		if value := previous {
			os.setenv('VTEST_MERGE_HEAVY', value, true)
		} else {
			os.unsetenv('VTEST_MERGE_HEAVY')
		}
	}
	os.setenv('VTEST_MERGE_HEAVY', '1', true)
	assert !test_file_is_heavy(heavy)
}
