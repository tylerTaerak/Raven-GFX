package game_vulkan

import "core:log"
import "core:os"

import vk "vendor:vulkan"

Pipeline :: struct {
    data : vk.Pipeline,
    layout : vk.PipelineLayout
}

create_pipeline :: proc(ctx : ^Context, vertex_path, fragment_path : string) -> (ok : bool = true) {
    vertex_bin := os.read_entire_file_from_filename(vertex_path) or_return
    fragment_bin := os.read_entire_file_from_filename(fragment_path) or_return

    vertex_mod := _load_shader_module(ctx.device.logical, vertex_bin) or_return
    fragment_mod := _load_shader_module(ctx.device.logical, fragment_bin) or_return

    defer vk.DestroyShaderModule(ctx.device.logical, vertex_mod, {})
    defer vk.DestroyShaderModule(ctx.device.logical, fragment_mod, {})

    shaders := load_shaders(ctx.device.logical, vertex_mod, fragment_mod) or_return

    viewport : vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = f32(ctx.swapchain.extent.width)
    viewport.height = f32(ctx.swapchain.extent.height)
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0

    scissor : vk.Rect2D
    scissor.offset = {0, 0}
    scissor.extent = ctx.swapchain.extent

    dyn_states := load_dynamic_states({.VIEWPORT, .SCISSOR})
    vertex_input := load_vertex_input()
    input_asm := load_input_assemply()
    viewport_data := load_viewport(&viewport, &scissor)
    rasterizer := load_rasterizer()
    multisample := load_multisampling()
    color_blend := load_color_blending()
    layout := load_pipeline_layout(ctx) or_return

    pipeline := load_pipeline(
        ctx,
        shaders,
        nil,
        &vertex_input,
        &input_asm,
        &viewport_data,
        &rasterizer,
        &multisample,
        &color_blend,
        layout
    ) or_return

    append(&ctx.pipelines, Pipeline{
        data = pipeline,
        layout = layout
    })

    return
}


_load_shader_module :: proc(device : vk.Device, binary : []byte) -> (mod : vk.ShaderModule, ok : bool = true) {
    bin_u32 := transmute([]u32)binary

    create_info : vk.ShaderModuleCreateInfo
    create_info.sType = .SHADER_MODULE_CREATE_INFO
    create_info.codeSize = len(binary)
    create_info.pCode = &bin_u32[0]

    res := vk.CreateShaderModule(device, &create_info, {}, &mod)
    if res != .SUCCESS {
        log.error("Error creating shader module:", res)
        ok = false
    }

    return
}

load_shaders :: proc(device : vk.Device, vertex_mod, fragment_mod : vk.ShaderModule) -> (shaders : []vk.PipelineShaderStageCreateInfo, ok : bool = true){
    vertex_stage_info : vk.PipelineShaderStageCreateInfo
    vertex_stage_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    vertex_stage_info.stage = {.VERTEX}
    vertex_stage_info.module = vertex_mod
    vertex_stage_info.pName = "main"

    frag_stage_info : vk.PipelineShaderStageCreateInfo
    frag_stage_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    frag_stage_info.stage = {.FRAGMENT}
    frag_stage_info.module = fragment_mod
    frag_stage_info.pName = "main"

    infos : []vk.PipelineShaderStageCreateInfo = {vertex_stage_info, frag_stage_info}

    shaders = make([]vk.PipelineShaderStageCreateInfo, len(infos))

    copy_count := copy(shaders, infos)

    return
}

load_dynamic_states :: proc(states : []vk.DynamicState) -> (create_info : vk.PipelineDynamicStateCreateInfo){
    create_info.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
    create_info.dynamicStateCount = u32(len(states))
    create_info.pDynamicStates = &states[0]

    return
}

load_vertex_input :: proc() -> (create_info : vk.PipelineVertexInputStateCreateInfo) {
    // TODO)) I think this is where I need to bind my vertex/instance descriptor sets from ctx.data
    create_info.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    create_info.vertexBindingDescriptionCount = 0
    create_info.pVertexBindingDescriptions = nil
    create_info.vertexAttributeDescriptionCount = 0
    create_info.pVertexAttributeDescriptions = nil
    return
}

load_input_assemply :: proc() -> (create_info : vk.PipelineInputAssemblyStateCreateInfo) {
    // TODO)) I need to be able to pass in the topology from loaded gltf files here
    create_info.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    create_info.topology = .TRIANGLE_LIST
    create_info.primitiveRestartEnable = false
    return
}

load_viewport :: proc(viewport : ^vk.Viewport, scissor : ^vk.Rect2D) -> (viewport_state : vk.PipelineViewportStateCreateInfo) {
    // TODO)) The viewport should probably? be dynamic, and therefore should be set by a camera object
    viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
    viewport_state.viewportCount = 1
    viewport_state.pViewports = viewport
    viewport_state.scissorCount = 1
    viewport_state.pScissors = scissor
    return
}

