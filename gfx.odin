package gfx

import core "core"
import sdl "vendor:sdl3"
import "core:log"

FRAMES_IN_FLIGHT :: 3

Context :: struct {
    backend         : ^Backend_Context,
    swapchain       : Swapchain,
    frame_fences    : [FRAMES_IN_FLIGHT]Fence,
    frame_index     : int,
    window          : core.Window,
    camera          : core.Camera
}

Core_Context : Context

Config :: struct {
    window_title: string,
    window_w, window_h: int
}


initialize :: proc(cfg: Config) -> (ok : bool = true) {
    sdl.Init({.EVENTS, .GAMEPAD, .VIDEO, .JOYSTICK}) or_return

    // TODO)) should probably expose a subset of window flags for a user
    Core_Context.window = core.create_window(
        cfg.window_title,
        cfg.window_w,
        cfg.window_h,
        WINDOW_FLAGS
    )

    Core_Context.backend = _create_context(&Core_Context.window) or_return

    Core_Context.swapchain = _create_swapchain(Core_Context.backend) or_return

    for i in 0..<FRAMES_IN_FLIGHT {
        Core_Context.frame_fences[i] = _create_fence(Core_Context.backend)
    }
    
    log.info("initialized graphics context")
    return
}

reload :: proc(cfg: Config) {
    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)

    core.update_window_data(&Core_Context.window, cfg.window_title, cfg.window_w, cfg.window_h)

    _create_swapchain(Core_Context.backend)
}

update :: proc() -> bool {
    core.refresh_frame_events(&Core_Context.window)

    if core.check_resize_event(Core_Context.window) {
        cfg : Config
        cfg.window_title = Core_Context.window.title
        cfg.window_w = Core_Context.window.w
        cfg.window_h = Core_Context.window.h

        reload(cfg)
    }

    screen_image := acquire_swapchain_image(&Core_Context, Core_Context.frame_index)

    _wait_for_fence(Core_Context.backend, &Core_Context.frame_fences[screen_image.index])
    _reset_fence(Core_Context.backend, &Core_Context.frame_fences[screen_image.index])

    present_swapchain_image(&Core_Context, &screen_image)

    Core_Context.frame_index = (Core_Context.frame_index + 1) % FRAMES_IN_FLIGHT

    return core.check_quit_event(Core_Context.window)
}

shutdown :: proc() {
    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)

    for i in 0..<FRAMES_IN_FLIGHT {
        _destroy_fence(Core_Context.backend, Core_Context.frame_fences[i])
    }

    _destroy_context(Core_Context.backend)
    core.destroy_window(&Core_Context.window)
}
