package gfx

import "core:log"
import vk "vendor:vulkan"
import gvk "./vulkan"
import "./core"
import "core:mem"

// import "../gpu_mem" // TODO))  I guess I need to continue doing it this way until I figue out how the heck imports ought to work in Odin
 
MAX_VERTICES :: 512_000

Model_Chunk :: struct {
    // offsets for GPU buffers
    vertex_offset   : uintptr,
    index_offset    : uintptr,

    // number of draws to run
    vertex_count    : u32,
    index_count     : u32,

    v_attributes    : []gvk.Gpu_Slice,
}

Model_Asset :: struct {
    chunks : []Model_Chunk
}

Model_Handle :: distinct u64

Texture_Asset :: struct {
    width : int,
    height : int,
    channel_count : int
}

Texture_Handle :: distinct u64

Font_Asset :: struct {
}

Font_Handle :: distinct u64

Shader_Asset :: struct {
    shader : gvk.Shader_Chain
}

Shader_Handle :: distinct u64

Byte :: 1
KiloByte :: 1024 * Byte
MegaByte :: 1024 * KiloByte
GigaByte :: 1024 * MegaByte

INITIAL_VERTEX_BYTE_COUNT       :: 2 * GigaByte
INITIAL_DESCRIPTOR_BYTE_COUNT   :: 500 * MegaByte

SCRATCHPAD_SIZE                 :: 500 * MegaByte

INITIAL_INDEX_BYTE_COUNT        :: 2 * GigaByte

// TODO)) it might be worth having a command buffer just for the asset handler...
// Transfer commands need to be run on their own anyway... - maybe the asset handler
// should run on its own CPU thread too
Asset_Handler :: struct {
    commands    : gvk.Command_Set,
    models      : [dynamic]Model_Asset,
    shaders     : [dynamic]Shader_Asset,
    gpu_queue_fam : ^gvk.QueueFamily,
    // textures    : [dynamic]Texture_Asset,
    // fonts       : [dynamic]Font_Asset,

    arena : gvk.Gpu_Arena,
    host_mem : gvk.Gpu_Arena,
    uniforms_arena : gvk.Gpu_Arena,
    descriptors_arena : gvk.Gpu_Arena,

    descriptors_raw : gvk.Gpu_Slice, // initialized to INITIAL_VERTEX_BYTE_COUNT
    index_data_raw  : gvk.Gpu_Slice, // initialized to INITIAL_INDEX_BYTE_COUNT

    // subsections of `descriptors_raw`, initialized at INITIAL_DESCRIPTOR_BYTE_COUNT
    descriptor_slices : map[string]gvk.Gpu_Slice, 

    // offsets
    vertex_offset   : uintptr, // bytes
    index_offset    : uintptr, // bytes

    // writing semaphore
    prev_write_sem      : gvk.Semaphore,
    current_write_sem   : gvk.Semaphore,
    write_fence         : gvk.Fence
}

create_asset_handler :: proc() -> (handler : Asset_Handler, ok : bool = true) {
    family_types : QueueTypes = {.TRANSFER, .GRAPHICS, .COMPUTE}

    mem_cfg : gvk.Arena_Config
    mem_cfg.queue_families = family_types
    mem_cfg.block_size = INITIAL_VERTEX_BYTE_COUNT
    mem_cfg.type = .DEVICE

    handler.arena = gvk.create_gpu_arena(Core_Context.backend, mem_cfg) or_return

    handler.gpu_queue_fam = gvk.find_queue_family_by_type(Core_Context.backend, family_types) or_return
    handler.commands = gvk.create_command_set(Core_Context.backend, 1, handler.gpu_queue_fam^) or_return

    handler.descriptors_raw = gvk.gpu_allocate(&handler.descriptors_arena, INITIAL_VERTEX_BYTE_COUNT) or_return
    handler.index_data_raw = gvk.gpu_allocate(&handler.arena, INITIAL_INDEX_BYTE_COUNT) or_return

    mem_cfg.type = .HOST
    mem_cfg.block_size = SCRATCHPAD_SIZE

    handler.host_mem = gvk.create_gpu_arena(Core_Context.backend, mem_cfg) or_return

    handler.uniforms_arena = gvk.create_gpu_arena(Core_Context.backend, mem_cfg) or_return

    handler.write_fence = gvk.init_fence(Core_Context.backend)

    mem_cfg.usage_types = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SAMPLER_DESCRIPTOR_BUFFER_EXT}
    handler.descriptors_arena = gvk.create_gpu_arena(Core_Context.backend, mem_cfg) or_return

    return
}

