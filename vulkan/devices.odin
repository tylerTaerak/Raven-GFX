package game_vulkan

import vk "vendor:vulkan"

import "core:log"
import "core:strings"

REQUIRED_DEVICE_EXTENSIONS : []string : {
    vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    vk.EXT_NESTED_COMMAND_BUFFER_EXTENSION_NAME,
    vk.KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME,
}

Device :: struct {
    physical        : vk.PhysicalDevice,
    logical         : vk.Device,
    queue_families  : []QueueFamily
}

_validate_device :: proc(device : vk.PhysicalDevice, extension_names : []string) -> bool {
    ext_count : u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)

    extensions := make([]vk.ExtensionProperties, ext_count)
    vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, &extensions[0])

    outer: for name in extension_names {
        for &ext in extensions {
            if name == strings.trim_right_null(string(ext.extensionName[:])) {
                continue outer
            }
        }

        // if the loop makes it to this point, the device didn't find an extension
        return false
    }

    return true
}

pick_physical_device :: proc(ctx : ^Context) -> (ok : bool) {
    ok = true

    device_count : u32
    vk.EnumeratePhysicalDevices(ctx.instance, &device_count, nil)

    devices := make([]vk.PhysicalDevice, device_count)
    vk.EnumeratePhysicalDevices(ctx.instance, &device_count, &devices[0])

    if device_count == 0 {
        log.error("No GPUs with Vulkan support available!")
        ok = false
    }

    ctx.device.physical = devices[0]
    for d in devices {
        if _validate_device(d, REQUIRED_DEVICE_EXTENSIONS) {
            props : vk.PhysicalDeviceProperties
            vk.GetPhysicalDeviceProperties(d, &props)
            log.info("Selecting device", string(props.deviceName[:]), "for rendering")
            ctx.device.physical = d
            break
        }
    }

    return
}

create_logical_device :: proc(ctx : ^Context, types : QueueTypes) -> (ok : bool) {
    ok = true

    // assume if graphics is in `types` that we want present support for it
    queues : [dynamic]QueueFamily
    defer delete(queues)

    for type in types {
        fam : ^QueueFamily
        switch {
            case type == .GRAPHICS:
                fam, ok = find_queue_family_present_support(ctx)
            case:
                fam, ok = find_queue_family_by_type(ctx, {type})

        }

        append(&queues, fam^)

        if !ok {
            log.error("Unable to find queue familieis for graphics device for type", type)
        }
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

    required_extensions_cstr := make([]cstring, len(REQUIRED_DEVICE_EXTENSIONS))

    for ext, i in REQUIRED_DEVICE_EXTENSIONS {
        required_extensions_cstr[i] = strings.clone_to_cstring(ext)
    }

    timeline_sems_feature : vk.PhysicalDeviceTimelineSemaphoreFeatures
    timeline_sems_feature.sType = .PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES
    timeline_sems_feature.timelineSemaphore = true

    nested_buffers_feature : vk.PhysicalDeviceNestedCommandBufferFeaturesEXT
    nested_buffers_feature.sType = .PHYSICAL_DEVICE_NESTED_COMMAND_BUFFER_FEATURES_EXT
    nested_buffers_feature.pNext = &timeline_sems_feature
    nested_buffers_feature.nestedCommandBuffer = true
    nested_buffers_feature.nestedCommandBufferSimultaneousUse = true
    nested_buffers_feature.nestedCommandBufferRendering = true

    features : vk.PhysicalDeviceFeatures2
    features.sType = .PHYSICAL_DEVICE_FEATURES_2
    features.pNext = &nested_buffers_feature


    create_info : vk.DeviceCreateInfo
    create_info.sType = .DEVICE_CREATE_INFO
    create_info.pQueueCreateInfos = &q_create_infos[0]
    create_info.queueCreateInfoCount = u32(len(q_create_infos))
    create_info.pEnabledFeatures = nil                             // TODO)) specify device features we want to use
    create_info.pNext = &features
    create_info.enabledExtensionCount = u32(len(required_extensions_cstr))
    create_info.ppEnabledExtensionNames = &required_extensions_cstr[0]

    res := vk.CreateDevice(ctx.device.physical, &create_info, {}, &ctx.device.logical)
    if res != .SUCCESS {
        log.error("Error creating logical device", res)
        ok = false
    }

    vk.load_proc_addresses_device(ctx.device.logical)

    return
}
