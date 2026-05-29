module os

@[params]
pub struct ExitCodeDiagnostics {
pub:
	label   string
	command string
	reason  string = 'unexpected_exit_code'
	action  string = 'inspect_test_command_output_and_reproduce'
	output  string
	stdout  string
	stderr  string
}

// exit_code_diagnostics returns a structured assertion message for command results.
pub fn (result Result) exit_code_diagnostics(expected string, options ExitCodeDiagnostics) string {
	mut opts := options
	if opts.output == '' {
		opts = ExitCodeDiagnostics{
			...options
			output: result.output
		}
	}
	return process_exit_code_diagnostics(result.exit_code, expected, opts)
}

// process_exit_code_diagnostics returns a structured assertion message for process exits.
pub fn process_exit_code_diagnostics(actual int, expected string, options ExitCodeDiagnostics) string {
	mut lines := [
		'vtest.assert.failed=true',
		'vtest.assert.reason=${options.reason}',
		'vtest.assert.action=${options.action}',
		'vtest.assert.message=process exited with an unexpected status',
		'vtest.assert.expected_exit_code=${os_diagnostic_value(expected)}',
		'vtest.assert.actual_exit_code=${actual}',
	]
	if options.label != '' {
		lines << 'vtest.assert.label=${os_diagnostic_value(options.label)}'
	}
	if options.command != '' {
		lines << 'vtest.assert.command=${os_diagnostic_value(options.command)}'
	}
	if options.output != '' {
		lines << 'vtest.assert.output=${os_diagnostic_value(options.output)}'
	}
	if options.stdout != '' {
		lines << 'vtest.assert.stdout=${os_diagnostic_value(options.stdout)}'
	}
	if options.stderr != '' {
		lines << 'vtest.assert.stderr=${os_diagnostic_value(options.stderr)}'
	}
	return lines.join('\n')
}

fn os_diagnostic_value(value string) string {
	return value.trim_space().replace('\r', '\\r').replace('\n', '\\n')
}
