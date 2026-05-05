package game_vulkan

import "core:sync"
import vk "vendor:vulkan"

Gpu_Arena :: struct {
    current_block : ^Gpu_Memory_Block,
    block_size : int,
    mutex : sync.Mutex
}

Gpu_Memory_Block :: struct {
    prev_block : ^Gpu_Memory_Block,
    buffer : vk.Buffer,
    memory : vk.DeviceMemory,
    current_offset : int,
    size : int,
    block_index : int
}

Gpu_Block_Handle :: distinct int

Gpu_Slice :: struct {
    block : Gpu_Block_Handle,
    offset : int,
    size : int
}

/// reserves a slice of the GPU for the caller
gpu_allocate :: proc(arena : ^Gpu_Arena, size : int) -> Gpu_Slice {
    if arena.current_block == nil {
        sync.lock(&arena.mutex)
        defer sync.unlock(&arena.mutex)

        _allocate_new_block(arena)
    }

    if arena.current_block.current_offset + size >= arena.current_block.size {
        sync.lock(&arena.mutex)
        defer sync.unlock(&arena.mutex)

        _allocate_new_block(arena)

    }

    return {}
}

/// frees all memory from the GPU
gpu_free :: proc(arena : ^Gpu_Arena) {
}

_allocate_new_block :: proc(arena : ^Gpu_Arena) {
    gpu_block := new(Gpu_Memory_Block)

    gpu_block.prev_block = arena.current_block
    arena.current_block = gpu_block

    // now allocate the gpu resources
}
