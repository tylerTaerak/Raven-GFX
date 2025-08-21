package game_vulkan

import vk "vendor:vulkan"

Buffer :: struct {
    buf         : vk.Buffer,
    mem         : vk.DeviceMemory,
    size        : vk.DeviceSize,
    chunks      : [dynamic]Buffer_Chunk,
    chunk_map   : map[Chunk_Handle]int
}

Buffer_Chunk :: struct {
    size            : vk.DeviceSize,
    capacity        : vk.DeviceSize,
    offset          : vk.DeviceSize,
    element_size    : int,
    index_map       : map[Element_Handle]int
}

Chunk_Handle :: distinct int

Element_Handle :: distinct int

Staging_Buffer :: struct {
    host_buffer : Buffer,
    device_buffer : ^Buffer,
    host_data : rawptr
}

Buffer_Slice :: struct {
    buffer : ^Buffer,
    offset : vk.DeviceSize,
    size   : vk.DeviceSize
}

Buffer_Copy_Op :: struct {
    source              : Buffer_Slice,
    dest                : Buffer_Slice,
    size                : vk.DeviceSize,
    free_source_buffer  : bool
}

Buffer_Write_Op :: struct {
    buffer : ^Buffer,
    chunk  : ^Buffer_Chunk,
    data   : []byte
}

Buffer_Free_Op :: struct {
    buffer : ^Buffer
}

Buffer_Op :: union {
    Buffer_Copy_Op,
    Buffer_Write_Op,
    Buffer_Free_Op
}

Buffer_Copy_Queue :: [dynamic]Buffer_Copy_Op

Buffer_Op_Queue :: [dynamic]Buffer_Op

_create_buffer_with_mem_flags :: proc(ctx : ^Context, initial_capacity : int, memory_flags : vk.MemoryPropertyFlags, queue_families : ..QueueFamily) -> (buf : Buffer) {
    create_info : vk.BufferCreateInfo
    create_info.sType = .BUFFER_CREATE_INFO
    create_info.size = vk.DeviceSize(initial_capacity)
    create_info.usage = {.STORAGE_BUFFER}
    create_info.queueFamilyIndexCount = u32(len(queue_families))

    q_dyn : [dynamic]u32
    defer delete(q_dyn)
    if len(queue_families) > 1 {
        for q in queue_families {
            append(&q_dyn, q.family_idx)
        }

        create_info.pQueueFamilyIndices = &q_dyn[0]
        create_info.sharingMode = .CONCURRENT
    } else {
        create_info.pQueueFamilyIndices = &queue_families[0].family_idx

    }

    vk.CreateBuffer(ctx.device.logical, &create_info, {}, &buf.buf)

    mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device.logical, buf.buf, &mem_req)

    mem_props : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(ctx.device.physical, &mem_props)

    mem_index : u32
    for i in 0..<mem_props.memoryTypeCount {
        mem_type := mem_props.memoryTypes[i]
        if memory_flags & mem_type.propertyFlags == memory_flags {
            mem_index = i
            break
        }
    }

    mem_alloc_info : vk.MemoryAllocateInfo
    mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    mem_alloc_info.allocationSize = mem_req.size
    mem_alloc_info.memoryTypeIndex = mem_index

    vk.AllocateMemory(ctx.device.logical, &mem_alloc_info, {}, &buf.mem)

    vk.BindBufferMemory(ctx.device.logical, buf.buf, buf.mem, 0)
    return

}

create_buffer :: proc(ctx : ^Context, initial_capacity : int, queue_families : ..QueueFamily) -> (buf : Buffer) {
    return _create_buffer_with_mem_flags(ctx, initial_capacity, {.DEVICE_LOCAL}, ..queue_families)
}

create_staging_buffer :: proc(ctx : ^Context, mapped_buffer : ^Buffer) -> (buf : Staging_Buffer) {
    buf.device_buffer = mapped_buffer
    q_fam, _ := find_queue_family_by_type(ctx, {.TRANSFER})
    buf.host_buffer = _create_buffer_with_mem_flags(ctx, int(mapped_buffer.size), {.HOST_VISIBLE, .HOST_COHERENT}, q_fam^)

    mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device.logical, buf.host_buffer.buf, &mem_req)

    vk.MapMemory(ctx.device.logical, buf.host_buffer.mem, 0, mem_req.size, {}, &buf.host_data)
    return
}

allocate_chunk :: proc(buffer : ^Buffer, chunk_size : vk.DeviceSize) -> (chunk : Chunk_Handle) {
    current_offset : vk.DeviceSize
    if len(buffer.chunks) > 0 {
        last_idx := len(buffer.chunks) - 1
        last_chunk := buffer.chunks[last_idx]
        current_offset = last_chunk.offset + last_chunk.size
    }

    new_chunk : Buffer_Chunk
    new_chunk.offset = current_offset
    new_chunk.capacity = chunk_size

    append(&buffer.chunks, new_chunk)

    chunk = Chunk_Handle(len(buffer.chunks) - 1)

    return
}

