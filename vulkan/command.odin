package vulkan

import vk "vendor:vulkan"

Command_Set :: struct {
    pool : vk.CommandPool,
    buffers : [dynamic]vk.CommandBuffer
}

create_command_set :: proc(ctx: ^Context, initial_buffer_count: int) -> (set: Command_Set, ok: bool = true) {
    return
}

destroy_command_set :: proc(ctx: ^Context, set: ^Command_Set) {
}
