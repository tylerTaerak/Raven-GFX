package core

import "core:os"
import "core:bytes"
import "core:image"
import "core:image/png"

Image :: struct {
    data : []byte,
    width : int,
    height : int
}

load_texture_from_filepath :: proc(filepath : string) -> (Image, bool) {
    data, err := os.read_entire_file_from_path(filepath, context.allocator)

    if err != os.ERROR_NONE {
        return {}, false
    }

    return load_texture_from_bytes(data)
}

// use vk.CmdCopyBufferToImage to move this data to the GPU
load_texture_from_bytes :: proc(data : []byte) -> (Image, bool) {
    img, err := image.load_from_bytes(data)
    if err != nil {
        return {}, false
    }

    image : Image
    image.data = bytes.buffer_to_bytes(&img.pixels)
    image.width = img.width
    image.height = img.height

    return image, true
}

load_texture :: proc {
    load_texture_from_filepath,
    load_texture_from_bytes,
}
