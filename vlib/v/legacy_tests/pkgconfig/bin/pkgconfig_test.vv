import os

const vexe = os.getenv('VEXE')

const vroot = os.dir(vexe)

fn test_pkgconfig_can_be_compiled() {
	tmp_exe := os.join_path(os.vtmp_dir(), '${os.getpid()}_pkgconfig.exe')
	pkgconfig_v_file := os.real_path(os.join_path(vroot, 'vlib/v/pkgconfig/bin/pkgconfig.v'))
	assert !os.exists(tmp_exe)
	cmd := '${os.quoted_path(vexe)} -o ${os.quoted_path(tmp_exe)} ${os.quoted_path(pkgconfig_v_file)}'
	res := os.execute(cmd)
	if res.exit_code != 0 {
		assert false, res.exit_code_diagnostics('0',
			label:   @FN
			command: cmd
			reason:  'pkgconfig_build_failed'
			action:  'inspect_compiler_output'
		)
	}
	assert os.exists(tmp_exe)
	os.rm(tmp_exe)!
}
