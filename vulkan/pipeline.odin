package game_vulkan

import "core:log"
import "core:os"

import vk "vendor:vulkan"

Pipeline :: struct {
    data : vk.Pipeline,
    layout : vk.PipelineLayout
}


// Pipeline Config
Pipeline_Config :: struct {
    vertex_shader_path : string,
    fragment_shader_path: string,
    layout: int,
    descriptor_sets: Descriptor_Collection,
    color_formats : []Image_Format,

    // these are optional fields that will be considered dynamic if not filled out
    topology: Topology_Primitive, // will default to NONE if not set by user
    viewport: Maybe(Viewport_Config),
    rasterization: Maybe(Rasterizer_Config),
    depth: Maybe(Depth_State_Config),
    blend_state: Maybe(Color_Blend_Config)
}

// TODO)) Maybe should live in core
Topology_Primitive :: enum {
    NONE,
    TRIANGLE_LIST
}

Front_Face :: enum {
    NONE,
    CLOCKWISE,
    COUNTERCLOCKWISE
}

Cull_Mode :: enum {
    NONE,
    BACK,
    FRONT
}

Compare_Operation :: enum {
    NONE,
    LESS,
    EQUAL,
    LEQUAL,
    GREATER,
    NOT_EQUAL,
    GEQUAL,
    ALWAYS
}

Stencil_Operation :: enum {
    NONE,
    KEEP,
    ZERO,
    REPLACE,
    INCREMENT_CLAMP,
    DECREMENT_CLAMP,
    INVERT,
    INCREMENT_WRAP,
    DECREMENT_WRAP
}

Blend_Operation :: enum {
    NONE,
    ADD,
    SUBTRACT,
    REVERSE_SUBTRACT,
    MIN,
    MAX
}

Viewport_Config :: struct {
    viewport_top_left : [2]f32,
    viewport_bot_right: [2]f32,
    scissor_top_left : [2]i32,
    scissor_bot_right: [2]i32
}

Rasterizer_Config :: struct {
    front_face: Front_Face,
    cull_mode: Cull_Mode,
    line_width: f32
}

Depth_State_Config :: struct {
    read_depth : b32,
    write_depth : b32,
    read_stencil: b32,
    depth_compare_op : Compare_Operation,
    stencil_compare_op : Compare_Operation,
    stencil_fail_op : Stencil_Operation,
    stencil_pass_op : Stencil_Operation,
    stencil_depth_fail_op : Stencil_Operation,
    depth_format : Image_Format,
    stencil_format: Image_Format
}

Color_Blend_Config :: struct {
    enable_blend : b32,
    color_blend_op : Blend_Operation,
    alpha_blend_op : Blend_Operation
}

