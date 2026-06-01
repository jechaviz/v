module target_osbuilder

import os
import v.pref

fn test_target_asm_path_prefers_explicit_emit_path() {
	prefs := pref.Preferences{
		out_name:            os.join_path(os.temp_dir(), 'APP')
		target_api_emit_asm: os.join_path(os.temp_dir(), 'explicit.asm')
	}
	assert target_asm_path(prefs).ends_with('explicit.asm')
}

fn test_target_port_root_discovers_runtime_root_from_child_file() {
	root := os.join_path(os.vtmp_dir(), 'target_osbuilder_port_${os.getpid()}')
	child := os.join_path(root, 'examples')
	os.mkdir_all(child) or { panic(err) }
	os.mkdir_all(os.join_path(root, 'runtime')) or { panic(err) }
	os.write_file(os.join_path(root, 'kosv.v'), 'module main\n') or { panic(err) }
	os.write_file(os.join_path(root, 'runtime', 'target_runtime.inc'), '') or { panic(err) }
	os.write_file(os.join_path(child, 'app.v'), 'module main\n') or { panic(err) }
	defer {
		if os.exists(root) {
			os.rmdir_all(root) or {}
		}
	}

	found := target_port_root(os.join_path(child, 'app.v'), '') or {
		assert false, err.msg()
		return
	}
	assert found == os.real_path(root)
}
