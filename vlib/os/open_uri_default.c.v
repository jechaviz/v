module os

// open_uri opens a given uri.
pub fn open_uri(uri string) ! {
	mut vopen_uri_cmd := getenv('VOPEN_URI_CMD')
	if vopen_uri_cmd == '' {
		$if macos {
			vopen_uri_cmd = 'open'
		} $else $if freebsd || openbsd {
			vopen_uri_cmd = 'xdg-open'
		} $else $if linux {
			providers := ['xdg-open', 'x-www-browser', 'www-browser', 'wslview', 'exo-open']
			// There are multiple possible providers to open a browser on linux
			// One of them is xdg-open, another is x-www-browser, then there's www-browser, etc.
			// Look for one that exists and run it
			for provider in providers {
				if exists_in_system_path(provider) {
					vopen_uri_cmd = provider
					break
				}
			}
		}
	}
	if vopen_uri_cmd == '' {
		return error('unsupported platform')
	}
	cmd := '${vopen_uri_cmd} "${uri}"'
	result := execute(cmd)
	if result.exit_code != 0 {
		return error(result.command_failure_report('os.open_uri',
			reason:  'open_uri_command_failed'
			action:  'inspect_command_and_open_uri_provider'
			message: 'unable to open url'
			command: cmd
		))
	}
}
