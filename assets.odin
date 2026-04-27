package gfx

import "core:log"
import vk "vendor:vulkan"
import gvk "./vulkan"
import "./core"
import "core:mem"

MAX_VERTICES :: 2_048_000

Model_Chunk :: struct {
    // offsets for GPU buffers
    vertex_offset   : u32,
    index_offset    : u32,

    // number of draws to run
    vertex_count    : u32,
    index_count     : u32,

    // bind this buffer to the index buffer
    i_indices       : gvk.Buffer_Slice(u32),    

    // these buffers are all for descriptor sets
    v_positions     : gvk.Buffer_Slice([3]f32),
    v_texcoords     : gvk.Buffer_Slice([2]f32),
    v_colors        : gvk.Buffer_Slice([4]f32),
    v_normals       : gvk.Buffer_Slice([3]f32),
    v_tangents      : gvk.Buffer_Slice([3]f32),
}

Model_Asset :: struct {
    chunks : []Model_Chunk
}

Model_Handle :: distinct u64

Texture_Asset :: struct {
}

Texture_Handle :: distinct u64

Font_Asset :: struct {
}

Font_Handle :: distinct u64

Shared_Buffer :: struct ($T: typeid) {
    device_mem  : gvk.Buffer(T),
    host_mem    : gvk.Host_Buffer(T)
}


// TODO)) it might be worth having a command buffer just for the asset handler...
// Transfer commands need to be run on their own anyway... - maybe the asset handler
// should run on its own CPU thread too
Asset_Handler :: struct {
    commands    : gvk.Command_Set,
    models      : [dynamic]Model_Asset,
    textures    : [dynamic]Texture_Asset,
    fonts       : [dynamic]Font_Asset,

    // buffers
    desc_positions  : Shared_Buffer([3]f32),
    desc_texcoords  : Shared_Buffer([2]f32),
    desc_colors     : Shared_Buffer([4]f32),
    desc_normals    : Shared_Buffer([3]f32),
    desc_tangents   : Shared_Buffer([3]f32),
    index_buffer    : Host_Buffer(u32),

    // offsets
    vertex_offset   : u32,
    index_offset    : u32,

    // writing semaphore
    prev_write_sem      : gvk.Semaphore,
    current_write_sem   : gvk.Semaphore,
    write_fence         : gvk.Fence
}

create_asset_handler :: proc() -> (handler : Asset_Handler, ok : bool = true) {
    fam := gvk.find_queue_family_by_type(Core_Context.backend, {.TRANSFER}) or_return

    handler.commands = gvk.create_command_set(Core_Context.backend, 1, fam^) or_return

    handler.desc_positions.device_mem = gvk.create_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
    handler.desc_positions.host_mem = gvk.create_host_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC})

    handler.desc_texcoords.device_mem = gvk.create_buffer(Core_Context.backend, [2]f32, MAX_VERTICES, {fam^}, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
    handler.desc_texcoords.host_mem = gvk.create_host_buffer(Core_Context.backend, [2]f32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC})

    handler.desc_colors.device_mem = gvk.create_buffer(Core_Context.backend, [4]f32, MAX_VERTICES, {fam^}, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
    handler.desc_colors.host_mem = gvk.create_host_buffer(Core_Context.backend, [4]f32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC})

    handler.desc_normals.device_mem = gvk.create_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
    handler.desc_normals.host_mem = gvk.create_host_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC})

    handler.desc_tangents.device_mem = gvk.create_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_DST, .STORAGE_BUFFER}, {.DEVICE_LOCAL})
    handler.desc_tangents.host_mem = gvk.create_host_buffer(Core_Context.backend, [3]f32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC})

    handler.index_buffer = gvk.create_host_buffer(Core_Context.backend, u32, MAX_VERTICES, {fam^}, {.TRANSFER_SRC, .TRANSFER_DST, .INDEX_BUFFER})

    handler.write_fence = gvk.init_fence(Core_Context.backend)

    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 0, 0, handler.desc_positions.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 1, 0, handler.desc_positions.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 2, 0, handler.desc_positions.device_mem)

    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 0, 1, handler.desc_texcoords.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 1, 1, handler.desc_texcoords.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 2, 1, handler.desc_texcoords.device_mem)

    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 0, 2, handler.desc_colors.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 1, 2, handler.desc_colors.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 2, 2, handler.desc_colors.device_mem)

    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 0, 3, handler.desc_normals.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 1, 3, handler.desc_normals.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 2, 3, handler.desc_normals.device_mem)

    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 0, 4, handler.desc_tangents.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 1, 4, handler.desc_tangents.device_mem)
    gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, 2, 4, handler.desc_tangents.device_mem)

    return
}

_copy_to_gpu :: proc(buffer : vk.CommandBuffer, data : ^$T/Shared_Buffer($E), begin, end : int) {
    host_slice := gvk.make_slice_from_indicies(&data.host_mem.internal_buffer, begin, end)
    dev_slice := gvk.make_slice_from_indicies(&data.device_mem, begin, end)

    gvk.copy_buffer_data(buffer, &host_slice, &dev_slice)
}

