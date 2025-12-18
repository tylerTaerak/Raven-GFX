package game_vulkan

import vk "vendor:vulkan"
import "core:sync"

Timeline :: struct {
    sem     : vk.Semaphore,
    value   : u64,
    mutex   : sync.Mutex
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
