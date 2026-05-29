import os
import term
import time
import flag

struct Context {
mut:
	show_help     bool
	cmd_line_opts []string
}

fn vtime_report_value(value string) string {
	return value.replace('\r', '\\r').replace('\n', '\\n')
}

fn main() {
	mut ctx := Context{}
	args := arguments()
	mut fp := flag.new_flag_parser(args#[1..])
	fp.application('v time')
	fp.version('0.0.1')
	fp.description('Start a command, and report how much time it took to run, and what its exit code was.')
	fp.arguments_description('CMD [ARGS]')
	fp.skip_executable()
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
	ecode := os.system(cmd)
	elapsed := sw.elapsed()
	stook_time := '${f64(elapsed.microseconds()) / 1000.0:8.3f} ms'
	if ecode != 0 {
		eprintln('vtime.command.failed=true')
		eprintln('vtime.command.reason=child_exit_nonzero')
		eprintln('vtime.command.action=report_timing_and_return_child_status')
		eprintln('vtime.command.message=timed command exited with a non-zero status')
		eprintln('vtime.command.exit_code=${ecode}')
		eprintln('vtime.command.command=${vtime_report_value(cmd)}')
	}
	eprintln('> ${term.ecolorize(term.bright_yellow, stook_time)}. Exit code: ${ecode:3}. Command: ${term.ecolorize(term.green,
		cmd)}')
	exit(ecode)
}
