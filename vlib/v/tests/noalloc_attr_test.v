import os
import rand

const vexe = os.quoted_path(@VEXE)

fn test_noalloc_attr_rejects_detected_allocations() {
	source_path := os.join_path(@VEXEROOT, 'vlib', 'v', 'tests', 'testdata',
		'noalloc_attr_failure.vv')
	cmd := '${vexe} -check ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code != 0, res.output
	assert res.output.contains('allocation (array initialization) is not allowed inside `@[noalloc]` function `make_values`'), res.output

	assert res.output.contains('allocation (array clone of `[]int`) is not allowed inside `@[noalloc]` function `clone_values`'), res.output
}

fn test_noalloc_attr_allows_non_allocating_function() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_noalloc_attr_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(@VEXEROOT, 'vlib', 'v', 'tests', 'testdata',
		'noalloc_attr_success.vv')
	out_path := os.join_path(test_dir, 'noalloc_success')
	cmd := '${vexe} -o ${os.quoted_path(out_path)} ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code == 0, res.exit_code_diagnostics('0',
		label:   @FN
		command: cmd
		reason:  'noalloc function without detected allocations should compile'
		action:  'inspect noalloc attr diagnostics'
	)
}
