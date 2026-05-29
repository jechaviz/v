import os

const vexe = @VEXE
const vfmt_test_tdir = os.join_path(os.vtmp_dir(), 'vfmt_test_25005')

fn testsuite_begin() {
	os.rmdir_all(vfmt_test_tdir) or {}
	os.mkdir_all(vfmt_test_tdir)!
}

fn testsuite_end() {
	os.rmdir_all(vfmt_test_tdir) or {}
}

fn test_fmt_keeps_invalid_assert_source_unchanged() {
	source_path := os.join_path(vfmt_test_tdir, 'invalid_assert_message.v')
	original := "fn main() {\n\tassert false 'bye'\n}\n"
	os.write_file(source_path, original)!

	res := os.execute('${os.quoted_path(vexe)} fmt -w ${os.quoted_path(source_path)}')

	assert res.exit_code != 0, res.output
	assert res.output.contains('unexpected string `bye`, expecting `,`'), res.output
	assert res.output.contains('vfmt.worker.failed=true'), res.output
	assert res.output.contains('vfmt.worker.reason=worker_exit_nonzero'), res.output
	assert res.output.contains('vfmt.worker.message=vfmt worker failed while formatting file:'), res.output
	assert res.output.contains('vfmt.worker.exit_code='), res.output
	assert res.output.contains('vfmt.worker.exit_description='), res.output
	assert res.output.contains('vfmt.worker.origin_pid='), res.output
	assert res.output.contains('vfmt.worker.command='), res.output
	assert os.read_file(source_path)! == original
}

fn test_fmt_preferences_respect_vflags() {
	source_path := os.join_path(vfmt_test_tdir, 'vflags_backend_js.v')
	os.write_file(source_path, "fn main() {\n\tx := 'abc'.str\n}\n")!

	old_vflags := os.getenv('VFLAGS')
	defer {
		if old_vflags == '' {
			os.unsetenv('VFLAGS')
		} else {
			os.setenv('VFLAGS', old_vflags, true)
		}
	}

	os.unsetenv('VFLAGS')
	warmup_res := os.execute('${os.quoted_path(vexe)} fmt -help')
	assert warmup_res.exit_code == 0, warmup_res.output

	os.setenv('VFLAGS', '-b js', true)
	res := os.execute('${os.quoted_path(vexe)} fmt ${os.quoted_path(source_path)}')

	assert res.exit_code == 0, res.output
	assert res.output.contains("x := 'abc'.str"), res.output
	assert !res.output.contains("x := c'abc'"), res.output
}

fn test_fmt_verify_accepts_formatted_file_with_utf8_bom() {
	source_path := os.join_path(vfmt_test_tdir, 'formatted_bom.v')
	original := "\xef\xbb\xbfmodule main\n\nfn main() {\n\tprintln('hi')\n}\n"
	os.write_file(source_path, original)!

	res := os.execute('${os.quoted_path(vexe)} fmt -verify ${os.quoted_path(source_path)}')

	assert res.exit_code == 0, res.output
	assert os.read_file(source_path)! == original
}

fn test_fmt_write_preserves_utf8_bom() {
	source_path := os.join_path(vfmt_test_tdir, 'unformatted_bom.v')
	original := '\xef\xbb\xbfmodule main\n\nfn main() {\nprintln("hi")\n}\n'
	os.write_file(source_path, original)!

	res := os.execute('${os.quoted_path(vexe)} fmt -w ${os.quoted_path(source_path)}')
	formatted := os.read_file(source_path)!

	assert res.exit_code == 0, res.output
	assert formatted.starts_with('\xef\xbb\xbf')
	assert formatted == "\xef\xbb\xbfmodule main\n\nfn main() {\n\tprintln('hi')\n}\n"
}
