package game_vulkan

import vk "vendor:vulkan"
import "core:log"

Command_Buffer :: vk.CommandBuffer

Command_Set :: struct($N: int) {
    pool 	: vk.CommandPool,
    buffers : [N]Command_Buffer,
	family  : QueueFamily
}

create_command_set :: proc(device : Device, $Count: int, queue_fam : QueueFamily) -> (set: Command_Set(Count), ok: bool = true) {
    pool_info : vk.CommandPoolCreateInfo
    pool_info.sType = .COMMAND_POOL_CREATE_INFO
    pool_info.flags = {.RESET_COMMAND_BUFFER}
    pool_info.queueFamilyIndex = queue_fam.family_idx

    res := vk.CreateCommandPool(device.core, &pool_info, {}, &set.pool)
    ok = res == .SUCCESS

	set.family = queue_fam

    buf_info : vk.CommandBufferAllocateInfo
    buf_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    buf_info.commandPool = set.pool
    buf_info.commandBufferCount = u32(Count)

    res = vk.AllocateCommandBuffers(device.core, &buf_info, &set.buffers[0])
    ok &= res == .SUCCESS

    return
}

destroy_command_set :: proc(device : Device, set: $T/Command_Set($N)) {
	buffers := set.buffers
    vk.FreeCommandBuffers(device.core, set.pool, u32(N), &buffers[0])
    vk.DestroyCommandPool(device.core, set.pool, {})
}

begin_command_buffer :: proc(buff : Command_Buffer) {
    info : vk.CommandBufferBeginInfo
    info.sType = .COMMAND_BUFFER_BEGIN_INFO

    res := vk.BeginCommandBuffer(buff, &info)

    if res != .SUCCESS {
        log.info("ERROR BEGINNING COMMAND BUFFER: ", res)
    }
}

end_command_buffer :: proc(buff : Command_Buffer) {
    vk.EndCommandBuffer(buff)
}

submit_command_buffer :: proc(device : Device, cmd_buf : Command_Buffer, queue_fam : QueueFamily, wait_sem, signal_sem : Semaphore, signal_fence : Fence) {
    submit_info : vk.SubmitInfo2KHR
    submit_info.sType = .SUBMIT_INFO_2_KHR
    submit_info.commandBufferInfoCount = 1

    cmd_info : vk.CommandBufferSubmitInfoKHR
    cmd_info.sType = .COMMAND_BUFFER_SUBMIT_INFO_KHR
    cmd_info.commandBuffer = cmd_buf
    submit_info.pCommandBufferInfos = &cmd_info

    if wait_sem != 0 {
        submit_info.waitSemaphoreInfoCount = 1

        wait_info : vk.SemaphoreSubmitInfo
        wait_info.sType = .SEMAPHORE_SUBMIT_INFO
        wait_info.semaphore = wait_sem
        submit_info.pWaitSemaphoreInfos = &wait_info
    }

    if signal_sem != 0 {
        submit_info.signalSemaphoreInfoCount = 1

        sig_info : vk.SemaphoreSubmitInfo
        sig_info.sType = .SEMAPHORE_SUBMIT_INFO
        sig_info.semaphore = signal_sem
        submit_info.pSignalSemaphoreInfos = &sig_info
    }

    vkq : vk.Queue
    vk.GetDeviceQueue(device.core, queue_fam.family_idx, 0, &vkq)

    vk.QueueSubmit2KHR(vkq, 1, &submit_info, signal_fence)
}

reset_command_buffer :: proc(buff : Command_Buffer) {
	vk.ResetCommandBuffer(buff, {})
}
