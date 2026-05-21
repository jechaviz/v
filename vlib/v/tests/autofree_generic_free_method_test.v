// vtest build: !sanitize-address-gcc && !sanitize-address-clang
// vtest vflags: -autofree
@[has_globals]
module main

__global (
	freed_boxes int
)

struct GenericBox[T] {
	value T
}

fn make_box(value string) GenericBox[string] {
	return GenericBox[string]{
		value: value
	}
}

fn (_ &GenericBox[T]) free() {
	unsafe {
		freed_boxes++
	}
}

fn run_generic_autofree_case() {
	make_box('kept until scope cleanup')
}

fn test_autofree_calls_generic_parent_free_method() {
	unsafe {
		freed_boxes = 0
	}
	run_generic_autofree_case()
	assert unsafe { freed_boxes } == 1
}

fn make_heap_box(value string) &GenericBox[string] {
	return &GenericBox[string]{
		value: value
	}
}

fn run_generic_pointer_autofree_case() {
	box := make_heap_box('heap value')
	assert box.value == 'heap value'
}

fn test_autofree_calls_generic_parent_free_method_for_pointer_var() {
	unsafe {
		freed_boxes = 0
	}
	run_generic_pointer_autofree_case()
	assert unsafe { freed_boxes } == 1
}
