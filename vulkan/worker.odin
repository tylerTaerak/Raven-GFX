package game_vulkan

import "core:log"
import vk "vendor:vulkan"

import "core:thread"
import "core:sync"
import "core:slice"

import "base:runtime"

Worker :: struct {
    thread                  : ^thread.Thread,
    ctx                     : ^Context,
    jobs                    : ^Job_Queue,
    reset_event             : sync.Auto_Reset_Event,
    gfx_buffers             : [FRAMES_IN_FLIGHT]vk.CommandBuffer,
    gfx_submissions         : [dynamic]vk.SubmitInfo2,
    highest_timeline        : u64,
    exit                    : bool
}

create_worker_thread :: proc(ctx: ^Context) -> (worker: ^Worker, ok : bool = true) {
    thread_ctx : runtime.Context
    thread_ctx = runtime.default_context()
    thread_ctx.allocator = runtime.heap_allocator()
    thread_ctx.logger = log.create_console_logger()

    worker = new(Worker, thread_ctx.allocator)
    worker.thread = thread.create(worker_proc)
    worker.thread.init_context = thread_ctx
    worker.thread.creation_allocator = runtime.heap_allocator()
    worker.thread.user_args[0] = rawptr(worker)
    worker.thread.user_args[1] = rawptr(ctx)
    return
}

handle_graphics_job :: proc(worker: ^Worker, job : Graphics_Job, command_buffer : vk.CommandBuffer) {
    desc_set := worker.ctx.descriptor_sets[worker.ctx.frame_idx]
    vk.CmdBindPipeline(command_buffer, .GRAPHICS, job.pipeline.data)
    vk.CmdBindIndexBuffer(command_buffer, worker.ctx.data[worker.ctx.frame_idx].index_buffer.buf, 0, .UINT32)
    vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, job.pipeline.layout, 0, 1, &desc_set, 0, nil)
    vk.CmdDrawIndexedIndirect(command_buffer, worker.ctx.data[worker.ctx.frame_idx].draw_commands.buf, 0, 0, 0)
}

handle_compute_job :: proc(worker: ^Worker, job : Compute_Job, command_buffer : vk.CommandBuffer) {
}

handle_transfer_job :: proc(worker: ^Worker, job : Transfer_Job, command_buffer : vk.CommandBuffer) {
    assert(job.src_buffer.size == job.dest_buffer.size)

    copy_info : vk.BufferCopy
    copy_info.size = job.src_buffer.size
    copy_info.srcOffset = job.src_buffer.offset
    copy_info.dstOffset = job.dest_buffer.offset
    
    vk.CmdCopyBuffer(command_buffer, job.src_buffer.buffer, job.dest_buffer.buffer, 1, &copy_info)
}

