module c

import v.flat
import os
import v.types

// set_trace_calls configures V1-compatible function-entry tracing. This is
// separate from the user-provided call-site hooks enabled with `-d trace`.
pub fn (mut g FlatGen) set_trace_calls(enabled bool, patterns []string) {
	g.is_trace_calls = enabled
	g.trace_fns = patterns.clone()
}

// set_trace_lines enables automatic V source-statement tracing.
pub fn (mut g FlatGen) set_trace_lines(enabled bool) {
	g.is_trace_lines = enabled
}

fn trace_fn_matches(patterns []string, module_name string, fn_name string) bool {
	if patterns.len == 0 {
		return true
	}
	for pattern in patterns {
		if fn_name.match_glob(pattern)
			|| (module_name.len > 0 && (module_name.match_glob(pattern)
				|| fn_name.all_after_last('.').match_glob(pattern))) {
			return true
		}
	}
	return false
}

fn trace_qualified_fn_name(module_name string, fn_name string) string {
	if module_name == 'builtin' {
		return fn_name.trim_string_left('builtin.')
	}
	mod := if module_name.len == 0 { 'main' } else { module_name }
	return if fn_name.starts_with('${mod}.') { fn_name } else { '${mod}.${fn_name}' }
}

// A user module named trace_calls makes the loader retain the canonical name
// v.trace_calls for the tracing runtime instead of its declared short name.
fn (g &FlatGen) trace_runtime_module_name() string {
	if 'v.trace_calls.g_stack_base' in g.global_types {
		return 'v.trace_calls'
	}
	return 'trace_calls'
}

fn (mut g FlatGen) gen_trace_fn_begin(node flat.Node, module_name string) {
	if !g.is_trace_calls || module_name == g.trace_runtime_module_name() {
		return
	}
	mut arity := 0
	for i in 0 .. node.children_count {
		if g.a.child_node(&node, i).kind == .param {
			arity++
		}
	}
	mod := if module_name.len == 0 { 'main' } else { module_name }
	name := trace_qualified_fn_name(mod, node.value)
	g.gen_trace_call('${mod} ${name}/${arity}', mod, name)
}

fn (mut g FlatGen) gen_trace_call(label string, module_name string, fn_name string) {
	if !g.is_trace_calls || !trace_fn_matches(g.trace_fns, module_name, fn_name) {
		return
	}
	runtime := g.fn_c_name_in_module(g.trace_runtime_module_name(), 'on_call')
	// Lifecycle functions are emitted after the literal table. Use a literal
	// compound value rather than interning a string too late (also fork-safe).
	g.writeln('${runtime}((string){(u8*)"${c_escape(label)}", ${label.len}, 1});')
}

fn (mut g FlatGen) gen_trace_line(node flat.Node) {
	if !g.is_trace_lines || g.cur_fn_name.len == 0
		|| g.tc.cur_module == g.trace_runtime_module_name()
		|| node.kind !in [.expr_stmt, .assign, .decl_assign, .selector_assign, .index_assign,
			.return_stmt, .if_expr, .for_stmt, .for_in_stmt, .break_stmt, .continue_stmt, .match_stmt,
			.match_branch, .defer_stmt, .assert_stmt, .goto_stmt, .label_stmt, .select_stmt,
			.select_branch, .comptime_if, .comptime_for, .asm_stmt, .debugger_stmt] {
		return
	}
	statement_pos := g.statement_start_pos(node)
	position := g.a.source_position(statement_pos) or { return }
	module_name := if g.tc.cur_module.len == 0 { 'main' } else { g.tc.cur_module }
	function_name := trace_qualified_fn_name(module_name, g.cur_fn_name)
	if !trace_fn_matches(g.trace_fns, module_name, function_name) {
		return
	}
	path := os.real_path(position.filename).replace('\\', '/')
	line := position.line.str()
	source := limit_trace_source(g.trace_source_line(int(statement_pos.id),
		int(statement_pos.offset)))
	runtime := g.fn_c_name_in_module(g.trace_runtime_module_name(), 'on_line')
	g.writeln('${runtime}((string){(u8*)"${c_escape(path)}", ${path.len}, 1}, (string){(u8*)"${line}", ${line.len}, 1}, (string){(u8*)"${c_escape(source)}", ${source.len}, 1}, (string){(u8*)"${c_escape(function_name)}", ${function_name.len}, 1});')
}

