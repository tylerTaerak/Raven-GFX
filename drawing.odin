#+feature dynamic-literals
package gfx

import "core:log"
import "./core"
import "./api"

Draw_Context :: struct($N: int) {
	swapchain 			: api.Swapchain(N),
	command_set 		: api.Command_Collection(N),

	fence_in_flight 	: [N]api.Fence,
	sem_image_acquired 	: [N]api.Binary_Semaphore,
	sem_render_finished : [N]api.Binary_Semaphore,

	frame_index 		: u64 // monotonic counter for each frame
}

create_draw_context :: proc(
	instance : api.Instance,
	device : api.Device,
	window : core.Window,
	$Num_Frames : int) -> (ctx : Draw_Context(Num_Frames), ok : bool = true) {

	ctx.swapchain = api.create_swapchain(instance, device, window, Num_Frames) or_return
	ctx.command_set = api.create_command_buffers(device, Num_Frames, {.GRAPHICS}) or_return

	for i in 0..<Num_Frames {
		ctx.fence_in_flight[i] = api.create_fence(device)
		ctx.sem_image_acquired[i] = api.create_semaphore(device)
		ctx.sem_render_finished[i] = api.create_semaphore(device)
	}

	ctx.frame_index = 0

	return
}

destroy_draw_context :: proc(device : api.Device, ctx : $T/Draw_Context($N)) {
	for i in 0..<N {
		api.destroy_fence(device, ctx.fence_in_flight[i])
		api.destroy_semaphore(device, ctx.sem_image_acquired[i])
		api.destroy_semaphore(device, ctx.sem_render_finished[i])
	}
	api.destroy_command_buffers(device, ctx.command_set)
	api.destroy_swapchain(device, ctx.swapchain)
}

Draw_Frame :: struct {
	image				: api.Image,
	index_swapchain_img : u32,
	index_frame_ctx  	: u64,
	acquired 			: bool,
    sem_acquired		: ^api.Binary_Semaphore,
    sem_draw_complete	: ^api.Binary_Semaphore
}


// We also report that we succeed in acquiring a frame - the Draw_Frame struct has a boolean field
// for if it was actually acquired that should be used to conditionally perform operations with it
acquire_next_image :: proc(device : api.Device, ctx : ^$T/Draw_Context($N)) -> (frame : Draw_Frame) {
	frame.image,
	frame.index_swapchain_img,
	frame.acquired = api.acquire_next_swapchain_image_index(
					 device,
					 &ctx.swapchain,
					 0,
					 ctx.sem_image_acquired[ctx.frame_index])


	frame.sem_acquired = &ctx.sem_image_acquired[ctx.frame_index]
	frame.sem_draw_complete = &ctx.sem_render_finished[frame.index_swapchain_img]

	frame.index_frame_ctx = ctx.frame_index

	return
}

present_frame :: proc(device : api.Device, ctx : ^$T/Draw_Context($N), frame : Draw_Frame) {
	res := api.present_image(device, &ctx.swapchain, int(frame.index_swapchain_img), frame.sem_draw_complete^)

	if !res {
		log.warn("Error presenting next frame")
	}
}