// TODO)) A lot of pipeline configurations can be dynamic - assess needs to ascertain if things need to be static or dynamic
// A way to handle this is to pass a config object where most fields are `Maybe(T)`, so if something is nil we assume it to
// be a dynamic state
create_pipeline :: proc(ctx : ^Context, cfg : Pipeline_Config) -> (pipeline: Pipeline, ok : bool = true) {
    vertex_bin := os.read_entire_file_from_filename(cfg.vertex_shader_path) or_return
    fragment_bin := os.read_entire_file_from_filename(cfg.fragment_shader_path) or_return

    vertex_mod := _load_shader_module(ctx.device, vertex_bin) or_return
    fragment_mod := _load_shader_module(ctx.device, fragment_bin) or_return

    defer vk.DestroyShaderModule(ctx.device, vertex_mod, {})
    defer vk.DestroyShaderModule(ctx.device, fragment_mod, {})

    shaders := _load_shaders(ctx.device, vertex_mod, fragment_mod) or_return

    dynamic_states : [dynamic]vk.DynamicState
    rendering_info : vk.PipelineRenderingCreateInfo
    rendering_info.sType = .PIPELINE_RENDERING_CREATE_INFO
    rendering_info.colorAttachmentCount = u32(len(cfg.color_formats))

    attachments := make([]vk.Format, len(cfg.color_formats))
    for i in 0..<len(cfg.color_formats) {
        attachments[i] = _to_vk_image_format(cfg.color_formats[i])
    }

    rendering_info.pColorAttachmentFormats = &attachments[0]

    vertex_input := _load_vertex_input() // are we enforcing bindless? I think I am okay with that...

    input_asm : ^vk.PipelineInputAssemblyStateCreateInfo
    if cfg.topology != .NONE {
        input_asm = new(vk.PipelineInputAssemblyStateCreateInfo)
        input_asm.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
         #partial switch cfg.topology {
             case .TRIANGLE_LIST:
                input_asm.topology = .TRIANGLE_LIST
         }
    } else {
        append(&dynamic_states, vk.DynamicState.PRIMITIVE_TOPOLOGY)
    }

    defer if input_asm != nil do free(input_asm)

    rasterizer : ^vk.PipelineRasterizationStateCreateInfo
    if raster_state, found_raster := cfg.rasterization.?; found_raster {
        rasterizer = new(vk.PipelineRasterizationStateCreateInfo)
        rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO

        #partial switch (raster_state.front_face) {
            case .CLOCKWISE:
                rasterizer.frontFace = .CLOCKWISE
            case .COUNTERCLOCKWISE:
                rasterizer.frontFace = .COUNTER_CLOCKWISE
        }

        #partial switch (raster_state.cull_mode) {
            case .BACK:
                rasterizer.cullMode = {.BACK}
            case .FRONT:
                rasterizer.cullMode = {.FRONT}
        }

        rasterizer.depthBiasEnable = false
        rasterizer.depthClampEnable = false
        rasterizer.lineWidth = raster_state.line_width
        rasterizer.polygonMode = .FILL
    } else {
        append(&dynamic_states, vk.DynamicState.CULL_MODE)
        append(&dynamic_states, vk.DynamicState.FRONT_FACE)
    }

    defer if rasterizer != nil do free(rasterizer)

    depth_state : ^vk.PipelineDepthStencilStateCreateInfo
    if depth, found_depth := cfg.depth.?; found_depth {
        depth_state = new(vk.PipelineDepthStencilStateCreateInfo)
        depth_state.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
        depth_state.depthTestEnable = depth.read_depth
        depth_state.depthWriteEnable = depth.write_depth

        #partial switch (depth.depth_compare_op) {
            case .GREATER:
                depth_state.depthCompareOp = .GREATER
            case .NOT_EQUAL:
                depth_state.depthCompareOp = .NOT_EQUAL
            case .LEQUAL:
                depth_state.depthCompareOp = .LESS_OR_EQUAL
            case .GEQUAL:
                depth_state.depthCompareOp = .GREATER_OR_EQUAL
            case .EQUAL:
                depth_state.depthCompareOp = .EQUAL
            case .LESS:
                depth_state.depthCompareOp = .LESS
            case .ALWAYS:
                depth_state.depthCompareOp = .ALWAYS
        }

        depth_state.stencilTestEnable = depth.read_stencil

        // TODO)) Stencils get kind of extra complicated, so leaving that for later

        rendering_info.depthAttachmentFormat = _to_vk_image_format(depth.depth_format)
        rendering_info.stencilAttachmentFormat = _to_vk_image_format(depth.stencil_format)

    } else {
        append(&dynamic_states, vk.DynamicState.DEPTH_BOUNDS)
        append(&dynamic_states, vk.DynamicState.DEPTH_COMPARE_OP)
        append(&dynamic_states, vk.DynamicState.DEPTH_TEST_ENABLE)
        append(&dynamic_states, vk.DynamicState.DEPTH_WRITE_ENABLE)
        append(&dynamic_states, vk.DynamicState.STENCIL_OP)
        append(&dynamic_states, vk.DynamicState.STENCIL_TEST_ENABLE)
    }

    defer if depth_state != nil do free(depth_state)

    viewport_state : ^vk.PipelineViewportStateCreateInfo
    vp : ^vk.Viewport
    sc : ^vk.Rect2D
    if viewport, found_viewport := cfg.viewport.?; found_viewport {
        viewport_state = new(vk.PipelineViewportStateCreateInfo)
        viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
        viewport_state.viewportCount = 1
        viewport_state.scissorCount = 1

        vp = new(vk.Viewport)
        vp.x = viewport.viewport_top_left.x
        vp.y = viewport.viewport_top_left.y
        vp.width = viewport.viewport_bot_right.x - viewport.viewport_top_left.x
        vp.height = viewport.viewport_top_left.y - viewport.viewport_bot_right.y

        sc = new(vk.Rect2D)
        sc.offset.x = viewport.scissor_top_left.x
        sc.offset.y = viewport.scissor_top_left.y
        sc.extent.width = u32(viewport.scissor_bot_right.x - viewport.scissor_top_left.x)
        sc.extent.height = u32(viewport.scissor_top_left.y - viewport.scissor_bot_right.y)
    } else {
        append(&dynamic_states, vk.DynamicState.VIEWPORT)
        append(&dynamic_states, vk.DynamicState.SCISSOR)
    }

    defer if viewport_state != nil do free(viewport_state)
    defer if vp != nil do free(vp)
    defer if sc != nil do free(sc)

    color_blend : ^vk.PipelineColorBlendStateCreateInfo
    blend_state : ^vk.PipelineColorBlendAttachmentState
    if color_state, found_blend := cfg.blend_state.?; found_blend {
        color_blend = new(vk.PipelineColorBlendStateCreateInfo)
        blend_state = new(vk.PipelineColorBlendAttachmentState)

        color_blend.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
        color_blend.attachmentCount = 1
        color_blend.blendConstants = {0.0, 0.0, 0.0, 0.0}

        blend_state.srcColorBlendFactor = .ONE
        blend_state.dstColorBlendFactor = .ZERO
        blend_state.srcAlphaBlendFactor = .ONE
        blend_state.dstAlphaBlendFactor = .ZERO
        blend_state.blendEnable = color_state.enable_blend
        #partial switch (color_state.color_blend_op) {
            case .ADD:
                blend_state.colorBlendOp = .ADD
            case .SUBTRACT:
                blend_state.colorBlendOp = .SUBTRACT
            case .REVERSE_SUBTRACT:
                blend_state.colorBlendOp = .REVERSE_SUBTRACT
            case .MIN:
                blend_state.colorBlendOp = .MIN
            case .MAX:
                blend_state.colorBlendOp = .MAX
        }

        #partial switch (color_state.alpha_blend_op) {
            case .ADD:
                blend_state.alphaBlendOp = .ADD
            case .SUBTRACT:
                blend_state.alphaBlendOp = .SUBTRACT
            case .REVERSE_SUBTRACT:
                blend_state.alphaBlendOp = .REVERSE_SUBTRACT
            case .MIN:
                blend_state.alphaBlendOp = .MIN
            case .MAX:
                blend_state.alphaBlendOp = .MAX
        }

        color_blend.pAttachments = blend_state
    } else {
        append(&dynamic_states, vk.DynamicState.BLEND_CONSTANTS)
        append(&dynamic_states, vk.DynamicState.COLOR_BLEND_ENABLE_EXT)
        append(&dynamic_states, vk.DynamicState.COLOR_BLEND_EQUATION_EXT)
    }

    defer if color_blend != nil do free(color_blend)
    defer if blend_state != nil do free(blend_state)


    layout_info : vk.PipelineLayoutCreateInfo
    layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
    layout_info.setLayoutCount = u32(len(cfg.descriptor_sets.layout))
    layout_info.pSetLayouts = &cfg.descriptor_sets.layout[0]
    // need to figure out if we be using push constants or not

    layout : vk.PipelineLayout
    vk.CreatePipelineLayout(ctx.device, &layout_info, {}, &layout)

    multisample := _load_multisampling()
    dyn_states := _load_dynamic_states(dynamic_states[:])

    pl := _load_pipeline(
        ctx,
        shaders,
        &dyn_states,
        &vertex_input, // default
        input_asm,
        viewport_state,
        rasterizer,
        &multisample, // default
        color_blend,
        depth_state,
        layout,
        &rendering_info // local scope
    ) or_return

    pipeline.data = pl
    pipeline.layout = layout

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

