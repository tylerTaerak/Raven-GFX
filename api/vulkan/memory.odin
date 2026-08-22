package game_vulkan

import "core:sync"
import vk "vendor:vulkan"

// Now, we're going to just move the entire memory library here and
// use the GPU device as the allocation manager - scopes are handled
// further up the chain

MEMORY_ALLOCATION_SIZE :: 250_000_000

Allocation_Location :: enum {
	DEVICE,
	HOST
}

Allocation_Type :: enum {
	BUFFER,
	IMAGE
}


Device_Allocation :: struct ($Location: Allocation_Location) {
	vkmem 			: vk.DeviceMemory,
	lock 			: sync.Mutex,
	allocations 	: [dynamic]Raw_Allocation,
	prev_block 		: ^Device_Allocation(Location),
	current_offset 	: u32,
	capacity 		: u32,
	granularity		: u32
}

Raw_Allocation :: struct {
	offset 	: int,
	size 	: int,
	type 	: Allocation_Type,
	is_free : bool
}

Allocation :: struct ($Location: Allocation_Location) {
	block 		: ^Memory,
	raw 		: ^Raw_Allocation,
	host_ptr 	: rawptr // Only populated if Location == .HOST
}

Memory :: vk.DeviceMemory

create_device_memory :: proc(
	device : Device,
	$Location : Allocation_Location,
	size : u32 = MEMORY_ALLOCATION_SIZE
	) -> (mem : Device_Allocation(Location), ok : bool = true) {
	assert(size > 0)

	dev_props : vk.PhysicalDeviceProperties2
	dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2

	vk.GetPhysicalDeviceProperties2(device.core, &dev_props)

	mem.granularity = dev_props.properties.limits.bufferImageGranularity

	mem_flags : vk.MemoryPropertyFlags

	switch Location {
		case .DEVICE:
			mem_flags = {.DEVICE_LOCAL}
		case .HOST:
			mem_flags = {.HOST_VISIBLE, .HOST_COHERENT}
	}

	mem_props : vk.PhysicalDeviceMemoryProperties2
	mem_props.sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2

	vk.GetPhysicalDeviceMemoryProperties2(device.physical, &mem_props)

	type_index : u32
	for i in 0..<mem_props.memoryProperties.memoryTypeCount {
		mem_type := mem_props.memoryProperties.memoryTypes[i]
		if (mem_type.propertyFlags & mem_flags) == mem_flags {
			type_index = i
		}
	}

	info : vk.MemoryAllocateInfo
	info.sType = .MEMORY_ALLOCATE_INFO
	info.memoryTypeIndex = type_index
	info.allocationSize = vk.DeviceSize(size)

	res := vk.AllocateMemory(device.core, &info, {}, &mem)

	ok = res == .SUCCESS

	return
}

allocate_memory :: proc(
	device : Device,
	memory : ^$T/Device_Allocation($L),
	type : Allocation_Type,
	size : u32,
	alignment : int = 1) -> (mem : Allocation(L), ok : bool = true) {
	assert(size > 0)

	sync.lock(&memory.mutex)
	defer sync.unlock(&memory.mutex)

	for &alloc, i in memory.allocations {
		if !alloc.is_free do continue

		offset := mem.align_forward_int(alloc.offset, alignment)

		if i > 0 {
			prev := memory.allocations[i - 1]
			if prev.is_free &&
				type != prev.type &&
				offset - alloc.offset < memory.granularity {

				offset  = mem.align_forward_int(alloc.offset + memory.granularity, alignment)
			}
		}

		lead := offset - alloc.offset
		if lead < 0 || alloc.size - lead < size do continue

		end := offset + size
		trail := (alloc.offset + alloc.size) - end

		if i + 1 < len(memory.allocations) {
			next := memory.allocations[i+1]
			if next.is_free &&
				type != next.type &&
				trail < memory.granularity {

				continue
			}
		}

		mem.raw.offset = offset
		mem.raw.size = size
		mem.raw.is_free = false
		mem.raw.type = type
		mem.block = memory

		end_alloc : Raw_Allocation
		end_alloc.offset = end
		end_alloc.size = trail
		end_alloc.is_free = true
		end_alloc.type = type


		if lead > 0 {
			alloc.size = lead
			inject_at(&memory.allocations, i + 1, mem.raw)
			if trail > 0 {
				inject_at(&memory.allocations, i + 2, end_alloc)
			}
		} else if trail > 0 {
			alloc = mem.raw
			inject_at(&memory.allocations, i + 1, end_alloc)
		} else {
			alloc = mem.raw
		}

		map_memory_if_possible(device, &mem)

		return
	}

	offset = memory.current_offset
	offset = mem.align_forward_int(offset, alignment)

	if len(memory.allocations) > 0 {
		prev := memory.allocations[len(memory.allocations) - 1]
		if prev.is_free &&
			type != prev.type &&
			offset - alloc.offset < memory.granularity {

			offset = mem.align_forward_int(alloc.offset + memory.granularity, alignment)
		}
	}

	if offset + size > memory.capacity {
		ok = false
		return
	}

	lead := offset - memory.current_offset

	if lead > 0 {
		inter_alloc : Raw_Allocation
		inter_alloc.offset = memory.current_offset
		inter_alloc.size = lead
		inter_alloc.is_free = true
		inter_alloc.type = type

		append(&memory.allocations, inter_alloc)
	}

	mem.block = memory
	mem.raw.offset = offset
	mem.raw.size = size
	mem.raw.type = type
	mem.raw.is_free = false

	map_memory_if_possible(device, &mem)

	append(&memory.allocations, mem.raw)

	memory.current_offset = offset + size

	return
}

free_memory :: proc(device : Device, memory : Memory) {

	vk.FreeMemory(device.core, memory, {})
}

map_memory_if_possible :: proc(device : Device, slice : ^$T/Allocation($L)) -> bool{
	when L == .HOST {
		map_info : vk.MemoryMapInfo
		map_info.sType = .MEMORY_MAP_INFO
		map_info.memory = memory.memory
		map_info.size = slice.raw.size
		map_info.offset = slice.raw.offset
		map_info.flags = {}

		res := vk.MapMemory2(device.core, &map_info, &slice.host_ptr)

		if res != .SUCCESS {
			return false
		}

		return true
	} else {
		// ignore for device-only memory
		return true
	}
}