load_model :: proc(handler : ^Asset_Handler, filepath : string) -> (handle : Model_Handle) {
    handle = Model_Handle(len(handler.models))

    model_data := core.load_models_from_file(filepath)

    _wait_for_fence(Core_Context.backend, &handler.write_fence)
    _reset_fence(Core_Context.backend, &handler.write_fence)

    // delete the old last semaphore
    if handler.prev_write_sem != 0 {
        gvk.destroy_semaphore(Core_Context.backend, handler.prev_write_sem)
    }

    // cycle to next semaphores
    handler.prev_write_sem = handler.current_write_sem
    handler.current_write_sem = gvk.init_semaphore(Core_Context.backend)

    // open the GPU command buffer for submitting transfer work
    buf := gvk.begin_command_buffer(handler.commands, 0)

    for model in model_data {
        new_model : Model_Asset
        chunks : [dynamic]Model_Chunk

        for prim in model.primitives {
            chunk : Model_Chunk

            chunk.vertex_offset = handler.vertex_offset
            chunk.index_offset = handler.index_offset

            chunk.vertex_count = prim.vertex_count
            chunk.index_count  = u32(len(prim.indices))

            v_start := handler.vertex_offset
            v_end := v_start + chunk.vertex_count
            i_start := handler.index_offset

            mem.copy(rawptr(uintptr(handler.index_buffer.data_ptr) + uintptr(i_start * size_of(u32))), raw_data(prim.indices), len(prim.indices) * size_of(u32))

            mem.copy(
                rawptr(uintptr(handler.desc_positions.host_mem.data_ptr) + uintptr(v_start * size_of([3]f32))),
                raw_data(prim.descriptor_data[.POSITION]),
                len(prim.descriptor_data[.POSITION]))

            mem.copy(
                rawptr(uintptr(handler.desc_texcoords.host_mem.data_ptr) + uintptr(v_start * size_of([2]f32))),
                raw_data(prim.descriptor_data[.TEXCOORD]),
                len(prim.descriptor_data[.TEXCOORD]))

            mem.copy(
                rawptr(uintptr(handler.desc_colors.host_mem.data_ptr) + uintptr(v_start * size_of([4]f32))),
                raw_data(prim.descriptor_data[.COLOR]),
                len(prim.descriptor_data[.COLOR]))

            mem.copy(
                rawptr(uintptr(handler.desc_normals.host_mem.data_ptr) + uintptr(v_start * size_of([3]f32))),
                raw_data(prim.descriptor_data[.NORMAL]),
                len(prim.descriptor_data[.NORMAL]))

            mem.copy(
                rawptr(uintptr(handler.desc_tangents.host_mem.data_ptr) + uintptr(v_start * size_of([3]f32))),
                raw_data(prim.descriptor_data[.TANGENT]),
                len(prim.descriptor_data[.TANGENT]))

            // add commands to command buffer to copy from the host buffer to the GPU buffer

            _copy_to_gpu(buf, &handler.desc_positions, int(v_start), int(v_end))
            _copy_to_gpu(buf, &handler.desc_texcoords, int(v_start), int(v_end))
            _copy_to_gpu(buf, &handler.desc_colors, int(v_start), int(v_end))
            _copy_to_gpu(buf, &handler.desc_normals, int(v_start), int(v_end))
            _copy_to_gpu(buf, &handler.desc_tangents, int(v_start), int(v_end))


            handler.index_offset += chunk.index_count
            handler.vertex_offset += chunk.vertex_count

            append(&chunks, chunk)
        }

        new_model.chunks = chunks[:]
        append(&handler.models, new_model)
    }

    gvk.end_command_buffer(buf)

    fam, ok := gvk.find_queue_family_by_type(Core_Context.backend, {.TRANSFER})

    if !ok
    {
        log.warn("Error finding correct queue family for transfer work, not submitting queue")
        return
    }
    
    gvk.submit_command_buffer(Core_Context.backend, buf, fam^, handler.prev_write_sem, handler.current_write_sem, handler.write_fence)

    return
}

destroy_asset_handler :: proc(handler : ^Asset_Handler) {
    if handler.current_write_sem != 0 {
        gvk.destroy_semaphore(Core_Context.backend, handler.current_write_sem)
    }

    if handler.prev_write_sem != 0 {
        gvk.destroy_semaphore(Core_Context.backend, handler.prev_write_sem)
    }

    gvk.destroy_fence(Core_Context.backend, handler.write_fence)

    gvk.destroy_host_buffer(Core_Context.backend, handler.desc_tangents.host_mem)
    gvk.destroy_host_buffer(Core_Context.backend, handler.desc_normals.host_mem)
    gvk.destroy_host_buffer(Core_Context.backend, handler.desc_colors.host_mem)
    gvk.destroy_host_buffer(Core_Context.backend, handler.desc_texcoords.host_mem)
    gvk.destroy_host_buffer(Core_Context.backend, handler.desc_positions.host_mem)

    gvk.destroy_buffer(Core_Context.backend, handler.desc_tangents.device_mem)
    gvk.destroy_buffer(Core_Context.backend, handler.desc_normals.device_mem)
    gvk.destroy_buffer(Core_Context.backend, handler.desc_colors.device_mem)
    gvk.destroy_buffer(Core_Context.backend, handler.desc_texcoords.device_mem)
    gvk.destroy_buffer(Core_Context.backend, handler.desc_positions.device_mem)

    gvk.destroy_host_buffer(Core_Context.backend, handler.index_buffer)

    gvk.destroy_command_set(Core_Context.backend, &handler.commands)
}
