package gfx

import "core:log"
Swapchain_Image :: struct {
    index: u32,
    image: Image
}

acquire_swapchain_image :: proc(ctx: ^Context, fence_index: int) -> (image: Swapchain_Image) {
    index := _acquire_swapchain_image(ctx.backend, &ctx.swapchain, 0, ctx.sync[fence_index].render)

    image.index = index
    image.image.image = ctx.swapchain.images[index]
    image.image.view = ctx.swapchain.views[index]
    image.image.size = {u32(ctx.window.w), u32(ctx.window.h)}

    return
}

present_swapchain_image :: proc(ctx: ^Context, image: ^Swapchain_Image) {
    _present_image(ctx.backend, &ctx.swapchain, image.index, &ctx.sync[image.index].present)
}
