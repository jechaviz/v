import os

fn test_command() {
	if os.user_os() == 'windows' {
		eprintln('>>> skipping command test on windows')
		return
	}

	mut cmd := os.start_new_command('ls')!
	for !cmd.eof {
		line := cmd.read_line()
		if line == '' {
			continue
		}
		dump(line)
	}
	cmd.close()!
	assert cmd.exit_code == 0, os.process_exit_code_diagnostics(cmd.exit_code, '0', label: @FN)

	eprintln('-------------------------')
	// This will return a non 0 code
	mut cmd_to_fail := os.start_new_command('ls -M')!
	for !cmd_to_fail.eof {
		line := cmd_to_fail.read_line()
		if line == '' {
			continue
		}
		dump(line)
	}
	cmd_to_fail.close()!
	assert cmd_to_fail.exit_code != 0, os.process_exit_code_diagnostics(cmd_to_fail.exit_code,
		'!= 0', label: @FN) // 2 on linux, 1 on macos
}