// TODO)) Fill this out next
transition_frame_layout :: proc(ctx : ^$T/Draw_Context($N), frame : Draw_Frame) {
	// calls some sort of api.cmd_image_barrier using the current frame and the desired usages
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

// Graphics_Shader :: struct {
//     vertex : gvk.Shader_Chain,
//     fragment : gvk.Shader_Chain
// }
// 
// Compute_Shader :: struct {
//     shader : gvk.Shader
// }
// 
// Shader_Set :: union { Graphics_Shader, Compute_Shader }

Draw_Key :: struct {
    model : Model_Handle,
    render_target : api.Image,
    shader : Shader_Handle
}

Draw_Map :: map[Draw_Key][dynamic]World_Transform

// TODO)) Ideally, I think the way to manage this is to have everything held by the central context,
// and just divvy out handles to all of these assets - then we can take something something take the hash
// between the image and shader steps and that gives us a really good set of actually divisible jobs to run
// draw_model_with_target_and_shader :: proc(model: Draw_Model, target: ^gvk.Render_Image, shader_steps : []Shader_Handle) {
//     for shader in shader_steps {
//         key : Draw_Key
//         key.model = model.model
//         key.render_target = target^
//         key.shader = shader
// 
//         // insert the model data into the draws
//         if list, ok := &Core_Context.draws[key]; ok {
//             append(list, model.pose)
//         } else {
//             Core_Context.draws[key] = { model.pose } // start the dynamic array off
//         }
//     }
// }

// draw_model_with_shader :: proc(model: Draw_Model, shader_steps : []Shader_Handle) {
// }
// 
// draw_model_with_target :: proc(model: Draw_Model, target : ^gvk.Render_Image) {
// }
// 
// draw_model_defaults :: proc(model: Draw_Model) {
//     // draw_model_with_target_and_shader(model, DEFAULT_RENDER_TARGET, DEFAULT_MODEL_SHADER)
// }
// 
// draw_model :: proc{
//     draw_model_with_target_and_shader,
//     draw_model_with_shader,
//     draw_model_with_target,
//     draw_model_defaults,
// }
// 
// draw_sprite :: proc(sprite: Draw_Sprite, target: ^gvk.Render_Image, shader_steps : []Shader_Set) {
// }
// 
// draw_text :: proc(text: Draw_Text, target: ^gvk.Render_Image, shader_steps : []Shader_Set) {
// }

/*
   TODO)) This function still has raw vulkan dependencies
   */
//write_draw_command_buffer :: proc(draw_commands : Draw_Map, dst_buffer : ^gvk.Host_Buffer(vk.DrawIndexedIndirectCommand)) -> u32{
//    commands : [dynamic]vk.DrawIndexedIndirectCommand
//    defer delete(commands)
//
//    instances : [dynamic]World_Transform
//
//    instance_offset : u32
//    draw_count : u32
//
//    for key, tforms in draw_commands {
//        for model_chunk in Core_Context.assets.models[key.model].chunks {
//            vk_draw_cmd : vk.DrawIndexedIndirectCommand
//            vk_draw_cmd.indexCount = model_chunk.index_count
//            vk_draw_cmd.firstIndex = u32(model_chunk.index_offset) / size_of(u16)
//            vk_draw_cmd.instanceCount = u32(len(tforms))
//            vk_draw_cmd.vertexOffset = i32(model_chunk.vertex_offset)
//            vk_draw_cmd.firstInstance = instance_offset
//
//            instance_offset += u32(len(tforms))
//
//            append(&commands, vk_draw_cmd)
//
//            draw_count += 1
//        }
//
//        append(&instances, ..tforms[:])
//    }
//
//    mem.copy(dst_buffer.data_ptr, raw_data(commands), len(commands) * size_of(vk.DrawIndexedIndirectCommand))
//    mem.copy(Core_Context.instances[Core_Context.frame_index].data_ptr, raw_data(instances), len(instances) * size_of(World_Transform))
//
//    return draw_count
//}

/**
  TODO)) This function still has raw vulkan dependencies
  */
// commit_draw_commands :: proc(cmd_buf : vk.CommandBuffer, draw_commands : gvk.Host_Buffer(vk.DrawIndexedIndirectCommand), command_count: u32, draw_map : Draw_Map) {
//     offset : vk.DeviceSize = 0
//     for key, _ in draw_map {
//         draw_count := u32(len(Core_Context.assets.models[key.model].chunks))
// 
//         image := key.render_target
// 
//         info : vk.RenderingInfoKHR
//         info.sType = .RENDERING_INFO_KHR
//         info.layerCount = 1
//         info.colorAttachmentCount = 1
//         info.renderArea = {{0, 0}, {image.size.x, image.size.y}}
// 
//         attachment : vk.RenderingAttachmentInfoKHR
//         attachment.sType = .RENDERING_ATTACHMENT_INFO_KHR
//         attachment.imageView = image.view
//         attachment.imageLayout = .COLOR_ATTACHMENT_OPTIMAL
//         attachment.loadOp = .CLEAR
//         attachment.storeOp = .STORE
//         attachment.clearValue = {color={uint32={60, 60, 205, 255}}}
// 
//         attachments : []vk.RenderingAttachmentInfoKHR = {attachment}
// 
//         info.pColorAttachments = &attachments[0]
// 
//         vk.CmdBeginRenderingKHR(cmd_buf, &info)
// 
//         vk.CmdSetRasterizerDiscardEnableEXT(cmd_buf, false)
//         vk.CmdSetCullModeEXT(cmd_buf, {.BACK})
//         vk.CmdSetFrontFaceEXT(cmd_buf, .CLOCKWISE)
//         vk.CmdSetDepthTestEnableEXT(cmd_buf, false)
//         vk.CmdSetDepthWriteEnableEXT(cmd_buf, false)
//         vk.CmdSetDepthBiasEnableEXT(cmd_buf, false)
//         vk.CmdSetStencilTestEnableEXT(cmd_buf, false)
//         vk.CmdSetLineWidth(cmd_buf, 1.0)
//         vk.CmdSetPolygonModeEXT(cmd_buf, .FILL)
//         vk.CmdSetDepthClipEnableEXT(cmd_buf, false)
//         vk.CmdSetAlphaToCoverageEnableEXT(cmd_buf, false)
//         vk.CmdSetPrimitiveTopologyEXT(cmd_buf, .TRIANGLE_LIST)
//         vk.CmdSetPrimitiveRestartEnableEXT(cmd_buf, false)
//         vk.CmdSetVertexInputEXT(cmd_buf, 0, nil, 0, nil)
// 
//         viewport : vk.Viewport
//         viewport.x = 0
//         viewport.y = 0
//         viewport.width = f32(image.size.x)
//         viewport.height = f32(image.size.y)
//         vk.CmdSetViewport(cmd_buf, 0, 1, &viewport)
//         vk.CmdSetViewportWithCountEXT(cmd_buf, 1, &viewport)
// 
//         scissor : vk.Rect2D
//         scissor.offset = {0, 0}
//         scissor.extent = {image.size.x, image.size.y}
//         vk.CmdSetScissor(cmd_buf, 0, 1, &scissor)
//         vk.CmdSetScissorWithCountEXT(cmd_buf, 1, &scissor)
// 
//         masks : []vk.ColorComponentFlags = {
//             {.R, .B, .G, .A}
//         }
// 
//         vk.CmdSetColorWriteMaskEXT(cmd_buf, 0, 1, &masks[0])
// 
//         enables : []b32 = {
//             true
//         }
// 
//         vk.CmdSetColorBlendEnableEXT(cmd_buf, 0, 1, &enables[0])
// 
//         vk.CmdSetRasterizationSamplesEXT(cmd_buf, {._1})
// 
//         sample_masks : vk.SampleMask = 1
// 
//         vk.CmdSetSampleMaskEXT(cmd_buf, {._1}, &sample_masks)
// 
//         eqs : []vk.ColorBlendEquationEXT = {
//             {
//                 srcColorBlendFactor = .SRC_COLOR,
//                 srcAlphaBlendFactor = .SRC_COLOR,
//                 dstColorBlendFactor = .ONE_MINUS_SRC_COLOR,
//                 dstAlphaBlendFactor = .ONE_MINUS_SRC_COLOR
//             }
//         }
// 
//         vk.CmdSetColorBlendEquationEXT(cmd_buf, 0, 1, &eqs[0])
// 
//         shader_chain := &Core_Context.assets.shaders[key.shader]
// 
//         stage_flags : [dynamic]vk.ShaderStageFlags
//         shaders : [dynamic]vk.ShaderEXT
//         for s in shader_chain.shader.shaders {
//             append(&stage_flags, vk.ShaderStageFlags{gvk.stage_to_vk_enum(s.stage)})
//             append(&shaders, s.obj)
//         }
// 
//         vk.CmdBindShadersEXT(cmd_buf, u32(len(shader_chain.shader.shaders)), &stage_flags[0], &shaders[0])
// 
//         binds : [dynamic]vk.DescriptorBufferBindingInfoEXT
//         for &d, i in shader_chain.shader.descriptors {
//             bind_info : vk.DescriptorBufferBindingInfoEXT
//             bind_info.sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT
//             bind_info.usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SAMPLER_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS_EXT}
//             bind_info.address = gvk.get_device_address(shader_chain.shader.descriptors[i].buffer)
// 
//             for &data, j in shader_chain.shader.descriptors[i].bindings {
//                 offset : vk.DeviceSize = vk.DeviceSize(data.memory.offset)
//                 buffer_idx : u32 = 0
//                 vk.CmdSetDescriptorBufferOffsetsEXT(cmd_buf, .GRAPHICS, shader_chain.shader.layout, u32(j), 1, &buffer_idx, &offset)
//             }
//         }
// 
//         vk.CmdBindDescriptorBuffersEXT(cmd_buf, u32(len(binds)), &binds[0])
// 
//         vk.CmdBindIndexBuffer(cmd_buf, gvk.get_underlying_buffer(Core_Context.assets.arena, Core_Context.assets.index_data_raw.block), 0, .UINT16)
// 
//         vk.CmdDrawIndexedIndirect(cmd_buf, draw_commands.internal_buffer.buf, offset, draw_count, size_of(vk.DrawIndexedIndirectCommand))
// 
//         vk.CmdEndRenderingKHR(cmd_buf)
//     }
// }
