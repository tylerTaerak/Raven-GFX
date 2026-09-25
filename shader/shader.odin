package shader

import "shared:raven-gfx/api"

Param :: api.Shader_Element

Data_Handle :: struct {
	handle : int,
	set_index : int
}

Set :: struct {
	data  		: [dynamic]api.Shader_Data,
	layout 		: api.Shader_Schema,
	params 		: [dynamic]Param,
	active_data : int
}

Schema :: map[int]Set


initialize_shader_schema :: proc(device : api.Device, schema : ^Schema) -> (bool){

	for idx in schema {
		set := &schema[idx]
		set.layout = api.create_shader_schema(device, schema[idx].params[:]) or_return
	}

	return true
}

cleanup_shader_schema :: proc(device : api.Device, schema : ^Schema) {
	for idx in schema {
		for &data in schema[idx].data {
			api.destroy_shader_data(device, &data)
		}

		api.destroy_shader_schema(device, schema[idx].layout)

		delete(schema[idx].params)
	}
}

allocate_shader_data :: proc(
	device : api.Device,
	schema : ^Schema,
	set_idx : int) -> (handle : Data_Handle, ok : bool){

	set := &schema[set_idx]

	shader_data := api.create_shader_data(device, set.layout) or_return

	handle.set_index = set_idx
	handle.handle = len(set.data)
	append(&set.data, shader_data)

	return handle, true
}

free_shader_data :: proc(device : api.Device, schema : ^Schema, handle : Data_Handle) {

	shader_data := &schema[handle.set_index].data[handle.handle]

	api.destroy_shader_data(device, shader_data)
}

set_active_shader_data :: proc(schema : ^Schema, handle : Data_Handle) {
	set := &schema[handle.set_index]
	set.active_data = handle.handle
}

bind_shader_schema :: proc(device : api.Device, schema : ^Schema) {
}

write_shader_data :: proc() {
	// TODO)) Might be a proc group
}
