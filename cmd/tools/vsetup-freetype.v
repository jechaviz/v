module main

$if windows {
	import os
}

fn main() {
	$if windows {
		println('Setup freetype...')
		vexe := os.real_path(os.getenv_opt('VEXE') or { @VEXE })
		vroot := os.dir(vexe)
		freetype_repo_url := 'https://github.com/ubawurinna/freetype-windows-binaries'
		freetype_folder := os.join_path('thirdparty', 'freetype')
		os.chdir(vroot)!
		if os.is_dir(freetype_folder) {
			println('Thirdparty "freetype" is already installed.')
		} else {
			s :=
				os.execute('${os.quoted_path(vexe)} retry -- git clone --filter=blob:none ${freetype_repo_url} ${freetype_folder}')
			if s.exit_code != 0 {
				panic(s.command_failure_report('vsetup_freetype.command',
					reason:  'freetype_clone_failed'
					action:  'inspect_git_clone_output'
					command: '${os.quoted_path(vexe)} retry -- git clone --filter=blob:none ${freetype_repo_url} ${freetype_folder}'
				))
			}
			println(s.output)
			println('Thirdparty "freetype" installed successfully.')
		}
	} $else {
		println('It is only for Windows to setup thirdparty "freetype".')
	}
}
