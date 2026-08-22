package game_vulkan

import vk "vendor:vulkan"

import "core:log"
import "core:strings"
import vmem "core:mem/virtual"

Device :: struct {
	core 			: vk.Device,
	physical 		: vk.PhysicalDevice,
	queues 			: []QueueFamily,
	instance 		: Instance,
	device_memory 	: Device_Allocation(.DEVICE),
	staging_memory 	: Device_Allocation(.HOST)
}

create_device :: proc(instance : Instance, types : QueueTypes, dev_extensions : []string) -> (device : Device, ok : bool = true) {
	device.instance = instance
	device.physical = pick_physical_device(instance.core, dev_extensions) or_return
	device.queues = populate_queue_family_properties(device.physical) or_return
	device.core = create_logical_device(device.physical, device.queues, types, dev_extensions) or_return

	return
}

destroy_device :: proc(device : Device) {
	delete(device.queues)
	vk.DestroyDevice(device.core, {})
}

_validate_device :: proc(device : vk.PhysicalDevice, extension_names : []string) -> bool {
    ext_count : u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)

    extensions := make([]vk.ExtensionProperties, ext_count)
    vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, &extensions[0])

	name_arena : vmem.Arena
	err := vmem.arena_init_growing(&name_arena)
	defer vmem.arena_destroy(&name_arena)

	if err != .None {
		return false
	}

	name_alloc := vmem.arena_allocator(&name_arena)

    outer: for name in extension_names {
        for &ext in extensions {
			ext_string := strings.clone_from_bytes(ext.extensionName[:], name_alloc)
			ext_string = strings.trim_right_null(ext_string)
			ext_string = strings.trim_left_null(ext_string)

            if name == ext_string {
                continue outer
            }
        }

		log.error("Unable to find extension:", name)
        // if the loop makes it to this point, the device didn't find an extension
        return false
    }

    return true
}

pick_physical_device :: proc(instance : vk.Instance, vulkan_extensions: []string) -> (dev : vk.PhysicalDevice, ok : bool) {
    device_count : u32
    vk.EnumeratePhysicalDevices(instance, &device_count, nil)

    devices := make([]vk.PhysicalDevice, device_count)
    vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0])

    if device_count == 0 {
        log.error("No GPUs with Vulkan support available!")
        ok = false
    }

    for d in devices {
        if _validate_device(d, vulkan_extensions) {
            props : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(d, &props)
            log.info("Selecting device", string(props.deviceName[:]), "for rendering")
            dev = d
			ok = true
            break
        }
    }

	if !ok {
		log.warn("Unable to find a suitable graphics device")
	}

    return
}

