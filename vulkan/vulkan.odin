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


// TODO)) There shouldn't really be a "central context" at this level -
// separate these things out into their own data pieces,
// which will be used by the rendering engine one layer up
//
// it stands to reason that things that aren't included here could fit well as separate libraries,
// like what I've done with the GPU memory allocator
Context :: struct {
    // init fields
    // --- These should be the "Instance Data"
    instance            : vk.Instance,
    debug_messenger     : vk.DebugUtilsMessengerEXT,

    // --- This should be the "Window Data"
    window_surface      : vk.SurfaceKHR,

    // --- This should be the "Device Data"
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

// TODO)) It might be worthwhile to have the "wait/signal" pattern be a common pattern throughout the project
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

submit_command_buffer :: proc(ctx: ^Context, cmd_buf : vk.CommandBuffer, queue: QueueFamily, wait_sem, signal_sem : Semaphore, signal_fence : Fence) {
    submit_info : vk.SubmitInfo2KHR
    submit_info.sType = .SUBMIT_INFO_2_KHR
    submit_info.commandBufferInfoCount = 1

    cmd_info : vk.CommandBufferSubmitInfoKHR
    cmd_info.sType = .COMMAND_BUFFER_SUBMIT_INFO_KHR
    cmd_info.commandBuffer = cmd_buf
    submit_info.pCommandBufferInfos = &cmd_info

    if wait_sem != 0 {
        submit_info.waitSemaphoreInfoCount = 1

        wait_info : vk.SemaphoreSubmitInfo
        wait_info.sType = .SEMAPHORE_SUBMIT_INFO
        wait_info.semaphore = wait_sem
        submit_info.pWaitSemaphoreInfos = &wait_info
    }

    if signal_sem != 0 {
        submit_info.signalSemaphoreInfoCount = 1

        sig_info : vk.SemaphoreSubmitInfo
        sig_info.sType = .SEMAPHORE_SUBMIT_INFO
        sig_info.semaphore = signal_sem
        submit_info.pSignalSemaphoreInfos = &sig_info
    }

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
