package game_vulkan

import vk "vendor:vulkan"
import "shared:raven-gfx/core"

Descriptor_Param :: struct {
	name : string,
	type : core.Descriptor_Type,
	stage : core.Shader_Stage,
	element_count : Maybe(int)
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

		if count, has_count := param.element_count.?; has_count {
			binding.descriptorCount = u32(count)
		} else {
			binding.descriptorCount = 1
		}

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
			case .IMAGE:
				size = desc_buf_props.sampledImageDescriptorSize
			case .SAMPLER:
				size = desc_buf_props.samplerDescriptorSize
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

Descriptor_Write_Data :: union{
	Buffer(.DEVICE), // TODO)) Is there a better way to manage a generic like this?
	Render_Image,
	vk.Sampler
}

write_descriptor_data :: proc(
	device : Device,
	descriptor_set : Descriptor_Set,
	parameter_info : Descriptor_Param,
	write_data : Descriptor_Write_Data,
	target_index : int = 0) {

    desc_buf_props : vk.PhysicalDeviceDescriptorBufferPropertiesEXT
    desc_buf_props.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT

    dev_props : vk.PhysicalDeviceProperties2KHR
    dev_props.sType = .PHYSICAL_DEVICE_PROPERTIES_2_KHR
    dev_props.pNext = &desc_buf_props

    vk.GetPhysicalDeviceProperties2KHR(device.physical, &dev_props)

    get_info : vk.DescriptorGetInfoEXT
    get_info.sType = .DESCRIPTOR_GET_INFO_EXT
    get_info.type = .SAMPLER

	size : int
	addr_info : vk.DescriptorAddressInfoEXT
	image_info : vk.DescriptorImageInfo
	sampler : vk.Sampler

	switch v in write_data {
		case Buffer(.DEVICE):
			addr_info.sType = .DESCRIPTOR_ADDRESS_INFO_EXT
			addr_info.address = get_buffer_address(device, v)
			addr_info.range = vk.DeviceSize(v.size)

			if parameter_info.type == .UNIFORM {
				get_info.data.pUniformBuffer = &addr_info
				size = desc_buf_props.uniformBufferDescriptorSize
			} else {
				get_info.data.pStorageBuffer = &addr_info
				size = desc_buf_props.storageBufferDescriptorSize
			}

		case Render_Image:
			image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
			image_info.imageView = v.view

			size = desc_buf_props.sampledImageDescriptorSize
			get_info.data.pSampledImage = &image_info

		case vk.Sampler:
			sampler = v
			get_info.data.pSampler = &sampler
			size = desc_buf_props.samplerDescriptorSize
	}

	host_ptr := rawptr(
		uintptr(descriptor_set.buffer.memory.host_ptr) +
		uintptr(descriptor_set.buffer.memory.raw.offset)
	)

	if count, has_count := parameter_info.element_count.?; has_count {
		host_ptr = rawptr(
			uintptr(host_ptr) +
			uintptr(size * target_index)
		)
	}

    vk.GetDescriptorEXT(device.core, &get_info,
		size,
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
