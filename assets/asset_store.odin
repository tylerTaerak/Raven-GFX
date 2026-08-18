package assets

import "core:os"
import "shared:raven-gfx/api"
import gmem "shared:gpu-memory"

// Asset_Type refers to a CPU-based struct that
// contains the data need to query the real asset
// data from the GPU
//
// the arena is a simple GPU-based memory management
// system that all asset data is allocated from 
Asset_Store :: struct($Asset_Type : typeid) {
	assets 			: [dynamic]Asset_Type,
	arena 			: gmem.Memory_Block(.DEVICE),
	staging 		: gmem.Memory_Block(.HOST),
	gmem_device 	: gmem.Device,
	cmd_set 		: api.Command_Collection(1),
	loading_fence 	: api.Fence
}

Asset_Handle :: struct($Asset_Type : typeid) {
	handle : int
}

create_asset_store :: proc(
	device : api.Device,
	$Asset_Type : typeid,
	initial_capacity_bytes : int) -> (store : Asset_Store(Asset_Type), ok : bool = true) {

	store.gmem_device = api.allocate_gmem_device(device)

	err : gmem.Error

	store.arena, err = gmem.create_memory_block(store.gmem_device, initial_capacity_bytes, .DEVICE)

	if err != nil {
		ok = false
		return
	}

	store.staging, err = gmem.create_memory_block(store.gmem_device, initial_capacity_bytes, .HOST)

	if err != nil {
		ok = false
		return
	}

	store.cmd_set = api.create_command_buffers(device, 1, {.TRANSFER}) or_return

	store.loading_fence = api.create_fence(device)

	return
}

load_asset_from_filepath :: proc(device : api.Device, store : ^$T/Asset_Store($E), filepath : string) -> (handle : Asset_Handle(E), ok : bool = true) {
	assets := load_multiple_assets_from_filepath(device, store, filepath) or_return
	defer delete(assets)

	handle = assets[0]

	return
}


load_asset_from_bytes :: proc(device : api.Device, store : ^$T/Asset_Store($E), data : []byte) -> (handle : Asset_Handle(E), ok : bool = true) {
	assets := load_multiple_assets_from_bytes(device, store, data) or_return
	defer delete(assets)

	handle = assets[0]
	return
}

load_asset :: proc{
	load_asset_from_filepath,
	load_asset_from_bytes,
}

load_multiple_assets_from_filepath :: proc(
	device : api.Device,
	store : ^$T/Asset_Store($E),
	filepath : string) -> (handles : []Asset_Handle(E), ok : bool = true) {

	bytes, err := os.read_entire_file_from_path(filepath, context.temp_allocator)
	defer free_all(context.temp_allocator)

	if err != nil {
		ok = false
		return
	}

	handles = load_multiple_assets_from_bytes(device, store, bytes, filepath) or_return

	return
}

dispatch_load_assets :: proc {
	load_model_assets,
	load_font_assets,
	load_shader_assets,
	load_texture_assets,
}

load_multiple_assets_from_bytes :: proc(
	device : api.Device,
	store : ^$T/Asset_Store($E),
	data : []byte,
	filepath : Maybe(string) = nil) -> (handles : []Asset_Handle(E), ok : bool = true) {

	api.wait_for_fence(device, store.loading_fence)
	api.reset_fence(device, store.loading_fence)

	assets : []E
	assets, ok = dispatch_load_assets(device, store, data)

	handles = make([]Asset_Handle(E), len(assets))

	for a, i in assets {
		handles[i].handle = len(store.assets)
		append(&store.assets, a)
	}

	api.submit_command_buffer(device, store.cmd_set, 0, 0, 0, store.loading_fence)

	return
}

load_multiple_assets :: proc{
	load_multiple_assets_from_filepath,
	load_multiple_assets_from_bytes
}


destroy_asset_store :: proc(device : api.Device, store : $T/Asset_Store($E)) {
	api.destroy_fence(device, store.loading_fence)
	api.destroy_command_buffers(device, store.cmd_set)
	gmem.destroy_memory_block(store.gmem_device, store.staging)
	gmem.destroy_memory_block(store.gmem_device, store.arena)
	api.free_gmem_device(store.gmem_device)
	delete(store.assets)
}
