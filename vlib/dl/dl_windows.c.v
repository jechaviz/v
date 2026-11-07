module dl

pub const rtld_now = 0
pub const rtld_lazy = 0
pub const rtld_global = 0
pub const rtld_local = 0
pub const rtld_nodelete = 0
pub const rtld_noload = 0

fn C.LoadLibrary(libfilename &u16) voidptr

fn C.GetProcAddress(handle voidptr, procname &u8) voidptr

fn C.FreeLibrary(handle voidptr) bool

const dl_format_message_allocate_buffer = 0x00000100
const dl_format_message_from_system = 0x00001000
const dl_format_message_ignore_inserts = 0x00000200

type FN_vinit_caller = fn ()

type FN_vcleanup_caller = fn ()

// open loads a given module into the address space of the calling process.
pub fn open(filename string, flags int) voidptr {
	res := C.LoadLibrary(filename.to_wide())
	if res != unsafe { nil } {
		register_interface_exports(res)
	}
	return res
}

// close frees the loaded a given module.
pub fn close(handle voidptr) bool {
	unregister_interface_exports(handle)
	return C.FreeLibrary(handle)
}

// sym returns an address of an exported function or variable from a given module.
pub fn sym(handle voidptr, symbol string) voidptr {
	return C.GetProcAddress(handle, voidptr(symbol.str))
}

// dlerror provides a text error diagnostic message for functions in `dl`.
// It returns a human-readable string, describing the most recent error
// that occurred from a call to one of the `dl` functions, since the last
// call to dlerror().
pub fn dlerror() string {
	// https://docs.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-getlasterror
	// Unlike dlerror(), GetLastError returns just an error code, that is function specific.
	cerr := int(C.GetLastError())
	if cerr == 0 {
		return ''
	}
	error_msg := dl_windows_error_message(cerr)
	return 'dl.error.failed=true\ndl.error.reason=win32_last_error\ndl.error.action=inspect_dynamic_library_or_symbol\ndl.error.message=Windows GetLastError reported a dynamic-loader failure\ndl.error.code=${cerr}\ndl.error.error=${dl_report_value(error_msg)}'
}

fn dl_windows_error_message(code int) string {
	if code <= 0 {
		return ''
	}
	mut msgbuf := voidptr(unsafe { nil })
	C.FormatMessageW(dl_format_message_allocate_buffer | dl_format_message_from_system | dl_format_message_ignore_inserts,
		unsafe { nil }, u32(code), 0, voidptr(&msgbuf), 0, unsafe { nil })
	if msgbuf == 0 {
		return ''
	}
	msg := unsafe { string_from_wide(&u16(msgbuf)) }
	C.LocalFree(msgbuf)
	return msg.trim_space()
}

fn dl_report_value(value string) string {
	return value.replace('\r', '\\r').replace('\n', '\\n')
}
