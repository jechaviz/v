module driver

import os

fn test_c_object_dependencies_parse_tcc_crlf_make_output_with_windows_paths() {
	root := os.join_path(os.vtmp_dir(), 'v3 dep scan spaces ${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	defer {
		os.rmdir_all(root) or {}
	}
	source := os.join_path(root, 'source file.c')
	header := os.join_path(root, 'include file.h')
	os.write_file(source, 'int source_value;\n')!
	os.write_file(header, '#define DEPENDENCY 1\n')!
	continuation := '\\' + '\r\n  '
	dep_source := source.replace(' ', '\\ ')
	dep_header := header.replace(' ', '\\ ')
	output := 'v3cache: ' + continuation + dep_source + ' ' + continuation + dep_header + '\r\n'

	dependencies := c_object_dependencies_from_output(output, source)

	assert !dependencies.used_fallback
	assert dependencies.files.len == 2
	assert source in dependencies.files
	assert header in dependencies.files
}

fn test_v3_c_object_cache_uses_shared_v3cache_for_test_sessions() {
	base := os.join_path(os.vtmp_dir(), 'c_object_cache_scope_test')
	session := os.join_path(base, 'tsession_test')
	shared := os.join_path(base, 'shared_cache')
	assert v3_c_object_cache_dir_for(session, '') == os.join_path(session, 'v3_thirdparty_objs')
	assert v3_c_object_cache_dir_for(session, shared) == os.join_path(shared, 'v3_thirdparty_objs')
}
