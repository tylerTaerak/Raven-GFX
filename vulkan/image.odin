package game_vulkan

import vk "vendor:vulkan"

// use images for render targets, will probably be used for textures down the road

Image_Format :: enum {
    RGBA8_UNORM, // 4 x 8-bit unsigned normmalized float
    RGBA8_SRGB,         // 4 x 8-bit sRGB
    RGBA16_FLOAT,       // 4 x 16 bit float (HDR)
    INT8,               // 1 x 8-bit float
    INT32,              // 1 x 32-bit float
    SHORT_U8,           // 1 x 8-bit unsigned int
    DEPTH32_FLOAT,      // 1 x 32-bit depth float
    DEPTH24_STENCIL8    // 1 x 24-bit depth float + 1 x 8-bit stencil float
}

Image_Usage :: enum {
    Color,
    Depth,
    Stencil,
    Depth_And_Stencil
}

Render_Image :: struct {
    image: vk.Image,
    view : vk.ImageView
}

_to_vk_image_format :: proc(fmt: Image_Format) -> vk.Format {
    switch (fmt) {
        case .RGBA8_UNORM:
            return .R8G8B8A8_UNORM
        case .RGBA8_SRGB:
            return .R8G8B8A8_SRGB
        case .RGBA16_FLOAT:
            return .R16G16B16A16_SFLOAT
        case .INT8:
            return .R8_UINT
        case .INT32:
            return .R32_UINT
        case .SHORT_U8:
            return .R8_UINT
        case .DEPTH32_FLOAT:
            return .D32_SFLOAT
        case .DEPTH24_STENCIL8:
            return .D24_UNORM_S8_UINT
    }

    return .R8G8B8A8_UNORM
}

create_image :: proc(ctx: ^Context, size: [2]u32, format: Image_Format, usage: Image_Usage) -> (img: Render_Image, ok: bool=true) {
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

    res := vk.CreateImage(ctx.device.logical, &image_info, {}, &img.image)

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

    switch (usage) {
        case .Color:
            view_info.subresourceRange = vk.ImageSubresourceRange{
                aspectMask = {.COLOR},
                baseMipLevel = 1,
                levelCount = 1,
                layerCount = 1
            }
        case .Depth:
            view_info.subresourceRange = vk.ImageSubresourceRange{
                aspectMask = {.DEPTH},
                baseMipLevel = 1,
                levelCount = 1,
                layerCount = 1
            }
        case .Stencil:
            view_info.subresourceRange = vk.ImageSubresourceRange{
                aspectMask = {.STENCIL},
                baseMipLevel = 1,
                levelCount = 1,
                layerCount = 1
            }
        case .Depth_And_Stencil:
            view_info.subresourceRange = vk.ImageSubresourceRange{
                aspectMask = {.DEPTH, .STENCIL},
                baseMipLevel = 1,
                levelCount = 1,
                layerCount = 1
            }
            
    }

    res = vk.CreateImageView(ctx.device.logical, &view_info, {}, &img.view)

    ok = res == .SUCCESS

    return
}
