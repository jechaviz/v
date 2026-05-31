#!/usr/bin/env -S v -raw-vsh-tmp-prefix tmp

import os
import term

// This script can be used to ensure that all committed V files are vfmt-ed automatically.
// By default, once setup, it will run `v fmt -w` on them, before committing them.

// To use the script in your V project, you need to be in the main folder
// of your project, then do the equivalent of:
// ```sh
// cp /PATH/TO_YOUR/V/cmd/tools/git_pre_commit_hook.vsh .git/hooks/pre-commit
// chmod 755 .git/hooks/pre-commit
// ```
//
// You could also use `vgit-fmt-hook` tool to install/update/remove and get
// status for this hook.
// This tool copies the git hook VSH script in .git/hooks/pre-commit
//
// Note: you can use this command:
// `git config --bool --add hooks.stopCommitOfNonVfmtedVFiles true`
// ... to make it just *prevent* the committing of unformatted .v files,
// i.e. stop the committing, if they are not, but *without modifying them*
// automatically (you will then need to run `v fmt -w` on them manually).
//
// Note 2: Git supports skipping the hooks, by passing the `--no-verify` option.
// That can be used to commit some .v files that are not formatted, without removing
// the hook.

fn main() {
	// This hook cares only about the changed V files, that will be committed, as reported by git itself:
	changed_cmd := 'git diff --cached --name-only --diff-filter=ACMR -- "*.v" "*.vsh" "*.vv"'
	changed := os.execute(changed_cmd)
	if changed.exit_code != 0 {
		eprintln(changed.command_failure_report('v.pre_commit.command',
			reason:  'git_diff_failed'
			action:  'inspect_git_repository_state'
			message: 'pre-commit hook could not list staged V files'
			command: changed_cmd
		))
		exit(1)
	}

	all_changed_vfiles := changed.output.trim_space().split('\n')
	// _input.vv files are NOT formatted on purpose.
	// There is no point in verifying them, or ruining them over with `v fmt -w`.
	// Just filter them out, but still report to the user, that they will not be formatted:
	vfiles := all_changed_vfiles.filter(!it.ends_with('_input.vv'))
	input_vfiles := all_changed_vfiles.filter(it.ends_with('_input.vv'))
	if input_vfiles.len > 0 {
		eprintln('>>> ${input_vfiles.len} `_input.vv` files found, that *will NOT be* formatted.')
		for ifile in input_vfiles {
			eprintln('     ${ifile}')
		}
	}
	if changed.output == '' || vfiles.len == 0 {
		eprintln('>>> 0 changed V files, that may need formatting found.')
		exit(0)
	}
	configured_stop_committing := os.execute('git config --bool hooks.stopCommitOfNonVfmtedVFiles')
	if configured_stop_committing.output.trim_space().bool() {
		verify_cmd := '${os.quoted_path(@VEXE)} fmt -verify ${vfiles.join(' ')}'
		verify_result := os.execute(verify_cmd)
		if verify_result.exit_code != 0 {
			eprintln(verify_result.command_failure_report('v.pre_commit.command',
				reason:  'fmt_verify_failed'
				action:  'run_v_fmt_write_and_stage_changes'
				message: 'pre-commit formatting verification failed'
				command: verify_cmd
			))
		}
		exit(verify_result.exit_code)
	} else {
		eprintln('The V pre commit hook will format ${vfiles.len} V file(s):')
		// vfmt off
		for vfile in vfiles {
			eprintln('    ${term.bold('${vfile}')}')
		}
		// vfmt on
		all_vfiles_on_a_line := vfiles.map(os.quoted_path(it)).join(' ')
		fmt_cmd := '${os.quoted_path(@VEXE)} fmt -w ${all_vfiles_on_a_line}'
		fmt_exit_code := os.system(fmt_cmd)
		if fmt_exit_code != 0 {
			eprintln(os.process_command_failure_report('v.pre_commit.command', fmt_exit_code,
				reason:         'fmt_write_failed'
				action:         'inspect_formatter_output'
				message:        'pre-commit hook failed while formatting staged V files'
				command:        fmt_cmd
				output_capture: 'inherited_stdio'
			))
			exit(fmt_exit_code)
		}
		git_add_cmd := 'git add ${all_vfiles_on_a_line}'
		git_add_exit_code := os.system(git_add_cmd)
		if git_add_exit_code != 0 {
			eprintln(os.process_command_failure_report('v.pre_commit.command', git_add_exit_code,
				reason:         'git_add_failed'
				action:         'inspect_git_repository_state'
				message:        'pre-commit hook failed while staging formatted V files'
				command:        git_add_cmd
				output_capture: 'inherited_stdio'
			))
			exit(git_add_exit_code)
		}
	}
}
