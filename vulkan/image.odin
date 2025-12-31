package game_vulkan

import vk "vendor:vulkan"
import "../core"

// use images for render targets, will probably be used for textures down the road

Render_Image :: struct {
    image: vk.Image,
    view : vk.ImageView,
    size : [2]u32
}

create_image :: proc(ctx: ^Context, size: [2]u32, format: core.Image_Format, usage: core.Image_Usage) -> (img: Render_Image, ok: bool=true) {
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

    queue_fams := find_queue_family_by_type(ctx, {.GRAPHICS}) or_return

    image_info.queueFamilyIndexCount = 1
    image_info.pQueueFamilyIndices = &queue_fams.family_idx

    res := vk.CreateImage(ctx.device, &image_info, {}, &img.image)

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

    res = vk.CreateImageView(ctx.device, &view_info, {}, &img.view)

    img.size = size

    ok = res == .SUCCESS

    return
}

destroy_image :: proc(ctx: ^Context, image: ^Render_Image) {
    vk.DestroyImageView(ctx.device, image.view, {})
    vk.DestroyImage(ctx.device, image.image, {})
}
