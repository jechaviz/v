module target_osbuilder

import os
import v.builder
import v.pref

const port_root_env = 'TARGET_OS_PORT_ROOT'

struct TargetBuildPlan {
	input    string
	port     string
	kosv     string
	vexe     string
	out_asm  string
	out_bin  string
	runtime  string
	fasm     string
	assemble bool
}

pub fn compile_target_os(mut b builder.Builder) {
	mut files := b.get_builtin_files()
	files << b.get_user_files()
	b.set_module_lookup_paths()
	if b.pref.is_verbose {
		println('all .v files:')
		println(files)
	}
	if b.pref.check_only || b.pref.only_check_syntax {
		b.front_and_middle_stages(files) or {
			if err.code() > 7000 {
				return
			}
			builder.verror(err.msg())
		}
		return
	}
	b.front_and_middle_stages(files) or {
		if err.code() > 7000 {
			return
		}
		builder.verror(err.msg())
	}
	b.pref.skip_running = true
	plan := target_build_plan(b) or { builder.verror(err.msg()) }
	run_target_bridge(plan) or { builder.verror(err.msg()) }
}

fn target_build_plan(b &builder.Builder) !TargetBuildPlan {
	if b.pref.should_output_to_stdout() {
		return error('target_os does not support stdout output; pass -o <target binary> or -target_api-emit-asm <path>')
	}
	input := target_input_path(b)!
	port := target_port_root(input, b.pref.target_api_runtime)!
	kosv := os.join_path(port, 'kosv.v')
	out_bin := b.pref.out_name
	out_asm := target_asm_path(b.pref)
	return TargetBuildPlan{
		input:    input
		port:     port
		kosv:     kosv
		vexe:     pref.vexe_path()
		out_asm:  out_asm
		out_bin:  out_bin
		runtime:  b.pref.target_api_runtime
		fasm:     b.pref.target_api_fasm
		assemble: !b.pref.target_api_no_assemble
	}
}

fn target_input_path(b &builder.Builder) !string {
	if b.pref.path.trim_space() == '' {
		return error('target_os needs a V source path')
	}
	return os.real_path(b.pref.path)
}

fn target_asm_path(p &pref.Preferences) string {
	if p.target_api_emit_asm.trim_space() != '' {
		return os.real_path(p.target_api_emit_asm)
	}
	return os.real_path('${p.out_name}.asm')
}

fn target_port_root(input string, runtime string) !string {
	if env_root := checked_port_root(os.getenv(port_root_env)) {
		return env_root
	}
	if runtime.trim_space() != '' {
		if root := find_target_port_root_from(runtime) {
			return root
		}
	}
	if root := find_target_port_root_from(input) {
		return root
	}
	return error('${port_root_env} must point at the target OS V/FASM port root when the input is outside that tree')
}

fn checked_port_root(path string) ?string {
	if path.trim_space() == '' {
		return none
	}
	real := os.real_path(path)
	if port_root_is_valid(real) {
		return real
	}
	return none
}

fn find_target_port_root_from(path string) ?string {
	mut current := os.real_path(path)
	if !os.is_dir(current) {
		current = os.dir(current)
	}
	for current != '' {
		if port_root_is_valid(current) {
			return current
		}
		parent := os.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return none
}

fn port_root_is_valid(path string) bool {
	return os.exists(os.join_path(path, 'kosv.v'))
		&& os.exists(os.join_path(path, 'runtime', 'target_runtime.inc'))
}

fn run_target_bridge(plan TargetBuildPlan) ! {
	os.mkdir_all(os.dir(plan.out_asm))!
	if plan.assemble {
		os.mkdir_all(os.dir(plan.out_bin))!
	}
	mut args := [
		os.quoted_path(plan.vexe),
		'run',
		os.quoted_path(plan.kosv),
		'--input',
		os.quoted_path(plan.input),
		'--out-asm',
		os.quoted_path(plan.out_asm),
		'--out-bin',
		os.quoted_path(plan.out_bin),
		'--v-exe',
		os.quoted_path(plan.vexe),
		'--use-checked-ast',
	]
	if plan.runtime.trim_space() != '' {
		args << ['--runtime', os.quoted_path(plan.runtime)]
	}
	if plan.fasm.trim_space() != '' {
		args << ['--fasm', os.quoted_path(plan.fasm)]
	}
	if plan.assemble {
		args << '--assemble'
	}
	cmd := args.join(' ')
	res := os.execute(cmd)
	if res.exit_code != 0 {
		return error(os.process_command_failure_report('v.target_osbuilder.bridge', res.exit_code,
			stage:          'target_os_fasm_bridge'
			command:        cmd
			reason:         'target_os_bridge_failed'
			action:         'inspect_backend_output_or_target_api_debug_flags'
			message:        'target OS V/FASM bridge failed'
			stderr:         res.output
			output_capture: 'combined'
		))
	}
	if res.output.trim_space() != '' {
		println(res.output.trim_space())
	}
}
