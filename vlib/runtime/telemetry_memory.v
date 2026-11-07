module runtime

fn classify_free_memory_backpressure(free u64, warn u64, hard u64, max_memory u64) MemoryPressure {
	if free == 0 || warn == 0 || hard == 0 || max_memory == 0 {
		return .unknown
	}
	critical_free := memory_headroom(hard, max_memory)
	warn_free := memory_headroom(warn, max_memory)
	if critical_free > 0 && free <= critical_free {
		return .critical
	}
	if warn_free > 0 && free <= warn_free {
		return .pressure
	}
	return .normal
}

fn strongest_memory_pressure(a MemoryPressure, b MemoryPressure) MemoryPressure {
	if memory_pressure_rank(b) > memory_pressure_rank(a) {
		return b
	}
	return a
}

fn memory_pressure_rank(pressure MemoryPressure) int {
	return match pressure {
		.critical { 3 }
		.pressure { 2 }
		.normal { 1 }
		.unknown { 0 }
	}
}

fn memory_effective_headroom(used u64, free u64, hard u64, max_memory u64) u64 {
	used_headroom := memory_headroom(used, hard)
	free_headroom := free_memory_headroom(free, hard, max_memory)
	if free > 0 && hard > 0 && max_memory > 0 {
		return min_u64(used_headroom, free_headroom)
	}
	return used_headroom
}

fn free_memory_headroom(free u64, hard u64, max_memory u64) u64 {
	if free == 0 || hard == 0 || max_memory == 0 || hard >= max_memory {
		return 0
	}
	critical_free := max_memory - hard
	if free <= critical_free {
		return 0
	}
	return free - critical_free
}

fn min_nonzero_u64(a u64, b u64) u64 {
	if a == 0 {
		return b
	}
	if b == 0 {
		return a
	}
	return min_u64(a, b)
}

fn used_virtual_memory(total u64, free u64) u64 {
	if total == 0 || free >= total {
		return 0
	}
	return total - free
}

fn available_memory(free u64, free_virtual u64) u64 {
	return min_nonzero_u64(free, free_virtual)
}

fn runtime_available_memory(snapshot HostTelemetry) u64 {
	if snapshot.available_memory_bytes > 0 {
		return snapshot.available_memory_bytes
	}
	return available_memory(snapshot.free_memory_bytes, snapshot.free_virtual_memory_bytes)
}

fn runtime_backpressure_max_memory(snapshot HostTelemetry, policy MemoryBackpressurePolicy) u64 {
	if policy.max_memory_bytes > 0 {
		return policy.max_memory_bytes
	}
	return min_nonzero_u64(snapshot.total_memory_bytes, snapshot.total_virtual_memory_bytes)
}
