import os
import time
import flag
import strconv

struct Context {
mut:
	timeout  f64
	cmd_args []string
}

fn report_vtimeout_command_failure(cmd_args []string, exit_code int, reason string) {
	command := cmd_args.join(' ')
	eprintln(os.process_command_failure_report('vtimeout.command', exit_code,
		stage:   'start_child'
		command: command
		reason:  reason
		action:  'report_command_start_failure'
		message: 'cannot execute command before applying timeout'
	))
}

fn report_vtimeout_exit(cmd_args []string, exit_code int, reason string) {
	if exit_code == 0 {
		return
	}
	action := if reason == 'timeout' {
		'increase_timeout_or_inspect_child_process'
	} else {
		'inspect_child_output_or_run_command_directly'
	}
	message := if reason == 'timeout' {
		'command exceeded the configured timeout'
	} else {
		'command exited with a non-zero status'
	}
	eprintln(os.process_command_failure_report('vtimeout.command', exit_code,
		stage:          'wait_for_child'
		command:        cmd_args.join(' ')
		reason:         reason
		action:         action
		message:        message
		output_capture: 'inherited_stdio'
	))
}

fn main() {
	mut fp := flag.new_flag_parser(os.args[1..])
	fp.application('v timeout')
	fp.version('0.0.2')
	fp.description('Run a command with a time limit. Example: `v timeout 0.3 v run examples/hello_world.v`')
	fp.arguments_description('timeout_in_seconds CMD [ARGS]')
	fp.limit_free_args_to_at_least(2)!

	if fp.bool('help', `h`, false, 'Show this help screen.') {
		println(fp.usage())
		exit(0)
	}

	args := fp.finalize() or {
		eprintln('Argument error: ${err}')
		exit(125) // mimic the exit codes of `timeout` in coreutils
	}

	ctx := Context{
		timeout:  strconv.atof64(args[0]) or {
			eprintln('Invalid timeout: ${args[0]}')
			exit(125)
		}
		cmd_args: args[1..].clone()
	}

	mut cmd := ctx.cmd_args[0]
	if !os.exists(cmd) {
		cmd = os.find_abs_path_of_executable(cmd) or { cmd }
	}

	mut p := os.new_process(cmd)
	p.set_args(ctx.cmd_args[1..])
	p.run()
	if p.err != '' {
		exit_code := if os.exists(ctx.cmd_args[0]) { 126 } else { 127 }
		reason := if exit_code == 126 { 'command_not_executable' } else { 'command_not_found' }
		report_vtimeout_command_failure(ctx.cmd_args, exit_code, reason)
		exit(exit_code)
	}

	child_exit := chan int{}

	spawn fn (mut p os.Process, ch chan int) {
		p.wait()
		ch <- p.code
		ch.close()
	}(mut p, child_exit)

	mut exit_code := 0
	mut exit_reason := 'completed'
	select {
		i64(ctx.timeout * time.second) {
			p.signal_term()
			time.sleep(2 * time.millisecond)
			if p.is_alive() {
				p.signal_kill()
			}
			p.wait()
			exit_code = 124 // timeout
			exit_reason = 'timeout'
		}
		code := <-child_exit {
			exit_code = code
			if exit_code != 0 {
				exit_reason = 'child_exit_nonzero'
			}
		}
	}
	report_vtimeout_exit(ctx.cmd_args, exit_code, exit_reason)
	exit(exit_code)
}
