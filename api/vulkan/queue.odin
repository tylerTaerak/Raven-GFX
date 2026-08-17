package game_vulkan

import vk "vendor:vulkan"
import "shared:raven-gfx/core"

import "core:log"

QueueType :: core.Queue_Type
QueueTypes :: bit_set[QueueType]

QueueFamily :: struct {
    family_idx      : u32,
    queue_count     : u32,
    family_types    : QueueTypes,
}

_to_vk_queue_flags :: proc(types : QueueTypes) -> vk.QueueFlags {
	flags : vk.QueueFlags

	for t in types {
		flags += {_to_vk_queue_type(t)}
	}

	return flags
}

_to_raven_queue_types :: proc(types : vk.QueueFlags) -> QueueTypes {
	flags : QueueTypes

	for t in types {
		flags += {_to_raven_queue_type(t)}
	}

	return flags
}

find_queue_family_by_type :: proc(families : []QueueFamily, types : QueueTypes) -> (fam_idx : int, ok : bool = false) {
    for &family, idx in families {
        if types & family.family_types == types {
            fam_idx = idx
            ok = true
            return
        }

    }

    return
}

find_queue_family_present_support :: proc(device : Device, families : []QueueFamily, window : vk.SurfaceKHR) -> (fam_idx : int, ok : bool = false) {
    for &family, idx in families {
		surface_support : b32
		res := vk.GetPhysicalDeviceSurfaceSupportKHR(device.physical, u32(idx), window, &surface_support)

		if res != .SUCCESS {
			ok = false
			return
		}

        if surface_support {
            fam_idx = idx
            ok = true
        }
    }

    return
}

populate_queue_family_properties :: proc(device : vk.PhysicalDevice) -> (families : []QueueFamily, ok : bool = true) {
    fam_count : u32
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &fam_count, nil)

    fam_props := make([]vk.QueueFamilyProperties, fam_count)
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &fam_count, &fam_props[0])

    if fam_count == 0 {
        log.error("Unable to find any queue families for given device")
    }

    families = make([]QueueFamily, fam_count)

    for fam, idx in fam_props {
        families[idx].family_idx = u32(idx)
        families[idx].queue_count = fam.queueCount
        families[idx].family_types = _to_raven_queue_types(fam.queueFlags)

        log.info("Queue Family", idx, "has flags", fam.queueFlags)
    }

    return
}
