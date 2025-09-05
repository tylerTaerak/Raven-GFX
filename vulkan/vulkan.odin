package game_vulkan

import "core:math"
import "core:container/queue"
import "core:flags"
import "core:sync"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:thread"
import "core:log"
import gfx_core "../core"

FRAMES_IN_FLIGHT :: 3

WORKER_THREAD_COUNT :: 1

Context :: struct {
    // init fields
    instance            : vk.Instance,
    debug_messenger     : vk.DebugUtilsMessengerEXT,
    window_surface      : vk.SurfaceKHR,
    device              : Device,
    swapchain           : Swapchain,
    render_pass         : vk.RenderPass,
    primary_cmd_pool    : vk.CommandPool,
    primary_cmd_buf     : [FRAMES_IN_FLIGHT]vk.CommandBuffer,

    // runtime fields
    frame_idx           : int,
    frame_semaphores    : [FRAMES_IN_FLIGHT]vk.Semaphore,
    workers             : [WORKER_THREAD_COUNT]^Worker,
    wait_group          : sync.Wait_Group,

    job_queue           : Job_Queue,
    copy_queue_mutex    : sync.Mutex,

    core_timeline       : vk.Semaphore,
    last_timeline_val   : u64,
    delete_buffers      : [dynamic]Buffer,

    // asset data
    descriptor_pool     : vk.DescriptorPool,
    descriptor_sets     : [FRAMES_IN_FLIGHT]vk.DescriptorSet,
    descriptor_layouts  : [FRAMES_IN_FLIGHT]vk.DescriptorSetLayout,
    data                : [FRAMES_IN_FLIGHT]Data,
    pipelines           : [dynamic]Pipeline,
}

create_context :: proc(window : gfx_core.Window) -> (ctx : ^Context, ok : bool = true) {
    ctx = new(Context)
    // first off, load our Vulkan procedures
    vk_instance_proc_addr := sdl.Vulkan_GetVkGetInstanceProcAddr()

    vk.load_proc_addresses(rawptr(vk_instance_proc_addr))

    create_vulkan_instance(ctx) or_return
    vk.load_proc_addresses_instance(ctx.instance)

    if ODIN_DEBUG do create_debug_messenger(ctx) or_return

    pick_physical_device(ctx) or_return
    create_window_surface(ctx, window.window_ptr) or_return

    log.info("Created window surface")

    create_queue_family_properties(ctx) or_return

    log.info("Created queue family properties")

    create_logical_device(ctx, {.GRAPHICS, .COMPUTE, .TRANSFER}) or_return // just assume these queue types
    log.info("Created logical device")

    swapchain_support, _ := get_swapchain_support(ctx)
    create_swapchain(ctx, swapchain_support) or_return

    log.info("Created swapchain")

    create_render_pass(ctx) or_return

    log.info("Created render pass")

    create_framebuffers(ctx) or_return

    log.info("Created framebuffers")

    for i in 0..<FRAMES_IN_FLIGHT {
        create_info : vk.SemaphoreCreateInfo
        create_info.sType = .SEMAPHORE_CREATE_INFO
        if vk.CreateSemaphore(ctx.device.logical, &create_info, {}, &ctx.frame_semaphores[i]) != .SUCCESS {
            log.warn("Error creating frame semaphores")
            ok = false
        }
    }

    log.info("Created frame semaphores")
    
    queue, _ := find_queue_family_by_type(ctx, {.GRAPHICS})
    log.info("Creating Command Pool from Q Fam:", queue.family_idx)
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = queue.family_idx

    if vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &ctx.primary_cmd_pool) != .SUCCESS {
        log.warn("Error creating command pool")
        ok = false
    }

    log.info("Created Command Pool")

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = ctx.primary_cmd_pool
    create_info.level = .PRIMARY

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &ctx.primary_cmd_buf[0])

    log.info("Allocated Buffers")

    sem_type_info : vk.SemaphoreTypeCreateInfo
    sem_type_info.sType = .SEMAPHORE_TYPE_CREATE_INFO
    sem_type_info.semaphoreType = .TIMELINE

    sem_info : vk.SemaphoreCreateInfo
    sem_info.sType = .SEMAPHORE_CREATE_INFO
    sem_info.pNext = &sem_type_info

    if vk.CreateSemaphore(ctx.device.logical, &sem_info, {}, &ctx.core_timeline) != .SUCCESS {
        log.warn("Error creating timline semaphore")
        ok = false
    }

    log.info("Created main timeline semaphore")

    for i in 0..<WORKER_THREAD_COUNT {
        ctx.workers[i], ok = create_worker_thread(ctx)
        ctx.workers[i].vk_context = ctx
        if !ok {
            log.warn("Error starting worker", i)
        }

        thread.start(ctx.workers[i].thread)
    }

    log.info("spun worker threads", ok)

    init_data(ctx)

    for i in 0..<FRAMES_IN_FLIGHT {
        ctx.data[i].camera = create_camera(ctx)
    }

    initialize_descriptor_sets(ctx)

    return
}

