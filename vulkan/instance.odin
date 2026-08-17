package game_vulkan

import "core:fmt"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"

import "core:log"
import "core:strings"
import vmem "core:mem/virtual"

Instance :: struct {
	core : vk.Instance,
	debug : vk.DebugUtilsMessengerEXT
}

create_vulkan_instance :: proc(extensions : []string) -> (instance : Instance, ok: bool = true) {
	vk.load_proc_addresses_global(rawptr(sdl.Vulkan_GetVkGetInstanceProcAddr()))

    vk_layers : []cstring
    vk_extensions : [dynamic]cstring
    defer delete(vk_extensions)

	cstring_arena : vmem.Arena

	err := vmem.arena_init_growing(&cstring_arena)
	defer vmem.arena_destroy(&cstring_arena)
	if err != .None {
		ok = false
		return
	}

	cstring_alloc := vmem.arena_allocator(&cstring_arena)

    for i in 0..<len(extensions) {
        append(&vk_extensions, strings.clone_to_cstring(extensions[i], cstring_alloc))
    }

    append(&vk_extensions, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)

    // load and check availability of validation layers
    when ODIN_DEBUG {
        vk_layers = {"VK_LAYER_KHRONOS_validation"}
        append(&vk_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    } else {
        vk_layers = {}
    }

	fmt.println(vk.EnumerateInstanceLayerProperties)

    layer_count : u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)

    layers := make([]vk.LayerProperties, layer_count)
    vk.EnumerateInstanceLayerProperties(&layer_count, &layers[0])

    for name in vk_layers {
        found : bool

        for &layer_props in layers {
            name_str := string(name)
            layer_name_str := strings.clone_from_bytes(layer_props.layerName[:])
			defer delete(layer_name_str)

            if name_str == layer_name_str[:len(name_str)] {
                found = true
                break
            }
        }

        if !found {
            log.error("Unable to find requested layer:", name)
        }
    }

    app_info : vk.ApplicationInfo
    app_info.sType = .APPLICATION_INFO
    app_info.pEngineName = cstring("Raven Graphics")
    app_info.apiVersion = vk.API_VERSION_1_4

    create_info : vk.InstanceCreateInfo
    create_info.sType = .INSTANCE_CREATE_INFO
    if len(vk_layers) > 0 {
        create_info.enabledLayerCount = u32(len(vk_layers))
        create_info.ppEnabledLayerNames = &vk_layers[0]
    } else {
        create_info.enabledLayerCount = 0
        create_info.ppEnabledLayerNames = nil
    }
    create_info.enabledExtensionCount = u32(len(vk_extensions))
    create_info.ppEnabledExtensionNames = &vk_extensions[0]
    create_info.flags = {}
    create_info.pApplicationInfo = &app_info

    log.info(create_info.enabledLayerCount)

    res := vk.CreateInstance(&create_info, {}, &instance.core)

    if res != .SUCCESS {
        log.error("Error creating vulkan instance with error:", res)
        ok = false
		return
    }

	log.debug("Initializing Procedures for Vulkan Instance")
	vk.load_proc_addresses_instance(instance.core)

	if ODIN_DEBUG {
		instance.debug = create_debug_messenger(instance.core) or_return
	}

    return
}

destroy_instance :: proc(instance : Instance) {
	destroy_debug_messenger(instance.core, instance.debug)
	vk.DestroyInstance(instance.core, nil)
}
