package game_vulkan

import vk "vendor:vulkan"
import "shared:raven-gfx/core"

Descriptor_Param :: struct {
	name : string,
	type : core.Descriptor_Type,
	stage : core.Shader_Stage
}

Descriptor_Layout :: struct {
	params : []Descriptor_Param,
	vklayout : vk.DescriptorSetLayout
}

Descriptor :: struct {
    type : core.Descriptor_Type,
    memory : Allocation(.HOST)
}

Descriptor_Set :: struct {
    buffer 		: Buffer(.HOST),
    bindings 	: []Descriptor,
    layout   	: Descriptor_Layout
}

_to_vk_shader_stage :: proc(stage : core.Shader_Stage) -> vk.ShaderStageFlags {
	switch stage {
		case .VERTEX:
			return {.VERTEX}
		case .GEOMETRY:
			return {.GEOMETRY}
		case .COMPUTE:
			return {.COMPUTE}
		case .MESH:
			return {.MESH_EXT}
		case .FRAGMENT:
			return {.FRAGMENT}
	}

	return {}
}

create_descriptor_layout :: proc(
	device : Device,
	params : []Descriptor_Param) -> (layout : Descriptor_Layout, ok : bool = true) {
	bindings := make([]vk.DescriptorSetLayoutBinding, len(params))
	defer delete(bindings)

	for param, i in params {
		binding := &bindings[i]
		binding.descriptorType = _to_vk_descriptor_type(param.type)
		binding.binding = u32(i)
		binding.descriptorCount = 1
		binding.stageFlags = _to_vk_shader_stage(param.stage)
	}

	layout_info : vk.DescriptorSetLayoutCreateInfo
	layout_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
	layout_info.bindingCount = u32(len(bindings))
	layout_info.pBindings = &bindings[0]
	layout_info.flags = {.DESCRIPTOR_BUFFER_EXT}

	vk.CreateDescriptorSetLayout(device.core, &layout_info, {}, &layout.vklayout)

	return
}

create_descriptor_set :: proc(
	device : Device,
    layout : Descriptor_Layout) -> (desc_set : Descriptor_Set, ok : bool = true) {

	set : ^Descriptor_Set = &desc_set
	set.bindings = make([]Descriptor, len(layout.params))

	set.layout = layout

	desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
	desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

	dev_props : vk.PhysicalDeviceProperties2KHR
	dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
	dev_props.pNext = &desc_buf_props

	vk.GetPhysicalDeviceProperties2KHR(device.physical, &dev_props)

	Descriptor_Offsets :: struct {
		offset  : vk.DeviceSize,
		size    : vk.DeviceSize
	}

	required_size : vk.DeviceSize
	vk.GetDescriptorSetLayoutSizeEXT(device.core, set.layout.vklayout, &required_size)

	// align size to desc_buf_props.descriptorBufferOffsetAlignment
	set.buffer = create_buffer(
		device,
		int(required_size),
		.HOST,
		{
			.SAMPLER_DESCRIPTOR_BUFFER_EXT,
			.RESOURCE_DESCRIPTOR_BUFFER_EXT,
			.SHADER_DEVICE_ADDRESS_EXT
		},
		int(desc_buf_props.descriptorBufferOffsetAlignment)) or_return

	for binding_idx in 0..<len(set.layout.params) {
		required_offset : vk.DeviceSize
		vk.GetDescriptorSetLayoutBindingOffsetEXT(device.core, set.layout.vklayout, u32(binding_idx), &required_offset)

		size : int
		switch set.layout.params[binding_idx].type {
			case .BUFFER:
				size = desc_buf_props.storageBufferDescriptorSize
			case .UNIFORM:
				size = desc_buf_props.uniformBufferDescriptorSize
			case .IMAGE_SAMPLER:
				size = desc_buf_props.combinedImageSamplerDescriptorSize
		}

		// get a slice of the buffer
		binding_mem := memalloc(set.buffer.memory, u32(required_offset), u32(size)) or_return

		data : Descriptor
		data.type = set.layout.params[binding_idx].type
		data.memory = binding_mem

		set.bindings[binding_idx] = data
	}

    return
}

