package assets

import gmem "shared:gpu-memory"
import "core:image"
import "shared:raven-gfx/api"
import "shared:raven-gfx/core"

Texture :: struct {
	handle 	: api.Image,
	data 	: gmem.Bytes(.DEVICE),
	dims  	: [2]u32, // we're asserting 2D down in Vulkan-land as well
	mips 	: int,
	layers 	: int,
	usage 	: core.Image_Usage
}

load_texture_assets :: proc(
	device : api.Device,
	store : Asset_Store(Texture),
	data : []byte) -> (texture : []Texture, ok : bool = true) {

	img, err := image.load(data, {.alpha_add_if_missing})

	if err != nil {
		ok = false
		return
	}

	format := _to_image_format(img, false)

	api_image : api.Image
	texture[0].handle, ok = api.create_image(device, {u32(img.width), u32(img.height)}, format, .Color)
	// we have the vulkan image now... but we need to actually save things to memory...

	return
}

_to_image_format :: proc(img : ^image.Image, srgb : bool) -> core.Image_Format {
	switch img.depth {
		case 8:
			switch img.channels {
				case 1:
					return .SHORT_U8 // 8-bit
				case 2:
					return .SHORT_U8 // 16-bit (RG8 unorm)
				case 3:
					return srgb ? .RGBA8_SRGB : .RGBA8_UNORM
				case 4:
					return srgb ? .RGBA8_SRGB : .RGBA8_UNORM
			}
		case 16:
			switch img.channels {
				case 1:
					return .SHORT_U8 // u16
				case 2:
					return .INT32 // rg16 unorm
				case 4:
					return .RGBA16_FLOAT
			}
	}

	return .RGBA8_UNORM
}
