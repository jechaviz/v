import os
import rand

const vexe = os.quoted_path(@VEXE)

fn test_warn_about_allocs_reports_explicit_clone_allocations() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_warn_about_allocs_clone_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(@VEXEROOT, 'vlib', 'v', 'tests', 'testdata',
		'warn_about_allocs_clone_main.vv')
	out_path := os.join_path(test_dir, 'clone_sample')
	cmd := '${vexe} -warn-about-allocs -o ${os.quoted_path(out_path)} ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code == 0, res.exit_code_diagnostics('0',
		label:   @FN
		command: cmd
		reason:  'clone allocation warnings should not fail compilation'
		action:  'inspect warn-about-allocs clone diagnostics'
	)

	assert res.output.contains('allocation (array clone of `[]int`)'), res.output
	assert res.output.contains('allocation (string clone of `string`)'), res.output
	assert res.output.contains('allocation (map clone of `map[string]int`)'), res.output
}
