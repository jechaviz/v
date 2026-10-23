module testing

#define PSAPI_VERSION 2
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <psapi.h>

const process_query_information = 0x0400
const process_query_limited_information = 0x1000
const process_vm_read = 0x0010
const process_set_quota = 0x0100
const process_terminate = 0x0001
const job_object_extended_limit_information = 9
const job_object_limit_process_memory = 0x00000100
const job_object_limit_job_memory = 0x00000200
const job_object_limit_kill_on_job_close = 0x00002000

@[typedef]
pub struct C.PROCESS_MEMORY_COUNTERS {
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

@[typedef]
struct C.LARGE_INTEGER {
	QuadPart i64
}

@[typedef]
struct C.JOBOBJECT_BASIC_LIMIT_INFORMATION {
	PerProcessUserTimeLimit C.LARGE_INTEGER
	PerJobUserTimeLimit     C.LARGE_INTEGER
	LimitFlags              u32
	MinimumWorkingSetSize   usize
	MaximumWorkingSetSize   usize
	ActiveProcessLimit      u32
	Affinity                usize
	PriorityClass           u32
	SchedulingClass         u32
}

@[typedef]
struct C.IO_COUNTERS {
	ReadOperationCount  u64
	WriteOperationCount u64
	OtherOperationCount u64
	ReadTransferCount   u64
	WriteTransferCount  u64
	OtherTransferCount  u64
}

@[typedef]
struct C.JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
	BasicLimitInformation C.JOBOBJECT_BASIC_LIMIT_INFORMATION
	IoInfo                C.IO_COUNTERS
	ProcessMemoryLimit    usize
	JobMemoryLimit        usize
	PeakProcessMemoryUsed usize
	PeakJobMemoryUsed     usize
}

fn C.OpenProcess(u32, bool, u32) voidptr
fn C.K32GetProcessMemoryInfo(voidptr, &C.PROCESS_MEMORY_COUNTERS, u32) bool
fn C.GetLastError() u32
fn C.GetModuleHandleA(name &char) voidptr
fn C.GetProcAddress(handle voidptr, procname &u8) voidptr

type FNCreateJobObjectW = fn (voidptr, voidptr) voidptr

type FNSetInformationJobObject = fn (voidptr, int, voidptr, u32) bool

type FNAssignProcessToJobObject = fn (voidptr, voidptr) bool

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

fn process_guard_job_create_windows(limit_bytes u64) ProcessGuardJob {
	if limit_bytes == 0 {
		return ProcessGuardJob{}
	}
	create_job_ptr := process_guard_kernel32_proc(c'CreateJobObjectW')
	set_info_ptr := process_guard_kernel32_proc(c'SetInformationJobObject')
	if isnil(create_job_ptr) || isnil(set_info_ptr) {
		return ProcessGuardJob{
			enabled:      true
			create_error: C.GetLastError()
		}
	}
	create_job := FNCreateJobObjectW(create_job_ptr)
	set_info := FNSetInformationJobObject(set_info_ptr)
	job := create_job(unsafe { nil }, unsafe { nil })
	if isnil(job) {
		return ProcessGuardJob{
			enabled:      true
			create_error: C.GetLastError()
		}
	}
	mut limits := C.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	limits.BasicLimitInformation.LimitFlags = u32(job_object_limit_process_memory | job_object_limit_job_memory | job_object_limit_kill_on_job_close)
	limits.ProcessMemoryLimit = usize(limit_bytes)
	limits.JobMemoryLimit = usize(limit_bytes)
	if !set_info(job, job_object_extended_limit_information, &limits, u32(sizeof(limits))) {
		error_code := C.GetLastError()
		C.CloseHandle(job)
		return ProcessGuardJob{
			enabled:      true
			create_error: error_code
		}
	}
	return ProcessGuardJob{
		handle:  job
		enabled: true
	}
}

fn process_guard_job_assign_windows(mut job ProcessGuardJob, pid int) {
	if !job.enabled || isnil(job.handle) || pid <= 0 {
		return
	}
	assign_ptr := process_guard_kernel32_proc(c'AssignProcessToJobObject')
	if isnil(assign_ptr) {
		job.assign_error = C.GetLastError()
		return
	}
	assign_to_job := FNAssignProcessToJobObject(assign_ptr)
	access := u32(process_terminate | process_set_quota | process_query_limited_information)
	process_handle := C.OpenProcess(access, false, u32(pid))
	if isnil(process_handle) {
		job.assign_error = C.GetLastError()
		return
	}
	defer {
		C.CloseHandle(process_handle)
	}
	if assign_to_job(job.handle, process_handle) {
		job.assigned = true
		job.assign_error = 0
		return
	}
	job.assign_error = C.GetLastError()
}

fn process_guard_job_close_windows(mut job ProcessGuardJob) {
	if !isnil(job.handle) {
		C.CloseHandle(job.handle)
		job.handle = unsafe { nil }
	}
}

fn process_guard_kernel32_proc(name &char) voidptr {
	kernel32 := C.GetModuleHandleA(c'kernel32.dll')
	if isnil(kernel32) {
		return unsafe { nil }
	}
	return C.GetProcAddress(kernel32, voidptr(name))
}
