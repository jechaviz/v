#!/usr/bin/env -S v -raw-vsh-tmp-prefix tmp

import os

const time_fmt = '"CPU: %Us\tReal: %es\tElapsed: %E\tRAM: %MKB\t%C"'
const flags = os.getenv('FLAGS')

unbuffer_stdout()

start := os.args[1] or { '1_000_000' }.int()
end := os.args[2] or { '10_000_000' }.int()
step := os.args[3] or { '500_000' }.int()

os.chdir(os.dir(@VEXE))!
vcmd := 'v ${flags} cmd/tools/bench/map_clear.v'

println('>> start: ${start} | end: ${end} | step: ${step} | workdir: "${os.getwd()}" | flags: "${flags}" | vcmd: "${vcmd}"')
build_res := os.execute(vcmd)
assert build_res.exit_code == 0, build_res.exit_code_diagnostics('0',
	label:   'map_clear_runner_build'
	command: vcmd
)

println('running...')
for i := start; i <= end; i += step {
	run_cmd := '/usr/bin/time -f ${time_fmt} cmd/tools/bench/map_clear ${i}'
	run_code := os.system(run_cmd)
	if run_code != 0 {
		eprintln(os.process_command_failure_report('map_clear_runner.command', run_code,
			reason:  'benchmark_command_failed'
			action:  'inspect_benchmark_command'
			command: run_cmd
		))
	}
}
