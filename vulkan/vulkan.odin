package game_vulkan

import "core:flags"
import "core:sync"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:thread"
import "core:log"
import gfx_core "../core"

FRAMES_IN_FLIGHT :: 3

WORKER_THREAD_COUNT :: 4

Frame_Sync :: struct {
    in_flight_fence : vk.Fence,
    image_available : vk.Semaphore,
    render_finished : vk.Semaphore
}

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
    frame_sync_data     : [FRAMES_IN_FLIGHT]Frame_Sync,
    job_queues          : [FRAMES_IN_FLIGHT]Job_Queue,
    job_id_offset       : u64,
    job_count           : u64,
    processed_jobs      : map[u32]Maybe(byte),
    subsystems          : [dynamic]Subsystem,
    workers             : [WORKER_THREAD_COUNT]Worker,
    wait_group          : sync.Wait_Group,

    // asset data
    data                : Data
}

// TODO)) I think this is the extent we need for basic rendering (of course more may be required later),
// but this is the basic stuff that now supports the common context
// the next thing to do is determine how workers need to work in order to properly run graphics/compute
// systems in parallel
create_context :: proc(window : gfx_core.Window) -> (ctx : Context, ok : bool = true) {
    // first off, load our Vulkan procedures
    vk_instance_proc_addr := sdl.Vulkan_GetVkGetInstanceProcAddr()

    vk.load_proc_addresses(rawptr(vk_instance_proc_addr))

    create_instance(&ctx) or_return
    vk.load_proc_addresses_instance(ctx.instance)

    if ODIN_DEBUG do create_debug_messenger(&ctx) or_return

    pick_physical_device(&ctx) or_return
    create_window_surface(&ctx, window.window_ptr) or_return

    log.info("Created window surface")

    create_queue_family_properties(&ctx) or_return

    log.info("Created queue family properties")

    create_logical_device(&ctx, {.GRAPHICS, .COMPUTE, .TRANSFER}) or_return // just assume these queue types
    log.info("Created logical device")

    swapchain_support, _ := get_swapchain_support(&ctx)
    create_swapchain(&ctx, swapchain_support) or_return

    log.info("Created swapchain")

    create_render_pass(&ctx) or_return

    log.info("Created render pass")

    create_framebuffers(&ctx) or_return

    log.info("Created framebuffers")

    for &f in ctx.frame_sync_data {
        f.in_flight_fence = create_fence(&ctx) or_return
        f.image_available = create_semaphore(&ctx) or_return
        f.render_finished = create_semaphore(&ctx) or_return
    }

    log.info("Created sync mechanisms")

    queue, _ := find_queue_family_present_support(&ctx)
    cmd_pool_create_info : vk.CommandPoolCreateInfo
    cmd_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
    cmd_pool_create_info.flags = {.RESET_COMMAND_BUFFER}
    cmd_pool_create_info.queueFamilyIndex = queue.family_idx

    if vk.CreateCommandPool(ctx.device.logical, &cmd_pool_create_info, {}, &ctx.primary_cmd_pool) != .SUCCESS {
        ok = false
    }

    create_info : vk.CommandBufferAllocateInfo
    create_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    create_info.commandBufferCount = FRAMES_IN_FLIGHT
    create_info.commandPool = ctx.primary_cmd_pool
    create_info.level = .PRIMARY

    vk.AllocateCommandBuffers(ctx.device.logical, &create_info, &ctx.primary_cmd_buf[0])

    return
}

run_frame :: proc(ctx : ^Context) {
    frame := ctx.frame_sync_data[ctx.frame_idx]
    img_idx : u32
    vk.AcquireNextImageKHR(ctx.device.logical, ctx.swapchain.chain, 15_000_000, frame.image_available, 0, &img_idx)

    vk.WaitForFences(ctx.device.logical, 1, &frame.in_flight_fence, true, 15_000_000)
    vk.ResetFences(ctx.device.logical, 1, &frame.in_flight_fence)

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

    log.info("Render Pass Begin")

    // start frame processes for subsystems and wait
    sync.wait_group_add(&ctx.wait_group, len(ctx.subsystems))

    for &sys in ctx.subsystems {
        sync.auto_reset_event_signal(&sys.reset_event)
    }
    log.info("Started subsystem frame procedure")

    sync.wait_group_wait(&ctx.wait_group)
    log.info("Jobs Done. Continuing render")

    gfx_fam, ok_gfx := find_queue_family_by_type(ctx, {.GRAPHICS})
    prs_fam, ok_prs := find_queue_family_present_support(ctx)

    gfx_q, prs_q : vk.Queue

    vk.GetDeviceQueue(ctx.device.logical, gfx_fam.family_idx, 0, &gfx_q)
    vk.GetDeviceQueue(ctx.device.logical, prs_fam.family_idx, 0, &prs_q)

    buffers : [dynamic]vk.CommandBuffer
    defer delete(buffers)

    for &sys in ctx.subsystems {
        append(&buffers, sys.command_buffers[ctx.frame_idx])
    }

    vk.CmdExecuteCommands(ctx.primary_cmd_buf[ctx.frame_idx], u32(len(buffers)), &buffers[0])

    vk.CmdEndRenderPass(ctx.primary_cmd_buf[ctx.frame_idx])
    vk.EndCommandBuffer(ctx.primary_cmd_buf[ctx.frame_idx])


    current_buffer := ctx.primary_cmd_buf[ctx.frame_idx]

    flags : vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}
    
    submit_info : vk.SubmitInfo
    submit_info.sType = .SUBMIT_INFO
    submit_info.waitSemaphoreCount = 1
    submit_info.pWaitSemaphores = &frame.image_available
    submit_info.signalSemaphoreCount = 1
    submit_info.pSignalSemaphores = &frame.render_finished
    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = &current_buffer
    submit_info.pWaitDstStageMask = &flags // need to get COLOR bit here

    log.info("Submitting Queue")
    vk.QueueSubmit(prs_q, 1, &submit_info, frame.in_flight_fence)

    present_info : vk.PresentInfoKHR
    present_info.sType = .PRESENT_INFO_KHR
    present_info.waitSemaphoreCount = 1
    present_info.pWaitSemaphores = &frame.render_finished
    present_info.swapchainCount = 1
    present_info.pSwapchains = &ctx.swapchain.chain
    present_info.pImageIndices = &img_idx

    log.info("Presenting Queue")
    vk.QueuePresentKHR(prs_q, &present_info)

    ctx.frame_idx = (ctx.frame_idx + 1) % FRAMES_IN_FLIGHT

    log.info("Render pass End")
}

destroy_context :: proc(ctx : ^Context) {
    for &sys in ctx.subsystems {
        sync.atomic_store(&sys.exit, true)
    }

    for &f in ctx.frame_sync_data {
        vk.DestroySemaphore(ctx.device.logical, f.render_finished, {})
        vk.DestroySemaphore(ctx.device.logical, f.image_available, {})
        vk.DestroyFence(ctx.device.logical, f.in_flight_fence, {})
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
}
