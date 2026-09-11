package assets

import "shared:raven-gfx/api"
import "shared:raven-gfx/core"

Shader :: struct {
	data : api.Shader
}

load_shader_asset :: proc(
	device : api.Device,
	store : ^Asset_Store,
	data : []byte,
	shader_stage : core.Shader_Stage,
	next_stage : bit_set[core.Shader_Stage],
	schema : []api.Shader_Schema) -> (shader : Shader, ok : bool = true) {

	cfg := api.Shader_Config{
		stage = shader_stage,
		layout = schema,
		next_stage = next_stage
	}

	shader.data = api.create_shader(device, data, &cfg) or_return

	return
}
