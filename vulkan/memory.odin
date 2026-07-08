// TODO)) We don't need this anymore - use external gpu-memory package
package game_vulkan

import "core:mem"
import "core:sync"
import vk "vendor:vulkan"

Gpu_Device :: struct {
    device : ^vk.Device,
    physical : ^vk.PhysicalDevice
}

Gpu_Arena :: struct {
    cmd_buf       : Command_Set,
    current_block : ^Gpu_Memory_Block,
    block_size : int,
    mutex : sync.Mutex,
    queue_families : []u32,
    usage_types : vk.BufferUsageFlags2,
    gpu_device : Gpu_Device,
    type : Arena_Type
}

Gpu_Scratchpad :: struct {
    using arena : Gpu_Arena,
}

Gpu_Memory_Block :: struct {
    prev_block : ^Gpu_Memory_Block,
    buffer : vk.Buffer,
    memory : vk.DeviceMemory,
    current_offset : int,
    size : int,
    block_index : int,
    host_memory : rawptr
}

Gpu_Block_Handle :: distinct int

Gpu_Slice :: struct {
    block : Gpu_Block_Handle,
    offset : int,
    size : int,
    arena : ^Gpu_Arena
}

Arena_Config :: struct {
    queue_families : QueueTypes,
    usage_types : vk.BufferUsageFlags2,
    block_size : int,
    type : Arena_Type
}

Arena_Type :: enum {
    DEVICE,
    HOST,
    DESCRIPTORS
}

get_buffer_device_address :: proc(slice : Gpu_Slice) -> vk.DeviceAddress {
    info : vk.BufferDeviceAddressInfoEXT
    info.sType = .BUFFER_DEVICE_ADDRESS_INFO_EXT
    info.buffer = get_underlying_buffer(slice.arena^, slice.block)

    addr : vk.DeviceAddress = vk.GetBufferDeviceAddressEXT(slice.arena.gpu_device.device^, &info)
    return addr
}

get_device_address :: proc(slice : Gpu_Slice) -> vk.DeviceAddress {
    addr : vk.DeviceAddress = get_buffer_device_address(slice)
    return addr + vk.DeviceAddress(slice.offset)
}

get_host_pointer :: proc(slice : Gpu_Slice) -> rawptr {
    block := slice.arena.current_block
    for {
        if block == nil {
            break
        }

        if int(slice.block) == block.block_index {
            return rawptr(uintptr(block.host_memory) + uintptr(slice.offset))
        }

        block = block.prev_block
    }

    return nil
}

gpu_copy :: proc(cmd : vk.CommandBuffer, dst : Gpu_Slice, src : Gpu_Slice) {
    assert(dst.size == src.size)

    dst_buf := get_underlying_buffer(dst.arena^, dst.block)
    src_buf := get_underlying_buffer(src.arena^, src.block)

    copy_info : vk.BufferCopy
    copy_info.srcOffset = vk.DeviceSize(src.offset)
    copy_info.dstOffset = vk.DeviceSize(dst.offset)
    copy_info.size = vk.DeviceSize(dst.size)

    vk.CmdCopyBuffer(cmd, src_buf, dst_buf, 1, &copy_info)
}

get_underlying_buffer :: proc(arena : Gpu_Arena, block_index: Gpu_Block_Handle) -> vk.Buffer {
    current_block := arena.current_block
    for {
        if current_block == nil {
            break
        }

        if int(block_index) == current_block.block_index {
            return current_block.buffer
        }

        current_block = current_block.prev_block
    }

    return {}
}

slice :: proc(origin : Gpu_Slice, offset, size : int) -> Gpu_Slice{
    new_slice : Gpu_Slice
    new_slice.block = origin.block
    new_slice.offset = origin.offset + offset
    new_slice.size = size
    new_slice.arena = origin.arena

    assert(new_slice.offset > origin.offset)
    assert(new_slice.offset + new_slice.size < origin.offset + origin.size)

    return new_slice
}

create_gpu_arena :: proc(ctx : ^Context, cfg : Arena_Config) -> (arena : Gpu_Arena, ok : bool = true) {
    sync.lock(&arena.mutex)
    defer sync.unlock(&arena.mutex)

    arena.block_size = cfg.block_size
    arena.usage_types = cfg.usage_types
    arena.gpu_device.device = &ctx.device
    arena.gpu_device.physical = &ctx.phys_dev

    queue_fams : ^QueueFamily
    queue_fams, ok = find_queue_family_by_type(ctx, cfg.queue_families)

    if !ok {
        return
    }

    arena.queue_families = {queue_fams.family_idx}
    arena.type = cfg.type

    _allocate_new_block(&arena)
    return
}

