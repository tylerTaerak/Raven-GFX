package game_vulkan

import "core:log"
import vk "vendor:vulkan"

import "core:thread"
import "core:sync"

import "base:runtime"

Worker_Data :: struct {
    command_pool    : vk.CommandPool,
    command_buffers : [FRAMES_IN_FLIGHT]vk.CommandBuffer
}

Worker :: struct {
    thread          : ^thread.Thread,
    frame_index     : int,
    graphics        : Worker_Data,
    compute         : Worker_Data,
    transfer        : Worker_Data,
    reset_event     : sync.Auto_Reset_Event,
    alloc           : runtime.Allocator,
    exit            : bool
}

add_worker :: proc(ctx : ^Context) -> (ok : bool = true) {
    new_worker : Worker
    new_worker.alloc = runtime.heap_allocator()
    // append(&ctx.subsystems, new_system)

    thread_ctx : runtime.Context
    thread_ctx = runtime.default_context()
    thread_ctx.allocator = new_worker.alloc
    thread_ctx.logger = log.create_console_logger()

    thread.create_and_start_with_poly_data2(ctx, len(ctx.subsystems) - 1, worker_proc, thread_ctx)
    return
}

handle_graphics_job :: proc(ctx : ^Context, job : Graphics_Job, command_buffer : vk.CommandBuffer) {
}

handle_compute_job :: proc(ctx : ^Context, job : Compute_Job, command_buffer : vk.CommandBuffer) {
}

handle_transfer_job :: proc(ctx : ^Context, job : Transfer_Job, command_buffer : vk.CommandBuffer) {
}

worker_proc :: proc(ctx : ^Context, sys_idx : int, job_queue : ^Job_Queue) {
    worker := &ctx.workers[sys_idx]

    _init_worker_graphics_data(ctx, worker)
    _init_worker_compute_data(ctx, worker)
    _init_worker_transfer_data(ctx, worker)

    defer vk.FreeCommandBuffers(ctx.device.logical, worker.graphics.command_pool, len(worker.graphics.command_buffers), &worker.graphics.command_buffers[0])
    defer vk.DestroyCommandPool(ctx.device.logical, worker.graphics.command_pool, {})

    defer vk.FreeCommandBuffers(ctx.device.logical, worker.compute.command_pool, len(worker.compute.command_buffers), &worker.compute.command_buffers[0])
    defer vk.DestroyCommandPool(ctx.device.logical, worker.compute.command_pool, {})

    defer vk.FreeCommandBuffers(ctx.device.logical, worker.transfer.command_pool, len(worker.transfer.command_buffers), &worker.transfer.command_buffers[0])
    defer vk.DestroyCommandPool(ctx.device.logical, worker.transfer.command_pool, {})

    for !sync.atomic_load(&worker.exit) {
        sync.auto_reset_event_wait(&worker.reset_event)

        vk.ResetCommandPool(ctx.device.logical, worker.graphics.command_pool, {})
        vk.ResetCommandPool(ctx.device.logical, worker.compute.command_pool, {})
        vk.ResetCommandPool(ctx.device.logical, worker.transfer.command_pool, {})

        // TODO)) Utilize vk.TimelineSemaphoreSubmitInfo to properly orchestrate timing of all the different jobs
        // We do this by specifying .TIMELINE in a vk.SemaphoreTypeCreateInfo and linking that to vk.SemaphoreCreateInfo's pNext field
        // Then use vk.QueueSubmit2 with vk.SubmitInfo2 to pass in the vk.TimelineSemaphoreSubmitInfo as pNext

        for {
            job : Job
            has_job : bool

            if job, has_job = pop(job_queue); has_job {
                dependencies_covered := true

                for dep, _ in job.depends_on {
                    switch ptr in dep {
                        case ^vk.Buffer:
                            if !(job_queue.buffer_writes[ptr^] in ctx.processed_jobs) {
                                dependencies_covered = false
                                break
                            }
                        case ^vk.Pipeline:
                            if !(job_queue.pipelines[ptr^] in ctx.processed_jobs) {
                                dependencies_covered = false
                                break
                            }
                    }
                }

                if !dependencies_covered {
                    push(job_queue, job)
                    continue
                }

                switch val in job.data {
                    case Graphics_Job:
                        // handle graphics job
                        handle_graphics_job(ctx, val, worker.graphics.command_buffers[worker.frame_index])
                    case Compute_Job:
                        // handle compute job
                        handle_compute_job(ctx, val, worker.compute.command_buffers[worker.frame_index])
                    case Transfer_Job:
                        // handle transfer job
                        handle_transfer_job(ctx, val, worker.transfer.command_buffers[worker.frame_index])
                }
            } else {
                break
            }
        }

        log.info("Jobs finished!")
        sync.wait_group_done(&ctx.wait_group)


        // log.info("Starting Draw Procedure")


        // log.info("Command pool reset")

        // inheritance_info : vk.CommandBufferInheritanceInfo
        // inheritance_info.sType = .COMMAND_BUFFER_INHERITANCE_INFO
        // inheritance_info.renderPass = ctx.render_pass

        // // begin recording buffer
        // begin_info : vk.CommandBufferBeginInfo
        // begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
        // begin_info.pInheritanceInfo = &inheritance_info
        // begin_info.flags = {.RENDER_PASS_CONTINUE}

        // buf := system.command_buffers[system.frame_index]

        // res := vk.BeginCommandBuffer(buf, &begin_info)
        // if res != .SUCCESS {
        //     log.error("Error beginning command buffer", res)
        // }

        // log.info("Command buffer begin")

        // for pipeline in system.pipelines {
        //     log.info("Binding pipeline")
        //     // bind pipeline
        //     vk.CmdBindPipeline(buf, .GRAPHICS, pipeline)

        //     log.info("Drawing")
        //     // add draw commands to buffer
        //     vk.CmdDraw(buf, 3, 1, 0, 0)

        // }

        // // end recording buffer
        // vk.EndCommandBuffer(buf)
        // log.info("Command Buffer End", buf)
    }
}

_init_worker_graphics_data :: proc(ctx : ^Context, worker : ^Worker) {
    gfx_queue, _ := find_queue_family_present_support(ctx)
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = gfx_queue.family_idx

    vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &worker.graphics.command_pool)

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = worker.graphics.command_pool
    create_info.level = .SECONDARY

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &worker.graphics.command_buffers[0])
}

_init_worker_compute_data :: proc(ctx : ^Context, worker : ^Worker) {
    cmp_queue, _ := find_queue_family_by_type(ctx, {.COMPUTE})
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = cmp_queue.family_idx

    vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &worker.compute.command_pool)

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = worker.compute.command_pool

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &worker.compute.command_buffers[0])
}

_init_worker_transfer_data :: proc(ctx : ^Context, worker : ^Worker) {
    trs_queue, _ := find_queue_family_by_type(ctx, {.TRANSFER})
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = trs_queue.family_idx

    vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &worker.transfer.command_pool)

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = worker.transfer.command_pool

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &worker.transfer.command_buffers[0])
}
