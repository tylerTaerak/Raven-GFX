package game_vulkan

import vk "vendor:vulkan"

import "core:log"

import "base:runtime"


_debug_callback :: proc "c" (severity        : vk.DebugUtilsMessageSeverityFlagsEXT,
                        type            : vk.DebugUtilsMessageTypeFlagsEXT,
                        callback_data   : ^vk.DebugUtilsMessengerCallbackDataEXT,
                        user_data       : rawptr) -> b32 {
    context = runtime.default_context()
    logger := log.create_console_logger()
    logger.options = {.Level, .Terminal_Color}
    context.logger = logger

    for sev in severity {
        switch sev {
            case .VERBOSE:
                log.debug("VK DEBUG --", type, "-- OBJECT TYPE", callback_data.sType, "-- ::", callback_data.pMessage)
            case .INFO:
                log.info("VK INFO --", type, "-- OBJECT TYPE", callback_data.sType, "-- ::", callback_data.pMessage)
            case .WARNING:
                log.warn("VK WARN --", type, "-- OBJECT TYPE", callback_data.sType, "-- ::", callback_data.pMessage)
            case .ERROR:
                log.error("VK ERROR --", type, "-- OBJECT TYPE", callback_data.sType, "-- ::", callback_data.pMessage)
        }
    }

    return true
}

create_debug_messenger :: proc(ctx : ^Context) -> (ok: bool) {
    ok = true

    severities : vk.DebugUtilsMessageSeverityFlagsEXT
    if ODIN_DEBUG {
        severities = {.VERBOSE, .INFO, .WARNING, .ERROR}
    } else {
        severities = {.INFO, .WARNING, .ERROR}
    }

    types : vk.DebugUtilsMessageTypeFlagsEXT
    types = {.GENERAL, .VALIDATION, .PERFORMANCE, /*.DEVICE_ADDRESS_BINDING*/}

    create_info : vk.DebugUtilsMessengerCreateInfoEXT
    create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    create_info.messageSeverity = severities
    create_info.messageType = types
    create_info.pfnUserCallback = _debug_callback

    // it doesn't seem like this EXT layer is getting instantiated properly, causing a
    // segfault here
    res := vk.CreateDebugUtilsMessengerEXT(ctx.instance, &create_info, {}, &ctx.debug_messenger)

    if res != .SUCCESS {
        log.error("Error creating debug messenger:", res)
        ok = false
    }

    return
}