destroy_gpu_arena :: proc(arena : ^Gpu_Arena) {
    sync.lock(&arena.mutex)
    defer sync.unlock(&arena.mutex)
    if arena.current_block != nil {
        _free_gpu_memory(arena.gpu_device.device, arena.current_block.buffer, arena.current_block.memory)
        free(arena.current_block)
    }
}

/// reserves a slice of the GPU for the caller
gpu_allocate_unaligned :: proc(arena : ^Gpu_Arena, size : int) -> (Gpu_Slice, bool) {
    sync.lock(&arena.mutex)
    defer sync.unlock(&arena.mutex)

    if arena.current_block == nil {
        if !_allocate_new_block(arena) {
            return {}, false
        }
    }

    if arena.current_block.current_offset + size >= arena.current_block.size {
        if !_allocate_new_block(arena) {
            return {}, false
        }

    }

    slice : Gpu_Slice
    slice.block = Gpu_Block_Handle(arena.current_block.block_index)
    slice.offset = arena.current_block.current_offset
    slice.size = size
    slice.arena = arena

    arena.current_block.current_offset += size

    return slice, true
}

gpu_allocate_aligned :: proc(arena : ^Gpu_Arena, size : int, alignment : int) -> (Gpu_Slice, bool) {
    sync.lock(&arena.mutex)
    defer sync.unlock(&arena.mutex)

    if arena.current_block == nil {
        if !_allocate_new_block(arena) {
            return {}, false
        }
    }

    new_offset := mem.align_forward_int(arena.current_block.current_offset, alignment)

    if new_offset + size >= arena.current_block.size {
        if !_allocate_new_block(arena) {
            return {}, false
        }
    }

    slice : Gpu_Slice
    slice.block = Gpu_Block_Handle(arena.current_block.block_index)
    slice.offset = new_offset
    slice.size = size
    slice.arena = arena

    arena.current_block.current_offset = new_offset + size

    return slice, true
}

gpu_allocate :: proc {
    gpu_allocate_unaligned,
    gpu_allocate_aligned,
}

/// frees all memory for the arena from the GPU
gpu_free_all :: proc(arena : ^Gpu_Arena) {
    sync.lock(&arena.mutex)
    defer sync.unlock(&arena.mutex)

    for arena.current_block != nil && arena.current_block.prev_block != nil {
        block := arena.current_block
        arena.current_block = arena.current_block.prev_block

        _free_gpu_memory(arena.gpu_device.device, block.buffer, block.memory)

        free(block)
    }

    if arena.current_block != nil {
        arena.current_block.current_offset = 0
    }
}


_allocate_new_block :: proc(arena : ^Gpu_Arena) -> (ok : bool = true) {
    gpu_block := new(Gpu_Memory_Block)

    gpu_block.prev_block = arena.current_block
    gpu_block.size = arena.block_size
    gpu_block.current_offset = 0
    if arena.current_block == nil {
        gpu_block.block_index = 0
    } else {
        gpu_block.block_index = arena.current_block.block_index + 1
    }

    switch arena.type {
        case .DEVICE:
            gpu_block.buffer, gpu_block.memory, ok = _allocate_device_local_memory(arena.gpu_device, gpu_block.size, arena.queue_families)
        case .HOST:
            gpu_block.buffer, gpu_block.memory, gpu_block.host_memory, ok = _allocate_host_coherent_memory(arena.gpu_device, gpu_block.size, arena.queue_families)
        case .DESCRIPTORS:

    }

    arena.current_block = gpu_block

    return
}

_allocate_device_local_memory :: proc(gpu : Gpu_Device, size : int, q_fam_indices : []u32) -> (buffer : vk.Buffer, memory : vk.DeviceMemory, ok : bool = true) {
    usage_flags : vk.BufferUsageFlags = {
        .TRANSFER_SRC,
        .TRANSFER_DST,
        .INDIRECT_BUFFER,
        .INDEX_BUFFER,
        .UNIFORM_BUFFER,
        .SHADER_DEVICE_ADDRESS_EXT
    }

    buffer, memory, ok = _allocate_gpu_memory(gpu.device, gpu.physical, size, q_fam_indices, usage_flags, {.DEVICE_LOCAL})
    return
}

