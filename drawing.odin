#+feature dynamic-literals
package gfx

import "core:mem"
import sdl "vendor:sdl3"
import gvk "./vulkan"
import vk "vendor:vulkan"

Frame :: struct {
    image_index: u32,
    frame_index: u32,
    image: Image
}

// encompasses all dynamic draw configurations -- TODO)) need to fill out things that aren't as simple as a bool or a float
Drawing_Configuration :: struct {
    rasterizer_discard : b32,
    cull_mode : []i32,
    front_face : []i32,
    depth_test : b32,
    depth_write : b32,
    depth_bias : b32,
    stencil_test : b32,
    line_width : f32,
    polygon_mode : []i32,
    viewport : []i32,
    scissor : []i32,
    color_mask : []i32,
    color_blend : b32,
    color_blend_eq : []i32
}

Screen_Coordinates  :: [2]f32
World_Transform     :: matrix[4, 4]f32

Draw_Model :: struct {
    pose : matrix[4, 4]f32,
    model : Model_Handle
}

Draw_Sprite :: struct {
    transform   : union{Screen_Coordinates, World_Transform},
    width       : int,
    height      : int
    // texture handle
}

Draw_Text :: struct {
    transform   : union{Screen_Coordinates, World_Transform},
    text        : string
    // font (maybe) -- not sure if the font should be something set with the context or not
}

Graphics_Shader :: struct {
    vertex : gvk.Shader,
    fragment : gvk.Shader
}

Compute_Shader :: struct {
    shader : gvk.Shader
}

Shader_Set :: union { Graphics_Shader, Compute_Shader }

Draw_Key :: struct {
    model : Model_Handle,
    render_target : Image,
    shader : Shader_Set
}

Draw_Map :: map[Draw_Key][dynamic]World_Transform

// TODO)) Ideally, I think the way to manage this is to have everything held by the central context,
// and just divvy out handles to all of these assets - then we can take something something take the hash
// between the image and shader steps and that gives us a really good set of actually divisible jobs to run
draw_model :: proc(model: Draw_Model, target: ^gvk.Render_Image, shader_steps : []Shader_Set) {
    for shader in shader_steps {
        key : Draw_Key
        key.model = model.model
        key.render_target = target^
        key.shader = shader

        // insert the model data into the draws
        if list, ok := &Core_Context.draws[key]; ok {
            append(list, model.pose)
        } else {
            Core_Context.draws[key] = { model.pose } // start the dynamic array off
        }
    }
}

draw_sprite :: proc(sprite: Draw_Sprite, target: ^gvk.Render_Image, shader_steps : []Shader_Set) {
}

draw_text :: proc(text: Draw_Text, target: ^gvk.Render_Image, shader_steps : []Shader_Set) {
}

write_draw_command_buffer :: proc(draw_commands : Draw_Map, dst_buffer : ^gvk.Host_Buffer(vk.DrawIndexedIndirectCommand)) -> u32{
    commands : [dynamic]vk.DrawIndexedIndirectCommand
    defer delete(commands)

    instance_offset : u32
    draw_count : u32

    for key, tforms in draw_commands {
        for model_chunk in Core_Context.assets.models[key.model].chunks {
            vk_draw_cmd : vk.DrawIndexedIndirectCommand
            vk_draw_cmd.indexCount = model_chunk.index_count
            vk_draw_cmd.firstIndex = model_chunk.index_offset
            vk_draw_cmd.instanceCount = u32(len(tforms))
            vk_draw_cmd.vertexOffset = i32(model_chunk.vertex_offset)
            vk_draw_cmd.firstInstance = instance_offset

            instance_offset += u32(len(tforms))

            append(&commands, vk_draw_cmd)

            draw_count += 1
        }
    }

    mem.copy(dst_buffer.data_ptr, raw_data(commands), len(commands) * size_of(vk.DrawIndexedIndirectCommand))

    return draw_count
}

