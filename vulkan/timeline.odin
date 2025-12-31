package game_vulkan

import vk "vendor:vulkan"
import "core:sync"

Timeline :: struct {
    sem     : vk.Semaphore,
    value   : u64,
    mutex   : sync.Mutex
}

Fence :: vk.Fence

init_timeline :: proc(ctx: ^Context) -> Timeline {
    type_info : vk.SemaphoreTypeCreateInfo
    type_info.sType = .SEMAPHORE_TYPE_CREATE_INFO
    type_info.semaphoreType = .TIMELINE
    type_info.initialValue = 0

    create_info : vk.SemaphoreCreateInfo
    create_info.sType = .SEMAPHORE_CREATE_INFO
    create_info.pNext = &type_info

    timeline : Timeline
    vk.CreateSemaphore(ctx.device, &create_info, {}, &timeline.sem)

    return timeline
}

// returns current tick count of timeline
get_current_ticks :: proc(timeline: ^Timeline) -> u64 {
    sync.lock(&timeline.mutex)
    defer sync.unlock(&timeline.mutex)

    return timeline.value
}

// returns the current tick count of timeline and then increments
tick :: proc(timeline: ^Timeline) -> u64 {
    sync.lock(&timeline.mutex)
    defer sync.unlock(&timeline.mutex)

    val := timeline.value
    timeline.value += 1

    return val
}

destroy_timeline :: proc(ctx: ^Context, timeline: ^Timeline) {
    vk.DestroySemaphore(ctx.device, timeline.sem, {})
}

init_fence :: proc(ctx: ^Context) -> (fence: Fence) {
    info : vk.FenceCreateInfo
    info.sType = .FENCE_CREATE_INFO
    
    vk.CreateFence(ctx.device, &info, {}, &fence)
    return
}

wait_for_fence :: proc(ctx: ^Context, fence: ^Fence) {
    vk.WaitForFences(ctx.device, 1, fence, true, 50_000)
}

reset_fence :: proc(ctx: ^Context, fence: ^Fence) {
    vk.ResetFences(ctx.device, 1, fence)
}

destroy_fence :: proc(ctx: ^Context, fence: Fence) {
    vk.DestroyFence(ctx.device, fence, {})
}
