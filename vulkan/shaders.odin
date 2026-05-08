package game_vulkan

import "core:os"
import "core:log"
import "../core"
import vk "vendor:vulkan"
import "core:strings"

/// TODO)) These objects should be templatized and brought into `core` - the are user-level objects, so they need to be usable with different backends
Shader :: struct {
    stage   : core.Shader_Stage,
    obj     : vk.ShaderEXT
}

Shader_Chain :: struct {
    shaders : []Shader
}

Shader_Chain_Config :: struct {
    file : union{string, []byte},
    entrypoint_name : string,
    stage : core.Shader_Stage,
    descriptors : Descriptor_Collection,
    next_shader : ^Shader_Chain_Config
    // I don't think I'm using push constants anywhere TODO)) yet... we'll be adding cameras etc. soon
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

create_shader :: proc(ctx : ^Context, cfg : ^Shader_Chain_Config) -> (shader_set : Shader_Chain, ok : bool = true) {
    current_cfg : ^Shader_Chain_Config = cfg

    shaders : [dynamic]Shader
    defer delete(shaders)

    visited_stages : bit_set[core.Shader_Stage]

    for current_cfg != nil {
        // Vulkan doesn't allow binding multiple shaders of the same type, so enforce that when loading a single set of shaders
        if current_cfg.stage in visited_stages {
            ok = false
            return
        }

        visited_stages += {current_cfg.stage}

        shader_code : []byte
        switch file in cfg.file {
        case string:
            err : os.Error
            shader_code, err = os.read_entire_file(file, context.temp_allocator)
            if (err != .NONE)
            {
                ok = false
                return
            }
        case []byte:
            shader_code = file
        }

        cname := strings.clone_to_cstring(cfg.entrypoint_name)
        defer delete(cname)

        cinfo : vk.ShaderCreateInfoEXT
        cinfo.sType = .SHADER_CREATE_INFO_EXT
        cinfo.flags = {}
        cinfo.stage = {stage_to_vk_enum(cfg.stage)}
        cinfo.codeType = .SPIRV
        cinfo.codeSize = len(shader_code)
        cinfo.pCode = &shader_code[0]
        cinfo.pName = cname
        cinfo.setLayoutCount = u32(cfg.descriptors.set_count)
        cinfo.pSetLayouts = &cfg.descriptors.layout[0]

        if cfg.next_shader != nil {
            cinfo.nextStage = {stage_to_vk_enum(cfg.next_shader.stage)}
        }

        shader : Shader

        res := vk.CreateShadersEXT(ctx.device, 1, &cinfo, {}, &shader.obj)

        if res != .SUCCESS
        {
            ok = false
            return
        }

        shader.stage = cfg.stage

        append(&shaders, shader)
    }

    shader_set.shaders = make([]Shader, len(shaders))

    copy(shader_set.shaders, shaders[:])

    return
}

Shader_Set :: [core.Shader_Stage]^Shader


bind_shaders :: proc(cmd_buf : vk.CommandBuffer, shaders : Shader_Set) {
    vk_set : [dynamic]vk.ShaderEXT
    vk_stages : [dynamic]vk.ShaderStageFlags
    for stage in core.Shader_Stage {
        if shaders[stage] != nil {
            append(&vk_set, shaders[stage].obj)
            append(&vk_stages, vk.ShaderStageFlags{stage_to_vk_enum(stage)})
        }
    }

    vk.CmdBindShadersEXT(cmd_buf, u32(len(vk_set)), &vk_stages[0], &vk_set[0])
}

unbind_shaders :: proc(cmd_buf : vk.CommandBuffer, shaders : Shader_Set) {
    stages : [dynamic]vk.ShaderStageFlags
    for stage in core.Shader_Stage {
        if shaders[stage] != nil {
            append(&stages, vk.ShaderStageFlags{stage_to_vk_enum(stage)})
        }
    }

    vk.CmdBindShadersEXT(cmd_buf, u32(len(stages)), &stages[0], nil)
}


destroy_shader :: proc(ctx: ^Context, shader: Shader) {
    vk.DestroyShaderEXT(ctx.device, shader.obj, {})
}
