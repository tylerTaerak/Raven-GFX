package game_vulkan

import "core:mem"
import "../core"
import vk "vendor:vulkan"
import "core:container/queue"

Render_Effect :: struct {
    next: []Render_Effect,
    wait_ticks : []u64,
    signal_tick: u64
}

run_effects :: proc(effects: []Render_Effect, timeline: ^Timeline) {
    render_queue: queue.Queue(^Render_Effect)

    for &fx in effects {
        queue.push_back(&render_queue, &fx)
    }

    for render_queue.len != 0 {
        fx : ^Render_Effect

        fx.signal_tick = tick(timeline)

        for &c in fx.next {
            new_mem := make([]u64, len(c.wait_ticks) + 1)
            mem.copy(&new_mem[0], &c.wait_ticks[0], len(c.wait_ticks))
            new_mem[len(c.wait_ticks)] = fx.signal_tick
            delete(c.wait_ticks)
            c.wait_ticks = new_mem

            queue.push_back(&render_queue, &c)
        }

        // drop onto a worker's job queue
    }
}