create_logical_device :: proc(physical : vk.PhysicalDevice, queues : []QueueFamily, types : QueueTypes, device_extensions : []string) -> (device : vk.Device, ok : bool) {
    ok = true

    // assume if graphics is in `types` that we want present support for it
    all_queues : [dynamic]QueueFamily
    defer delete(all_queues)

    for type in types {
		fam_idx : int
		// present support will have to be queried later
		fam_idx, ok = find_queue_family_by_type(queues, {type})

        if !ok {
            log.error("Unable to find queue families for graphics device for type", type)
            continue
        }

        append(&all_queues, queues[fam_idx])
    }

    real_queues : [dynamic]QueueFamily
    defer delete(real_queues)

    outer: for q in queues {
        for rq in real_queues {
            if q.family_idx == rq.family_idx do continue outer
        }

        append(&real_queues, q)
    }


    q_create_infos : = make([]vk.DeviceQueueCreateInfo, len(real_queues))

    q_priorities : f32 = 1.0
    for q, i in real_queues {
        q_create_info : vk.DeviceQueueCreateInfo
        q_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
        q_create_info.queueFamilyIndex = q.family_idx
        q_create_info.queueCount = 1 // we only want to create one queue per type
        q_create_info.pQueuePriorities = &q_priorities

        q_create_infos[i] = q_create_info
    }

    required_extensions_cstr := make([]cstring, len(device_extensions))
    defer delete(required_extensions_cstr)

	cstring_arena : vmem.Arena
	err := vmem.arena_init_growing(&cstring_arena)
	defer vmem.arena_destroy(&cstring_arena)

	if err != .None {
		ok = false
		return
	}

	cstring_alloc := vmem.arena_allocator(&cstring_arena)


    for ext, i in device_extensions {
        required_extensions_cstr[i] = strings.clone_to_cstring(ext, cstring_alloc)
    }

	untyped_ptrs_feature : vk.PhysicalDeviceShaderUntypedPointersFeaturesKHR
	untyped_ptrs_feature.sType = .PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR
	untyped_ptrs_feature.shaderUntypedPointers = true

    desc_buffers_feature : vk.PhysicalDeviceDescriptorBufferFeaturesEXT
    desc_buffers_feature.sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT
    desc_buffers_feature.descriptorBuffer = true
	desc_buffers_feature.pNext = &untyped_ptrs_feature

    mesh_shaders_feature : vk.PhysicalDeviceMeshShaderFeaturesEXT
    mesh_shaders_feature.sType = .PHYSICAL_DEVICE_MESH_SHADER_FEATURES_EXT
    mesh_shaders_feature.meshShader = true
    mesh_shaders_feature.pNext = &desc_buffers_feature
    
    depth_clip_feature : vk.PhysicalDeviceDepthClipEnableFeaturesEXT
    depth_clip_feature.sType = .PHYSICAL_DEVICE_DEPTH_CLIP_ENABLE_FEATURES_EXT
    depth_clip_feature.depthClipEnable = true
    depth_clip_feature.pNext = &mesh_shaders_feature

    shobject_feature : vk.PhysicalDeviceShaderObjectFeaturesEXT
    shobject_feature.sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT
    shobject_feature.shaderObject = true
    shobject_feature.pNext = &depth_clip_feature

    ext_state_3_feature : vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT
    ext_state_3_feature.sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT
    ext_state_3_feature.extendedDynamicState3ColorBlendEnable = true
    ext_state_3_feature.extendedDynamicState3DepthClampEnable = true
    ext_state_3_feature.extendedDynamicState3PolygonMode = true
    ext_state_3_feature.extendedDynamicState3ColorBlendEquation = true
    ext_state_3_feature.extendedDynamicState3LogicOpEnable = true
    ext_state_3_feature.extendedDynamicState3ColorWriteMask = true
    ext_state_3_feature.extendedDynamicState3DepthClipEnable = true;
    ext_state_3_feature.pNext = &shobject_feature

    ext_state_2_feature : vk.PhysicalDeviceExtendedDynamicState2FeaturesEXT
    ext_state_2_feature.sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT
    ext_state_2_feature.extendedDynamicState2 = true
    ext_state_2_feature.extendedDynamicState2LogicOp = true
    ext_state_2_feature.pNext = &ext_state_3_feature

    extended_dynamic_feature : vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT
    extended_dynamic_feature.sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT
    extended_dynamic_feature.extendedDynamicState = true
    extended_dynamic_feature.pNext = &ext_state_2_feature

    desc_indexing_feature : vk.PhysicalDeviceDescriptorIndexingFeaturesEXT
    desc_indexing_feature.sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT
    desc_indexing_feature.descriptorBindingUniformBufferUpdateAfterBind = true
    desc_indexing_feature.descriptorBindingStorageBufferUpdateAfterBind = true
    desc_indexing_feature.pNext = &extended_dynamic_feature

    // chain the features we need into the device creation
    dynamic_rendering_feature : vk.PhysicalDeviceDynamicRenderingFeatures
    dynamic_rendering_feature.sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
    dynamic_rendering_feature.dynamicRendering = true
    dynamic_rendering_feature.pNext = &desc_indexing_feature

    sync2_feature : vk.PhysicalDeviceSynchronization2Features
    sync2_feature.sType = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
    sync2_feature.synchronization2 = true
    sync2_feature.pNext = &dynamic_rendering_feature

    timeline_sems_feature : vk.PhysicalDeviceTimelineSemaphoreFeatures
    timeline_sems_feature.sType = .PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES
    timeline_sems_feature.pNext = &sync2_feature
    timeline_sems_feature.timelineSemaphore = true

    nested_buffers_feature : vk.PhysicalDeviceNestedCommandBufferFeaturesEXT
    nested_buffers_feature.sType = .PHYSICAL_DEVICE_NESTED_COMMAND_BUFFER_FEATURES_EXT
    nested_buffers_feature.pNext = &timeline_sems_feature
    nested_buffers_feature.nestedCommandBuffer = true
    nested_buffers_feature.nestedCommandBufferSimultaneousUse = true
    nested_buffers_feature.nestedCommandBufferRendering = true

    features2 : vk.PhysicalDeviceFeatures2
    features2.sType = .PHYSICAL_DEVICE_FEATURES_2
    features2.pNext = &nested_buffers_feature
    features2.features.multiDrawIndirect = true

    create_info : vk.DeviceCreateInfo
    create_info.sType = .DEVICE_CREATE_INFO
    create_info.pNext = &features2

    create_info.pQueueCreateInfos = &q_create_infos[0]
    create_info.queueCreateInfoCount = u32(len(q_create_infos))
    create_info.enabledExtensionCount = u32(len(required_extensions_cstr))
    create_info.ppEnabledExtensionNames = &required_extensions_cstr[0]

    res := vk.CreateDevice(physical, &create_info, {}, &device)
    if res != .SUCCESS {
        log.error("Error creating logical device", res)
        ok = false
    }

	log.debug("Loading procedure addresses for device")

    vk.load_proc_addresses_device(device)

    return
}
