package game_vulkan

import vk "vendor:vulkan"

import "core:log"

QueueType :: vk.QueueFlag
QueueTypes :: vk.QueueFlags

QueueFamily :: struct {
    family_idx      : u32,
    queue_count     : u32,
    family_types    : QueueTypes,
    surface_support : b32
}

populate_queue_family_properties :: proc(ctx : ^Context) -> (ok : bool = true) {
    fam_count : u32
    vk.GetPhysicalDeviceQueueFamilyProperties(ctx.device.physical, &fam_count, nil)

    fam_props := make([]vk.QueueFamilyProperties, fam_count)
    vk.GetPhysicalDeviceQueueFamilyProperties(ctx.device.physical, &fam_count, &fam_props[0])

    if fam_count == 0 {
        log.error("Unable to find any queue families for given device")
    }

    ctx.device.queue_families = make([]QueueFamily, fam_count)

    for fam, idx in fam_props {
        ctx.device.queue_families[idx].family_idx = u32(idx)
        ctx.device.queue_families[idx].queue_count = fam.queueCount
        ctx.device.queue_families[idx].family_types = fam.queueFlags

        log.info("Queue Family", idx, "has flags", fam.queueFlags)


        vk.GetPhysicalDeviceSurfaceSupportKHR(ctx.device.physical, u32(idx), ctx.window_surface, &ctx.device.queue_families[idx].surface_support)
    }

    return
}

find_queue_family_by_type :: proc(ctx : ^Context, types : QueueTypes) -> (fam : ^QueueFamily, ok : bool = false) {
    for &family in ctx.device.queue_families {
        if types & family.family_types == types {
            log.info("Found queue family", family, "for types", types)
            fam = &family
            ok = true
            return
        }

    }

    return
}

find_queue_family_present_support :: proc(ctx : ^Context) -> (fam : ^QueueFamily, ok : bool = false) {
    for &family in ctx.device.queue_families {
        if family.surface_support && .GRAPHICS in family.family_types {
            fam = &family
            ok = true
        }
    }

    return
}

init_queue :: proc(family : QueueFamily, device : vk.Device) -> (q : vk.Queue, ok : bool) {
    vk.GetDeviceQueue(device, family.family_idx, 0, &q)
    ok = true
    return
}