commit_draw_commands :: proc(cmd_buf : vk.CommandBuffer, draw_commands : gvk.Host_Buffer(vk.DrawIndexedIndirectCommand), command_count: u32, draw_map : Draw_Map) {
    offset : vk.DeviceSize = 0
    for key, _ in draw_map {
        draw_count := u32(len(Core_Context.assets.models[key.model].chunks))

        image := key.render_target

        info : vk.RenderingInfoKHR
        info.sType = .RENDERING_INFO_KHR
        info.layerCount = 1
        info.colorAttachmentCount = 1
        info.renderArea = {{0, 0}, {image.size.x, image.size.y}}

        attachment : vk.RenderingAttachmentInfoKHR
        attachment.sType = .RENDERING_ATTACHMENT_INFO_KHR
        attachment.imageView = image.view
        attachment.imageLayout = .COLOR_ATTACHMENT_OPTIMAL
        attachment.loadOp = .CLEAR
        attachment.storeOp = .STORE
        attachment.clearValue = {color={uint32={60, 60, 205, 255}}}

        attachments : []vk.RenderingAttachmentInfoKHR = {attachment}

        info.pColorAttachments = &attachments[0]

        vk.CmdBeginRenderingKHR(cmd_buf, &info)

        vk.CmdSetRasterizerDiscardEnableEXT(cmd_buf, false)
        vk.CmdSetCullModeEXT(cmd_buf, {})
        vk.CmdSetFrontFaceEXT(cmd_buf, .CLOCKWISE)
        vk.CmdSetDepthTestEnableEXT(cmd_buf, false)
        vk.CmdSetDepthWriteEnableEXT(cmd_buf, false)
        vk.CmdSetDepthBiasEnableEXT(cmd_buf, false)
        vk.CmdSetStencilTestEnableEXT(cmd_buf, false)
        vk.CmdSetLineWidth(cmd_buf, 1.0)
        vk.CmdSetPolygonModeEXT(cmd_buf, .FILL)
        vk.CmdSetDepthClipEnableEXT(cmd_buf, false)
        vk.CmdSetAlphaToCoverageEnableEXT(cmd_buf, false)
        vk.CmdSetPrimitiveTopologyEXT(cmd_buf, .TRIANGLE_LIST)
        vk.CmdSetPrimitiveRestartEnableEXT(cmd_buf, false)
        vk.CmdSetVertexInputEXT(cmd_buf, 0, nil, 0, nil)

        viewport : vk.Viewport
        viewport.x = 0
        viewport.y = 0
        viewport.width = f32(image.size.x)
        viewport.height = f32(image.size.y)
        vk.CmdSetViewport(cmd_buf, 0, 1, &viewport)
        vk.CmdSetViewportWithCountEXT(cmd_buf, 1, &viewport)

        scissor : vk.Rect2D
        scissor.offset = {0, 0}
        scissor.extent = {image.size.x, image.size.y}
        vk.CmdSetScissor(cmd_buf, 0, 1, &scissor)
        vk.CmdSetScissorWithCountEXT(cmd_buf, 1, &scissor)

        masks : []vk.ColorComponentFlags = {
            {.R, .B, .G, .A}
        }

        vk.CmdSetColorWriteMaskEXT(cmd_buf, 0, 1, &masks[0])

        enables : []b32 = {
            true
        }

        vk.CmdSetColorBlendEnableEXT(cmd_buf, 0, 1, &enables[0])

        vk.CmdSetRasterizationSamplesEXT(cmd_buf, {._1})

        sample_masks : vk.SampleMask = 1

        vk.CmdSetSampleMaskEXT(cmd_buf, {._1}, &sample_masks)

        eqs : []vk.ColorBlendEquationEXT = {
            {
                srcColorBlendFactor = .SRC_COLOR,
                srcAlphaBlendFactor = .SRC_COLOR,
                dstColorBlendFactor = .ONE_MINUS_SRC_COLOR,
                dstAlphaBlendFactor = .ONE_MINUS_SRC_COLOR
            }
        }

        vk.CmdSetColorBlendEquationEXT(cmd_buf, 0, 1, &eqs[0])


        switch &s in key.shader {
            case Graphics_Shader:
                stage_flags : []vk.ShaderStageFlags = {{.VERTEX}, {.FRAGMENT}}
                shaders : []vk.ShaderEXT = {s.vertex.obj, s.fragment.obj}
                vk.CmdBindShadersEXT(cmd_buf, 2, &stage_flags[0], &shaders[0])
            case Compute_Shader:
                stage_flags : vk.ShaderStageFlags = {.COMPUTE}
                vk.CmdBindShadersEXT(cmd_buf, 1, &stage_flags, &s.shader.obj)

        }

        vk.CmdBindIndexBuffer(cmd_buf, Core_Context.assets.index_buffer.internal_buffer.buf, 0, .UINT16)

        vk.CmdDrawIndexedIndirect(cmd_buf, draw_commands.internal_buffer.buf, offset, draw_count, size_of(vk.DrawIndexedIndirectCommand))

        vk.CmdEndRenderingKHR(cmd_buf)
    }
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

draw :: proc {
    draw_model,
    draw_sprite,
    draw_text,
}

present_frame :: proc(ctx: ^Context, image: Frame) {
    gvk.present_image(ctx.backend, &ctx.swapchain, image.image_index, &ctx.swapchain.sync[image.image_index].render_finished)
}
