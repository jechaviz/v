import os

// Expect has to be installed for the test.
const expect_exe = os.find_abs_path_of_executable('expect') or {
	eprintln('skipping test, since expect is missing')
	exit(0)
}
// Directory that contains the Expect scripts used in the test.
const expect_tests_path = os.join_path(@VMODROOT, 'examples', 'readline', 'tests')

fn test_password_input() {
	correct := os.execute(os.join_path(expect_tests_path, 'readline.expect'))
	assert correct.exit_code == 0, correct.exit_code_diagnostics('0', label: @FN)

	send_a := 'a'
	expect_a := 'got 97' // readline output for `a`
	a_res :=
		os.execute('${os.join_path(expect_tests_path, 'readline_from_expect_arg.expect')} ${send_a} "${expect_a}"')
	assert a_res.exit_code == 0, a_res.exit_code_diagnostics('0', label: @FN)

	send_b := 'b'
	b_res :=
		os.execute('${os.join_path(expect_tests_path, 'readline_from_expect_arg.expect')} ${send_b} "${expect_a}"')
	assert b_res.exit_code == 1, b_res.exit_code_diagnostics('1', label: @FN)
	assert b_res.output.contains('got 98')
}