resize_chunk :: proc(queue : ^Buffer_Copy_Queue, buffer : ^Buffer, chunk : Chunk_Handle, multiplier : f32 = 2.0) {
    chunk_index := buffer.chunk_map[chunk]

    chunk := &buffer.chunks[chunk_index]

    new_chunk_capacity := f32(chunk.capacity) * multiplier

    chunk.capacity = vk.DeviceSize(new_chunk_capacity)

    if chunk_index != len(buffer.chunks) - 1 {
        // then we need to move everything in the buffer

        next_chunk_idx := chunk_index + 1
        next_chunk := buffer.chunks[next_chunk_idx]
        
        last_chunk_idx := len(buffer.chunks) - 1
        last_chunk := buffer.chunks[last_chunk_idx]

        copy_size : vk.DeviceSize
        for c in buffer.chunks[next_chunk_idx:last_chunk_idx] {
            copy_size += c.capacity
        }

        copy_op : Buffer_Copy_Op
        copy_op.source = {
            buffer = buffer,
            offset = next_chunk.offset,
            size = copy_size
        }
        copy_op.source = {
            buffer = buffer,
            offset = chunk.offset + chunk.capacity,
            size = copy_size
        }

        append(queue, copy_op)
    }
}

free_chunk :: proc(queue : ^Buffer_Copy_Queue, buffer : ^Buffer, chunk : Chunk_Handle) {
    // freeing memory space with a handle-based access system is tricky...
    removed_index := buffer.chunk_map[chunk]
    removal_start : int
    if removed_index != 0 {
        removal_start = int(buffer.chunks[removed_index-1].offset) + int(buffer.chunks[removed_index-1].capacity)
    }

    removal_size := buffer.chunks[removed_index].capacity

    for k in buffer.chunk_map {
        if buffer.chunk_map[k] > removed_index {
            buffer.chunk_map[k] -= 1
        }
    }

    buf_mem_size := buffer.size - (vk.DeviceSize(removal_start) + removal_size)

    copy_op : Buffer_Copy_Op
    copy_op.source = {
        buffer = buffer,
        offset = vk.DeviceSize(removal_start) + removal_size,
        size = buf_mem_size
    }
    copy_op.dest = {
        buffer = buffer,
        offset = vk.DeviceSize(removal_start),
        size = buf_mem_size
    }

    append(queue, copy_op)
}

append_element :: proc(buffer : ^Buffer, chunk: Chunk_Handle, element: []byte) -> Element_Handle {
    chunk_idx := buffer.chunk_map[chunk]
    chunk_data := &buffer.chunks[chunk_idx]

    return 0
}

insert_element :: proc(buffer: ^Buffer, chunk: Chunk_Handle, element: []byte, index: int) -> Element_Handle {
    return 0
}

delete_element :: proc(buffer: ^Buffer, chunk: Chunk_Handle, index: int) {
}

destroy_buffer :: proc(ctx : ^Context, buffer : Buffer) {
    vk.DestroyBuffer(ctx.device.logical, buffer.buf, {})
    vk.FreeMemory(ctx.device.logical, buffer.mem, {})

    delete(buffer.chunks)
}

perform_buffer_copy_op :: proc(ctx: ^Context, op : Buffer_Copy_Op, cmd_buffer : vk.CommandBuffer) {
    // NOTE: Call before beginning render pass
    source_buf := op.source.buffer
    dest_buf := op.dest.buffer
    if source_buf.buf == dest_buf.buf {
        staging_buf := create_buffer(ctx, int(op.size))

        src_cpy : vk.BufferCopy
        src_cpy.size = op.size
        src_cpy.srcOffset = op.source.offset
        src_cpy.dstOffset = 0

        vk.CmdCopyBuffer(cmd_buffer, source_buf.buf, staging_buf.buf, 1, &src_cpy)

        mem_barrier : vk.BufferMemoryBarrier
        mem_barrier.sType = .BUFFER_MEMORY_BARRIER
        mem_barrier.srcAccessMask = {.TRANSFER_READ}
        mem_barrier.dstAccessMask = {.TRANSFER_WRITE}
        mem_barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
        mem_barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
        mem_barrier.buffer = staging_buf.buf
        mem_barrier.offset = 0
        mem_barrier.size = op.size

        vk.CmdPipelineBarrier(cmd_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 1, &mem_barrier, 0, nil)

        dst_cpy : vk.BufferCopy
        dst_cpy.size = op.size
        dst_cpy.srcOffset = 0
        dst_cpy.dstOffset = op.dest.offset

        vk.CmdCopyBuffer(cmd_buffer, staging_buf.buf, dest_buf.buf, 1, &dst_cpy)
    } else {

        copy_info : vk.BufferCopy
        copy_info.size = op.size
        copy_info.srcOffset = op.source.offset
        copy_info.dstOffset = op.dest.offset

        vk.CmdCopyBuffer(cmd_buffer, source_buf.buf, dest_buf.buf, 1, &copy_info)
    }
}

cleanup_task :: proc(ctx: ^Context) {

    // use vk.GetSemaphoreCounterValue to check if a used buffer's step in the timeline has completed
    // the Context has a list of buffers that need cleaned up
}
