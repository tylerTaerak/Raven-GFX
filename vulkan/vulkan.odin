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

    populate_queue_family_properties(ctx) or_return

    log.info("Created queue family properties")

    create_logical_device(ctx, {.GRAPHICS, .COMPUTE, .TRANSFER}) or_return // just assume these queue types
    log.info("Created logical device")

    return
}

destroy_context :: proc(ctx : ^Context) {
    delete(ctx.queues)

    vk.DestroyDevice(ctx.device, {})
    vk.DestroySurfaceKHR(ctx.instance, ctx.window_surface, {})
    if ODIN_DEBUG do vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, {})
    vk.DestroyInstance(ctx.instance, {})

    free(ctx)
}
