module main

import os

fn main() {
	args := os.args[2..]
	if args.len == 0 || args == ['help'] || '-help' in args || '--help' in args {
		cmd := '${os.quoted_path(vexe)} help where'
		exit_code := os.system(cmd)
		if exit_code != 0 {
			eprintln(os.process_command_failure_report('vwhere.command', exit_code,
				stage:          'show_help'
				command:        cmd
				reason:         'help_delegate_failed'
				action:         'rerun_help_command'
				message:        'vwhere help delegation exited with a non-zero status'
				output_capture: 'inherited_stdio'
			))
			exit(exit_code)
		}
		exit(0)
	}
	mut fdr := Finder{}
	fdr.configure_from_arguments(args)
	fdr.search_for_matches()
	fdr.show_results()
}
