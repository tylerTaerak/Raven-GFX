package game_vulkan

import vk "vendor:vulkan"
import "../core"
import "core:mem"
import gmem "../../gpu_mem" // TODO)) Import something normal plz

Descriptor :: struct {
    buffer : gmem.Bytes(.DESCRIPTORS),
    layout : vk.DescriptorSetLayout,
    binding : u32
}

Descriptor_Data :: struct {
    type : core.Descriptor_Type,
    memory : gmem.Bytes(.DESCRIPTORS)
}

Descriptor_Set :: struct {
    buffer : gmem.Bytes(.DESCRIPTORS),
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

create_descriptor_sets :: proc(ctx : ^Context,
    set_count : int,
    cfg : []core.Descriptor_Type,
    memory : ^gmem.Memory_Block(.DESCRIPTORS)) -> (desc_sets : []Descriptor_Set, ok : bool = true) {

    desc_sets = make([]Descriptor_Set, set_count)

    for s_idx in 0..<set_count {
        set : ^Descriptor_Set = &desc_sets[s_idx]
        set.bindings = make([]Descriptor_Data, len(cfg))

        set.layout = create_descriptor_layout(ctx, cfg)

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
        err : gmem.Error
        set.buffer, err = gmem.galloc(memory, required_size, desc_buf_props.descriptorBufferOffsetAlignment)
        set.bindings = make([]Descriptor_Data, len(cfg))

        for binding_idx in 0..<len(cfg) {
            required_offset : vk.DeviceSize
            vk.GetDescriptorSetLayoutBindingOffsetEXT(ctx.device, set.layout, u32(binding_idx), &required_offset)

            size : int
            switch cfg[binding_idx] {
                case .UNIFORM:
                    size = desc_buf_props.uniformBufferDescriptorSize
                case .IMAGE_SAMPLER:
                    size = desc_buf_props.combinedImageSamplerDescriptorSize
            }

            binding_mem := gmem.gslice(set.buffer, int(required_offset), size)

            data : Descriptor_Data
            data.type = cfg[binding_idx]
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
        gmem.host_pointer(descriptors[set_index].bindings[binding_index].memory))
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
        gmem.host_pointer(descriptors[set_index].bindings[binding_index].memory)
    )
}

bind_descriptor_sets :: proc(ctx : ^Context, cmd_buf : vk.CommandBuffer, desc_sets : []Descriptor_Set, layout : vk.PipelineLayout, ) {
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

    binding_info : vk.DescriptorBufferBindingInfoEXT
    binding_info.sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT
    binding_info.usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SAMPLER_DESCRIPTOR_BUFFER_EXT}

    // TODO)) Just supporting one memory block for descriptors right now - later I can add support back for passing multiple buffers here
    for i in 0..<len(desc_sets) {
        binding_info.address = gmem.device_pointer({ctx.device, ctx.phys_dev, {}}, desc_sets[i].buffer.block^)
        append(&buffer_indices, 0)
        append(&buffer_offsets, vk.DeviceSize(desc_sets[i].buffer.offset))
    }

    vk.CmdBindDescriptorBuffersEXT(cmd_buf, 1, &binding_info)
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
