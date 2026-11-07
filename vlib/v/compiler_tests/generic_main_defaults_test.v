import os
import v.cmdexec

fn test_generic_main_struct_keeps_collection_defaults_with_name_collision() {
	root := os.join_path(os.vtmp_dir(), 'generic_main_defaults_${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'factory'))!
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, 'v.mod'), "Module { name: 'generic_main_defaults' }\n")!
	factory_source := $embed_file('testdata/generic_main_defaults/factory.v.txt').to_string()
	os.write_file(os.join_path(root, 'factory', 'factory.v'), factory_source)!
	main_path := os.join_path(root, 'main.v')
	main_source := $embed_file('testdata/generic_main_defaults/main.vv').to_string()
	os.write_file(main_path, main_source)!
	for serial in [false, true] {
		binary := os.join_path(root, if serial { 'serial.exe' } else { 'default.exe' })
		mut flags := ['-new-compiler', '-cc', 'gcc', '-gc', 'none']
		if serial { flags << '-no-parallel' }
		flags << ['-o', binary, main_path]
		compiled := cmdexec.run_with_timeout(@VEXE, flags, 120_000)
		assert compiled.exit_code == 0, compiled.output
		run := cmdexec.run_with_timeout(binary, []string{}, 10_000)
		assert run.exit_code == 0, run.output
		assert run.output.trim_space() == 'generic_value_ok\ngeneric_heap_ok\ngeneric_fixed_ok\ngeneric_json_ok'
	}
}

fn test_comptime_value_reflection_still_rejects_incompatible_sources() {
	root := os.join_path(os.vtmp_dir(), 'comptime_value_sources_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	cases := [
		'fn main() {\n value := 42\n \$for variant in value.variants { println(variant.typ) }\n}\n',
		'struct Box { n int }\nfn main() {\n value := Box{}\n \$for member in value.values { println(member.name) }\n}\n',
	]
	for index, source in cases {
		path := os.join_path(root, 'bad_${index}.v')
		os.write_file(path, source)!
		checked := cmdexec.run_with_timeout(@VEXE, ['-new-compiler', '-check', path], 30_000)
		assert checked.exit_code != 0, checked.output
		assert checked.output.contains('error:'), checked.output
		assert !checked.output.contains('C compilation failed'), checked.output
	}
}
