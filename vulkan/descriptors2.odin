package game_vulkan

import vk "vendor:vulkan"
import "../core"

Descriptor :: struct {
    buffer : Gpu_Slice,
    layout : vk.DescriptorSetLayout,
    binding : u32
}

Descriptor_Set :: struct {
    buffer : Gpu_Slice, // master memory slice
    descriptors : [][]Gpu_Slice, // pointers to each individual descriptor, the first index is set index, the second is binding index
}

create_descriptor_layout :: proc(ctx: ^Context, desc_configs : []$T/Descriptor_Set_Binding($N)) -> vk.DescriptorSetLayout {
    bindings := make([]vk.DescriptorSetLayoutBinding, len(desc_configs))

    for cfg, i in desc_configs {
        binding := &bindings[i]
        binding.descriptorType = _to_vk_descriptor_type(cfg.type)
        binding.binding = cfg.binding
        binding.descriptorCount = 1
        binding.stageFlags = {.VERTEX, .FRAGMENT, .COMPUTE, .MESH}
    }

    layout_info : vk.DescriptorSetLayoutCreateInfo
    layout_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
    layout_info.bindingCount = u32(len(bindings))
    layout_info.pBindings = &bindings[0]

    layout : vk.DescriptorSetLayout
    vk.CreateDescriptorSetLayout(ctx.device, &layout_info, {}, layout)

    return layout
}

create_descriptor_2 :: proc(ctx : ^Context, d_type : core.Descriptor_Type, layout : vk.DescriptorSetLayout, arena : ^Gpu_Arena) {
    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(ctx.phys_dev, &dev_props)

    required_size : vk.DeviceSize
    vk.GetDescriptorSetLayoutSizeEXT(ctx.device, layout, &required_size)

    required_offset : vk.DeviceSize
    vk.GetDescriptorSetLayoutBindingOffsetEXT(ctx.device, layout, 0, &required_offset)
}
