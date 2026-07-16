import os

@[markused]
const turn_off_vcolors = os.setenv('VCOLORS', 'never', true)

const issue_20147_vexe = @VEXE

fn issue_20147_env_snapshot(name string) (string, bool) {
	val := os.getenv_opt(name) or { return '', false }
	return val, true
}

fn issue_20147_restore_env(name string, value string, existed bool) {
	if existed {
		os.setenv(name, value, true)
	} else {
		os.unsetenv(name)
	}
}

fn issue_20147_workspace() string {
	return os.join_path(os.vtmp_dir(), 'issue_20147_vmodules_package_compile')
}

fn issue_20147_module_root() string {
	return os.join_path(issue_20147_workspace(), '.vmodules', 'msgpack')
}

fn issue_20147_write_file(path string, contents string) {
	os.write_file(path, contents) or { panic(err) }
}

fn issue_20147_write_vmod(path string, name string) {
	contents := ['Module {', "\tname: '${name}'", '}'].join_lines() + '\n'
	issue_20147_write_file(os.join_path(path, 'v.mod'), contents)
}

fn issue_20147_execute_v(args []string, workdir string) os.Result {
	mut env := os.environ()
	env['VJOBS'] = '1'
	mut process := os.new_process(issue_20147_vexe)
	process.set_args(args)
	process.set_work_folder(workdir)
	process.set_environment(env)
	process.set_redirect_stdio()
	process.run()
	if process.status == .not_started || process.err != '' {
		return os.Result{
			exit_code: -1
			output:    os.process_command_failure_report('vmodules_package_compile.child', -1,
				command:        '${os.quoted_path(issue_20147_vexe)} ${args.join(' ')}'
				reason:         'child_start_failed'
				action:         'inspect_child_process_environment'
				message:        'failed to start nested V command'
				stderr:         process.err
				output_capture: 'not_started'
			)
		}
	}
	process.wait()
	stdout := process.stdout_slurp()
	stderr := process.stderr_slurp()
	exit_code := process.code
	process.close()
	return os.Result{
		exit_code: exit_code
		output:    stdout + stderr
	}
}

fn issue_20147_write_project() {
	basepath := issue_20147_module_root()
	config_contents :=
		['module config', '', 'pub struct Config {}', '', 'pub fn default_config() Config {', '\treturn Config{}', '}'].join_lines() +
		'\n'
	decoder_contents := ['module decoder', '', 'pub struct Decoder {}'].join_lines() + '\n'
	to_contents := ['module msgpack.to', '', 'pub fn new_decoder(src []u8) {}'].join_lines() + '\n'
	msgpack_contents :=
		['module msgpack', '', "pub const description = 'an empty module, used as a placeholder, for other modules'"].join_lines() +
		'\n'
	test_contents := ['fn test_a() {', '\tassert true', '}'].join_lines()
	import_config_test_contents := ['import msgpack.config', '', test_contents].join_lines() + '\n'
	import_decoder_test_contents := ['import decoder', '', test_contents].join_lines() + '\n'
	import_to_test_contents := ['import msgpack.config', '', test_contents].join_lines() + '\n'
	os.rmdir_all(issue_20147_workspace()) or {}
	os.mkdir_all(os.join_path(basepath, 'config')) or { panic(err) }
	os.mkdir_all(os.join_path(basepath, 'decoder')) or { panic(err) }
	os.mkdir_all(os.join_path(basepath, 'to')) or { panic(err) }
	issue_20147_write_vmod(basepath, 'msgpack')
	issue_20147_write_file(os.join_path(basepath, 'config', 'config.v'), config_contents)
	issue_20147_write_file(os.join_path(basepath, 'decoder', 'decoder.v'), decoder_contents)
	issue_20147_write_file(os.join_path(basepath, 'to', 'to.v'), to_contents)
	issue_20147_write_file(os.join_path(basepath, 'msgpack.v'), msgpack_contents)
	issue_20147_write_file(os.join_path(basepath, 'import_config_test.v'),
		import_config_test_contents)
	issue_20147_write_file(os.join_path(basepath, 'import_decoder_test.v'),
		import_decoder_test_contents)
	issue_20147_write_file(os.join_path(basepath, 'import_to_test.v'), import_to_test_contents)
}

fn test_issue_20147_vmodules_package_tests_compile() {
	issue_20147_write_project()
	old_wd := os.getwd()
	old_vmodules, had_vmodules := issue_20147_env_snapshot('VMODULES')
	os.setenv('VMODULES', os.join_path(issue_20147_workspace(), '.vmodules'), true)
	os.chdir(issue_20147_module_root()) or { panic(err) }
	defer {
		os.chdir(old_wd) or { panic(err) }
		issue_20147_restore_env('VMODULES', old_vmodules, had_vmodules)
		os.rmdir_all(issue_20147_workspace()) or {}
	}
	res := issue_20147_execute_v(['test', '.'], issue_20147_module_root())
	assert res.exit_code == 0, res.exit_code_diagnostics('0', label: @FN)
}