load_rasterizer :: proc() -> (rasterizer : vk.PipelineRasterizationStateCreateInfo) {
    // TODO)) I think the only things that would need changing here would be debug things
    // Although I have heard something about reverse-Z axis? that does use a clamped depth
    // I think? That might be something to look into here later
    rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    rasterizer.depthClampEnable = false
    rasterizer.rasterizerDiscardEnable = false
    rasterizer.polygonMode = .FILL
    rasterizer.lineWidth = 1.0
    rasterizer.cullMode = {.BACK}
    rasterizer.frontFace = .CLOCKWISE
    rasterizer.depthBiasEnable = false

    return
}

load_multisampling :: proc() -> (create_info : vk.PipelineMultisampleStateCreateInfo) {
    create_info.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    create_info.sampleShadingEnable = false
    create_info.rasterizationSamples = {._1}
    create_info.minSampleShading = 1.0
    create_info.pSampleMask = nil
    create_info.alphaToCoverageEnable = false
    create_info.alphaToOneEnable = false
    return
}

load_depth_and_stencil_testing :: proc() {
    // TODO)) nothing here for now
}

load_color_blending :: proc() -> (create_info : vk.PipelineColorBlendStateCreateInfo) {
    // this actually disables blending, so once we want that, this needs to be changed
    state := new(vk.PipelineColorBlendAttachmentState) // see also here
    state.colorWriteMask = {.R, .G, .B, .A}
    state.blendEnable = false
    state.srcColorBlendFactor = .ONE
    state.dstColorBlendFactor = .ZERO
    state.colorBlendOp = .ADD
    state.srcAlphaBlendFactor = .ONE
    state.dstAlphaBlendFactor = .ZERO
    state.alphaBlendOp = .ADD

    create_info.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    create_info.logicOpEnable = false
    create_info.logicOp = .COPY
    create_info.attachmentCount = 1
    create_info.pAttachments = state // I'll need to do something else to make sure I don't return a hanging pointer
    create_info.blendConstants[0] = 0.0
    create_info.blendConstants[1] = 0.0
    create_info.blendConstants[2] = 0.0
    create_info.blendConstants[3] = 0.0
    return
}

load_pipeline_layout :: proc(ctx: ^Context) -> (pipeline : vk.PipelineLayout, ok : bool = true) {
    log.info(ctx.descriptor_layouts)
    create_info : vk.PipelineLayoutCreateInfo
    create_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
    create_info.setLayoutCount = FRAMES_IN_FLIGHT 
    create_info.pSetLayouts = &ctx.descriptor_layouts[0]
    create_info.pushConstantRangeCount = 0
    create_info.pPushConstantRanges = nil

    res := vk.CreatePipelineLayout(ctx.device.logical, &create_info, {}, &pipeline)
    if res != .SUCCESS {
        log.error("Error creating pipeline layout:", res)
        ok = false
    }
    return
}

load_pipeline :: proc(ctx : ^Context,
                      shader_stages : []vk.PipelineShaderStageCreateInfo,
                      dynamic_states : ^vk.PipelineDynamicStateCreateInfo,
                      vertex_input : ^vk.PipelineVertexInputStateCreateInfo,
                      input_assembly : ^vk.PipelineInputAssemblyStateCreateInfo,
                      viewport : ^vk.PipelineViewportStateCreateInfo,
                      rasterizer : ^vk.PipelineRasterizationStateCreateInfo,
                      multisampling : ^vk.PipelineMultisampleStateCreateInfo,
                      color_blend : ^vk.PipelineColorBlendStateCreateInfo,
                      layout : vk.PipelineLayout) -> (pipeline : vk.Pipeline, ok : bool = true) {
    create_info : vk.GraphicsPipelineCreateInfo
    create_info.sType = .GRAPHICS_PIPELINE_CREATE_INFO
    create_info.stageCount = u32(len(shader_stages))
    create_info.pStages = &shader_stages[0]

    create_info.pVertexInputState = vertex_input
    create_info.pInputAssemblyState = input_assembly
    create_info.pViewportState = viewport
    create_info.pRasterizationState = rasterizer
    create_info.pMultisampleState = multisampling
    create_info.pDynamicState = dynamic_states
    create_info.pColorBlendState = color_blend
    create_info.pDepthStencilState = nil
    create_info.layout = layout
    create_info.subpass = 0
    create_info.renderPass = ctx.render_pass // TODO)) Not needed with dynamic rendering, use pNext to point to PipelineRenderingCreateInfo struct instead

    // TODO)) it is possible to create multiple pipelines at once - we can look into this to see if this can be extended
    res := vk.CreateGraphicsPipelines(ctx.device.logical, 0, 1, &create_info, {}, &pipeline)
    if res != .SUCCESS {
        log.error("Error creating graphics pipeline:", res)
        ok = false
    }

    return
}