worker_proc :: proc(subproc: ^thread.Thread) {
    worker : ^Worker = cast(^Worker)subproc.user_args[0]
    worker.ctx = cast(^Context)subproc.user_args[1]
    defer free(worker)

    gfx_pool, gfx_buffers, g_ok := _init_worker_graphics_data(worker)
    cmp_pool, cmp_buffers, c_ok := _init_worker_compute_data(worker)
    trs_pool, trs_buffers, t_ok := _init_worker_transfer_data(worker)

    worker.gfx_buffers = gfx_buffers
    
    cmp_submissions : [dynamic]vk.SubmitInfo2
    trs_submissions : [dynamic]vk.SubmitInfo2

    defer vk.DestroyCommandPool(worker.ctx.device.logical, gfx_pool, {})
    defer vk.FreeCommandBuffers(worker.ctx.device.logical, gfx_pool, len(gfx_buffers), &gfx_buffers[0])

    defer vk.DestroyCommandPool(worker.ctx.device.logical, cmp_pool, {})
    defer vk.FreeCommandBuffers(worker.ctx.device.logical, cmp_pool, len(cmp_buffers), &cmp_buffers[0])

    defer vk.DestroyCommandPool(worker.ctx.device.logical, trs_pool, {})
    defer vk.FreeCommandBuffers(worker.ctx.device.logical, trs_pool, len(trs_buffers), &trs_buffers[0])

    for !sync.atomic_load(&worker.exit) {
        sync.auto_reset_event_wait(&worker.reset_event)
        if sync.atomic_load(&worker.exit) do break


        vk.ResetCommandPool(worker.ctx.device.logical, gfx_pool, {})
        vk.ResetCommandPool(worker.ctx.device.logical, cmp_pool, {})
        vk.ResetCommandPool(worker.ctx.device.logical, trs_pool, {})

        clear(&worker.gfx_submissions)
        clear(&cmp_submissions)
        clear(&trs_submissions)

        inheritance_info : vk.CommandBufferInheritanceInfo
        inheritance_info.sType = .COMMAND_BUFFER_INHERITANCE_INFO
        inheritance_info.renderPass = worker.ctx.render_pass

        begin_info : vk.CommandBufferBeginInfo
        begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
        begin_info.flags = {.RENDER_PASS_CONTINUE}
        begin_info.pInheritanceInfo = &inheritance_info

        bare_begin_info : vk.CommandBufferBeginInfo
        bare_begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO

        log.info(worker.ctx.frame_idx)
        vk.BeginCommandBuffer(gfx_buffers[worker.ctx.frame_idx], &begin_info)
        vk.BeginCommandBuffer(cmp_buffers[worker.ctx.frame_idx], &bare_begin_info)
        vk.BeginCommandBuffer(trs_buffers[worker.ctx.frame_idx], &bare_begin_info)

        for {
            job : Job
            has_job : bool

            if job, has_job = pop(worker.jobs); has_job {

                full_timeline_val := 1 + worker.ctx.last_timeline_val + u64(job.timeline_stage)

                if full_timeline_val > worker.highest_timeline {
                    worker.highest_timeline = full_timeline_val
                }

                wait_infos : [dynamic]vk.SemaphoreSubmitInfo
                defer delete(wait_infos)

                deps, _ := slice.map_keys(job.depends_on)

                for d in deps {
                    if d in worker.jobs.dependencies {
                        wait_timeline_val := 1 + worker.ctx.last_timeline_val + u64(worker.jobs.dependencies[d])
                        append(&wait_infos, vk.SemaphoreSubmitInfo {
                            sType = .SEMAPHORE_SUBMIT_INFO,
                            semaphore = worker.ctx.core_timeline,
                            value = wait_timeline_val
                        })
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
                    semaphore=worker.ctx.core_timeline,
                    value=full_timeline_val
                }

                submit_info.pSignalSemaphoreInfos = &signal_semaphore
                submit_info.commandBufferInfoCount = 1

                cmd_buffer_submit_info : vk.CommandBufferSubmitInfo
                cmd_buffer_submit_info.sType = .COMMAND_BUFFER_SUBMIT_INFO
                
                submit_info.pCommandBufferInfos = &cmd_buffer_submit_info

                switch val in job.data {
                    case Graphics_Job:
                        // handle graphics job
                        log.info("Processing graphics job with timeline value", full_timeline_val)
                        handle_graphics_job(worker, val, gfx_buffers[worker.ctx.frame_idx])
                        cmd_buffer_submit_info.commandBuffer = worker.ctx.primary_cmd_buf[worker.ctx.frame_idx]
                        append(&worker.gfx_submissions, submit_info)
                    case Compute_Job:
                        // handle compute job
                        log.info("Processing compute job with timeline value", full_timeline_val)
                        handle_compute_job(worker, val, cmp_buffers[worker.ctx.frame_idx])
                        cmd_buffer_submit_info.commandBuffer = cmp_buffers[worker.ctx.frame_idx]
                        append(&cmp_submissions, submit_info)
                    case Transfer_Job:
                        // handle transfer job
                        log.info("Processing transfer job with timeline value", full_timeline_val)
                        handle_transfer_job(worker, val, trs_buffers[worker.ctx.frame_idx])
                        cmd_buffer_submit_info.commandBuffer = trs_buffers[worker.ctx.frame_idx]
                        append(&trs_submissions, submit_info)
                }

            } else {
                break
            }
        }
        // submit transfer and compute queues
        // the graphics jobs need to be submitted on the main thread

        vk.EndCommandBuffer(gfx_buffers[worker.ctx.frame_idx])

        // signal to main thread that we're done with gramfix
        sync.wait_group_done(&worker.ctx.wait_group)

        vk.EndCommandBuffer(cmp_buffers[worker.ctx.frame_idx])
        vk.EndCommandBuffer(trs_buffers[worker.ctx.frame_idx])

        log.info(cmp_buffers[worker.ctx.frame_idx])
        log.info(trs_buffers[worker.ctx.frame_idx])

        compute_queue_fam, _ := find_queue_family_by_type(worker.ctx, {.COMPUTE})
        transfer_queue_fam, _ := find_queue_family_by_type(worker.ctx, {.TRANSFER})

        compute_queue, transfer_queue : vk.Queue

        vk.GetDeviceQueue(worker.ctx.device.logical, compute_queue_fam.family_idx, 0, &compute_queue)
        vk.GetDeviceQueue(worker.ctx.device.logical, transfer_queue_fam.family_idx, 0, &transfer_queue)
        
        log.info(vk.QueueSubmit2, vk.QueueSubmit2KHR)

        if len(cmp_submissions) > 0 {
            vk.QueueSubmit2KHR(compute_queue, u32(len(cmp_submissions)), &cmp_submissions[0], 0)
        }

        if len(trs_submissions) > 0 {
            log.info("TRS Queue Fam", transfer_queue_fam.family_idx)
            log.info("Worker Submit")
            vk.QueueSubmit2KHR(transfer_queue, u32(len(trs_submissions)), &trs_submissions[0], 0)
        }

    }
}

_init_worker_graphics_data :: proc(worker : ^Worker) -> (command_pool: vk.CommandPool, buffers: [FRAMES_IN_FLIGHT]vk.CommandBuffer, ok : bool = true) {
    gfx_queue, _ := find_queue_family_present_support(worker.ctx)
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = gfx_queue.family_idx

    res := vk.CreateCommandPool(worker.ctx.device.logical, &cmd_pool_create_info, {}, &command_pool)
    if res != .SUCCESS {
        log.warn("Error creating command pool:", res)
        ok = false
    }

    log.info("Command Pool for GFX:", command_pool, "; GFX Queue Fam:", gfx_queue.family_idx)
    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = command_pool
    create_info.level = .SECONDARY

    res = vk.AllocateCommandBuffers(worker.ctx.device.logical, &create_info, &buffers[0])

    if res != .SUCCESS {
        log.warn("Error allocating command buffer:", res)
    }
    return
}

_init_worker_compute_data :: proc(worker : ^Worker) -> (command_pool: vk.CommandPool, buffers: [FRAMES_IN_FLIGHT]vk.CommandBuffer, ok: bool = true) {
    cmp_queue, _ := find_queue_family_by_type(worker.ctx, {.COMPUTE})
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = cmp_queue.family_idx

    vk.CreateCommandPool(worker.ctx.device.logical, &cmd_pool_create_info, {}, &command_pool)

    log.info("Command Pool for CMP:", command_pool)
    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = command_pool

    vk.AllocateCommandBuffers(worker.ctx.device.logical, &create_info, &buffers[0])
    return
}

_init_worker_transfer_data :: proc(worker : ^Worker) -> (command_pool: vk.CommandPool, buffers: [FRAMES_IN_FLIGHT]vk.CommandBuffer, ok: bool = true) {
    trs_queue, _ := find_queue_family_by_type(worker.ctx, {.TRANSFER})
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = trs_queue.family_idx

    vk.CreateCommandPool(worker.ctx.device.logical, &cmd_pool_create_info, {}, &command_pool)

    log.info("Command Pool for TRS:", command_pool, "; Queue Fam:", trs_queue.family_idx)
    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = command_pool

    vk.AllocateCommandBuffers(worker.ctx.device.logical, &create_info, &buffers[0])
    return
}
