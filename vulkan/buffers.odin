package game_vulkan

import "core:mem"
import "core:slice"
import "core:log"
import vk "vendor:vulkan"

// These buffers are very rudimentary - everything is bytes when it comes to these buffers
Buffer :: struct {
    buf             : vk.Buffer,
    mem             : vk.DeviceMemory,
    size            : vk.DeviceSize,

    staging_buffer  : vk.Buffer,
    staging_mem     : vk.DeviceMemory,
    host_data       : rawptr
}

Buffer_Slice :: struct {
    buffer      : ^Buffer,
    offset      : vk.DeviceSize,
    size        : vk.DeviceSize
}

Raw_Buffer_Slice :: struct {
    buffer : vk.Buffer,
    offset : vk.DeviceSize,
    size   : vk.DeviceSize
}

/* Create Buffer */

create_buffer :: proc(
    ctx: ^Context,
    initial_capacity: int,
    queue_families : []QueueFamily,
    usage_flags: vk.BufferUsageFlags = {.STORAGE_BUFFER, .TRANSFER_DST}) -> (buf : Buffer) {

    create_info : vk.BufferCreateInfo
    create_info.sType = .BUFFER_CREATE_INFO
    create_info.size = vk.DeviceSize(initial_capacity)
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
    
    vk.CreateBuffer(ctx.device.logical, &create_info, {}, &buf.buf)

    buf.size = vk.DeviceSize(initial_capacity)

    mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device.logical, buf.buf, &mem_req)

    mem_props : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(ctx.device.physical, &mem_props)

    buf_mem_idx, staging_mem_idx : u32
    for i in 0..<mem_props.memoryTypeCount {
        mem_type := mem_props.memoryTypes[i]
        if .DEVICE_LOCAL in mem_type.propertyFlags {
            buf_mem_idx = i
        }

        if mem_type.propertyFlags & {.HOST_VISIBLE, .HOST_COHERENT} == {.HOST_VISIBLE, .HOST_COHERENT} {
            staging_mem_idx = i
        }
    }

    // log.info("Buffer size:", buf.size)

    create_info.usage = {.TRANSFER_SRC}

    vk.CreateBuffer(ctx.device.logical, &create_info, {}, &buf.staging_buffer)

    staging_mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device.logical, buf.staging_buffer, &staging_mem_req)

    buf_alloc_info : vk.MemoryAllocateInfo
    buf_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    buf_alloc_info.allocationSize = mem_req.size
    buf_alloc_info.memoryTypeIndex = buf_mem_idx

    vk.AllocateMemory(ctx.device.logical, &buf_alloc_info, {}, &buf.mem)

    vk.BindBufferMemory(ctx.device.logical, buf.buf, buf.mem, 0)

    staging_alloc_info : vk.MemoryAllocateInfo
    staging_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    staging_alloc_info.allocationSize = staging_mem_req.size
    staging_alloc_info.memoryTypeIndex = staging_mem_idx

    vk.AllocateMemory(ctx.device.logical, &staging_alloc_info, {}, &buf.staging_mem)

    vk.BindBufferMemory(ctx.device.logical, buf.staging_buffer, buf.staging_mem, 0)


    vk.MapMemory(ctx.device.logical, buf.staging_mem, 0, staging_mem_req.size, {}, &buf.host_data)

    return
}

/* Slice Creation */

make_slice_from_indicies :: proc(buffer: ^Buffer, start, end: int) -> (slice : Buffer_Slice) {
    assert(end > start)

    size := vk.DeviceSize(end - start)

    slice = make_slice_from_size_and_offset(buffer, vk.DeviceSize(start), size)

    return
}

make_slice_from_size_and_offset :: proc(buffer: ^Buffer, offset, size: vk.DeviceSize) -> (slice : Buffer_Slice) {
    assert(size <= buffer.size)

    slice.buffer    = buffer
    slice.offset    = offset
    slice.size      = size

    return
}

make_slice_from_slice_and_indicies :: proc(src: ^Buffer_Slice, start, end: int) -> (slice : Buffer_Slice) {
    assert(end > start)
    assert(end < int(src.size))

    size := vk.DeviceSize(end - start)

    slice = make_slice_from_slice_and_size_and_offset(src, vk.DeviceSize(start), size)

    return
}

