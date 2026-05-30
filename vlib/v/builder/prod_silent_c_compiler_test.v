import os
import rand

const vexe = os.quoted_path(@VEXE)

fn write_silent_failing_c_compiler(path string) {
	$if windows {
		os.write_file(path, '@echo off\r\nexit /b 17\r\n') or { panic(err) }
	} $else {
		os.write_file(path, '#!/bin/sh\nexit 17\n') or { panic(err) }
		os.chmod(path, 0o700) or { panic(err) }
	}
}

fn test_prod_reports_silent_c_compiler_failure() {
	test_dir := os.join_path(os.vtmp_dir(), 'v_prod_silent_cc_${rand.ulid()}')
	os.mkdir_all(test_dir) or { panic(err) }
	defer {
		os.rmdir_all(test_dir) or {}
	}
	source_path := os.join_path(test_dir, 'main.v')
	os.write_file(source_path, 'fn main() {}\n') or { panic(err) }
	mut fake_cc := os.join_path(test_dir, 'silent-clang')
	$if windows {
		fake_cc += '.cmd'
	} $else {
		fake_cc += '.sh'
	}
	write_silent_failing_c_compiler(fake_cc)
	out_path := os.join_path(test_dir, 'app')
	cmd := '${vexe} -prod -cc ${os.quoted_path(fake_cc)} -o ${os.quoted_path(out_path)} ${os.quoted_path(source_path)}'
	res := os.execute(cmd)

	assert res.exit_code != 0, res.exit_code_diagnostics('!= 0',
		label:   @FN
		command: cmd
		reason:  'prod_silent_c_compiler_should_fail'
		action:  'inspect_prod_silent_c_compiler_diagnostics'
	)

	assert res.output.contains('v.builder.cc.command.failed=true'), res.output
	assert res.output.contains('v.builder.cc.command.stage=prod_c_compile_or_link'), res.output
	assert res.output.contains('v.builder.cc.command.reason=c_compiler_failed_without_output'), res.output
	assert res.output.contains('v.builder.cc.command.output_empty=true'), res.output
	assert res.output.contains('v.builder.cc.command.command='), res.output
	assert res.output.contains('v.builder.cc.command.ccompiler='), res.output
	assert res.output.contains('v.builder.cc.command.prod=true'), res.output
}
