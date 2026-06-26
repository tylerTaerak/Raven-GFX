package game_vulkan

import vk "vendor:vulkan"
import "../core"
import "core:mem"

Descriptor :: struct {
    buffer : Gpu_Slice,
    layout : vk.DescriptorSetLayout,
    binding : u32
}

Descriptor_Data :: struct {
    type : core.Descriptor_Type,
    memory : Gpu_Slice
}

Descriptor_Set :: struct {
    buffer : Gpu_Slice,
    bindings : []Descriptor_Data,
    layout   : vk.DescriptorSetLayout
}

Descriptor_Layout_Config :: [][]core.Descriptor_Type

create_descriptor_layout :: proc(ctx: ^Context, desc_configs : []core.Descriptor_Type) -> vk.DescriptorSetLayout {
    bindings := make([]vk.DescriptorSetLayoutBinding, len(desc_configs))
    defer delete(bindings)

    for cfg, i in desc_configs {
        binding := &bindings[i]
        binding.descriptorType = _to_vk_descriptor_type(cfg)
        binding.binding = u32(i)
        binding.descriptorCount = 1
        binding.stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE, .MESH_EXT, .GEOMETRY}
    }

    layout_info : vk.DescriptorSetLayoutCreateInfo
    layout_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layout_info.bindingCount = u32(len(bindings))
    layout_info.pBindings = &bindings[0]
    layout_info.flags = {.DESCRIPTOR_BUFFER_EXT}

    layout : vk.DescriptorSetLayout
    vk.CreateDescriptorSetLayout(ctx.device, &layout_info, {}, &layout)

    return layout
}

create_descriptor_sets :: proc(ctx : ^Context, cfg : Descriptor_Layout_Config, arena : ^Gpu_Arena) -> (desc_sets : []Descriptor_Set, ok : bool = true) {
    assert(arena.type == .DESCRIPTORS)

    desc_sets = make([]Descriptor_Set, len(cfg))

    for s_idx in 0..<len(cfg) {
        set : ^Descriptor_Set = &desc_sets[s_idx]
        set.bindings = make([]Descriptor_Data, len(cfg[s_idx]))

        set.layout = create_descriptor_layout(ctx, cfg[s_idx])

        desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
        desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

        dev_props : vk.PhysicalDeviceProperties2KHR
        dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
        dev_props.pNext = &desc_buf_props

        vk.GetPhysicalDeviceProperties2KHR(ctx.phys_dev, &dev_props)

        Descriptor_Offsets :: struct {
            offset  : vk.DeviceSize,
            size    : vk.DeviceSize
        }

        required_size : vk.DeviceSize
        vk.GetDescriptorSetLayoutSizeEXT(ctx.device, set.layout, &required_size)

        // align size to desc_buf_props.descriptorBufferOffsetAlignment
        set.buffer = gpu_allocate(arena, int(required_size), int(desc_buf_props.descriptorBufferOffsetAlignment)) or_return
        set.bindings = make([]Descriptor_Data, len(cfg[s_idx]))

        for binding_idx in 0..<len(cfg[s_idx]) {
            required_offset : vk.DeviceSize
            vk.GetDescriptorSetLayoutBindingOffsetEXT(ctx.device, set.layout, u32(binding_idx), &required_offset)

            size : int
            /// TODO)) I just need to remove the storage descriptor option from core
            switch cfg[s_idx][binding_idx] {
                case .UNIFORM:
                    size = desc_buf_props.uniformBufferDescriptorSize
                case .IMAGE_SAMPLER:
                    size = desc_buf_props.combinedImageSamplerDescriptorSize
            }

            binding_mem := slice(set.buffer, int(required_offset), size)

            data : Descriptor_Data
            data.type = cfg[s_idx][binding_idx]
            data.memory = binding_mem

            set.bindings[binding_idx] = data
        }
    }


    return
}

write_descriptor_buffer :: proc(ctx : ^Context, descriptors : []Descriptor_Set, set_index : int, binding_index : int, write_data : Gpu_Slice, arena : ^Gpu_Arena) {
    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(ctx.phys_dev, &dev_props)

    addr_info : vk.DescriptorAddressInfoEXT
    addr_info.sType = .DESCRIPTOR_ADDRESS_INFO_EXT
    addr_info.address = get_device_address(write_data)
    addr_info.range = vk.DeviceSize(write_data.size)

    get_info : vk.DescriptorGetInfoEXT
    get_info.sType = .DESCRIPTOR_GET_INFO_EXT
    get_info.type = _to_vk_descriptor_type(descriptors[set_index].bindings[binding_index].type)
    get_info.data.pUniformBuffer = &addr_info

    vk.GetDescriptorEXT(ctx.device, &get_info,
        desc_buf_props.uniformBufferDescriptorSize,
        get_host_pointer(descriptors[set_index].bindings[binding_index].memory))
}

