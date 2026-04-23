package gfx

import sdl "vendor:sdl3"
import gvk "./vulkan"

Frame :: struct {
    image_index: u32,
    frame_index: u32,
    image: Image
}

/**
  Here is how the core drawing API should go:

  1. Acquire Frame
  2. Draw Elements (models, UI, Sprites, Fonts, etc
  3. Commit Frame (passes all commands to GPU and presents frame)

  So we more or less have 1 and 3 done (although we'll need to update 3. to include
  the command processing), so we'll need to add support for drawing now...

  Should I allow arbitrary vertex types, and allow for really liberal use of the
  low-level side of things? Or would it be better for this to define a strict set
  of types to write to the GPU?

  I think the end goal for this framework is to be straightforward to use, so I think the latter
  is more of what I want
 */

Draw_Model :: struct {
    pose : matrix[4, 4]f32,
    model : Model_Handle
    // origin -- translation + orientation
    // model handle
    // -- model data is an asset stored with the central context, not found here
}

Draw_Sprite :: struct {
    // center, -- (0, 0) will draw at the center of the screen (assuming screen space drawing)
    // -- this center could also be a pose for billboarding purposes
    // -- it could also be a union of vec2 and mat4
    // width,
    // height,
    // texture handle
}

Draw_Text :: struct {
    // basically a generated sprite using atlas-mapped textures
    // center pose -- [vec2 | mat4]
    // text -- string
    // font (maybe) -- not sure if the font should be something set with the context or not
}

get_next_frame :: proc(ctx: ^Context, fence_index: int) -> (image: Frame, ok : bool = true) {
    index : u32
    index, ok = gvk.acquire_next_image_index(ctx.backend, &ctx.swapchain, 0, ctx.swapchain.sync[fence_index].image_acquired)

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

// TODO)) Ideally, I think the way to manage this is to have everything held by the central context,
// and just divvy out handles to all of these assets - then we can take something something take the hash
// between the image and shader steps and that gives us a really good set of actually divisible jobs to run
draw_model :: proc(model: Draw_Model, target: ^gvk.Render_Image, shader_steps : []gvk.Shader) {
}

draw_sprite :: proc(sprite: Draw_Sprite, target: ^gvk.Render_Image, shader_steps : []gvk.Shader) {
}

draw_text :: proc(text: Draw_Text, target: ^gvk.Render_Image, shader_steps : []gvk.Shader) {
}

draw :: proc {
    draw_model,
    draw_sprite,
    draw_text,
}

present_frame :: proc(ctx: ^Context, image: Frame) {
    gvk.present_image(ctx.backend, &ctx.swapchain, image.image_index, &ctx.swapchain.sync[image.image_index].render_finished)
}
