import os
import rand

const vexe = os.quoted_path(@VEXE)

fn test_check_syntax_reports_parser_error_text() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_check_syntax_diagnostics_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'broken.v')
	os.write_file(source_path, 'fn main() {\n\tprintln(\n}\n') or { panic(err) }
	cmd := '${vexe} -check-syntax ${os.quoted_path(source_path)}'
	res := os.execute(cmd)
	assert res.exit_code == 1, res.exit_code_diagnostics('1',
		label:   @FN
		command: cmd
		reason:  'check_syntax_should_fail'
		action:  'inspect_parser_output'
	)

	assert res.output.contains('error:'), res.output
	assert res.output.contains(os.to_slash(source_path)), res.output
}

fn test_check_only_does_not_write_backend_artifacts() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_check_only_no_backend_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'main.v')
	out_path := os.join_path(test_dir, 'app')
	os.write_file(source_path, 'fn main() {\n\tprintln("ok")\n}\n') or { panic(err) }
	for flag in ['-check', '-check-syntax'] {
		cmd := '${vexe} ${flag} -o ${os.quoted_path(out_path)} ${os.quoted_path(source_path)}'
		res := os.execute(cmd)
		assert res.exit_code == 0, res.exit_code_diagnostics('0',
			label:   @FN
			command: cmd
			reason:  'check_only_should_succeed'
			action:  'inspect_check_output'
		)

		assert !os.exists(out_path), '${flag} should not write executable ${out_path}'
		assert !os.exists('${out_path}.exe'), '${flag} should not write executable ${out_path}.exe'
		assert !os.exists('${out_path}.tmp.c'), '${flag} should not write C artifact ${out_path}.tmp.c'
		assert !os.exists('${out_path}.tmp.so.c'), '${flag} should not write C artifact ${out_path}.tmp.so.c'
	}
}