_cycle_semaphores :: proc(handler : ^Asset_Handler) {
    // delete the old last semaphore
    if handler.prev_write_sem != 0 {
        gvk.destroy_semaphore(Core_Context.backend, handler.prev_write_sem)
    }

    // cycle to next semaphores
    handler.prev_write_sem = handler.current_write_sem
    handler.current_write_sem = gvk.init_semaphore(Core_Context.backend)
}

load_model :: proc(handler : ^Asset_Handler, filepath : string) -> (handle : Model_Handle) {
    handle = Model_Handle(len(handler.models))

    model_data := core.load_models_from_file(filepath)

    _wait_for_fence(Core_Context.backend, &handler.write_fence)
    _reset_fence(Core_Context.backend, &handler.write_fence)

    // clear out the scratchpad
    gvk.gpu_free_all(&handler.host_mem)

    _cycle_semaphores(handler)

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
            v_end := v_start + uintptr(chunk.vertex_count * 4 * size_of(f32)) // descriptor data is padded to [4]f32
            v_size := v_end - v_start

            i_start := handler.index_offset
            i_end := i_start + uintptr(chunk.index_count * size_of(u16))
            i_size := i_end - i_start

            log.info("Copying", chunk.vertex_count, "vertices into GPU memory at vertex offset", chunk.vertex_offset)
            log.info("Copying", chunk.index_count, "indicies into GPU memory at offset", chunk.index_offset)

            // copy indices to scratchpad
            index_slice_src, ok := gvk.gpu_allocate(&handler.host_mem, int(i_size))
            index_slice_dst := gvk.slice(handler.index_data_raw, int(i_start), int(i_size))

            curr_ptr := uintptr(handler.host_mem.current_block.host_memory)
            init_ptr := curr_ptr // we can then just perform a copy from init_ptr to curr_ptr
            //TODO)) This bypasses the actual use of our arena, so it can't grow dynamically - there needs to be a utility to write data to the host-side of a coherent arena
            mem.copy(rawptr(curr_ptr), raw_data(prim.indices), int(i_size))
            curr_ptr += i_size

            gvk.gpu_copy(buf, index_slice_dst, index_slice_src)


            for name, data in prim.descriptor_data {
                // copy descriptor data to scratchpad
                if !(name in handler.descriptor_slices) {
                    handler.descriptor_slices[name] = gvk.slice(
                            handler.descriptors_raw,
                            INITIAL_DESCRIPTOR_BYTE_COUNT * len(handler.descriptor_slices),
                            INITIAL_DESCRIPTOR_BYTE_COUNT)

                }

                descriptor_slice := handler.descriptor_slices[name]

                subslice := gvk.slice(descriptor_slice, int(v_start), int(v_size))

                mem.copy(rawptr(curr_ptr), raw_data(data), int(v_size))
                vertex_slice, vok := gvk.gpu_allocate(&handler.host_mem, int(v_size))

                gvk.gpu_copy(buf, subslice, vertex_slice)

                curr_ptr += v_size
            }
            
            handler.index_offset += i_size
            handler.vertex_offset += v_size

            append(&chunks, chunk)
        }

        new_model.chunks = chunks[:]
        append(&handler.models, new_model)
    }

    gvk.end_command_buffer(buf)

    gvk.submit_command_buffer(Core_Context.backend, buf, handler.gpu_queue_fam^, handler.prev_write_sem, handler.current_write_sem, handler.write_fence)

    return
}

load_shader :: proc(handler : ^Asset_Handler, config : ^gvk.Shader_Chain_Config) -> (handle : Shader_Handle, ok : bool = true) {
    chain := gvk.create_shader(Core_Context.backend, config, &handler.descriptors_arena) or_return

    handle = Shader_Handle(len(handler.shaders))
    append(&handler.shaders, Shader_Asset{chain})

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

    gvk.gpu_free_all(&handler.uniforms_arena)
    gvk.gpu_free_all(&handler.host_mem)
    gvk.gpu_free_all(&handler.arena)

    gvk.destroy_command_set(Core_Context.backend, &handler.commands)
}
