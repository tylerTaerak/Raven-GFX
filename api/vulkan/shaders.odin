package game_vulkan

import "core:os"
import "core:log"
import "shared:raven-gfx/core"
import vk "vendor:vulkan"
import "core:strings"
import gmem "shared:gpu-memory"

Shader_Description :: struct {
    descriptors : []Descriptor_Set,
    layout : vk.PipelineLayout
}

/// TODO)) These objects should be templatized and brought into `core` - the are user-level objects, so they need to be usable with different backends
Shader :: struct {
    stage   : core.Shader_Stage,
    obj     : vk.ShaderEXT
}

Shader_Chain :: struct {
    shaders : []Shader,
    descriptors : []Descriptor_Set,
    layout : vk.PipelineLayout
}

Shader_Config :: struct {
    file : union{string, []byte},
    entrypoint_name : string,
    stage : core.Shader_Stage,
    next_shader : ^Shader_Config
}

Shader_Chain_Config :: struct {
    first_shader : ^Shader_Config,
    descriptor_layout : []core.Descriptor_Type,
    descriptor_set_count : int
}

stage_to_vk_enum :: proc(stage : core.Shader_Stage) -> vk.ShaderStageFlag
{
    switch (stage)
    {
        case .VERTEX:
            return .VERTEX
        case .GEOMETRY:
            return .GEOMETRY
        case .FRAGMENT:
            return .FRAGMENT
        case .COMPUTE:
            return .COMPUTE
        case .MESH:
            return .MESH_EXT
    }

    return .VERTEX
}

create_shader_description :: proc(
	device : Device,
    $N : int,
    cfg : [$Size]core.Descriptor_Type,
    memory : gmem.Memory_Block(.DESCRIPTORS)) -> (desc: Shader_Description, ok : bool = true) {

    desc.descriptors = create_descriptor_sets(device, cfg, memory) or_return
    desc.layout = create_pipeline_layout(device, desc.descriptors)

    return
}

destroy_shader_description :: proc(device : Device, desc: ^Shader_Description) {
    // destroy_pipeline_layout(device, desc.layout)
    // destroy_descriptor_sets(device, desc.descriptors)
}

create_shader :: proc(device : Device, cfg : ^Shader_Chain_Config, descriptor_memory : ^gmem.Memory_Block(.DESCRIPTORS)) -> (shader_set : Shader_Chain, ok : bool = true) {
    shader_set.descriptors = create_descriptor_sets(device, cfg.descriptor_set_count, cfg.descriptor_layout, descriptor_memory) or_return
    // shader_set.layout = create_pipeline_layout(device, shader_set.descriptors)

    current_cfg : ^Shader_Config = cfg.first_shader

    shaders : [dynamic]Shader
    defer delete(shaders)

    visited_stages : bit_set[core.Shader_Stage]

    for current_cfg != nil {
        // Vulkan doesn't allow binding multiple shaders of the same type, so enforce that when loading a single set of shaders
        if current_cfg.stage in visited_stages {
            ok = false
            log.error("Multiple shaders of the same type can't be bound together")
            return
        }

        visited_stages += {current_cfg.stage}

        shader_code : []byte
        switch file in current_cfg.file {
            case string:
                err : os.Error
                shader_code, err = os.read_entire_file(file, context.temp_allocator)
                if (err != .NONE)
                {
                    ok = false
                    log.error("Error reading shader file:", err)
                    return
                }
            case []byte:
                shader_code = file
        }

        cname := strings.clone_to_cstring(current_cfg.entrypoint_name)
        defer delete(cname)

        cinfo : vk.ShaderCreateInfoEXT
        cinfo.sType = .SHADER_CREATE_INFO_EXT
        cinfo.flags = {}
        cinfo.stage = {stage_to_vk_enum(current_cfg.stage)}
        cinfo.codeType = .SPIRV
        cinfo.codeSize = len(shader_code)
        cinfo.pCode = &shader_code[0]
        cinfo.pName = cname
        cinfo.setLayoutCount = u32(len(shader_set.descriptors))

        layouts := make([]vk.DescriptorSetLayout, len(shader_set.descriptors))
        defer delete(layouts)

        for i in 0..<len(shader_set.descriptors) {
            layouts[i] = shader_set.descriptors[i].layout
        }

        cinfo.pSetLayouts = &layouts[0]

        if current_cfg.next_shader != nil {
            cinfo.nextStage = {stage_to_vk_enum(current_cfg.next_shader.stage)}
        }

        shader : Shader

        res := vk.CreateShadersEXT(device.core, 1, &cinfo, {}, &shader.obj)

        if res != .SUCCESS
        {
            ok = false
            log.error("Error creating shaders:", res)
            return
        }

        shader.stage = current_cfg.stage

        append(&shaders, shader)
    }

    shader_set.shaders = make([]Shader, len(shaders))

    copy(shader_set.shaders, shaders[:])

    return
}

// bind_shader_chain :: proc(ctx : ^Context, cmd_buf : vk.CommandBuffer, chain : Shader_Chain) {
//     bind_descriptor_sets(ctx, cmd_buf, chain.descriptors, chain.layout)
// 
//     shader_set : [dynamic]vk.ShaderEXT
//     shader_stages : [dynamic]vk.ShaderStageFlags
// 
//     defer delete(shader_stages)
//     defer delete(shader_set)
// 
//     for shader in chain.shaders {
//         if shader.stage != nil {
//             append(&shader_set, shader.obj)
//             append(&shader_stages, vk.ShaderStageFlags{stage_to_vk_enum(shader.stage)})
//         }
//     }
// 
//     vk.CmdBindShadersEXT(cmd_buf, u32(len(shader_set)), &shader_stages[0], &shader_set[0])
// }
// 
// Shader_Set :: [core.Shader_Stage]^Shader
// 
// 
// bind_shaders :: proc(cmd_buf : vk.CommandBuffer, shaders : Shader_Set) {
//     vk_set : [dynamic]vk.ShaderEXT
//     vk_stages : [dynamic]vk.ShaderStageFlags
//     for stage in core.Shader_Stage {
//         if shaders[stage] != nil {
//             append(&vk_set, shaders[stage].obj)
//             append(&vk_stages, vk.ShaderStageFlags{stage_to_vk_enum(stage)})
//         }
//     }
// 
//     vk.CmdBindShadersEXT(cmd_buf, u32(len(vk_set)), &vk_stages[0], &vk_set[0])
// }
// 
// unbind_shaders :: proc(cmd_buf : vk.CommandBuffer, shaders : Shader_Set) {
//     stages : [dynamic]vk.ShaderStageFlags
//     for stage in core.Shader_Stage {
//         if shaders[stage] != nil {
//             append(&stages, vk.ShaderStageFlags{stage_to_vk_enum(stage)})
//         }
//     }
// 
//     vk.CmdBindShadersEXT(cmd_buf, u32(len(stages)), &stages[0], nil)
// }


destroy_shader :: proc(device : Device, shader: Shader) {
    vk.DestroyShaderEXT(device.core, shader.obj, {})
}

destroy_shader_chain :: proc(device : Device, chain : Shader_Chain) {
    // destroy_pipeline_layout(device, chain.layout)
    // destroy_descriptor_sets(device, chain.descriptors)

    for shader in chain.shaders {
        destroy_shader(device, shader)
    }
}