_load_shaders :: proc(device : vk.Device, vertex_mod, fragment_mod : vk.ShaderModule) -> (shaders : []vk.PipelineShaderStageCreateInfo, ok : bool = true){
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

_load_dynamic_states :: proc(states : []vk.DynamicState) -> (create_info : vk.PipelineDynamicStateCreateInfo){
    create_info.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
    create_info.dynamicStateCount = u32(len(states))
    create_info.pDynamicStates = &states[0]

    return
}

_load_vertex_input :: proc() -> (create_info : vk.PipelineVertexInputStateCreateInfo) {
    // TODO)) I think this is where I need to bind my vertex/instance descriptor sets from ctx.data
    create_info.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    create_info.vertexBindingDescriptionCount = 0
    create_info.pVertexBindingDescriptions = nil
    create_info.vertexAttributeDescriptionCount = 0
    create_info.pVertexAttributeDescriptions = nil
    return
}

_load_multisampling :: proc() -> (create_info : vk.PipelineMultisampleStateCreateInfo) {
    create_info.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    create_info.sampleShadingEnable = false
    create_info.rasterizationSamples = {._1}
    create_info.minSampleShading = 1.0
    create_info.pSampleMask = nil
    create_info.alphaToCoverageEnable = false
    create_info.alphaToOneEnable = false
    return
}

_load_pipeline :: proc(ctx : ^Context,
                      shader_stages : []vk.PipelineShaderStageCreateInfo,
                      dynamic_states : ^vk.PipelineDynamicStateCreateInfo,
                      vertex_input : ^vk.PipelineVertexInputStateCreateInfo,
                      input_assembly : ^vk.PipelineInputAssemblyStateCreateInfo,
                      viewport : ^vk.PipelineViewportStateCreateInfo,
                      rasterizer : ^vk.PipelineRasterizationStateCreateInfo,
                      multisampling : ^vk.PipelineMultisampleStateCreateInfo,
                      color_blend : ^vk.PipelineColorBlendStateCreateInfo,
                      depth_state : ^vk.PipelineDepthStencilStateCreateInfo,
                      layout : vk.PipelineLayout,
                      rendering_info : ^vk.PipelineRenderingCreateInfo) -> (pipeline : vk.Pipeline, ok : bool = true) {
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
    create_info.pDepthStencilState = depth_state
    create_info.layout = layout
    create_info.subpass = 0

    create_info.pNext = rendering_info // this allows us to use dynamic rendering

    // TODO)) it is possible to create multiple pipelines at once - we can look into this to see if this can be extended
    res := vk.CreateGraphicsPipelines(ctx.device, 0, 1, &create_info, {}, &pipeline)
    if res != .SUCCESS {
        log.error("Error creating graphics pipeline:", res)
        ok = false
    }

    return
}
