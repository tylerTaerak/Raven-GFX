package game_vulkan

import "core:log"
import vk "vendor:vulkan"

import "core:thread"
import "core:sync"

import "base:runtime"

Subsystem :: struct {
    thread          : ^thread.Thread,
    command_pool    : vk.CommandPool,
    command_buffers : [FRAMES_IN_FLIGHT]vk.CommandBuffer,
    reset_event     : sync.Auto_Reset_Event,
    pipelines       : []Pipeline,
    alloc           : runtime.Allocator,
    exit            : bool
}

create_fence :: proc(ctx : ^Context) -> (fence : vk.Fence, ok : bool = true) {
    create_info : vk.FenceCreateInfo
    create_info.sType = .FENCE_CREATE_INFO

    res := vk.CreateFence(ctx.device.logical, &create_info, {}, &fence)
    if res != .SUCCESS {
        ok = false
    }
    return
}

create_semaphore :: proc(ctx : ^Context) -> (sem : vk.Semaphore, ok : bool = true) {
    create_info : vk.SemaphoreCreateInfo
    create_info.sType = .SEMAPHORE_CREATE_INFO

    res := vk.CreateSemaphore(ctx.device.logical, &create_info, {}, &sem)
    if res != .SUCCESS {
        ok = false
    }
    return
}

add_subsystem :: proc(ctx : ^Context, pipelines : ..Pipeline) -> (ok : bool = true) {
    new_system : Subsystem
    new_system.alloc = runtime.heap_allocator()
    new_system.pipelines = make([]Pipeline, len(pipelines), new_system.alloc)
    copy(new_system.pipelines, pipelines)

    append(&ctx.subsystems, new_system)

    thread_ctx : runtime.Context
    thread_ctx = runtime.default_context()
    thread_ctx.allocator = new_system.alloc
    thread_ctx.logger = log.create_console_logger()

    thread.create_and_start_with_poly_data2(ctx, len(ctx.subsystems) - 1, subsystem_proc, thread_ctx)
    log.info("Spawned new subsystem thread for graphics context with pipelines", ctx.subsystems[len(ctx.subsystems) - 1].pipelines)
    return
}

// TODO)) It might be better to turn this into a queue-based system... not convinced though...
subsystem_proc :: proc(ctx : ^Context, sys_idx : int) {
    system := &ctx.subsystems[sys_idx]

    queue, _ := find_queue_family_present_support(ctx)
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = queue.family_idx

    vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &system.command_pool)
    defer vk.DestroyCommandPool(ctx.device.logical, system.command_pool, {})

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = system.command_pool
    create_info.level = .SECONDARY

    log.warn("Initialized subystem with pipelines", system.pipelines)

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &system.command_buffers[0])
    defer vk.FreeCommandBuffers(ctx.device.logical, system.command_pool, len(system.command_buffers), &system.command_buffers[0])

    for !sync.atomic_load(&system.exit) {
        sync.auto_reset_event_wait(&system.reset_event)

        log.info("Starting Draw Procedure")

        vk.ResetCommandPool(ctx.device.logical, system.command_pool, {})

        log.info("Command pool reset")

        inheritance_info : vk.CommandBufferInheritanceInfo
        inheritance_info.sType = .COMMAND_BUFFER_INHERITANCE_INFO
        inheritance_info.renderPass = ctx.render_pass

        // begin recording buffer
        begin_info : vk.CommandBufferBeginInfo
        begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
        begin_info.pInheritanceInfo = &inheritance_info
        begin_info.flags = {.RENDER_PASS_CONTINUE}

        buf := system.command_buffers[ctx.frame_idx]

        res := vk.BeginCommandBuffer(buf, &begin_info)
        if res != .SUCCESS {
            log.error("Error beginning command buffer", res)
        }

        log.info("Command buffer begin")

        for pipeline in system.pipelines {
            log.info("Binding pipeline")
            // bind pipeline
            vk.CmdBindPipeline(buf, .GRAPHICS, pipeline)

            log.info("Drawing")
            // add draw commands to buffer
            vk.CmdDraw(buf, 3, 1, 0, 0)

        }

        // end recording buffer
        vk.EndCommandBuffer(buf)
        log.info("Command Buffer End", buf)

        log.info("Job done!")
        sync.wait_group_done(&ctx.wait_group)
    }
}
