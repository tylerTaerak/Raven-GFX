package assets

import "core:mem"
import "core:bytes"
import "core:image"
import "shared:raven-gfx/api"
import "shared:raven-gfx/core"

Texture :: struct {
	handle 	: api.Image,
	dims  	: [2]u32, // we're asserting 2D down in Vulkan-land as well

	// We ain't using these for now... (but TODO)) it's pretty easy to implement down the stack)
	mips 	: int,
	layers 	: int,
	usage 	: core.Image_Usage
}

load_texture_data :: proc(
	device : api.Device,
	store : ^Asset_Store,
	data : []byte) -> (texture : Texture, ok : bool = true) {

	img, err := image.load(data, {.alpha_add_if_missing})

	if err != nil {
		ok = false
		return
	}

	format := _to_image_format(img, false)

	texture.dims = {u32(img.width), u32(img.height)}

	api_image : api.Image
	texture.handle = api.create_image(device, texture.dims, format) or_return

	byte_buf := bytes.buffer_to_bytes(&img.pixels)

	slice := make_host_buffer(device, store, len(byte_buf)) or_return

	mem.copy(api.host_pointer(slice), &byte_buf[0], len(byte_buf))

	api.copy_buffer_to_image(store.cmd_set, 0, texture.handle, slice)

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

destroy_texture :: proc(device : api.Device, store : ^Asset_Store, texture : Texture_Handle) {
	texture_data := &store.textures[int(texture)]

	api.destroy_image(device, &texture_data.handle)
}
