package assets

import "shared:raven-gfx/api"
import "shared:raven-gfx/core"

Shader_Parameter :: struct {
	set_idx 	: int,
	param_idx 	: int,
}

Shader_Data :: distinct []api.Shader_Data
Shader_Data_Handle :: distinct u64

// When an input object is allocated, this is what is returned to the user for writing etc for
// descriptors
Shader_Parameters :: struct {
	handle : Shader_Data_Handle,
	params : map[string]Shader_Parameter
}

Shader :: struct {
	data : api.Shader,
	schema : []api.Shader_Schema,
	input_objs : [dynamic]Shader_Data,
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
