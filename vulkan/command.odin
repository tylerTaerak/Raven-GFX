package game_vulkan

import vk "vendor:vulkan"

Command_Set :: struct {
    pool : vk.CommandPool,
    buffers : []vk.CommandBuffer
}

create_command_set :: proc(ctx: ^Context, buffer_count: int, queue_fam : QueueFamily) -> (set: Command_Set, ok: bool = true) {
    pool_info : vk.CommandPoolCreateInfo
    pool_info.sType = .COMMAND_POOL_CREATE_INFO
    pool_info.flags = {.RESET_COMMAND_BUFFER}
    pool_info.queueFamilyIndex = queue_fam.family_idx

    res := vk.CreateCommandPool(ctx.device, &pool_info, {}, &set.pool)
    ok = res == .SUCCESS

    buf_info : vk.CommandBufferAllocateInfo
    buf_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    buf_info.commandPool = set.pool
    buf_info.commandBufferCount = u32(buffer_count)

    set.buffers = make([]vk.CommandBuffer, buffer_count)

    res = vk.AllocateCommandBuffers(ctx.device, &buf_info, &set.buffers[0])
    ok &= res == .SUCCESS

    return
}

destroy_command_set :: proc(ctx: ^Context, set: ^Command_Set) {
    vk.FreeCommandBuffers(ctx.device, set.pool, u32(len(set.buffers)), &set.buffers[0])
    delete(set.buffers)
    vk.DestroyCommandPool(ctx.device, set.pool, {})
}

begin_command_buffer :: proc(cmd_set : Command_Set, index : int) {
    info : vk.CommandBufferBeginInfo
    info.sType = .COMMAND_BUFFER_BEGIN_INFO

    vk.BeginCommandBuffer(cmd_set.buffers[index], &info)
}

end_command_buffer :: proc(cmd_set : Command_Set, index : int) {
    vk.EndCommandBuffer(cmd_set.buffers[index])
}