run_frame :: proc(ctx : ^Context) {
    img_idx : u32
    // this is a semaphore to signal... not to wait
    vk.AcquireNextImageKHR(ctx.device.logical, ctx.swapchain.chain, 15_000_000, ctx.frame_semaphores[ctx.frame_idx], 0, &img_idx)

    // commit all of our draw commands for this frame
    commit_draws(ctx)

    for pipeline in ctx.pipelines {
        push(&ctx.job_queue, Graphics_Job{
            pipeline=pipeline,
            data={ctx.data[ctx.frame_idx].draw_commands}
        })
    }

    wait_info : vk.SemaphoreWaitInfo
    wait_info.sType = .SEMAPHORE_WAIT_INFO
    wait_info.semaphoreCount = 1
    wait_info.pSemaphores = &ctx.core_timeline
    wait_info.pValues = &ctx.last_timeline_val

    vk.WaitSemaphoresKHR(ctx.device.logical, &wait_info, 15_000_000)

    log.info("Starting Frame")

    for i in 0..<len(ctx.delete_buffers) {
        _destroy_buffer(ctx, ctx.delete_buffers[i])
    }

    clear(&ctx.delete_buffers)

    // It seems like I can have multiple render passes that handle different areas of the framebuffer
    pass_info : vk.RenderPassBeginInfo
    pass_info.sType = .RENDER_PASS_BEGIN_INFO
    pass_info.renderPass = ctx.render_pass
    pass_info.framebuffer = ctx.swapchain.framebuffers[img_idx]
    pass_info.renderArea.offset = {0, 0}
    pass_info.renderArea.extent = ctx.swapchain.extent
    
    clear_color : vk.ClearValue
    clear_color.color.float32 = {0.0, 0.0, 0.0, 1.0}

    pass_info.clearValueCount = 1
    pass_info.pClearValues = &clear_color

    begin_info : vk.CommandBufferBeginInfo
    begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO

    vk.BeginCommandBuffer(ctx.primary_cmd_buf[ctx.frame_idx], &begin_info)

    vk.CmdBeginRenderPass(ctx.primary_cmd_buf[ctx.frame_idx], &pass_info, .INLINE_AND_SECONDARY_COMMAND_BUFFERS_KHR)

    log.info("Started Render Pass", ctx.render_pass)

    log.info("Primary buffer:", ctx.primary_cmd_buf[ctx.frame_idx])

    // copy out the job queue from the context and create a new one for it
    jobs : Job_Queue
    {
        sync.mutex_lock(&ctx.job_queue.mutex)
        defer sync.mutex_unlock(&ctx.job_queue.mutex)

        jobs.jobs = ctx.job_queue.jobs
        queue.clear(&ctx.job_queue.jobs)
    }

    job_count := q_len(&jobs)

    for &worker,i in ctx.workers {
        if worker != nil {
            worker.jobs = &jobs
        }
    }

    log.info("Main Ctx Ptr:", rawptr(ctx))

    // start frame processes for worker threads and do some simple things before waiting
    sync.wait_group_add(&ctx.wait_group, len(ctx.workers))

    for i in 0..<len(ctx.workers) {
        if ctx.workers[i] != nil {
            sync.auto_reset_event_signal(&ctx.workers[i].reset_event)
        }
    }

    gfx_fam, ok_gfx := find_queue_family_by_type(ctx, {.GRAPHICS})
    prs_fam, ok_prs := find_queue_family_present_support(ctx)

    log.info("Graphics Queue:", gfx_fam.family_idx)
    log.info("Present Queue:", prs_fam.family_idx)

    gfx_q, prs_q : vk.Queue

    vk.GetDeviceQueue(ctx.device.logical, gfx_fam.family_idx, 0, &gfx_q)
    vk.GetDeviceQueue(ctx.device.logical, prs_fam.family_idx, 0, &prs_q)

    log.info("Waiting for worker threads")
    // wait for worker threads
    sync.wait_group_wait(&ctx.wait_group)

    buffers : [dynamic]vk.CommandBuffer
    defer delete(buffers)

    for &worker in ctx.workers {
        if worker != nil {
            append(&buffers, worker.gfx_buffers[ctx.frame_idx])
        }
    }

    vk.CmdExecuteCommands(ctx.primary_cmd_buf[ctx.frame_idx], u32(len(buffers)), &buffers[0])

    vk.CmdEndRenderPass(ctx.primary_cmd_buf[ctx.frame_idx])
    vk.EndCommandBuffer(ctx.primary_cmd_buf[ctx.frame_idx])

    submit_infos : [dynamic]vk.SubmitInfo2
    defer delete(submit_infos)

    final_wait_infos    : [dynamic]vk.SemaphoreSubmitInfo
    defer delete(final_wait_infos)

    highest_value : u64 = ctx.last_timeline_val

    for &worker in ctx.workers {
        if worker != nil {
            append(&submit_infos, ..worker.gfx_submissions[:])

            for &info in worker.gfx_submissions {
                for i in 0..<info.signalSemaphoreInfoCount {
                    append(&final_wait_infos, info.pSignalSemaphoreInfos[i])
                }
            }

            log.info("Worker's Highest Timeline", worker.highest_timeline)

            if worker.highest_timeline > highest_value {
                highest_value = worker.highest_timeline
            }
        }

    }

    // frame_wait_info : vk.SemaphoreSubmitInfo
    // frame_wait_info.sType = .SEMAPHORE_SUBMIT_INFO
    // frame_wait_info.semaphore = ctx.frame_semaphores[ctx.frame_idx]

    // append(&final_wait_infos, frame_wait_info)

    frame_signal_info : vk.SemaphoreSubmitInfo
    frame_signal_info.sType = .SEMAPHORE_SUBMIT_INFO
    frame_signal_info.value = highest_value + 1
    frame_signal_info.semaphore = ctx.core_timeline

    final_submit_info : vk.SubmitInfo2
    final_submit_info.sType = .SUBMIT_INFO_2
    final_submit_info.waitSemaphoreInfoCount = u32(len(final_wait_infos))
    final_submit_info.pWaitSemaphoreInfos = &final_wait_infos[0]
    final_submit_info.signalSemaphoreInfoCount = 1
    final_submit_info.pSignalSemaphoreInfos = &frame_signal_info

    append(&submit_infos, final_submit_info)

    log.info("Main Thread Submit")
    vk.QueueSubmit2KHR(gfx_q, u32(len(submit_infos)), &submit_infos[0], 0)

    ctx.last_timeline_val = highest_value + 1

    log.info("Setting Last Frame Value At", ctx.last_timeline_val)

    present_info : vk.PresentInfoKHR
    present_info.sType = .PRESENT_INFO_KHR
    present_info.waitSemaphoreCount = 1
    present_info.pWaitSemaphores = &ctx.frame_semaphores[ctx.frame_idx]
    present_info.swapchainCount = 1
    present_info.pSwapchains = &ctx.swapchain.chain
    present_info.pImageIndices = &img_idx

    log.info("Main Thread Present")
    vk.QueuePresentKHR(prs_q, &present_info)

    ctx.frame_idx = (ctx.frame_idx + 1) % FRAMES_IN_FLIGHT
}

destroy_context :: proc(ctx : ^Context) {
    for &w in ctx.workers {
        sync.atomic_store(&w.exit, true)
    }

    for f in ctx.swapchain.framebuffers {
        vk.DestroyFramebuffer(ctx.device.logical, f, {})
    }
    delete(ctx.swapchain.framebuffers)

    for v in ctx.swapchain.views {
        vk.DestroyImageView(ctx.device.logical, v, {})
    }
    delete(ctx.swapchain.views)

    for i in ctx.swapchain.images {
        vk.DestroyImage(ctx.device.logical, i, {})
    }
    delete(ctx.swapchain.images)

    vk.DestroySwapchainKHR(ctx.device.logical, ctx.swapchain.chain, {})
    delete(ctx.swapchain.images)

    vk.DestroyDevice(ctx.device.logical, {})
    vk.DestroySurfaceKHR(ctx.instance, ctx.window_surface, {})
    if ODIN_DEBUG do vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, {})
    vk.DestroyInstance(ctx.instance, {})

    free(ctx)
}
