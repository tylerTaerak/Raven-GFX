package game_vulkan

import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "../core"

import "core:log"

SwapchainSupport :: struct {
    capabilities    : vk.SurfaceCapabilitiesKHR,
    formats         : []vk.SurfaceFormatKHR,
    present_modes   : []vk.PresentModeKHR
}

Swapchain :: struct ($Frame_Count : int) {
    chain           : vk.SwapchainKHR,
    images          : [Frame_Count]vk.Image,
    views           : [Frame_Count]vk.ImageView,
    sync            : [Frame_Count]Frame_Sync,
    window_ptr      : ^sdl.Window,
    format          : vk.SurfaceFormatKHR,
    extent          : vk.Extent2D,
    present_mode    : vk.PresentModeKHR
}

create_swapchain :: proc(ctx : ^Context, window : ^sdl.Window, $N: int, previous_swapchain : ^Swapchain(N)) -> (chain: Swapchain(N), ok : bool) {
    support := _get_swapchain_support(ctx) or_return

    w, h : i32
    sdl.GetWindowSizeInPixels(window, &w, &h)

    chain.format = _pick_swap_surface_format(support)
    chain.present_mode = _pick_swap_present_mode(support)
    chain.extent = _pick_swap_extent(support, u32(w), u32(h)) // TODO)) figure out a way to get window dimensions here
    chain.window_ptr = window

    if support.capabilities.maxImageCount == 0 {
        log.error("No images available for swapchain")
        ok = false
    }

    image_count : u32 = clamp(support.capabilities.minImageCount + 1, support.capabilities.minImageCount, support.capabilities.maxImageCount)
    // TODO)) I might need to determine whether a graphics queue family is distinct from a family that supports presentKHR
    supported_family, _ := find_queue_family_present_support(ctx)
    queue_indices : []u32 = {supported_family.family_idx}

    create_info : vk.SwapchainCreateInfoKHR
    create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
    create_info.imageFormat = chain.format.format
    create_info.imageColorSpace = chain.format.colorSpace
    create_info.presentMode = chain.present_mode
    create_info.imageExtent = chain.extent
    create_info.minImageCount = image_count
    create_info.imageArrayLayers = 1
    create_info.imageUsage = {.COLOR_ATTACHMENT}
    create_info.surface = ctx.window_surface

    // reuse any applicable resources
    if previous_swapchain != nil { 
        create_info.oldSwapchain = previous_swapchain.chain
    }

    create_info.imageSharingMode = .EXCLUSIVE
    create_info.queueFamilyIndexCount = u32(len(queue_indices))
    create_info.pQueueFamilyIndices = &queue_indices[0]

    create_info.preTransform = support.capabilities.currentTransform
    create_info.compositeAlpha = {.OPAQUE}
    create_info.clipped = true

    res := vk.CreateSwapchainKHR(ctx.device, &create_info, {}, &chain.chain)
    if res != .SUCCESS {
        log.error("Error creating swapchain:", res)
        ok = false
    }

    img_count := u32(N)
    vk.GetSwapchainImagesKHR(ctx.device, chain.chain, &img_count, &chain.images[0])

    chain.views, ok = _create_image_views(ctx.device, chain)

    for i in 0..<N {
        chain.sync[i] = init_frame_sync(ctx)
    }

    log.info("Created Swapchain", chain.chain)

    return
}

recreate_swapchain :: proc(ctx: ^Context, swapchain: ^$S/Swapchain($N)) -> (ok: bool = true) {
    w, h : i32
    sdl.GetWindowSizeInPixels(swapchain.window_ptr, &w, &h)
    if w == 0 || h == 0  {
        log.info("Found invalid window size, skipping frame")
        ok = false
        return
    }

    wait_for_idle(ctx)

    old_chain := swapchain^

    swapchain^, ok = create_swapchain(ctx, swapchain.window_ptr, len(swapchain.images), swapchain)

    if !ok {
        log.error("Error recreating swapchain")
        swapchain^ = old_chain
    } else {
        destroy_swapchain(ctx, &old_chain)
    }

    return
}


