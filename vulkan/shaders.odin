package game_vulkan

import "core:os"
import "core:log"
import "../core"
import vk "vendor:vulkan"
import "core:strings"

Shader :: struct {
    name    : string,
    stage   : core.Shader_Stage,
    obj     : vk.ShaderEXT
}

Shader_Config :: struct {
    filename : string,
    shader_name : string,
    stage : core.Shader_Stage,
    descriptors : Descriptor_Collection
    // I don't think I'm using push constants anywhere
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
    }

    return .VERTEX
}

create_shader :: proc(ctx : ^Context, cfg : ^Shader_Config) -> (shader : Shader, ok : bool = true) {
    shader_code, err := os.read_entire_file(cfg.filename, context.temp_allocator)

    if (err != .NONE)
    {
        ok = false
        return
    }

    log.info(cfg.descriptors.set_count)
    log.info(len(cfg.descriptors.layout))
    log.info(&cfg.descriptors.layout[0])

    cname := strings.clone_to_cstring(cfg.shader_name)
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

    if cfg.stage == .VERTEX {
        cinfo.nextStage = {.FRAGMENT}
    }

    log.info(cinfo)

    res := vk.CreateShadersEXT(ctx.device, 1, &cinfo, {}, &shader.obj)

    if res != .SUCCESS
    {
        ok = false
        return
    }

    shader.name = cfg.shader_name
    shader.stage = cfg.stage

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
