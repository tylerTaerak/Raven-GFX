package game_vulkan

import "core:mem"
import "core:slice"
import "core:log"
import vk "vendor:vulkan"

Buffer :: struct ($T: typeid) {
    buf             : vk.Buffer,
    mem             : vk.DeviceMemory,
    size            : vk.DeviceSize,

    type            : T,
    count           : int,
    element_size    : int
}

Host_Buffer :: struct ($T: typeid) {
    internal_buffer : Buffer(T),
    data_ptr        : rawptr
}

Buffer_Slice :: struct ($T: typeid) {
    buffer      : ^Buffer(T),
    offset      : vk.DeviceSize,
    size        : vk.DeviceSize
}

create_buffer :: proc(
    ctx: ^Context,
    $T: typeid,
    element_count: int,
    queue_families : []QueueFamily,
    usage_flags: vk.BufferUsageFlags,
    memory_flags: vk.MemoryPropertyFlags) -> (buf : Buffer(T)) {

    create_info : vk.BufferCreateInfo
    create_info.sType = .BUFFER_CREATE_INFO
    create_info.size = vk.DeviceSize(element_count * size_of(T))
    create_info.usage = usage_flags
    create_info.queueFamilyIndexCount = u32(len(queue_families))
    
    queues := make([]u32, len(queue_families))
    defer delete(queues)
    for i in 0..<len(queue_families) {
        queues[i] = queue_families[i].family_idx
    }

    create_info.pQueueFamilyIndices = &queues[0]
    if len(queues) > 1 {
        create_info.sharingMode = .CONCURRENT
    } else {
        create_info.sharingMode = .EXCLUSIVE
    }
    
    vk.CreateBuffer(ctx.device, &create_info, {}, &buf.buf)

    buf.size = vk.DeviceSize(initial_capacity)

    mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device, buf.buf, &mem_req)

    mem_props : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(ctx.phys_dev, &mem_props)

    buf_mem_idx, staging_mem_idx : u32
    for i in 0..<mem_props.memoryTypeCount {
        mem_type := mem_props.memoryTypes[i]
        if (mem_type.propertyFlags & memory_flags) == memory_flags {
            buf_mem_idx = i
        }
    }

    buf_alloc_info : vk.MemoryAllocateInfo
    buf_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    buf_alloc_info.allocationSize = mem_req.size
    buf_alloc_info.memoryTypeIndex = buf_mem_idx

    vk.AllocateMemory(ctx.device, &buf_alloc_info, {}, &buf.mem)

    vk.BindBufferMemory(ctx.device, buf.buf, buf.mem, 0)

    // this is just for staging buffers that need host coherent memory
    // vk.MapMemory(ctx.device, buf.staging_mem, 0, staging_mem_req.size, {}, &buf.host_data)

    return
}

create_host_buffer :: proc(
    ctx: ^Context,
    $T: typeid,
    element_count: int,
    queue_families : []QueueFamily,
    usage_flags: vk.BufferUsageFlags, // this might be able to just be TRANSFER_SRC... we'll see if we need the ability to change this later
    ) -> (buf: Host_Buffer(T)) {

    buf.internal_buffer = create_buffer(ctx, T, element_count, queue_families, usage_flags, {.HOST_VISIBLE, .HOST_COHERENT})
    vk.MapMemory(ctx.device, buf.internal_buffer.mem, 0, buf.internal_buffer.size, {}, &buf.data_ptr)
    
    return
}

/* Slice Creation */

make_slice_from_indicies :: proc(buffer: ^$T/Buffer($E), start, end: int) -> (slice : Buffer_Slice(E)) {
    assert(end > start)

    size := vk.DeviceSize(end - start)

    slice = make_slice_from_size_and_offset(buffer, vk.DeviceSize(start), size)

    return
}

make_slice_from_size_and_offset :: proc(buffer: ^$T/Buffer($E), offset, size: vk.DeviceSize) -> (slice : Buffer_Slice(E)) {
    assert(size <= buffer.size)

    slice.buffer    = buffer
    slice.offset    = offset
    slice.size      = size

    return
}

make_slice_from_slice_and_indicies :: proc(src: ^$T/Buffer_Slice($E), start, end: int) -> (slice : Buffer_Slice(E)) {
    assert(end > start)
    assert(end < int(src.size))

    size := vk.DeviceSize(end - start)

    slice = make_slice_from_slice_and_size_and_offset(src, vk.DeviceSize(start), size)

    return
}

make_slice_from_slice_and_size_and_offset :: proc(src: ^$T/Buffer_Slice($E), offset, size: vk.DeviceSize) -> (slice : Buffer_Slice(E)) {
    assert(offset + size <= src.size)

    slice.buffer = src.buffer
    slice.offset = src.offset + offset
    slice.size = size

    return
}

make_slice :: proc{
    make_slice_from_indicies,
    make_slice_from_size_and_offset,
    make_slice_from_slice_and_indicies,
    make_slice_from_slice_and_size_and_offset,
}

copy_buffer_data :: proc(command_buf: vk.CommandBuffer, src, dest: ^$T/Buffer_Slice($E)) {
    assert(src.size == dest.size)

    copy_info : vk.BufferCopy
    copy_info.srcOffset = src.offset
    copy_info.dstOffset = dest.offset
    copy_info.size = dest.size

    vk.CmdCopyBUffer(command_buf, src.buffer.buf, dest.buffer.buf, 1, &copy_info)
}

destroy_host_buffer :: proc(ctx: ^Context, buffer: $T/Host_Buffer($E)) {
    destroy_buffer(buffer.internal_buffer)
}

destroy_buffer :: proc(ctx: ^Context, buffer: $T/Buffer($E)) {
    vk.FreeMemory(ctx.device, buffer.mem, {})
    vk.DestroyBuffer(ctx.device, buffer.buf, {})
}
