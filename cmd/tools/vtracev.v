module main

import os

fn main() {
	vexe := os.real_path(os.getenv_opt('VEXE') or { @VEXE })
	vroot := os.dir(vexe)
	os.chdir(vroot)!
	os.setenv('VCOLORS', 'always', true)
	self_idx := os.args.index('tracev')
	args := os.args[1..self_idx]
	args_str := args.join(' ')
	options := if args.len > 0 { '(${args_str})' } else { '' }
	println('Compiling a `tracev` executable ${options}...')
	tracev_cmd := '${os.quoted_path(vexe)} -cg -d trace_parser -d trace_checker -d trace_gen -o tracev ${args_str} cmd/v'
	exit_code := os.system(tracev_cmd)
	if exit_code != 0 {
		eprintln(os.process_command_failure_report('vtracev.command', exit_code,
			stage:          'compile_tracev'
			command:        tracev_cmd
			reason:         'tracev_compilation_failed'
			action:         'inspect_tracev_build_output'
			message:        'tracev helper compilation exited with a non-zero status'
			output_capture: 'inherited_stdio'
		))
		exit(exit_code)
	}
}