make_slice_from_slice_and_size_and_offset :: proc(src: ^Buffer_Slice, offset, size: vk.DeviceSize) -> (slice : Buffer_Slice) {
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

/* Write and Copy Ops */

buf_write :: proc(ctx: ^Context, buffer : ^Buffer, data: []byte, location: int) {
    // adds a transfer job to the job queue from staging to main
    
    byte_slice := slice.bytes_from_ptr(buffer.host_data, int(buffer.size))
    copy(byte_slice[location:location + len(data)], data)

    src_slice := Raw_Buffer_Slice{
        buffer=buffer.staging_buffer,
        offset=vk.DeviceSize(location),
        size=vk.DeviceSize(len(data))
    }

    dest_slice := Raw_Buffer_Slice{
        buffer=buffer.buf,
        offset=vk.DeviceSize(location),
        size=vk.DeviceSize(len(data))
    }

    push(&ctx.job_queue, Transfer_Job {
        src_buffer = src_slice,
        dest_buffer = dest_slice
    })
}

buffer_write :: proc{
    buf_write,
}

buffer_copy :: proc(ctx : ^Context, src, dst : Buffer_Slice) {
    // adds a transfer job to the job queue

    raw_src := Raw_Buffer_Slice {
        buffer = src.buffer.buf,
        offset = src.offset,
        size = src.size
    }

    raw_dest := Raw_Buffer_Slice {
        buffer = dst.buffer.buf,
        offset = dst.offset,
        size = dst.size
    }

    push(&ctx.job_queue, Transfer_Job {
        src_buffer = raw_src,
        dest_buffer = raw_dest
    })
}

/* Cleanup */

destroy_buffer :: proc(ctx: ^Context, buffer: Buffer) {
    append(&ctx.delete_buffers, buffer)
}

_destroy_buffer :: proc(ctx : ^Context, buffer : Buffer) {
    vk.DestroyBuffer(ctx.device.logical, buffer.buf, {})
    vk.FreeMemory(ctx.device.logical, buffer.mem, {})

    vk.UnmapMemory(ctx.device.logical, buffer.staging_mem)
    vk.DestroyBuffer(ctx.device.logical, buffer.staging_buffer, {})
    vk.FreeMemory(ctx.device.logical, buffer.staging_mem, {})
}

// perform_buffer_copy_op :: proc(ctx: ^Context, op : Buffer_Copy_Op, cmd_buffer : vk.CommandBuffer) {
//     source_buf := op.source.buffer
//     dest_buf := op.dest.buffer
//     if source_buf.buf == dest_buf.buf {
//         staging_buf := create_buffer(ctx, int(op.size))
// 
//         src_cpy : vk.BufferCopy
//         src_cpy.size = op.size
//         src_cpy.srcOffset = op.source.offset
//         src_cpy.dstOffset = 0
// 
//         vk.CmdCopyBuffer(cmd_buffer, source_buf.buf, staging_buf.buf, 1, &src_cpy)
// 
//         mem_barrier : vk.BufferMemoryBarrier
//         mem_barrier.sType = .BUFFER_MEMORY_BARRIER
//         mem_barrier.srcAccessMask = {.TRANSFER_READ}
//         mem_barrier.dstAccessMask = {.TRANSFER_WRITE}
//         mem_barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
//         mem_barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
//         mem_barrier.buffer = staging_buf.buf
//         mem_barrier.offset = 0
//         mem_barrier.size = op.size
// 
//         vk.CmdPipelineBarrier(cmd_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 1, &mem_barrier, 0, nil)
// 
//         dst_cpy : vk.BufferCopy
//         dst_cpy.size = op.size
//         dst_cpy.srcOffset = 0
//         dst_cpy.dstOffset = op.dest.offset
// 
//         vk.CmdCopyBuffer(cmd_buffer, staging_buf.buf, dest_buf.buf, 1, &dst_cpy)
//     } else {
// 
//         copy_info : vk.BufferCopy
//         copy_info.size = op.size
//         copy_info.srcOffset = op.source.offset
//         copy_info.dstOffset = op.dest.offset
// 
//         vk.CmdCopyBuffer(cmd_buffer, source_buf.buf, dest_buf.buf, 1, &copy_info)
//     }
// }

cleanup_task :: proc(ctx: ^Context) {

    // use vk.GetSemaphoreCounterValue to check if a used buffer's step in the timeline has completed
    // the Context has a list of buffers that need cleaned up
}
