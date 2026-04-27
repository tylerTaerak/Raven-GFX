package game_vulkan

import "core:log"
import vk "vendor:vulkan"
import "../core"


// Each Descriptor_Collection has `set_count` descriptor sets and layouts,
// each of which have `binding_count` elements/bindings in them
Descriptor_Collection :: struct {
    set_count : int,
    binding_count : int,
    pool : vk.DescriptorPool,
    layout : []vk.DescriptorSetLayout,
    set : []vk.DescriptorSet,
    type_count : [core.Descriptor_Type]u32
}

Descriptor_Config :: struct {
    // how many sets you need, e.g. 1 for permanent, FRAMES_IN_FLIGHT for per-frame, X for per-batch, etc.
    count : u32,

    // how many bindings you need, based on usage type
    type_count : [core.Descriptor_Type]u32
}

create_descriptor_set :: proc(ctx: ^Context, cfg: Descriptor_Config) -> (collection: Descriptor_Collection, ok: bool=true) {
    pool_sizes : [core.Descriptor_Type]vk.DescriptorPoolSize

    pool_sizes[.STORAGE] = {
        type = .STORAGE_BUFFER,
        descriptorCount = cfg.type_count[.STORAGE] * cfg.count
    }

    pool_sizes[.UNIFORM] = {
        type = .UNIFORM_BUFFER,
        descriptorCount = cfg.type_count[.UNIFORM] * cfg.count
    }

    pool_info : vk.DescriptorPoolCreateInfo
    pool_info.sType = .DESCRIPTOR_POOL_CREATE_INFO
    pool_info.maxSets = cfg.count
    pool_info.poolSizeCount = u32(len(pool_sizes))
    pool_info.pPoolSizes = &pool_sizes[.STORAGE]
    pool_info.flags = {.FREE_DESCRIPTOR_SET, .UPDATE_AFTER_BIND}

    res := vk.CreateDescriptorPool(ctx.device, &pool_info, {}, &collection.pool)

    if res != .SUCCESS {
        ok = false
        return
    }

    collection.set_count = int(cfg.count)

    collection.layout = make([]vk.DescriptorSetLayout, cfg.count)
    collection.set = make([]vk.DescriptorSet, cfg.count)

    collection.type_count = cfg.type_count

    bindings : [dynamic]vk.DescriptorSetLayoutBinding
    defer delete(bindings)

    index : u32 = 0
    for type in core.Descriptor_Type {
        for _ in 0..<cfg.type_count[type] {
            binding : vk.DescriptorSetLayoutBinding
            binding.descriptorType = _to_vk_descriptor_type(type)
            binding.binding = index
            binding.descriptorCount = 1
            binding.stageFlags = {.VERTEX}

            append(&bindings, binding)

            index += 1
        }
    }

    collection.binding_count = int(index)

    layout_info : vk.DescriptorSetLayoutCreateInfo
    layout_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layout_info.bindingCount = u32(len(bindings))
    layout_info.pBindings = &bindings[0]

    for i in 0..<cfg.count {
        res = vk.CreateDescriptorSetLayout(ctx.device, &layout_info, {}, &collection.layout[i])

        if res != .SUCCESS {
            ok = false
            return
        }
    }

    set_info : vk.DescriptorSetAllocateInfo
    set_info.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
    set_info.descriptorPool = collection.pool
    set_info.descriptorSetCount = cfg.count
    set_info.pSetLayouts = &collection.layout[0]

    res = vk.AllocateDescriptorSets(ctx.device, &set_info, &collection.set[0])

    if res != .SUCCESS {
        ok = false
    }

    return
}

update_descriptor_set :: proc(ctx: ^Context, set: ^Descriptor_Collection, set_index, binding : u32, buffer : $T/Buffer($E)) -> bool {
    assert(set_index < u32(set.set_count) && binding < u32(set.binding_count))

    update : vk.WriteDescriptorSet
    buffer_info : vk.DescriptorBufferInfo

    buffer_info.buffer = buffer.buf
    buffer_info.offset = 0
    buffer_info.range = buffer.size

    update.sType = .WRITE_DESCRIPTOR_SET
    update.dstSet = set.set[set_index]
    update.dstBinding = binding
    update.dstArrayElement = 0
    update.descriptorCount = 1
    update.pBufferInfo = &buffer_info

    buffer_type : core.Descriptor_Type
    for type in core.Descriptor_Type {
        if set.type_count[type] < binding do continue

        buffer_type = type
        break
    }

    update.descriptorType = _to_vk_descriptor_type(buffer_type)

    vk.UpdateDescriptorSets(ctx.device, 1, &update, 0, nil)

    return true
}

update_descriptor_sets :: proc(ctx: ^Context, set: ^Descriptor_Collection, buffers: [][]$T/Buffer($E)) -> bool {
    assert(len(buffers) == set.set_count)

    updates : [dynamic]vk.WriteDescriptorSet
    defer delete(updates)

    buffer_infos : [dynamic]vk.DescriptorBufferInfo
    defer delete(buffer_infos)

    for i in 0..<set.set_count {
        buffer_set := buffers[i]

        assert (len(buffer_set) == set.binding_count)

        for j in 0..<set.binding_count {
            buffer_info : vk.DescriptorBufferInfo
            buffer_info.buffer = buffers[i][j].buf
            buffer_info.offset = 0
            buffer_info.range = buffers[i][j].size

            append(&buffer_infos, buffer_info)

            write_info : vk.WriteDescriptorSet
            write_info.sType = .WRITE_DESCRIPTOR_SET
            write_info.dstSet = set.set[i]
            write_info.dstBinding = u32(j)
            write_info.dstArrayElement = 0
            write_info.descriptorCount = 1
            write_info.pBufferInfo = &buffer_infos[(i * set.binding_count) + j]

            buffer_type : core.Descriptor_Type
            for type in core.Descriptor_Type {
                if set.type_count[type] < j do continue

                buffer_type = type
                break
            }
            write_info.descriptorType = _to_vk_descriptor_type(buffer_type)

            append(&updates, write_info)
        }
    }

    vk.UpdateDescriptorSets(ctx.device, u32(len(updates)), &updates[0], 0, {})

    return true
}

// TODO)) this command can probably just wrap descriptor sets and pipelines together
// the way I have things laid out right now, descriptors and pipelines are very intertwined.
// Should they just be one unified abstraction?
bind_descriptors :: proc(cmd_buf : vk.CommandBuffer, pipeline : Pipeline, set: ^Descriptor_Collection, index: u32, offset: u32 = 0) {
    vk.CmdBindDescriptorSets(cmd_buf, .GRAPHICS, pipeline.layout, offset, 1, &set.set[index], 0, nil)
    vk.CmdBindPipeline(cmd_buf, .GRAPHICS, pipeline.data)
}

destroy_descriptor_set :: proc(ctx: ^Context, set: ^Descriptor_Collection) {
    vk.FreeDescriptorSets(ctx.device, set.pool, u32(set.set_count), &set.set[0])

    for i in 0..<set.set_count {
        vk.DestroyDescriptorSetLayout(ctx.device, set.layout[i], {})
    }

    vk.DestroyDescriptorPool(ctx.device, set.pool, {})
}
