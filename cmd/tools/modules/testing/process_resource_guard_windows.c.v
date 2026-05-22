module testing

#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>

const process_query_information = 0x0400
const process_query_limited_information = 0x1000
const process_vm_read = 0x0010

@[typedef]
struct C.PROCESS_MEMORY_COUNTERS {
	cb                         u32
	PageFaultCount             u32
	PeakWorkingSetSize         usize
	WorkingSetSize             usize
	QuotaPeakPagedPoolUsage    usize
	QuotaPagedPoolUsage        usize
	QuotaPeakNonPagedPoolUsage usize
	QuotaNonPagedPoolUsage     usize
	PagefileUsage              usize
	PeakPagefileUsage          usize
}

fn C.OpenProcess(u32, bool, u32) voidptr
fn C.K32GetProcessMemoryInfo(voidptr, &C.PROCESS_MEMORY_COUNTERS, u32) bool

fn child_process_memory_bytes_windows(pid int) u64 {
	if pid <= 0 {
		return 0
	}
	access := u32(process_query_limited_information | process_query_information | process_vm_read)
	handle := C.OpenProcess(access, false, u32(pid))
	if isnil(handle) {
		return 0
	}
	defer {
		C.CloseHandle(handle)
	}
	mut pmc := C.PROCESS_MEMORY_COUNTERS{}
	pmc.cb = u32(sizeof(pmc))
	if C.K32GetProcessMemoryInfo(handle, &pmc, pmc.cb) {
		if pmc.PagefileUsage > 0 {
			return u64(pmc.PagefileUsage)
		}
		return u64(pmc.WorkingSetSize)
	}
	return 0
}
