import os
import term
import time
import flag

struct Context {
mut:
	show_help     bool
	cmd_line_opts []string
}

fn main() {
	mut ctx := Context{}
	args := arguments()
	mut fp := flag.new_flag_parser(args#[1..])
	fp.application('v time')
	fp.version('0.0.1')
	fp.description('Start a command, and report how much time it took to run, and what its exit code was.')
	fp.arguments_description('CMD [ARGS]')
	fp.limit_free_args_to_at_least(1)!
	ctx.show_help = fp.bool('help', `h`, false, 'Show this help screen.')
	if ctx.show_help {
		println(fp.usage())
		exit(0)
	}
	ctx.cmd_line_opts = fp.finalize() or {
		eprintln('Error: ${err}')
		exit(1)
	}
	cmd := ctx.cmd_line_opts.join(' ')
	sw := time.new_stopwatch()
	ecode := os.system_args(ctx.cmd_line_opts)
	elapsed := sw.elapsed()
	stook_time := '${f64(elapsed.microseconds()) / 1000.0:8.3f} ms'
	if ecode != 0 {
		eprintln(os.process_command_failure_report('vtime.command', ecode,
			stage:          'timed_command'
			command:        cmd
			reason:         'child_exit_nonzero'
			action:         'report_timing_and_return_child_status'
			message:        'timed command exited with a non-zero status'
			output_capture: 'inherited_stdio'
		))
	}
	eprintln('> ${term.ecolorize(term.bright_yellow, stook_time)}. Status: ${ecode:3} (${os.process_exit_code_meaning(ecode)}). Command: ${term.ecolorize(term.green,
		cmd)}')
	exit(ecode)
}
