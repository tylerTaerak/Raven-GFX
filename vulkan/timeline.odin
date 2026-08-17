package game_vulkan

import vk "vendor:vulkan"
import "core:sync"

Timeline :: struct {
    sem     : vk.Semaphore,
    value   : u64,
    mutex   : sync.Mutex
}

Fence :: vk.Fence

Semaphore :: vk.Semaphore

init_timeline :: proc(device : Device) -> Timeline {
    type_info : vk.SemaphoreTypeCreateInfo
    type_info.sType = .SEMAPHORE_TYPE_CREATE_INFO
    type_info.semaphoreType = .TIMELINE
    type_info.initialValue = 0

    create_info : vk.SemaphoreCreateInfo
    create_info.sType = .SEMAPHORE_CREATE_INFO
    create_info.pNext = &type_info

    timeline : Timeline
    vk.CreateSemaphore(device.core, &create_info, {}, &timeline.sem)

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

destroy_timeline :: proc(device : Device, timeline: ^Timeline) {
    vk.DestroySemaphore(device.core, timeline.sem, {})
}

init_fence :: proc(device : Device) -> (fence: Fence) {
    info : vk.FenceCreateInfo
    info.sType = .FENCE_CREATE_INFO
    
    vk.CreateFence(device.core, &info, {}, &fence)
    return
}

wait_for_fence :: proc(device : Device, fence: Fence) {
	fence := fence
    vk.WaitForFences(device.core, 1, &fence, true, 100_000)
}

wait_for_fences :: proc(device : Device, fences: []Fence) {
    vk.WaitForFences(device.core, u32(len(fences)), &fences[0], true, 100_000);
}

reset_fence :: proc(device : Device, fence: Fence) {
	fence := fence
    vk.ResetFences(device.core, 1, &fence)
}

reset_fences :: proc(device : Device, fences: []Fence) {
    vk.ResetFences(device.core, u32(len(fences)), &fences[0])
}

destroy_fence :: proc(device : Device, fence: Fence) {
    vk.DestroyFence(device.core, fence, {})
}

init_semaphore :: proc(device : Device) -> (sem : Semaphore) {
    info : vk.SemaphoreCreateInfo
    info.sType = .SEMAPHORE_CREATE_INFO
    info.flags = {}

    vk.CreateSemaphore(device.core, &info, {}, &sem)
    return
}

destroy_semaphore :: proc(device : Device, sem : Semaphore) {
    vk.DestroySemaphore(device.core, sem, {})
}
