package game_vulkan

import "core:mem"
import "../core"
import vk "vendor:vulkan"
import "core:container/queue"

/**
  A Render Effect wraps Pipelines wraps draw calls

  A "graphics job" would look something like:

  RenderingInfo info
  info.pRenderPass = job.pass
  ...

  vk.beginRendering(ctx, &info)
  ...
  vk.bindPipeline(ctx, job.pipeline)
  ...
  vk.drawIndexedIndirect(ctx, job.draws)

  vk.endRendering(ctx)

  And there would be a job spawned for each combination
  of render pass/target and pipeline -> draw calls are the
  same across each render pass/target -> each combination
  needs a timeline semaphore assignment

  What I'm thinking is that I could load pipelines up in
  a "format-agnostic" way, then use VK_PIPELINE_CREATE_DERIVATIVE_BIT
  to create "child" pipelines that do have a targeted format, on
  a per-render effect basis - maybe

  I really just need to play around with formulating these larger
  pipelines that consist of vk.Pipeline and the Render_Effect objects
  to get a better understanding of how they're actually going to react
  */

Pipeline_Graph :: struct {
    next: []^Pipeline_Graph,

    pipeline: Pipeline
}

// TODO)) I'll probably want a more user-friendly image type that encapsulates a vulkan image with its metadata
Render_Image :: vk.Image

Render_Effect :: struct {
    next: []Render_Effect,

    color_images: []Render_Image,
    depth_image: Maybe(Render_Image),
    stencil_image: Maybe(Render_Image),

    pipelines: []^Pipeline_Graph,

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