_get_swapchain_support :: proc(ctx : ^Context) -> (support : SwapchainSupport, ok : bool) {
    ok = true

    res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.phys_dev, ctx.window_surface, &support.capabilities)
    if res != .SUCCESS {
        log.error("Error retrieving surface capabilities for swapchain support detection")
        ok = false
    }

    format_count : u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.phys_dev, ctx.window_surface, &format_count, nil)

    log.info("Found", format_count, "color formats for physical device")

    support.formats = make([]vk.SurfaceFormatKHR, format_count)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.phys_dev, ctx.window_surface, &format_count, &support.formats[0])

    log.info("PHysical device formats:", support.formats)

    pm_count : u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.phys_dev, ctx.window_surface, &pm_count, nil)

    support.present_modes = make([]vk.PresentModeKHR, pm_count)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.phys_dev, ctx.window_surface, &pm_count, &support.present_modes[0])

    if format_count == 0 || pm_count == 0 {
        log.error("Unable to properly retrieve swapchain support details")
        ok = false
    }

    return
}

_pick_swap_surface_format :: proc(sc_support : SwapchainSupport) -> (format : vk.SurfaceFormatKHR) {
    format = sc_support.formats[0]
    log.info("available swapchain formats:", sc_support.formats)
    for available_format in sc_support.formats {
        if available_format.format == .R8G8B8A8_UNORM && available_format.colorSpace == .SRGB_NONLINEAR {
            format = available_format
            break
        }
    }

    log.info("Picking swapchain color format: ", format)

    return
}

_pick_swap_present_mode :: proc(sc_support : SwapchainSupport) -> (present_mode : vk.PresentModeKHR) {
    present_mode = .FIFO

    for mode in sc_support.present_modes {
        if mode == .MAILBOX {
            present_mode = mode
        }
    }

    return
}

_pick_swap_extent :: proc(sc_support : SwapchainSupport, w, h : u32) -> (extent : vk.Extent2D) {
    if (sc_support.capabilities.currentExtent.width != max(u32)) {
        extent = sc_support.capabilities.currentExtent
    } else {
        extent.width = clamp(w, sc_support.capabilities.minImageExtent.width, sc_support.capabilities.maxImageExtent.width)
        extent.height = clamp(h, sc_support.capabilities.minImageExtent.height, sc_support.capabilities.maxImageExtent.height)
    }

    return
}


_create_image_views :: proc(device : vk.Device, swapchain : Swapchain($N)) -> (views : [N]vk.ImageView, ok : bool) {
    ok = true

    for img, idx in swapchain.images {
        create_info : vk.ImageViewCreateInfo
        create_info.sType = .IMAGE_VIEW_CREATE_INFO
        create_info.image = img
        create_info.viewType = .D2
        create_info.format = swapchain.format.format

        create_info.components.r = .IDENTITY
        create_info.components.g = .IDENTITY
        create_info.components.b = .IDENTITY
        create_info.components.a = .IDENTITY

        create_info.subresourceRange.aspectMask = {.COLOR}
        create_info.subresourceRange.baseMipLevel = 0
        create_info.subresourceRange.levelCount = 1
        create_info.subresourceRange.baseArrayLayer = 0
        create_info.subresourceRange.layerCount = 1

        res := vk.CreateImageView(device, &create_info, {}, &views[idx])
        if res != .SUCCESS {
            log.error("Error creating image view for index", idx)
            ok = false
        }
    }
    
    return
}

destroy_swapchain :: proc(ctx: ^Context, chain: ^$S/Swapchain($N)) {
    for i in 0..<N {
        destroy_frame_sync(ctx, &chain.sync[i])
    }

    for i in 0..<N {
        vk.DestroyImageView(ctx.device, chain.views[i], {})
    }

    vk.DestroySwapchainKHR(ctx.device, chain.chain, {})
}
