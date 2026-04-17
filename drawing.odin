package gfx

import sdl "vendor:sdl3"

Swapchain_Image :: struct {
    image_index: u32,
    frame_index: u32,
    image: Image
}

acquire_swapchain_image :: proc(ctx: ^Context, fence_index: int) -> (image: Swapchain_Image, ok : bool = true) {
    index : u32
    index, ok = _acquire_swapchain_image(ctx.backend, &ctx.swapchain, 0, ctx.swapchain.sync[fence_index].image_acquired)

    w, h : i32
    sdl.GetWindowSizeInPixels(ctx.window.window_ptr, &w, &h)

    ctx.window.w = int(w)
    ctx.window.h = int(h)

    image.image_index = index
    image.frame_index = u32(fence_index)
    image.image.image = ctx.swapchain.images[index]
    image.image.view = ctx.swapchain.views[index]
    image.image.size = {u32(ctx.window.w), u32(ctx.window.h)}

    return
}

present_swapchain_image :: proc(ctx: ^Context, image: ^Swapchain_Image) {
    _present_image(ctx.backend, &ctx.swapchain, image.image_index, &ctx.swapchain.sync[image.image_index].render_finished)
}