_allocate_host_coherent_memory :: proc(gpu : Gpu_Device, size : int, q_fam_indices : []u32) -> (buffer : vk.Buffer, memory : vk.DeviceMemory, scratchpad : rawptr, ok : bool = true) {
    usage_flags : vk.BufferUsageFlags = {
        .TRANSFER_SRC,
        .TRANSFER_DST,
        .INDIRECT_BUFFER,
        .INDEX_BUFFER,
        .UNIFORM_BUFFER,
        .SHADER_DEVICE_ADDRESS_EXT
    }

    buffer, memory, ok = _allocate_gpu_memory(gpu.device, gpu.physical, size, q_fam_indices, usage_flags, {.HOST_COHERENT, .HOST_VISIBLE})

    map_info : vk.MemoryMapInfo
    map_info.sType = .MEMORY_MAP_INFO
    map_info.memory = memory
    map_info.size = vk.DeviceSize(size)
    map_info.offset = 0
    map_info.flags = {}

    res := vk.MapMemory2(gpu.device^, &map_info, &scratchpad)

    if res != .SUCCESS {
        ok = false
    }

    return
}

_allocate_descriptor_memory :: proc(gpu : Gpu_Device, size : int, q_fam_indices : []u32) -> (buffer : vk.Buffer, memory : vk.DeviceMemory, scratchpad : rawptr, ok : bool = true) {
    usage_flags : vk.BufferUsageFlags = {
        .SAMPLER_DESCRIPTOR_BUFFER_EXT,
        .RESOURCE_DESCRIPTOR_BUFFER_EXT,
        .SHADER_DEVICE_ADDRESS_EXT
    }

    buffer, memory, ok = _allocate_gpu_memory(gpu.device, gpu.physical, size, q_fam_indices, usage_flags, {.HOST_COHERENT, .HOST_VISIBLE})

    map_info : vk.MemoryMapInfo
    map_info.sType = .MEMORY_MAP_INFO
    map_info.memory = memory
    map_info.size = vk.DeviceSize(size)
    map_info.offset = 0
    map_info.flags = {}

    res := vk.MapMemory2(gpu.device^, &map_info, &scratchpad)

    if res != .SUCCESS {
        ok = false
    }
    return
}

_allocate_gpu_memory :: proc(
    gpu : ^vk.Device,
    physical_gpu : ^vk.PhysicalDevice,
    size : int,
    family_indices : []u32,
    usage_flags : vk.BufferUsageFlags,
    mem_flags : vk.MemoryPropertyFlags) -> (buffer : vk.Buffer, memory : vk.DeviceMemory, ok : bool = true) {

    create_info : vk.BufferCreateInfo
    create_info.sType = .BUFFER_CREATE_INFO
    create_info.size = vk.DeviceSize(size)
    create_info.usage = usage_flags
    create_info.queueFamilyIndexCount = u32(len(family_indices))
    create_info.pQueueFamilyIndices = &family_indices[0]

    if len(family_indices) > 1 {
        create_info.sharingMode = .CONCURRENT
    } else {
        create_info.sharingMode = .EXCLUSIVE
    }

    res := vk.CreateBuffer(gpu^, &create_info, {}, &buffer)
    
    if res != .SUCCESS {
        ok = false
        return
    }

    mem_req : vk.MemoryRequirements2
    mem_props : vk.PhysicalDeviceMemoryProperties2

    req_info : vk.BufferMemoryRequirementsInfo2
    req_info.sType = .BUFFER_MEMORY_REQUIREMENTS_INFO_2
    req_info.buffer = buffer

    vk.GetBufferMemoryRequirements2(gpu^, &req_info, &mem_req)

    vk.GetPhysicalDeviceMemoryProperties2(physical_gpu^, &mem_props)

    memory_index : u32
    for i in 0..<mem_props.memoryProperties.memoryTypeCount {
        mem_type := mem_props.memoryProperties.memoryTypes[i]
        if (mem_type.propertyFlags & mem_flags) == mem_flags {
            memory_index = i
        }
    }

    mem_alloc_info : vk.MemoryAllocateInfo
    mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    mem_alloc_info.allocationSize = mem_req.memoryRequirements.size
    mem_alloc_info.memoryTypeIndex = memory_index

    res = vk.AllocateMemory(gpu^, &mem_alloc_info, {}, &memory)

    if res != .SUCCESS {
        ok = false
        return
    }

    res = vk.BindBufferMemory(gpu^, buffer, memory, 0)

    if res != .SUCCESS {
        ok = false
    }

    return
}

_free_gpu_memory :: proc(gpu : ^vk.Device, buffer : vk.Buffer, memory : vk.DeviceMemory) {
    vk.FreeMemory(gpu^, memory, {})
    vk.DestroyBuffer(gpu^, buffer, {})
}