write_descriptor_image :: proc(ctx : ^Context, descriptors : []Descriptor_Set, set_index : int, binding_index : int, sampler : vk.Sampler, image : Render_Image, arena: ^Gpu_Arena) {
    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(ctx.phys_dev, &dev_props)

    image_info : vk.DescriptorImageInfo
    image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
    image_info.imageView = image.view
    image_info.sampler = sampler

    get_info : vk.DescriptorGetInfoEXT
    get_info.sType = .DESCRIPTOR_GET_INFO_EXT
    get_info.type = .COMBINED_IMAGE_SAMPLER
    get_info.data.pCombinedImageSampler = &image_info

    vk.GetDescriptorEXT(ctx.device, &get_info,
        desc_buf_props.combinedImageSamplerDescriptorSize,
        get_host_pointer(descriptors[set_index].bindings[binding_index].memory)
    )
}

bind_descriptor_sets :: proc(ctx : ^Context, cmd_buf : vk.CommandBuffer, desc_sets : []Descriptor_Set, layout : vk.PipelineLayout) {
    Info_Index_Pair :: struct {
        info : vk.DescriptorBufferBindingInfoEXT,
        index : int
    }
    buffer_bindings : map[Gpu_Block_Handle]Info_Index_Pair
    buffer_indices : [dynamic]u32
    buffer_offsets : [dynamic]vk.DeviceSize

    defer delete(buffer_offsets)
    defer delete(buffer_indices)
    defer delete_map(buffer_bindings)

    current_index := 0
    for i in 0..<len(desc_sets) {
        if desc_sets[i].buffer.block in buffer_bindings {
            append(&buffer_indices, u32(buffer_bindings[desc_sets[i].buffer.block].index))
            append(&buffer_offsets, vk.DeviceSize(desc_sets[i].buffer.offset))
            continue
        }

        binding_info : vk.DescriptorBufferBindingInfoEXT
        binding_info.sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT
        binding_info.address = get_buffer_device_address(desc_sets[i].buffer)
        binding_info.usage = {.SAMPLER_DESCRIPTOR_BUFFER_EXT, .RESOURCE_DESCRIPTOR_BUFFER_EXT}
        buffer_bindings[desc_sets[i].buffer.block] = {binding_info, current_index}

        current_index += 1
    }

    buffer_infos := make([]vk.DescriptorBufferBindingInfoEXT, len(buffer_bindings))
    for _, v in buffer_bindings {
        buffer_infos[v.index] = v.info
    }

    vk.CmdBindDescriptorBuffersEXT(cmd_buf, u32(len(buffer_infos)), &buffer_infos[0])
    vk.CmdSetDescriptorBufferOffsetsEXT(
        cmd_buf,
        .GRAPHICS,
        layout,
        0,
        u32(len(buffer_indices)),
        &buffer_indices[0],
        &buffer_offsets[0]
    )
}

create_pipeline_layout :: proc(ctx : ^Context, descriptor_sets : []Descriptor_Set) -> vk.PipelineLayout {
    create_info : vk.PipelineLayoutCreateInfo
    create_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
    create_info.setLayoutCount = u32(len(descriptor_sets))

    layouts := make([]vk.DescriptorSetLayout, len(descriptor_sets))
    defer delete(layouts)

    for i in 0..<len(descriptor_sets) {
        layouts[i] = descriptor_sets[i].layout
    }

    create_info.pSetLayouts = &layouts[0]

    pipeline_layout : vk.PipelineLayout
    vk.CreatePipelineLayout(ctx.device, &create_info, {}, &pipeline_layout)

    return pipeline_layout
}

destroy_pipeline_layout :: proc(ctx : ^Context, layout : vk.PipelineLayout) {
    vk.DestroyPipelineLayout(ctx.device, layout, {})
}

destroy_descriptor_sets :: proc(ctx : ^Context, sets : []Descriptor_Set) {
    for i in 0..<len(sets) {
        delete(sets[i].bindings)
        vk.DestroyDescriptorSetLayout(ctx.device, sets[i].layout, {})
    }

    delete(sets)
}
