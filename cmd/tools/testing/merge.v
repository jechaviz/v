module testing

import os
import sync.pool

// merge.v - One compilation for the test files of a module.
//
// `v test dir/` compiles every `_test.v` file as its own program, and each of those programs
// re-parses, re-checks and re-generates the whole module under test. For a module with 50 test
// files that is 50 compilations of the same 20000 lines. Test files of a non-main module are in the
// same module, so they can be one file: their imports are hoisted and deduplicated, the rest is
// concatenated, and the result is compiled and run once.
//
// The merge is an optimisation and never a change of verdict:
//   * only plain `_test.v` files of a non-main module with no attributes before the module line and
//     no `// vtest` directives are merged, and only when a directory has at least `merge_min_files`;
//   * if the merged program fails to compile (a helper defined twice in two files, for instance) or a
//     test of it fails, its files are run again one by one, so the report names the real file;
//   * test files that wait on another process (a C compiler, MetaEditor, a child program) are not
//     merged: they run beside the merged program, in parallel, instead of after the other tests;
//   * VTEST_NO_MERGE=1 turns it off.

const merge_min_files = get_merge_min_files()
const merged_prefix = 'zz_vmerged_'

fn get_merge_min_files() int {
	configured := os.getenv('VTEST_MERGE_MIN')
	return if configured == '' { 3 } else { configured.int() }
}

fn merging_disabled(vargs string) bool {
	return os.getenv('VTEST_NO_MERGE') != '' || vargs.contains('fmt') || vargs.contains('vet')
		|| vargs.contains('-check')
}

// heavy_markers are the calls that make a test wait on another process: a C compiler, MetaEditor, a
// child program. Such a test costs seconds of waiting, not of computing, and a merged program runs its
// tests one after the other, so merging it with the others would put that waiting on the critical
// path. Left alone, the pool runs it in parallel with the merged program.
const heavy_markers = ['os.execute(', 'os.new_process(', 'os.exec(', 'compile_mql5(', 'compile_folder(']

// test_file_is_heavy says whether a test file waits on other processes (VTEST_MERGE_HEAVY=1 merges
// them anyway).
fn test_file_is_heavy(file string) bool {
	if os.getenv('VTEST_MERGE_HEAVY') != '' {
		return false
	}
	text := os.read_file(file) or { return false }
	return heavy_markers.any(text.contains(it))
}

// module_of_test returns the module of a test file that is safe to merge, or '' when it is not.
fn module_of_test(file string) string {
	if !file.ends_with('_test.v') || file.ends_with('_test.c.v') || file.ends_with('_test.js.v') {
		return ''
	}
	if os.file_name(file).starts_with(merged_prefix) {
		return ''
	}
	lines := os.read_lines(file) or { return '' }
	for line in lines {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('//') {
			if trimmed.starts_with('// vtest') {
				return ''
			}
			continue
		}
		if trimmed.starts_with('module ') {
			name := trimmed['module '.len..].trim_space()
			return if name == 'main' || name == '' { '' } else { name }
		}
		return '' // an attribute or anything else before the module line
	}
	return ''
}

// merged_source builds the text of the merged test file of a module.
fn merged_source(module_name string, files []string) !string {
	mut imports := []string{}
	mut seen := map[string]bool{}
	mut bodies := []string{}
	for file in files {
		mut past_module := false
		mut body := ['// ---- ${os.file_name(file)}']
		for line in os.read_lines(file)! {
			if !past_module {
				if line.trim_space().starts_with('module ') {
					past_module = true
				}
				continue
			}
			if line.starts_with('import ') {
				key := line.trim_space()
				if key !in seen {
					seen[key] = true
					imports << key
				}
				continue
			}
			body << line
		}
		bodies << body.join('\n')
	}
	return 'module ${module_name}\n\n${imports.join('\n')}\n\n${bodies.join('\n\n')}\n'
}

// MergePlan says which files were replaced by which merged file.
pub struct MergePlan {
pub mut:
	merged map[string][]string // merged file -> the test files it stands for
}

// is_empty says whether nothing was merged.
pub fn (plan MergePlan) is_empty() bool {
	return plan.merged.len == 0
}

// plan_module_merging replaces, in `files`, the test files of each module by one merged file written
// next to them, and returns the new list. Stale merged files from an interrupted run are removed.
pub fn plan_module_merging(files []string, skip_files []string) ([]string, MergePlan) {
	return plan_module_merging_for(files, skip_files, 2)
}

