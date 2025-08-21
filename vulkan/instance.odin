package game_vulkan

import sdl "vendor:sdl3"
import vk "vendor:vulkan"

import "core:log"
import "core:mem"
import "core:strings"

create_instance :: proc(ctx : ^Context) -> (ok: bool = true) {
    ext_count : u32
    sdl_ext := sdl.Vulkan_GetInstanceExtensions(&ext_count) // get number of extensions for SDL to use

    // vk.EXT_VALIDATION_FLAGS_EXTENSION_NAME

    vk_layers : []cstring
    vk_extensions : [dynamic]cstring
    defer delete(vk_extensions)

    for i in 0..<ext_count {
        append(&vk_extensions, sdl_ext[i])
    }

    append(&vk_extensions, vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME)

    // load and check availability of validation layers
    when ODIN_DEBUG {
        vk_layers = {"VK_LAYER_KHRONOS_validation"}
        append(&vk_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    } else {
        vk_layers = {}
    }

    layer_count : u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)

    layers := make([]vk.LayerProperties, layer_count)
    vk.EnumerateInstanceLayerProperties(&layer_count, &layers[0])

    for name in vk_layers {
        found : bool

        for &layer_props in layers {
            name_str := string(name)
            layer_name_str := strings.clone_from_bytes(layer_props.layerName[:])
            if name_str == layer_name_str[:len(name_str)] {
                found = true
                break
            }

            delete(layer_name_str)
        }

        if !found {
            log.error("Unable to find requested layer:", name)
        }
    }

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

    log.info(create_info.enabledLayerCount)

    res := vk.CreateInstance(&create_info, {}, &ctx.instance)

    if res != .SUCCESS {
        log.error("Error creating vulkan instance with error:", res)
        ok = false
    }

    return
}
