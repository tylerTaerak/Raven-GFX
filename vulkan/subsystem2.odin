package game_vulkan

import "core:log"
import vk "vendor:vulkan"

import "core:thread"
import "core:sync"

import "base:runtime"

Worker_Data :: struct {
    command_pool    : vk.CommandPool,
    command_buffers : [FRAMES_IN_FLIGHT]vk.CommandBuffer,
    submit_infos    : [dynamic]vk.SubmitInfo2
}

Worker :: struct {
    thread                  : ^thread.Thread,
    frame_index             : int,
    graphics                : Worker_Data,
    compute                 : Worker_Data,
    transfer                : Worker_Data,
    jobs                    : ^Job_Queue,
    reset_event             : sync.Auto_Reset_Event,
    alloc                   : runtime.Allocator,
    exit                    : bool
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

worker_proc :: proc(ctx : ^Context, sys_idx : int) {
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

        clear(&worker.graphics.submit_infos)
        clear(&worker.compute.submit_infos)
        clear(&worker.transfer.submit_infos)

        for {
            job : Job
            has_job : bool

            if job, has_job = pop(worker.jobs); has_job {

                wait_infos := make([]vk.SemaphoreSubmitInfo, len(job.depends_on))

                for i in 0..<len(wait_infos) {
                    wait_infos[i] = vk.SemaphoreSubmitInfo{
                        sType = .SEMAPHORE_SUBMIT_INFO,
                        
                    }
                }

                submit_info : vk.SubmitInfo2
                submit_info.sType = .SUBMIT_INFO_2
                submit_info.waitSemaphoreInfoCount = u32(len(wait_infos))
                if len(wait_infos) > 0 {
                    submit_info.pWaitSemaphoreInfos = &wait_infos[0]
                }
                
                submit_info.signalSemaphoreInfoCount = 1

                signal_semaphore := vk.SemaphoreSubmitInfo{
                    sType=.SEMAPHORE_SUBMIT_INFO,
                    semaphore=ctx.core_timeline,
                    value=ctx.current_timeline_val + u64(job.timeline_stage)
                }

                submit_info.pSignalSemaphoreInfos = &signal_semaphore
                submit_info.commandBufferInfoCount = 1

                cmd_buffer_submit_info : vk.CommandBufferSubmitInfo
                cmd_buffer_submit_info.sType = .COMMAND_BUFFER_SUBMIT_INFO
                
                submit_info.pCommandBufferInfos = &cmd_buffer_submit_info

                switch val in job.data {
                    case Graphics_Job:
                        // handle graphics job
                        handle_graphics_job(ctx, val, worker.graphics.command_buffers[worker.frame_index])
                        cmd_buffer_submit_info.commandBuffer = ctx.primary_cmd_buf[ctx.frame_idx]
                        append(&worker.graphics.submit_infos, submit_info)
                    case Compute_Job:
                        // handle compute job
                        handle_compute_job(ctx, val, worker.compute.command_buffers[worker.frame_index])
                        cmd_buffer_submit_info.commandBuffer = worker.compute.command_buffers[ctx.frame_idx]
                        append(&worker.compute.submit_infos, submit_info)
                    case Transfer_Job:
                        // handle transfer job
                        handle_transfer_job(ctx, val, worker.transfer.command_buffers[worker.frame_index])
                        cmd_buffer_submit_info.commandBuffer = worker.transfer.command_buffers[ctx.frame_idx]
                        append(&worker.transfer.submit_infos, submit_info)
                }

            } else {
                break
            }
        }
        // submit transfer and compute queues
        // the graphics jobs need to be submitted on the main thread

        compute_queue_fam, _ := find_queue_family_by_type(ctx, {.COMPUTE})
        transfer_queue_fam, _ := find_queue_family_by_type(ctx, {.TRANSFER})

        compute_queue, transfer_queue : vk.Queue

        vk.GetDeviceQueue(ctx.device.logical, compute_queue_fam.family_idx, 0, &compute_queue)
        vk.GetDeviceQueue(ctx.device.logical, transfer_queue_fam.family_idx, 0, &transfer_queue)

        vk.QueueSubmit2(compute_queue, u32(len(worker.compute.submit_infos)), &worker.compute.submit_infos[0], 0)
        vk.QueueSubmit2(transfer_queue, u32(len(worker.transfer.submit_infos)), &worker.transfer.submit_infos[0], 0)

        sync.wait_group_done(&ctx.wait_group)
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