write_descriptor_buffer :: proc(device : Device,
	descriptor_set : Descriptor_Set,
	set_index : int,
	binding_index : int,
	write_data : $T/Buffer($L)) {

    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(device.core, &dev_props)

    addr_info : vk.DescriptorAddressInfoEXT
    addr_info.sType = .DESCRIPTOR_ADDRESS_INFO_EXT
    addr_info.address = get_buffer_address(device, write_data)
    addr_info.range = vk.DeviceSize(write_data.size)

    get_info : vk.DescriptorGetInfoEXT
    get_info.sType = .DESCRIPTOR_GET_INFO_EXT
    get_info.type = _to_vk_descriptor_type(descriptors[set_index].bindings[binding_index].type)
    get_info.data.pUniformBuffer = &addr_info

	host_ptr := rawptr(
		uintptr(descriptor_set.buffer.memory.host_ptr) +
		uintptr(descriptor_set.buffer.memory.raw.offset)
	)

    vk.GetDescriptorEXT(ctx.device, &get_info,
        desc_buf_props.uniformBufferDescriptorSize,
        host_ptr)
}

write_descriptor_image :: proc(
	device : Device,
	descriptor_set : Descriptor_Set,
	binding_index : int,
	sampler : vk.Sampler,
	image : Render_Image) {

    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(device.physical, &dev_props)

    image_info : vk.DescriptorImageInfo
    image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
    image_info.imageView = image.view
    image_info.sampler = sampler

    get_info : vk.DescriptorGetInfoEXT
    get_info.sType = .DESCRIPTOR_GET_INFO_EXT
    get_info.type = .COMBINED_IMAGE_SAMPLER
    get_info.data.pCombinedImageSampler = &image_info

	host_ptr := rawptr(
		uintptr(descriptor_set.buffer.memory.host_ptr) +
		uintptr(descriptor_set.buffer.memory.raw.offset)
	)

    vk.GetDescriptorEXT(device.core, &get_info,
        desc_buf_props.combinedImageSamplerDescriptorSize,
        host_ptr)
}

bind_descriptor_sets :: proc(
	device : Device,
	cmd_buf : vk.CommandBuffer,
	layout : Pipeline_Layout,
	descriptor_sets : []Descriptor_Set) -> (ok : bool = true) {

 	// we want to make sure the inputs given actually match the layout that's being worked
	// with
	if (len(descriptor_sets) != len(layout.descriptors)) {
		return false
	}

	for i in 0..<len(descriptor_sets) {
		if descriptor_sets[i].layout.vklayout != layout.descriptors[i].vklayout {
			return false
		}
	}

    buffer_indices : [dynamic]u32
    buffer_offsets : [dynamic]vk.DeviceSize
	bindings : [dynamic]vk.DescriptorBufferBindingInfoEXT

    defer delete(buffer_offsets)
    defer delete(buffer_indices)
	defer delete(bindings)

	for i in 0..<len(descriptor_sets) {
		binding : vk.DescriptorBufferBindingInfoEXT
		binding.sType = .DESCRIPTOR_BUFFER_BINDING_INFO_EXT
		binding.address = get_buffer_address(device, descriptor_sets[i].buffer)
		binding.usage = {.RESOURCE_DESCRIPTOR_BUFFER_EXT, .SAMPLER_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS}

		append(&buffer_indices, u32(i))
		append(&buffer_offsets, 0)
		append(&bindings, binding)
	}

    vk.CmdBindDescriptorBuffersEXT(cmd_buf, u32(len(bindings)), &bindings[0])
    vk.CmdSetDescriptorBufferOffsetsEXT(
        cmd_buf,
        .GRAPHICS,
        layout.vklayout,
        0,
        u32(len(buffer_indices)),
        &buffer_indices[0],
        &buffer_offsets[0]
    )

	return
}

destroy_descriptor_set :: proc(device : Device, set : ^Descriptor_Set) {
	delete(set.bindings)
	destroy_buffer(device, &set.buffer)
}

destroy_descriptor_layout :: proc(device : Device, layout : Descriptor_Layout) {
	vk.DestroyDescriptorSetLayout(device.core, layout.vklayout, {})
}
