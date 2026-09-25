package assets

import "shared:raven-gfx/api"
import "shared:raven-gfx/core"

// So with most of these assets, the use case is load -> use by handle,
// and maybe index them in the case of fonts. But for shaders, things are a little
// bit more complicated. These are basically externally loaded functions that get
// run on the graphics device, and as such, need to have their inputs etc. accessible
// as part of the program. So how should this API look? Does it require a whole separate
// library to interface with it? Yeah probably...

// So we initialize a shader with its schema, which looks something like:

/*
   var1 (set 0, binding 0)
   var2 (set 0, binding 1)

   var3 (set 1, binding 0)
   var4 (set 1, binding 1)
   var5 (set 1, binding 2)

   var6 (set 2, binding 0)
*/

// These are made of shader schema objects, each of which include parameters, which themselves
// include a name, type, and shader stage for that parameter

// So we have something that looks like this:

/*
   {
   		0: {
			{
				"name": "var1",
				"type": UNIFORM,
				"stage": VERTEX
			}

			--- OR ---
			
			"var2": {
				"type": UNIFORM,
				"stage": FRAGMENT
			}
		},
		1: {
			etc...
		},
		2: {
			etc...
		}
   }
*/

// So maybe we can use maps extensively to manage this data:

// Shader_Param :: struct { type: Descriptor_Type, stage: Shader_Stage {
// Shader_Param_Set :: map[string]Shader_Param
// Shader_Schema :: map[int]Shader_Param_Set

// And then we can do something like

/* set0 : Shader_Param_Set
   defer delete(set0)

   set0["var1"] = {.UNIFORM, .VERTEX}
   set0["var2"] = {.UNIFORM, .FRAGMENT}

   schema : Shader_Schema
   schema[0] = set0

   initialize_shader_schema(..., &schema)

   create_shader(..., schema)
   create_shader(..., schema)
*/

// And then we have a reusable schema that we can use across shaders as needed

// Shader input datas should be allocated from these schema objects, rather than from the
// shaders themselves:

/*
   shader_data0 = create_shader_data(..., schema, 0)

   write_shader_data(..., my_uniform0, shader_data0, "var1")

   set_current_shader_data(schema, 0, shader_data0)

   ...

   bind_shader_schema(..., schema)

   bind_shader(..., shader0)

   draw(...)
*/

// Using this, we can utilize multiple shader input data descriptors so we can use different data// per frame, or per draw, or per batch, etc.

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
