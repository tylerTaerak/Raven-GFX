package game_vulkan

import vk "vendor:vulkan"
import "core:log"

SwapchainSupport :: struct {
    capabilities    : vk.SurfaceCapabilitiesKHR,
    formats         : []vk.SurfaceFormatKHR,
    present_modes   : []vk.PresentModeKHR
}

// Really, a swapchain just contains a series of Render_Images, plus some various configuration data
// And I think most of this configuration data is baked into the swapchain creation - so...
// I think it is basically a set of Render Images with a Swapchain Handle
Swapchain :: struct ($Frame_Count : int) {
    chain           : vk.SwapchainKHR,
	render_images 	: [Frame_Count]Render_Image,
    surface      	: vk.SurfaceKHR,
}

create_swapchain :: proc(
	device : Device,
	surface : vk.SurfaceKHR,
	w, h: u32,
	$Num_Frames: int,
	previous_swapchain : ^Swapchain(Num_Frames)) -> (chain: Swapchain(Num_Frames), ok : bool) {

    support := _get_swapchain_support(device, surface) or_return

    format := _pick_swap_surface_format(support)
    present_mode := _pick_swap_present_mode(support)
    extent := _pick_swap_extent(support, w, h)

    if support.capabilities.maxImageCount == 0 {
        log.error("No images available for swapchain")
        ok = false
    }

	chain.surface = surface

    image_count : u32 = clamp(u32(Num_Frames), support.capabilities.minImageCount, support.capabilities.maxImageCount)
    supported_family := u32(find_queue_family_present_support(device, device.queues, surface) or_return)

    create_info : vk.SwapchainCreateInfoKHR
    create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
    create_info.imageFormat = format.format
    create_info.imageColorSpace = format.colorSpace
    create_info.presentMode = present_mode
    create_info.imageExtent = extent
    create_info.minImageCount = image_count
    create_info.imageArrayLayers = 1
    create_info.imageUsage = {.COLOR_ATTACHMENT}
    create_info.surface = surface

    // reuse any applicable resources
    if previous_swapchain != nil { 
        create_info.oldSwapchain = previous_swapchain.chain
    }

    create_info.imageSharingMode = .EXCLUSIVE
    create_info.queueFamilyIndexCount = 1
    create_info.pQueueFamilyIndices = &supported_family

    create_info.preTransform = support.capabilities.currentTransform
    create_info.compositeAlpha = {.OPAQUE}
    create_info.clipped = true

    res := vk.CreateSwapchainKHR(device.core, &create_info, {}, &chain.chain)
    if res != .SUCCESS {
        log.error("Error creating swapchain:", res)
        ok = false
    }

    img_count := u32(Num_Frames)
	images : [Num_Frames]vk.Image
    vk.GetSwapchainImagesKHR(device.core, chain.chain, &img_count, &images[0])

	views : [Num_Frames]vk.ImageView
    views, ok = _create_image_views(device.core, images, format)

	for i in 0..<Num_Frames {
		chain.render_images[i].size = {
			extent.width,
			extent.height
		}

		chain.render_images[i].image = images[i]
		chain.render_images[i].view = views[i]
	}

    log.info("Created Swapchain", chain.chain)

    return
}

recreate_swapchain :: proc(device : Device, swapchain: ^$S/Swapchain($N), w, h : u32) -> (ok: bool = true) {
    wait_for_idle(ctx)

    old_chain := swapchain^

    swapchain^, ok = create_swapchain(device, {}, w, h, N, swapchain)

    if !ok {
        log.error("Error recreating swapchain")
        swapchain^ = old_chain
    } else {
        destroy_swapchain(device, old_chain)
    }

    return
}


_get_swapchain_support :: proc(device : Device, surface : vk.SurfaceKHR) -> (support : SwapchainSupport, ok : bool) {
    ok = true

    res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device.physical, surface, &support.capabilities)
    if res != .SUCCESS {
        log.error("Error retrieving surface capabilities for swapchain support detection")
        ok = false
    }

    format_count : u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device.physical, surface, &format_count, nil)

    log.info("Found", format_count, "color formats for physical device")

    support.formats = make([]vk.SurfaceFormatKHR, format_count)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device.physical, surface, &format_count, &support.formats[0])

    log.info("PHysical device formats:", support.formats)

    pm_count : u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device.physical, surface, &pm_count, nil)

    support.present_modes = make([]vk.PresentModeKHR, pm_count)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device.physical, surface, &pm_count, &support.present_modes[0])

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


_create_image_views :: proc(device : vk.Device, images : [$N]vk.Image, format : vk.SurfaceFormatKHR) -> (views : [N]vk.ImageView, ok : bool) {
    ok = true

    for i in 0..<N {
        create_info : vk.ImageViewCreateInfo
        create_info.sType = .IMAGE_VIEW_CREATE_INFO
        create_info.image = images[i]
        create_info.viewType = .D2
        create_info.format = format.format

        create_info.components.r = .IDENTITY
        create_info.components.g = .IDENTITY
        create_info.components.b = .IDENTITY
        create_info.components.a = .IDENTITY

        create_info.subresourceRange.aspectMask = {.COLOR}
        create_info.subresourceRange.baseMipLevel = 0
        create_info.subresourceRange.levelCount = 1
        create_info.subresourceRange.baseArrayLayer = 0
        create_info.subresourceRange.layerCount = 1

        res := vk.CreateImageView(device, &create_info, {}, &views[i])
        if res != .SUCCESS {
            log.error("Error creating image view for index", i)
            ok = false
        }
    }
    
    return
}

destroy_swapchain :: proc(device : Device, chain: $S/Swapchain($N)) {
    for i in 0..<N {
        vk.DestroyImageView(device.core, chain.render_images[i].view, {})
    }

	vk.DestroySwapchainKHR(device.core, chain.chain, {})
	vk.DestroySurfaceKHR(device.instance.core, chain.surface, {})
}
