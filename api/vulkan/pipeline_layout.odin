package game_vulkan

import vk "vendor:vulkan"

// now this struct is kind of "invisible" to the outside
// it's owned by Shader objects, which create their own using
// multipointers to Descriptor Sets
Pipeline_Layout :: struct {
	vklayout 			: vk.PipelineLayout,
	descriptors	 		: []Descriptor_Layout
}

create_pipeline_layout :: proc(
	device : Device,
	layouts : []Descriptor_Layout) -> (layout : Pipeline_Layout, ok : bool = true) {

	layout.descriptors = layouts

	create_info : vk.PipelineLayoutCreateInfo
	create_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	create_info.setLayoutCount = u32(len(layouts))

	vklayouts : [dynamic]vk.DescriptorSetLayout
	defer delete(vklayouts)

	for i in 0..<len(layouts) {
		append(&vklayouts, layouts[i].vklayout)
	}

	res := vk.CreatePipelineLayout(device.core, &create_info, {}, &layout.vklayout)

	ok = res == .SUCCESS

	return
}

destroy_pipeline_layout :: proc(
	device : Device,
	layout : Pipeline_Layout) {
	vk.DestroyPipelineLayout(device.core, layout.vklayout, {})
}
