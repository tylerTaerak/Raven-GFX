package assets

import "core:os"
import "shared:raven-gfx/core"
import "shared:raven-gfx/api"

Model_Handle :: distinct int
Font_Handle  :: distinct int
Texture_Handle :: distinct int
Shader_Handle  :: distinct int

Asset_Store :: struct {
	image_store 	: [dynamic]api.Image,
	pending_allocs  : [dynamic]api.Buffer(.HOST),

	textures 		: [dynamic]Texture,
	models 			: [dynamic]Model,
	fonts 			: [dynamic]Font,
	shaders 		: [dynamic]Shader,

	cmd_set 		: api.Command_Collection(1),
	loading_fence 	: api.Fence
}

make_host_buffer :: proc(device : api.Device, store : ^Asset_Store, size : int) -> (api.Buffer(.HOST), bool) {
	buf, ok := api.create_host_buffer(device, size)

	if !ok {
		return {}, false
	}

	append(&store.pending_allocs, buf)

	return buf, true
}

create_asset_store :: proc(
	device : api.Device,
	initial_capacity_bytes : int) -> (store : Asset_Store, ok : bool = true) {

	store.cmd_set = api.create_command_buffers(device, 1, {.TRANSFER}) or_return

	store.loading_fence = api.create_fence(device)

	return
}

load_models_from_filepath :: proc(device : api.Device, store : ^Asset_Store, filepath : string) -> (handle : []Model_Handle, ok : bool = true) {

	bytes, err := os.read_entire_file_from_path(filepath, context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		ok = false
		return
	}

	handle, ok = load_models_from_bytes(device, store, bytes, filepath)

	return
}

load_models_from_bytes :: proc(device : api.Device, store : ^Asset_Store, data : []byte, filepath: string) -> (handle : []Model_Handle, ok : bool = true) {

	api.wait_for_fence(device, store.loading_fence)
	api.reset_fence(device, store.loading_fence)

	// cleanse the pending host buffer before allocating a new asset
	for i in 0..<len(store.pending_allocs) {
		api.destroy_buffer(device, store.pending_allocs[i])
	}

	clear(&store.pending_allocs)

	api.begin_command_buffer(store.cmd_set, 0)

	models := load_model_data(device, store, data, filepath) or_return

	api.end_command_buffer(store.cmd_set, 0)

	api.submit_command_buffer(device, store.cmd_set, 0, 0, 0, store.loading_fence)

	model_count := len(models)
	first := len(store.models)

	handle = make([]Model_Handle, model_count)

	for i in 0..<model_count {
		handle[i] = Model_Handle(first + i)
	}

	append(&store.models, ..models)

	return
}

load_models :: proc{
	load_models_from_filepath,
	load_models_from_bytes
}

load_texture_from_filepath :: proc(device : api.Device, store : ^Asset_Store, filepath : string) -> (handle : Texture_Handle, ok : bool = true) {

	bytes, err := os.read_entire_file_from_path(filepath, context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		ok = false
		return
	}

	handle, ok = load_texture_from_bytes(device, store, bytes)

	return
}

load_texture_from_bytes :: proc(device : api.Device, store : ^Asset_Store, data : []byte) -> (handle : Texture_Handle, ok : bool = true) {
	api.wait_for_fence(device, store.loading_fence)
	api.reset_fence(device, store.loading_fence)

	api.begin_command_buffer(store.cmd_set, 0)

	texture := load_texture_data(device, store, data) or_return

	api.end_command_buffer(store.cmd_set, 0)

	api.submit_command_buffer(device, store.cmd_set, 0, 0, 0, store.loading_fence)

	handle = Texture_Handle(len(store.textures))

	append(&store.textures, texture)

	return
}

load_texture :: proc{
	load_texture_from_filepath,
	load_texture_from_bytes
}

load_fonts_from_filepath :: proc(device : api.Device, store : ^Asset_Store, filepath : string) -> (handle : []Font_Handle, ok : bool = true) {

	bytes, err := os.read_entire_file_from_path(filepath, context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		ok = false
		return
	}

	return
}

load_fonts_from_bytes :: proc(device : api.Device, store : ^Asset_Store, data : []byte) -> (handle : []Font_Handle, ok : bool = true) {
	api.wait_for_fence(device, store.loading_fence)
	api.reset_fence(device, store.loading_fence)

	api.begin_command_buffer(store.cmd_set, 0)

	//------------------

	api.end_command_buffer(store.cmd_set, 0)

	api.submit_command_buffer(device, store.cmd_set, 0, 0, 0, store.loading_fence)

	return
}

load_fonts :: proc{
	load_fonts_from_filepath,
	load_fonts_from_bytes
}

load_shader_from_filepath :: proc(
	device : api.Device,
	store : ^Asset_Store,
	filepath : string,
	stage : core.Shader_Stage,
	next_stage : bit_set[core.Shader_Stage],
	schema : []api.Shader_Schema) -> (handle : Shader_Handle, ok : bool = true) {
	bytes, err := os.read_entire_file_from_path(filepath, context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		ok = false
		return
	}

	handle, ok = load_shader_from_bytes(device, store, bytes, stage, next_stage, schema)

	return
}

load_shader_from_bytes :: proc(
	device : api.Device,
	store : ^Asset_Store,
	data : []byte,
	stage : core.Shader_Stage,
	next_stage : bit_set[core.Shader_Stage],
	schema : []api.Shader_Schema) -> (handle : Shader_Handle, ok : bool = true) {

	shader := load_shader_asset(device, store, data, stage, next_stage, schema) or_return

	handle = Shader_Handle(len(store.shaders))

	append(&store.shaders, shader)

	return
}

load_shader :: proc{
	load_shader_from_filepath,
	load_shader_from_bytes
}


destroy_asset_store :: proc(device : api.Device, store : ^Asset_Store) {
	api.destroy_fence(device, store.loading_fence)
	api.destroy_command_buffers(device, store.cmd_set)

	for i in 0..<len(store.pending_allocs) {
		api.destroy_buffer(device, store.pending_allocs[i])
	}

	delete(store.pending_allocs)

	delete(store.image_store)

	delete(store.textures)
	delete(store.fonts)
	delete(store.models)
}