fn test_local_vmod_root_module_preferred_over_stale_vmodules_from_nested_test() {
	workspace := os.join_path(issue_20147_workspace(), 'local_precedence')
	local_root := os.join_path(workspace, 'local_pkg')
	stale_root := os.join_path(workspace, '.vmodules', 'local_pkg')
	old_wd := os.getwd()
	old_vmodules, had_vmodules := issue_20147_env_snapshot('VMODULES')
	os.rmdir_all(workspace) or {}
	os.mkdir_all(os.join_path(local_root, 'tests')) or { panic(err) }
	os.mkdir_all(stale_root) or { panic(err) }
	issue_20147_write_vmod(local_root, 'local_pkg')
	issue_20147_write_vmod(stale_root, 'local_pkg')
	issue_20147_write_file(os.join_path(local_root, 'local_pkg.v'),
		"module local_pkg\n\npub fn origin() string {\n\treturn 'local'\n}\n")
	issue_20147_write_file(os.join_path(stale_root, 'local_pkg.v'),
		"module local_pkg\n\npub fn origin() string {\n\treturn 'stale'\n}\n")
	issue_20147_write_file(os.join_path(local_root, 'tests', 'origin_test.v'),
		"module main\n\nimport local_pkg\n\nfn test_local_root_module_wins() {\n\tassert local_pkg.origin() == 'local'\n}\n")
	os.setenv('VMODULES', os.join_path(workspace, '.vmodules'), true)
	os.chdir(workspace) or { panic(err) }
	defer {
		os.chdir(old_wd) or { panic(err) }
		issue_20147_restore_env('VMODULES', old_vmodules, had_vmodules)
		os.rmdir_all(workspace) or {}
	}

	args := ['test', os.join_path('local_pkg', 'tests', 'origin_test.v')]
	res := issue_20147_execute_v(args, workspace)
	assert res.exit_code == 0, res.exit_code_diagnostics('0',
		label:   @FN
		command: '${os.quoted_path(issue_20147_vexe)} ${args.map(os.quoted_path(it)).join(' ')}'
		reason:  'nested local module test should prefer the local v.mod root over VMODULES'
		action:  'inspect module lookup order'
	)
}

// Regression test for https://github.com/vlang/v/issues/27391 :
// modules installed as symlinks inside a `.vmodules` namespace folder
// (e.g. `.vmodules/einar_hjortdal/luuid -> /real/luuid`) were resolved to
// their real path via os.real_path and then rejected as belonging to a
// different v.mod project, so `import einar_hjortdal.luuid` could not be found.
fn issue_27391_workspace() string {
	return os.join_path(os.vtmp_dir(), 'issue_27391_symlinked_vmodules')
}

fn issue_27391_write_project() ! {
	workspace := issue_27391_workspace()
	vmodules_ns := os.join_path(workspace, '.vmodules', 'einar_hjortdal')
	real_luuid := os.join_path(workspace, 'real', 'luuid')
	real_firebird := os.join_path(workspace, 'real', 'firebird')
	app_root := os.join_path(workspace, 'app')
	luuid_vmod := ['Module {', "\tname: 'luuid'", '}'].join_lines() + '\n'
	luuid_contents :=
		['module luuid', '', "pub fn hello() string { return 'luuid-ok' }"].join_lines() + '\n'
	firebird_vmod := ['Module {', "\tname: 'firebird'", '}'].join_lines() + '\n'
	firebird_contents :=
		['module firebird', '', 'import einar_hjortdal.luuid', '', 'pub fn run() string { return luuid.hello() }'].join_lines() +
		'\n'
	app_vmod := ['Module {', "\tname: 'app'", '}'].join_lines() + '\n'
	app_contents :=
		['module main', '', 'import einar_hjortdal.luuid', 'import einar_hjortdal.firebird', '', 'fn main() {', '\tprintln(luuid.hello())', '\tprintln(firebird.run())', '}'].join_lines() +
		'\n'
	os.rmdir_all(workspace) or {}
	os.mkdir_all(vmodules_ns)!
	os.mkdir_all(real_luuid)!
	os.mkdir_all(real_firebird)!
	os.mkdir_all(app_root)!
	issue_20147_write_file(os.join_path(real_luuid, 'v.mod'), luuid_vmod)
	issue_20147_write_file(os.join_path(real_luuid, 'luuid.v'), luuid_contents)
	issue_20147_write_file(os.join_path(real_firebird, 'v.mod'), firebird_vmod)
	issue_20147_write_file(os.join_path(real_firebird, 'firebird.v'), firebird_contents)
	// install both real modules as symlinks inside the `einar_hjortdal` namespace
	os.symlink(real_luuid, os.join_path(vmodules_ns, 'luuid'))!
	os.symlink(real_firebird, os.join_path(vmodules_ns, 'firebird'))!
	issue_20147_write_file(os.join_path(app_root, 'v.mod'), app_vmod)
	issue_20147_write_file(os.join_path(app_root, 'main.v'), app_contents)
}

fn test_issue_27391_symlinked_namespaced_vmodules_import_compiles() {
	issue_27391_write_project() or {
		$if windows {
			eprintln('skipping symlinked vmodules import regression test: ${err}')
			return
		} $else {
			panic(err)
		}
	}
	old_vmodules, had_vmodules := issue_20147_env_snapshot('VMODULES')
	os.setenv('VMODULES', os.join_path(issue_27391_workspace(), '.vmodules'), true)
	defer {
		issue_20147_restore_env('VMODULES', old_vmodules, had_vmodules)
		os.rmdir_all(issue_27391_workspace()) or {}
	}
	main_file := os.join_path(issue_27391_workspace(), 'app', 'main.v')
	res := os.execute('${os.quoted_path(issue_20147_vexe)} run ${os.quoted_path(main_file)}')
	assert res.exit_code == 0, res.output
	assert res.output.trim_space() == 'luuid-ok\nluuid-ok', res.output
}
