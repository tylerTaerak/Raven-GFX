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


Context :: struct {
    // init fields
    instance            : vk.Instance,
    debug_messenger     : vk.DebugUtilsMessengerEXT,
    window_surface      : vk.SurfaceKHR,
    phys_dev            : vk.PhysicalDevice,
    device              : vk.Device,
    queues              : []QueueFamily
}

_create_window_surface :: proc(ctx : ^Context, window : ^sdl.Window) -> (surface: vk.SurfaceKHR, ok : bool) {
    ok = sdl.Vulkan_CreateSurface(window, ctx.instance, {}, &surface)

    return
}

create_context :: proc(window: ^gfx_core.Window, vulkan_extensions: []string) -> (ctx : ^Context, ok : bool = true) {
    ctx = new(Context)
    // first off, load our Vulkan procedures
    vk_instance_proc_addr := sdl.Vulkan_GetVkGetInstanceProcAddr()

    vk.load_proc_addresses(rawptr(vk_instance_proc_addr))

    create_vulkan_instance(ctx) or_return
    vk.load_proc_addresses_instance(ctx.instance)

    if ODIN_DEBUG do create_debug_messenger(ctx) or_return

    pick_physical_device(ctx, vulkan_extensions) or_return

    ctx.window_surface = _create_window_surface(ctx, window.window_ptr) or_return

    log.info("Created window surface")

    _populate_queue_family_properties(ctx) or_return

    log.info("Created queue family properties")

    create_logical_device(ctx, {.GRAPHICS, .COMPUTE, .TRANSFER}, vulkan_extensions) or_return // just assume these queue types
    log.info("Created logical device")

    return
}

acquire_next_image_index :: proc(ctx: ^Context, swapchain: ^$S/Swapchain($N), fence: Fence, semaphore: Semaphore) -> (index: u32, ok : bool = true) {
    res := vk.AcquireNextImageKHR(ctx.device, swapchain.chain, 500, semaphore, fence, &index)

    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
        log.info("Recreating swapchain")
        ok = recreate_swapchain(ctx, swapchain)
    } else if res != .SUCCESS {
        log.error("Error acquiring next swapchain image:", res)
        ok = false
    }
    return
}

draw_rendering :: proc(cmd_buffer : vk.CommandBuffer, pipeline: Pipeline, image: Render_Image) {
    color_barrier : vk.ImageMemoryBarrier2KHR
    color_barrier.sType = .IMAGE_MEMORY_BARRIER_2_KHR
    color_barrier.image = image.image
    color_barrier.oldLayout = .UNDEFINED
    color_barrier.newLayout = .COLOR_ATTACHMENT_OPTIMAL
    color_barrier.subresourceRange.aspectMask = {.COLOR}
    color_barrier.subresourceRange.layerCount = 1
    color_barrier.subresourceRange.levelCount = 1
    color_barrier.srcAccessMask = {}
    color_barrier.srcStageMask = {}
    color_barrier.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT_KHR}
    color_barrier.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}

    dependencies : vk.DependencyInfoKHR
    dependencies.sType = .DEPENDENCY_INFO_KHR
    dependencies.imageMemoryBarrierCount = 1
    dependencies.pImageMemoryBarriers = &color_barrier

    vk.CmdPipelineBarrier2KHR(cmd_buffer, &dependencies)

    info : vk.RenderingInfoKHR
    info.sType = .RENDERING_INFO_KHR
    info.layerCount = 1
    info.colorAttachmentCount = 1
    info.renderArea = {{0, 0}, {image.size.x, image.size.y}}

    attachment : vk.RenderingAttachmentInfoKHR
    attachment.sType = .RENDERING_ATTACHMENT_INFO_KHR
    attachment.imageView = image.view
    attachment.imageLayout = .COLOR_ATTACHMENT_OPTIMAL
    attachment.loadOp = .CLEAR
    attachment.storeOp = .STORE
    attachment.clearValue = {color={uint32={60, 60, 205, 255}}}

    attachments : []vk.RenderingAttachmentInfoKHR = {attachment}

    info.pColorAttachments = &attachments[0]

    vk.CmdBeginRenderingKHR(cmd_buffer, &info)

    vk.CmdBindPipeline(cmd_buffer, .GRAPHICS, pipeline.data)

    vk.CmdSetRasterizerDiscardEnableEXT(cmd_buffer, false)
    vk.CmdSetCullModeEXT(cmd_buffer, {})
    vk.CmdSetFrontFaceEXT(cmd_buffer, .CLOCKWISE)
    vk.CmdSetDepthTestEnableEXT(cmd_buffer, false)
    vk.CmdSetDepthWriteEnableEXT(cmd_buffer, false)
    vk.CmdSetDepthBiasEnableEXT(cmd_buffer, false)
    vk.CmdSetStencilTestEnableEXT(cmd_buffer, false)
    vk.CmdSetLineWidth(cmd_buffer, 1.0)
    vk.CmdSetPolygonModeEXT(cmd_buffer, .FILL)

    viewport : vk.Viewport
    viewport.x = 0
    viewport.y = 0
    viewport.width = f32(image.size.x)
    viewport.height = f32(image.size.y)
    vk.CmdSetViewport(cmd_buffer, 0, 1, &viewport)

    scissor : vk.Rect2D
    scissor.offset = {0, 0}
    scissor.extent = {image.size.x, image.size.y}
    vk.CmdSetScissor(cmd_buffer, 0, 1, &scissor)

    masks : []vk.ColorComponentFlags = {
        {.R, .B, .G, .A}
    }

    vk.CmdSetColorWriteMaskEXT(cmd_buffer, 0, 1, &masks[0])

    enables : []b32 = {
        true
    }

    vk.CmdSetColorBlendEnableEXT(cmd_buffer, 0, 1, &enables[0])

    eqs : []vk.ColorBlendEquationEXT = {
        {
            srcColorBlendFactor = .SRC_COLOR,
            srcAlphaBlendFactor = .SRC_COLOR,
            dstColorBlendFactor = .ONE_MINUS_SRC_COLOR,
            dstAlphaBlendFactor = .ONE_MINUS_SRC_COLOR
        }
    }

    vk.CmdSetColorBlendEquationEXT(cmd_buffer, 0, 1, &eqs[0])

    vk.CmdDraw(cmd_buffer, 3, 1, 0, 0)

    vk.CmdEndRenderingKHR(cmd_buffer)

    present_barrier : vk.ImageMemoryBarrier2KHR
    present_barrier.sType = .IMAGE_MEMORY_BARRIER_2_KHR
    present_barrier.image = image.image
    present_barrier.oldLayout = .COLOR_ATTACHMENT_OPTIMAL
    present_barrier.newLayout = .PRESENT_SRC_KHR
    present_barrier.subresourceRange.aspectMask = {.COLOR}
    present_barrier.subresourceRange.layerCount = 1
    present_barrier.subresourceRange.levelCount = 1
    present_barrier.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT_KHR}
    present_barrier.srcAccessMask = {.COLOR_ATTACHMENT_WRITE}
    present_barrier.dstStageMask = {}
    present_barrier.dstAccessMask = {}

    dependencies2 : vk.DependencyInfo
    dependencies2.sType = .DEPENDENCY_INFO_KHR
    dependencies2.imageMemoryBarrierCount = 1
    dependencies2.pImageMemoryBarriers = &present_barrier

    vk.CmdPipelineBarrier2KHR(cmd_buffer, &dependencies2)
}

