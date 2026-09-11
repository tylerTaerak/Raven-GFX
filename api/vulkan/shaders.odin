package game_vulkan

import "core:log"
import "shared:raven-gfx/core"
import vk "vendor:vulkan"

Shader :: struct {
    stage   : core.Shader_Stage,
    obj     : vk.ShaderEXT,
	layout  : Pipeline_Layout
}

Shader_Config :: struct {
	stage 		: core.Shader_Stage,
	layout 		: []Descriptor_Layout,
	next_stage 	: bit_set[core.Shader_Stage]
}

create_shader :: proc(
	device : Device,
	data : []byte,
	cfg : ^Shader_Config) -> (shader : Shader, ok : bool = true) {

	cinfo : vk.ShaderCreateInfoEXT
	cinfo.sType = .SHADER_CREATE_INFO_EXT
	cinfo.flags = {}
	cinfo.stage = _to_vk_shader_stage(cfg.stage)
	cinfo.codeType = .SPIRV
	cinfo.codeSize = len(data)
	cinfo.pCode = &data[0]
	cinfo.pName = "main"

	desc_layouts : [dynamic]vk.DescriptorSetLayout
	defer delete(desc_layouts)

	for i in 0..<len(cfg.layout) {
		append(&desc_layouts, cfg.layout[i].vklayout)
	}


	cinfo.setLayoutCount = u32(len(cfg.layout))
	cinfo.pSetLayouts = &desc_layouts[0]

	for stage in cfg.next_stage {
		cinfo.nextStage &= _to_vk_shader_stage(stage)
	}

	res := vk.CreateShadersEXT(device.core, 1, &cinfo, {}, &shader.obj)

	if res != .SUCCESS
	{
		ok = false
		log.error("Error creating shaders:", res)
		return
	}

	shader.stage = cfg.stage
	shader.layout = create_pipeline_layout(device, cfg.layout) or_return

    return
}

bind_shaders :: proc(device : Device, cmd_buf : vk.CommandBuffer, shaders : [core.Shader_Stage]Shader, descriptors : []Descriptor_Set) -> (ok : bool = true){
    vk_set : [dynamic]vk.ShaderEXT
    vk_stages : [dynamic]vk.ShaderStageFlags

	for shader in shaders {
		if shader.obj != 0x0 {
			append(&vk_set, shader.obj)
			append(&vk_stages, _to_vk_shader_stage(shader.stage))
		}

		bind_descriptor_sets(device, cmd_buf, shader.layout, descriptors) or_return
	}

    vk.CmdBindShadersEXT(cmd_buf, u32(len(vk_set)), &vk_stages[0], &vk_set[0])

	return
}

unbind_shaders :: proc(cmd_buf : vk.CommandBuffer, shaders : [core.Shader_Stage]Shader) {
    stages : [dynamic]vk.ShaderStageFlags

	for shader in shaders {
		if shader.obj != 0x0 {
			append(&stages, _to_vk_shader_stage(shader.stage))
		}
    }

    vk.CmdBindShadersEXT(cmd_buf, u32(len(stages)), &stages[0], nil)
}

destroy_shader :: proc(device : Device, shader: Shader) {
    vk.DestroyShaderEXT(device.core, shader.obj, {})
}
