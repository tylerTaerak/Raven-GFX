package game_vulkan

import vk "vendor:vulkan"
import "core:sync"

Timeline :: struct {
    sem     : vk.Semaphore,
    value   : u64,
    mutex   : sync.Mutex
}

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
