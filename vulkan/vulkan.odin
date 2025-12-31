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

    create_logical_device(ctx, {.GRAPHICS, .COMPUTE, .TRANSFER}) or_return // just assume these queue types
    log.info("Created logical device")

    return
}

acquire_next_image_index :: proc(ctx: ^Context, swapchain: ^Swapchain, fence: Fence) -> (index: u32) {
    vk.AcquireNextImageKHR(ctx.device, swapchain.chain, 500, 0, fence, &index)
    return
}

draw_rendering :: proc(cmd_buffer : vk.CommandBuffer, image: Render_Image) {
    info : vk.RenderingInfo
    info.sType = .RENDERING_INFO
    info.layerCount = 1
    info.colorAttachmentCount = 1
    info.renderArea = {{0, 0}, {image.size.x, image.size.y}}

    attachment : vk.RenderingAttachmentInfo
    attachment.sType = .RENDERING_ATTACHMENT_INFO
    attachment.imageView = image.view
    attachment.imageLayout = .COLOR_ATTACHMENT_OPTIMAL
    attachment.resolveImageView = image.view
    attachment.resolveImageLayout = .PRESENT_SRC_KHR
    attachment.loadOp = .CLEAR
    attachment.storeOp = .STORE
    attachment.clearValue = {color={uint32={60, 60, 205, 255}}}

    info.pColorAttachments = &attachment

    vk.CmdBeginRendering(cmd_buffer, &info)

    vk.CmdEndRendering(cmd_buffer)
}

present_image :: proc(ctx: ^Context, swapchain: ^Swapchain, index: u32) {
    image_indices : []u32 = {index}

    queue_fam, ok := find_queue_family_present_support(ctx)

    queue : vk.Queue
    vk.GetDeviceQueue(ctx.device, queue_fam.family_idx, 0, &queue)

    info : vk.PresentInfoKHR
    info.sType = .PRESENT_INFO_KHR
    info.swapchainCount = 1
    info.pSwapchains = &swapchain.chain
    info.pImageIndices = &image_indices[0]

    vk.QueuePresentKHR(queue, &info)
}

destroy_context :: proc(ctx : ^Context) {
    delete(ctx.queues)

    vk.DestroySurfaceKHR(ctx.instance, ctx.window_surface, {})

    vk.DestroyDevice(ctx.device, {})
    if ODIN_DEBUG do vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, {})
    vk.DestroyInstance(ctx.instance, {})

    free(ctx)
}
