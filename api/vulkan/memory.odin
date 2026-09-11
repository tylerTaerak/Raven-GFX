package game_vulkan

import "core:sync"
import vk "vendor:vulkan"
import "core:mem"

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


// TODO)) Should I just be treating each and every allocation as if it's its own arena?
// Or should buffers get their own arena-style allocator on top of this memory one?
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
	block 		: ^Device_Allocation(Location),
	raw 		: ^Raw_Allocation,
	host_ptr 	: rawptr // Only populated if Location == .HOST
}

Memory :: vk.DeviceMemory

create_device_memory :: proc(
	device : Device,
	$Location : Allocation_Location,
	) -> (mem : ^Device_Allocation(Location), ok : bool = true) {

	m3_props : vk.PhysicalDeviceMaintenance3Properties
	m3_props.sType = .PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES

	dev_props : vk.PhysicalDeviceProperties2
	dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2
	dev_props.pNext = &m3_props

	vk.GetPhysicalDeviceProperties2(device.physical, &dev_props)

	mem = new(Device_Allocation(Location))

	mem.granularity = u32(dev_props.properties.limits.bufferImageGranularity)
	allocation_size := m3_props.maxMemoryAllocationSize

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
	info.allocationSize = allocation_size

	res := vk.AllocateMemory(device.core, &info, {}, &mem.vkmem)

	ok = res == .SUCCESS

	return
}

allocate_memory :: proc(
	device : Device,
	memory : ^$T/Device_Allocation($L),
	type : Allocation_Type,
	size : u32,
	alignment : u32 = 1) -> (new_allocation : Allocation(L), ok : bool = true) {
	assert(size > 0)

	sync.lock(&memory.lock)
	defer sync.unlock(&memory.lock)

	for &alloc, i in memory.allocations {
		if !alloc.is_free do continue

		offset := mem.align_forward_int(alloc.offset, int(alignment))

		if i > 0 {
			prev := memory.allocations[i - 1]
			if prev.is_free &&
				type != prev.type &&
				u32(offset - alloc.offset) < memory.granularity {

				offset  = mem.align_forward_int(alloc.offset + int(memory.granularity), int(alignment))
			}
		}

		lead := offset - alloc.offset
		if lead < 0 || alloc.size - lead < int(size) do continue

		end := offset + int(size)
		trail := (alloc.offset + alloc.size) - end

		if i + 1 < len(memory.allocations) {
			next := memory.allocations[i+1]
			if next.is_free &&
				type != next.type &&
				trail < int(memory.granularity) {

				continue
			}
		}

		new_raw : Raw_Allocation

		new_raw.offset = offset
		new_raw.size = int(size)
		new_raw.is_free = false
		new_raw.type = type

		new_allocation.block = memory

		end_alloc : Raw_Allocation
		end_alloc.offset = end
		end_alloc.size = trail
		end_alloc.is_free = true
		end_alloc.type = type


		if lead > 0 {
			alloc.size = lead
			inject_at(&memory.allocations, i + 1, new_raw)
			new_allocation.raw = &memory.allocations[len(memory.allocations) - 1]
			if trail > 0 {
				inject_at(&memory.allocations, i + 2, end_alloc)
			}
		} else if trail > 0 {
			alloc = new_raw
			new_allocation.raw = &alloc
			inject_at(&memory.allocations, i + 1, end_alloc)
		} else {
			alloc = new_raw
			new_allocation.raw = &alloc
		}

		map_memory_if_possible(device, &new_allocation)

		return
	}

	offset := int(memory.current_offset)
	offset = mem.align_forward_int(offset, int(alignment))

	if len(memory.allocations) > 0 {
		prev := memory.allocations[len(memory.allocations) - 1]
		if prev.is_free &&
			type != prev.type &&
			u32(offset - prev.offset) < memory.granularity {

			offset = mem.align_forward_int(prev.offset + int(memory.granularity), int(alignment))
		}
	}

	if u32(offset) + size > memory.capacity {
		when L == .HOST {
			ok = false
			// we don't want things growing for our host memory scratchpad - 
			// that's on the developers to manage their resources better
			return
		}

		// create a new device memory block 
		old_memory := memory
		new_memory := create_device_memory(device, L) or_return
		new_memory.prev_block = old_memory
		memory^ = new_memory^

		offset = 0
	}

	lead := offset - int(memory.current_offset)

	if lead > 0 {
		inter_alloc : Raw_Allocation
		inter_alloc.offset = int(memory.current_offset)
		inter_alloc.size = lead
		inter_alloc.is_free = true
		inter_alloc.type = type

		append(&memory.allocations, inter_alloc)
	}

	new_allocation.block = memory

	raw : Raw_Allocation
	raw.offset = offset
	raw.size = int(size)
	raw.type = type
	raw.is_free = false

	append(&memory.allocations, raw)
	new_allocation.raw = &memory.allocations[len(memory.allocations) - 1]

	map_memory_if_possible(device, &new_allocation)

	memory.current_offset = u32(offset) + size

	return
}

suballocate :: proc(
	origin : $T/Allocation($L),
	offset, size : u32) -> (subslice : Allocation(L), ok : bool = true) {
	if offset + size < u32(origin.raw.size) {
		ok = false
		return
	}

	subslice.block = origin.block
	subslice.raw.is_free = origin.raw.is_free
	subslice.raw.size = int(size)
	subslice.raw.offset = subslice.raw.offset + int(offset)

	if origin.host_ptr != nil {
		subslice.host_ptr = rawptr(
			uintptr(origin.host_ptr) + uintptr(offset)
		)
	}

	return
}

memalloc :: proc{
	allocate_memory,
	suballocate,
}

memfree :: proc(slice : ^$T/Allocation($L)) {
	slice.raw.is_free = true
}

destroy_device_memory :: proc(device : Device, memory : ^$T/Device_Allocation($L)) {
	mem_block := memory
	for mem_block.prev_block != nil {
		vk.FreeMemory(device.core, mem_block.vkmem, {})
		delete(mem_block.allocations)

		mem_block = mem_block.prev_block

		free(mem_block)
	}
}

map_memory_if_possible :: proc(device : Device, slice : ^$T/Allocation($L)) -> bool{
	when L == .HOST {
		map_info : vk.MemoryMapInfo
		map_info.sType = .MEMORY_MAP_INFO
		map_info.memory = slice.block.vkmem
		map_info.size = vk.DeviceSize(slice.raw.size)
		map_info.offset = vk.DeviceSize(slice.raw.offset)
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

