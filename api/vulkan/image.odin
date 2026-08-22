// TODO)) This part may be more apt as an external package, similar to what we're doing with buffers now... TBD
package game_vulkan

import vk "vendor:vulkan"
import "shared:raven-gfx/core"

// use images for render targets, will probably be used for textures down the road

Render_Image :: struct {
    image: vk.Image,
    view : vk.ImageView,
	memory : vk.DeviceMemory,
    size : [2]u32
}

create_image :: proc(device : Device, size: [2]u32, format: core.Image_Format, usage: core.Image_Usage) -> (img: Render_Image, ok: bool=true) {
    image_info : vk.ImageCreateInfo
    image_info.sType = .IMAGE_CREATE_INFO
    image_info.format = _to_vk_image_format(format)
    image_info.imageType = .D2
    image_info.extent = vk.Extent3D{
        width=size[0],
        height=size[1]
    }
    image_info.mipLevels = 1
    image_info.samples = {._1}
    image_info.tiling = .OPTIMAL

    if usage == .Color {
        image_info.usage = {.COLOR_ATTACHMENT}
        image_info.initialLayout = .COLOR_ATTACHMENT_OPTIMAL
    } else {
        image_info.usage = {.DEPTH_STENCIL_ATTACHMENT}
        image_info.initialLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    }

    queue_fams : u32 = u32(find_queue_family_by_type(device.queues, {.GRAPHICS}) or_return)

    image_info.queueFamilyIndexCount = 1
    image_info.pQueueFamilyIndices = &queue_fams

    res := vk.CreateImage(device.core, &image_info, {}, &img.image)

    ok = res == .SUCCESS

    if !ok do return

    view_info : vk.ImageViewCreateInfo
    view_info.sType = .IMAGE_VIEW_CREATE_INFO
    view_info.image = img.image
    view_info.viewType = .D2
    view_info.format = _to_vk_image_format(format)
    view_info.components = vk.ComponentMapping{
        r=.IDENTITY,
        g=.IDENTITY,
        b=.IDENTITY,
        a=.IDENTITY
    }

    view_info.subresourceRange = vk.ImageSubresourceRange {
        aspectMask = _to_vk_image_aspect(usage),
        baseMipLevel = 1,
        levelCount = 1,
        layerCount = 1
    }

    res = vk.CreateImageView(device.core, &view_info, {}, &img.view)

    img.size = size

    ok = res == .SUCCESS

	if !ok {
		return
	}

	mem_req : vk.MemoryRequirements2
	mem_req.sType = .MEMORY_REQUIREMENTS_2

	mem_props : vk.PhysicalDeviceMemoryProperties2
	mem_props.sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2

	req_info : vk.ImageMemoryRequirementsInfo2
	req_info.sType = .IMAGE_MEMORY_REQUIREMENTS_INFO_2
	req_info.image = img.image

	vk.GetImageMemoryRequirements2(device.core, &req_info, &mem_req)
	vk.GetPhysicalDeviceMemoryProperties2(device.physical, &mem_props)

	mem_flags : vk.MemoryPropertyFlags = {.DEVICE_LOCAL}

	mem_idx : u32
	for i in 0..<mem_props.memoryProperties.memoryTypeCount {
		mem_type := mem_props.memoryProperties.memoryTypes[i]
		if (mem_type.propertyFlags & mem_flags) == mem_flags {
			mem_idx = i
			break
		}
	}

	mem_alloc_info : vk.MemoryAllocateInfo
	mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
	mem_alloc_info.allocationSize = mem_req.memoryRequirements.size
	mem_alloc_info.memoryTypeIndex = mem_idx

	res = vk.AllocateMemory(device.core, &mem_alloc_info, {}, &img.memory)

	if res != .SUCCESS {
		ok = false
		return
	}

	res = vk.BindImageMemory(device.core, img.image, img.memory, 0)

	if res != .SUCCESS {
		ok = false
		return
	}

    return
}

image_barrier :: proc(
	cmd : Command_Buffer,
	image : Render_Image,
	old_layout, new_layout : vk.ImageLayout,
	old_access_mask, new_access_mask : vk.AccessFlags2,
	old_stage_mask, new_stage_mask : vk.PipelineStageFlags2) {

	barrier : vk.ImageMemoryBarrier2KHR
	barrier.sType = .IMAGE_MEMORY_BARRIER_2_KHR
	barrier.image = image.image
	barrier.oldLayout = old_layout
	barrier.newLayout = new_layout
	barrier.subresourceRange.aspectMask = {.COLOR}
	barrier.subresourceRange.layerCount = 1
	barrier.subresourceRange.levelCount = 1
	barrier.srcAccessMask = old_access_mask
	barrier.dstAccessMask = new_access_mask
	barrier.srcStageMask = old_stage_mask
	barrier.dstStageMask = new_stage_mask

	dependencies : vk.DependencyInfoKHR
	dependencies.sType = .DEPENDENCY_INFO_KHR
	dependencies.imageMemoryBarrierCount = 1
	dependencies.pImageMemoryBarriers = &barrier

	vk.CmdPipelineBarrier2KHR(cmd, &dependencies)
}

destroy_image :: proc(device : Device, image: Render_Image) {
    vk.DestroyImageView(device.core, image.view, {})
    vk.DestroyImage(device.core, image.image, {})
}
