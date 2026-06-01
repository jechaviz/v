module checker

import v.ast
import v.token

fn (mut c Checker) warn_clone_alloc_if_needed(method_name string, left_type ast.Type, left_sym ast.TypeSymbol, final_left_sym ast.TypeSymbol, pos token.Pos) {
	if !c.pref.warn_about_allocs || method_name != 'clone' {
		return
	}
	if left_sym.kind == .alias && left_sym.has_method(method_name) {
		return
	}
	clone_kind := match final_left_sym.kind {
		.array { 'array' }
		.array_fixed { 'fixed array' }
		.map { 'map' }
		.string { 'string' }
		else { return }
	}

	type_name := c.table.type_to_str(left_type)
	c.warn_alloc('${clone_kind} clone of `${type_name}`', pos)
}
