module runtime

import os

@[typedef]
pub struct C.MEMORYSTATUS {
	dwLength        u32
	dwMemoryLoad    u32
	dwTotalPhys     usize
	dwAvailPhys     usize
	dwTotalPageFile usize
	dwAvailPageFile usize
	dwTotalVirtual  usize
	dwAvailVirtual  usize
}

fn C.GlobalMemoryStatus(&C.MEMORYSTATUS)

// nr_cpus returns the number of virtual CPU cores found on the system.
pub fn nr_cpus() int {
	sinfo := C.SYSTEM_INFO{}
	C.GetSystemInfo(&sinfo)
	mut nr := int(sinfo.dwNumberOfProcessors)
	if nr == 0 {
		nr = os.getenv('NUMBER_OF_PROCESSORS').int()
	}
	return nr
}

// total_memory returns total physical memory found on the system.
pub fn total_memory() !usize {
	memory_status := windows_memory_status()!
	return memory_status.dwTotalPhys
}

// free_memory returns free physical memory found on the system.
pub fn free_memory() !usize {
	memory_status := windows_memory_status()!
	return memory_status.dwAvailPhys
}

// total_virtual_memory returns the current Windows commit limit
// (physical RAM plus pagefile), not just the per-process address space.
pub fn total_virtual_memory() !usize {
	memory_status := windows_memory_status()!
	return memory_status.dwTotalPageFile
}

// free_virtual_memory returns the remaining Windows commit/pagefile headroom.
pub fn free_virtual_memory() !usize {
	memory_status := windows_memory_status()!
	return memory_status.dwAvailPageFile
}

fn windows_memory_status() !C.MEMORYSTATUS {
	mut memory_status := C.MEMORYSTATUS{}
	memory_status.dwLength = u32(sizeof(C.MEMORYSTATUS))
	C.GlobalMemoryStatus(&memory_status)
	return memory_status
}
