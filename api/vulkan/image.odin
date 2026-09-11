package game_vulkan

import vk "vendor:vulkan"
import "shared:raven-gfx/core"

Render_Image :: struct {
    image: vk.Image,
    view : vk.ImageView,
	memory : Allocation(.DEVICE), // all images *SHOULD* just be on device
    size : [2]u32
}

create_image :: proc(device : Device, size: [2]u32, format: core.Image_Format) -> (img: Render_Image, ok: bool=true) {
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

	req_info : vk.ImageMemoryRequirementsInfo2
	req_info.sType = .IMAGE_MEMORY_REQUIREMENTS_INFO_2
	req_info.image = img.image

	vk.GetImageMemoryRequirements2(device.core, &req_info, &mem_req)

	img.memory = memalloc(
		device,
		device.device_memory,
		Allocation_Type.IMAGE,
		u32(mem_req.memoryRequirements.size),
		u32(mem_req.memoryRequirements.alignment)
	) or_return

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

destroy_image :: proc(device : Device, image: ^Render_Image) {
	memfree(&image.memory)
    vk.DestroyImageView(device.core, image.view, {})
    vk.DestroyImage(device.core, image.image, {})
}