// plan_module_merging_for is plan_module_merging for a runner with `jobs` parallel jobs. Tests that wait
// on other processes are kept aside to run in parallel only when there is more than one job: with a
// single job they would run one after the other anyway, and as separate programs they would also
// pay a compilation each, so they are merged with the rest.
pub fn plan_module_merging_for(files []string, skip_files []string, jobs int) ([]string, MergePlan) {
	mut plan := MergePlan{}
	mut groups := map[string][]string{} // directory + module -> files
	mut module_of := map[string]string{}
	for file in files {
		real := os.real_path(file)
		if real in skip_files {
			continue
		}
		name := module_of_test(file)
		if name == '' {
			continue
		}
		if jobs > 1 && test_file_is_heavy(file) {
			continue // it stays a program of its own, so the pool runs it beside the merged one
		}
		details := get_test_details(file)
		if details.vflags != '' || details.vbuild != '' {
			continue
		}
		key := '${os.dir(real)}|${name}'
		groups[key] << file
		module_of[key] = name
	}
	mut replaced := map[string]string{} // original file -> merged file ('' for the first of its group)
	mut merged_files := []string{}
	for key, members in groups {
		if members.len < merge_min_files {
			continue
		}
		dir := key.all_before('|')
		merged_path := os.join_path(dir, '${merged_prefix}${module_of[key]}_test.v')
		text := merged_source(module_of[key], members) or { continue }
		os.write_file(merged_path, text) or { continue }
		plan.merged[merged_path] = members.clone()
		merged_files << merged_path
		for member in members {
			replaced[member] = merged_path
		}
	}
	mut out := []string{}
	for file in files {
		if file in replaced {
			continue
		}
		if os.file_name(file).starts_with(merged_prefix) {
			os.rm(file) or {}
			continue
		}
		out << file
	}
	out << merged_files
	return out, plan
}

// forget_failure removes the failed commands that mention `file` and returns how many there were.
fn (mut ts TestSession) forget_failure(file string) int {
	mut forgotten := 0
	lock ts.failed_cmds {
		mut kept := []string{}
		for cmd in ts.failed_cmds {
			if cmd.contains(file) {
				forgotten++
			} else {
				kept << cmd
			}
		}
		ts.failed_cmds = kept
	}
	if forgotten > 0 {
		// the merged attempt is not a result: the files it stood for are rerun and counted
		ts.benchmark_mu.lock()
		ts.benchmark.nfail -= forgotten
		ts.benchmark.ntotal -= forgotten
		ts.benchmark_mu.unlock()
	}
	return forgotten
}

// count_merged_passes counts a merged program that passed as the test files it stood for.
fn (mut ts TestSession) count_merged_passes(files int) {
	ts.benchmark_mu.lock()
	ts.benchmark.nok += files - 1
	ts.benchmark.ntotal += files - 1
	ts.benchmark_mu.unlock()
}

// rerun_failed_merges runs, one by one, the files of every merged program that failed to compile or
// had a failing test, so that the report names the real file. A merged program that passed is
// reported with an info line saying how many test files it stood for.
fn (mut ts TestSession) rerun_failed_merges(plan MergePlan, njobs int) {
	mut originals := []string{}
	for merged_path, members in plan.merged {
		mtc := MessageThreadContext{
			file:    merged_path
			flow_id: '-1'
		}
		if ts.forget_failure(os.file_name(merged_path)) == 0 {
			ts.count_merged_passes(members.len)
			ts.append_message(.info, '${os.file_name(merged_path)}: ${members.len} test files of one module compiled and ran as one program',
				mtc)
			continue
		}
		ts.append_message(.info, '${os.file_name(merged_path)} failed: running its ${members.len} test files one by one',
			mtc)
		originals << members
	}
	if originals.len == 0 {
		return
	}
	mut retry_pool := pool.new_pool_processor(
		callback: worker_trunner
		maxjobs:  if originals.len < njobs { originals.len } else { njobs }
	)
	retry_pool.set_shared_context(&ts)
	retry_pool.work_on_pointers(unsafe { originals.pointers() })
}

// remove_merged_files deletes the merged files of a plan.
pub fn (plan MergePlan) remove_merged_files() {
	for merged_path, _ in plan.merged {
		os.rm(merged_path) or {}
	}
}