fn (mut g FlatGen) trace_source_line(file_id int, offset int) string {
	lines := if cached := g.trace_source_lines[file_id] {
		cached
	} else {
		source := g.a.source_texts[file_id] or { return '' }
		mut starts := [0]
		for i, ch in source {
			if ch == `\n` {
				starts << i + 1
			}
		}
		cached := TraceSourceLines{
			lines:  source.split_into_lines()
			starts: starts
		}
		g.trace_source_lines[file_id] = cached
		cached
	}
	mut low := 0
	mut high := lines.starts.len
	for low < high {
		middle := (low + high) / 2
		if lines.starts[middle] <= offset {
			low = middle + 1
		} else {
			high = middle
		}
	}
	line_index := low - 1
	if line_index < 0 || line_index >= lines.lines.len {
		return ''
	}
	return lines.lines[line_index].trim_space()
}

fn limit_trace_source(source string) string {
	runes := source.runes()
	if runes.len > 240 {
		return runes[..240].string() + '…'
	}
	return source
}

fn (mut g FlatGen) gen_trace_values(node flat.Node) {
	if !g.is_trace_lines || g.cur_fn_name.len == 0
		|| g.tc.cur_module == g.trace_runtime_module_name()
		|| node.kind !in [.expr_stmt, .assign, .decl_assign, .selector_assign, .index_assign, .if_expr,
			.for_stmt, .for_in_stmt, .match_stmt, .select_stmt, .assert_stmt] {
		return
	}
	module_name := if g.tc.cur_module.len == 0 { 'main' } else { g.tc.cur_module }
	function_name := trace_qualified_fn_name(module_name, g.cur_fn_name)
	if !trace_fn_matches(g.trace_fns, module_name, function_name) {
		return
	}
	runtime := g.fn_c_name_in_module(g.trace_runtime_module_name(), 'on_value')
	for variable in g.debugger_scope_vars() {
		if types.unwrap_pointer(variable.typ).name().contains('snoop.Tracer') {
			continue
		}
		mut value_type := variable.typ
		mut expr := g.debugger_var_expr(variable.name)
		if semantic_type := g.local_indirect_value_type(variable.name) {
			value_type = semantic_type
			expr = '*(${expr})'
		} else if g.local_storage_needs_implicit_deref(variable.name) {
			expr = '*(${expr})'
		} else if g.current_param_is_mut(variable.name) {
			expr = '*(${expr})'
			if variable.typ is types.Pointer && !(g.cur_explicit_mut_pointer_params[variable.name] or { false }) {
				value_type = variable.typ.base_type
			}
		}
		mut stack := []InterfaceStringifyVisit{}
		value_expr := g.interface_implicit_str_expr(value_type, expr, false, mut stack) or {
			g.interface_str_lit('<value>')
		}
		name := debugger_string_literal('${function_name}.${variable.name}')
		g.writeln('${runtime}(${name}, ${value_expr});')
	}
}

fn (mut g FlatGen) gen_trace_startup() {
	if !g.is_trace_calls {
		return
	}
	mod := g.trace_runtime_module_name()
	stack_base := g.global_c_name('${mod}.g_stack_base')
	start_time := g.global_c_name('${mod}.g_start_time')
	on_main := g.fn_c_name_in_module(mod, 'on_c_main')
	trace_main := trace_fn_matches(g.trace_fns, '', 'C.main')
	// Keep the anchor in the entry frame, not in on_c_main's temporary frame.
	// The guard also avoids a second header for exported callbacks initialized
	// before the synthesized main function.
	g.writeln('volatile u8 _v_trace_stack_base = 0;')
	g.writeln('if (!${start_time}) {')
	g.writeln('${stack_base} = (u8*)&_v_trace_stack_base;')
	g.writeln('${on_main}(${trace_main});')
	g.writeln('}')
}
