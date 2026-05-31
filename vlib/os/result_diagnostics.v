module os

@[params]
pub struct ExitCodeDiagnostics {
pub:
	label          string
	command        string
	reason         string = 'unexpected_exit_code'
	action         string = 'inspect_test_command_output_and_reproduce'
	output         string
	stdout         string
	stderr         string
	output_capture string
}

@[params]
pub struct CommandFailureDiagnostics {
pub:
	stage             string
	command           string
	reason            string = 'child_exit_nonzero'
	action            string = 'inspect_command_output_and_reproduce'
	message           string = 'command exited with a non-zero status'
	output            string
	stdout            string
	stderr            string
	output_capture    string
	output_empty      bool
	exit_code_meaning string
	possible_causes   string
	error_code        int = -1
	error_kind        string
	error             string
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

// command_failure_report returns a structured message for command execution failures.
pub fn (result Result) command_failure_report(prefix string, options CommandFailureDiagnostics) string {
	mut opts := options
	if opts.output == '' {
		opts = CommandFailureDiagnostics{
			...options
			output: result.output
		}
	}
	return process_command_failure_report(prefix, result.exit_code, opts)
}

// process_command_failure_report returns a structured message for process failures.
pub fn process_command_failure_report(prefix string, actual int, options CommandFailureDiagnostics) string {
	exit_code_meaning := if options.exit_code_meaning != '' {
		options.exit_code_meaning
	} else {
		process_exit_code_meaning(actual)
	}
	mut lines := [
		'${prefix}.failed=true',
		'${prefix}.reason=${options.reason}',
		'${prefix}.action=${options.action}',
		'${prefix}.message=${os_diagnostic_value(options.message)}',
		'${prefix}.exit_code=${actual}',
		'${prefix}.exit_code_meaning=${exit_code_meaning}',
	]
	if options.possible_causes != '' {
		lines << '${prefix}.possible_causes=${os_diagnostic_value(options.possible_causes)}'
	} else if possible_causes := process_exit_code_possible_causes(actual) {
		lines << '${prefix}.possible_causes=${possible_causes}'
	}
	if options.stage != '' {
		lines << '${prefix}.stage=${os_diagnostic_value(options.stage)}'
	}
	if options.command != '' {
		lines << '${prefix}.command=${os_diagnostic_value(options.command)}'
	}
	if options.output_capture != '' {
		lines << '${prefix}.output_capture=${os_diagnostic_value(options.output_capture)}'
	}
	if options.output != '' {
		lines << '${prefix}.output=${os_diagnostic_value(options.output)}'
	} else if options.output_empty
		|| (options.stdout == '' && options.stderr == '' && options.output_capture == '') {
		lines << '${prefix}.output_empty=true'
	}
	if options.stdout != '' {
		lines << '${prefix}.stdout=${os_diagnostic_value(options.stdout)}'
	}
	if options.stderr != '' {
		lines << '${prefix}.stderr=${os_diagnostic_value(options.stderr)}'
	}
	if options.error_code != -1 {
		lines << '${prefix}.error_code=${options.error_code}'
	}
	if options.error_kind != '' {
		lines << '${prefix}.error_kind=${os_diagnostic_value(options.error_kind)}'
	}
	if options.error != '' {
		lines << '${prefix}.error=${os_diagnostic_value(options.error)}'
	}
	return lines.join('\n')
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
		'vtest.assert.actual_exit_code_meaning=${process_exit_code_meaning(actual)}',
	]
	if possible_causes := process_exit_code_possible_causes(actual) {
		lines << 'vtest.assert.possible_causes=${possible_causes}'
	}
	if options.label != '' {
		lines << 'vtest.assert.label=${os_diagnostic_value(options.label)}'
	}
	if options.command != '' {
		lines << 'vtest.assert.command=${os_diagnostic_value(options.command)}'
	}
	if options.output_capture != '' {
		lines << 'vtest.assert.output_capture=${os_diagnostic_value(options.output_capture)}'
	}
	if options.output != '' {
		lines << 'vtest.assert.output=${os_diagnostic_value(options.output)}'
	} else if options.stdout == '' && options.stderr == '' && options.output_capture == '' {
		lines << 'vtest.assert.output_empty=true'
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

// process_exit_code_meaning maps platform process statuses to stable diagnostic labels.
pub fn process_exit_code_meaning(actual int) string {
	if actual == 0 {
		return 'success'
	}
	if actual == -1 {
		return 'process_start_or_wait_failed'
	}
	if actual < 0 {
		return 'negative_process_status'
	}
	if actual >= 128 {
		return 'terminated_by_signal_or_platform_encoded_status'
	}
	return 'child_exited_nonzero'
}

pub fn process_exit_code_possible_causes(actual int) ?string {
	if actual == -1 {
		return 'process_spawn_failed;wait_failed;resource_exhaustion;missing_or_blocked_shell;terminated_before_stdio_flush'
	}
	if actual < 0 {
		return 'platform_specific_negative_status;process_start_or_wait_failed'
	}
	return none
}
