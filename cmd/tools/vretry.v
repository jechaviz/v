import os
import time
import flag

struct Context {
mut:
	show_help bool
	timeout   time.Duration
	delay     time.Duration
	retries   int
}

fn report_vretry_failure(cmd string, exit_code int, reason string, context Context) {
	action := if reason == 'timeout_exceeded' {
		'increase_timeout_or_inspect_command'
	} else {
		'increase_retries_or_inspect_command'
	}
	message := if reason == 'timeout_exceeded' {
		'command retries exceeded the configured timeout'
	} else {
		'command failed after the configured retry count'
	}
	eprintln(os.process_command_failure_report('vretry.command', exit_code,
		stage:          'retry_command'
		command:        cmd
		reason:         reason
		action:         action
		message:        message
		output_capture: 'inherited_stdio'
	))
	eprintln('vretry.command.retries=${context.retries}')
	eprintln('vretry.command.timeout_seconds=${context.timeout.seconds()}')
}

// arg_needs_no_quoting reports whether `arg` survives a trip through the shell
// unchanged. Everything else is quoted rather than enumerated, so a character that
// is special on only some shells is still handled.
fn arg_needs_no_quoting(arg string) bool {
	if arg.len == 0 {
		return false
	}
	for c in arg {
		if c.is_alnum() || c in [`_`, `-`, `.`, `/`, `:`, `=`, `@`, `+`, `,`, `%`] {
			continue
		}
		return false
	}
	return true
}

// quote_arg spells one argument of a vector-form command so that the shell hands the
// command the single argument it already is. `v retry -- git clone URL DEST` arrives
// as four arguments, whatever quoting the caller's own shell removed, and is run
// through a shell again, so joining them with spaces would split a DEST like
// `C:\Users\Jane Doe\.vmodules\markdown` back into two arguments.
fn quote_arg(arg string) string {
	if arg_needs_no_quoting(arg) {
		return arg
	}
	$if windows {
		return windows_quote_arg(arg)
	} $else {
		return "'" + arg.replace("'", "'\\''") + "'"
	}
}

$if windows {
	// windows_quote_arg applies the backslash-and-quote rules Windows uses when it
	// rebuilds argv from a command line. Wrapping in quotes is not enough on its own: a
	// trailing backslash would escape the closing quote, so `C:\work space\` has to come
	// out as `"C:\work space\\"` or it swallows the argument after it. This is the same
	// escaping `os.Process` does in vlib/os/process_windows.c.v.
	fn windows_quote_arg(arg string) string {
		mut out := '"'
		mut pending_backslashes := 0
		for c in arg {
			if c == `\\` {
				pending_backslashes++
				continue
			}
			if c == `"` {
				// Each backslash run before a quote is doubled, and the quote escaped.
				out += '\\'.repeat(pending_backslashes * 2 + 1) + '"'
				pending_backslashes = 0
				continue
			}
			out += '\\'.repeat(pending_backslashes) + c.ascii_str()
			pending_backslashes = 0
		}
		// The run that ends the argument is doubled, so none of it escapes the closing quote.
		out += '\\'.repeat(pending_backslashes * 2) + '"'
		return out
	}
}

// seconds_to_duration converts a fractional number of seconds, as given on the
// command line, to a Duration. The scaling is done in floating point so that a
// value like `--delay 0.5` keeps its sub-second part.
fn seconds_to_duration(seconds f64) time.Duration {
	return time.Duration(i64(seconds * f64(time.second)))
}

fn main() {
	mut context := Context{}
	args := os.args#[1..]
	// dump(args)
	mut fp := flag.new_flag_parser(args)
	fp.application('v retry')
	fp.version('0.0.1')
	fp.description('Run the command CMD in a loop, until it succeeds, or until a predetermined amount of seconds pass.')
	fp.arguments_description('CMD')
	fp.skip_executable()
	fp.limit_free_args_to_at_least(1)!
	context.show_help = fp.bool('help', `h`, false, 'Show this help screen.')
	context.timeout = seconds_to_duration(fp.float('timeout', `t`, 900.0,
		'Timeout in seconds (for all retries). Default: 900.0 seconds (15 minutes).'))
	context.delay = seconds_to_duration(fp.float('delay', `d`, 1.0,
		'Delay between each retry in seconds. Default: 1.0 second.'))
	context.retries = fp.int('retries', `r`, 10, 'Maximum number of retries. Default: 10.')
	if context.show_help {
		println(fp.usage())
		exit(0)
	}
	command_args := fp.finalize() or {
		eprintln('error: ${err}')
		exit(1)
	}
	// Two call forms reach here. `v retry -- git clone URL DEST` passes the command as a
	// vector: the arguments arrive already split, whatever quoting the caller's own shell
	// removed, so each has to be quoted again before the shell that runs them sees it.
	// `v retry 'sudo apt update'` passes the command as shell syntax in a single argument,
	// which has to go through untouched - quoting that would ask the shell for a program
	// whose name contains spaces.
	cmd := if fp.idx_dashdash >= 0 {
		command_args.map(quote_arg(it)).join(' ')
	} else {
		command_args.join(' ')
	}
	// dump(cmd)

	spawn fn (context Context, cmd string) {
		time.sleep(context.timeout)
		eprintln('error: exceeded maximum timeout (${context.timeout.seconds()}s)!')
		report_vretry_failure(cmd, 1, 'timeout_exceeded', context)
		exit(1)
	}(context, cmd)

	mut res := 0
	for i in 0 .. context.retries {
		res = os.system(cmd)
		if res == 0 {
			break
		}
		if i == context.retries - 1 {
			eprintln('error: exceeded maximum number of retries (${context.retries})!')
			report_vretry_failure(cmd, res, 'retries_exhausted', context)
			exit(res)
		}
		time.sleep(context.delay)
	}
	exit(res)
}
