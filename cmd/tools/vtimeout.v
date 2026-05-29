import os
import time
import flag
import strconv

struct Context {
mut:
	timeout  f64
	cmd_args []string
}

fn vtimeout_report_value(value string) string {
	return value.replace('\r', '\\r').replace('\n', '\\n')
}

fn report_vtimeout_command_failure(cmd_args []string, exit_code int, reason string) {
	command := cmd_args.join(' ')
	eprintln('vtimeout.command.failed=true')
	eprintln('vtimeout.command.reason=${reason}')
	eprintln('vtimeout.command.action=report_command_start_failure')
	eprintln('vtimeout.command.message=cannot execute command before applying timeout')
	eprintln('vtimeout.command.exit_code=${exit_code}')
	eprintln('vtimeout.command.command=${vtimeout_report_value(command)}')
}

fn main() {
	mut fp := flag.new_flag_parser(os.args[1..])
	fp.application('v timeout')
	fp.version('0.0.2')
	fp.description('Run a command with a time limit. Example: `v timeout 0.3 v run examples/hello_world.v`')
	fp.arguments_description('timeout_in_seconds CMD [ARGS]')
	fp.skip_executable()
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
	select {
		i64(ctx.timeout * time.second) {
			p.signal_term()
			time.sleep(2 * time.millisecond)
			if p.is_alive() {
				p.signal_kill()
			}
			p.wait()
			exit_code = 124 // timeout
		}
		code := <-child_exit {
			exit_code = code
		}
	}
	exit(exit_code)
}