submit_command_buffer :: proc(ctx: ^Context, cmd_buf : vk.CommandBuffer, queue: QueueFamily, wait_sem, signal_sem : Semaphore, signal_fence : Fence) {
    submit_info : vk.SubmitInfo2KHR
    submit_info.sType = .SUBMIT_INFO_2_KHR
    submit_info.commandBufferInfoCount = 1
    submit_info.waitSemaphoreInfoCount = 1
    submit_info.signalSemaphoreInfoCount = 1

    cmd_info : vk.CommandBufferSubmitInfoKHR
    cmd_info.sType = .COMMAND_BUFFER_SUBMIT_INFO_KHR
    cmd_info.commandBuffer = cmd_buf

    wait_info : vk.SemaphoreSubmitInfo
    wait_info.sType = .SEMAPHORE_SUBMIT_INFO
    wait_info.semaphore = wait_sem

    sig_info : vk.SemaphoreSubmitInfo
    sig_info.sType = .SEMAPHORE_SUBMIT_INFO
    sig_info.semaphore = signal_sem

    submit_info.pCommandBufferInfos = &cmd_info
    submit_info.pWaitSemaphoreInfos = &wait_info
    submit_info.pSignalSemaphoreInfos = &sig_info

    vkq : vk.Queue
    vk.GetDeviceQueue(ctx.device, queue.family_idx, 0, &vkq)

    vk.QueueSubmit2KHR(vkq, 1, &submit_info, signal_fence)
}

present_image :: proc(ctx: ^Context, swapchain: ^$S/Swapchain($N), index: u32, wait_sem : ^Semaphore) -> (ok : bool = true) {
    image_indices : []u32 = {index}

    queue_fam, _ := find_queue_family_present_support(ctx)

    queue : vk.Queue
    vk.GetDeviceQueue(ctx.device, queue_fam.family_idx, 0, &queue)

    info : vk.PresentInfoKHR
    info.sType = .PRESENT_INFO_KHR
    info.swapchainCount = 1
    info.pSwapchains = &swapchain.chain
    info.pImageIndices = &image_indices[0]
    info.waitSemaphoreCount = 1
    info.pWaitSemaphores = wait_sem

    res := vk.QueuePresentKHR(queue, &info)

    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
        log.info("recreating swapchain")
        ok = recreate_swapchain(ctx, swapchain)
    } else if res != .SUCCESS {
        log.error("Error Presenting Queue: ", res)
        ok = false
    }

    return
}

destroy_context :: proc(ctx : ^Context) {
    delete(ctx.queues)

    vk.DestroySurfaceKHR(ctx.instance, ctx.window_surface, {})

    vk.DestroyDevice(ctx.device, {})
    if ODIN_DEBUG do vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, {})
    vk.DestroyInstance(ctx.instance, {})

    free(ctx)
}

wait_for_idle :: proc(ctx : ^Context) {
    vk.DeviceWaitIdle(ctx.device)
}
