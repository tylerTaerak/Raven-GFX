package gfx

import core "core"
import sdl "vendor:sdl3"
import "core:log"

FRAMES_IN_FLIGHT :: 3

Frame_Sync :: struct {
    fence : Fence,
    render : Semaphore,
    present : Semaphore
}

Context :: struct {
    backend         : ^Backend_Context,
    swapchain       : Swapchain(FRAMES_IN_FLIGHT),
    frame_index     : int,
    window          : core.Window,
    camera          : core.Camera,
    main_cmd_set    : CommandSet
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

    Core_Context.swapchain = _create_swapchain(Core_Context.backend, Core_Context.window.window_ptr, FRAMES_IN_FLIGHT, nil) or_return

    queue_fam : ^QueueFamily 
    queue_fam, ok = _find_queue_family(Core_Context.backend, {.GRAPHICS})

    Core_Context.main_cmd_set, ok = _create_command_set(Core_Context.backend, FRAMES_IN_FLIGHT, queue_fam^)
    
    log.info("initialized graphics context")
    return
}

reload :: proc(cfg: Config) {
    _wait_for_idle(Core_Context.backend)

    core.update_window_data(&Core_Context.window, cfg.window_title, cfg.window_w, cfg.window_h)

    // Core_Context.swapchain, _ = _create_swapchain(Core_Context.backend, FRAMES_IN_FLIGHT, &Core_Context.swapchain)

    // destroy the old one now that we're finished with it
    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)
}

update :: proc() -> bool {
    core.refresh_frame_events(&Core_Context.window)

    _wait_for_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)
    _reset_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)

    screen_image, acquired := acquire_swapchain_image(&Core_Context, Core_Context.frame_index)

    if !acquired {
        log.warn("Error acquiring swapchain image")
        return true
    }

    // if core.check_resize_event(Core_Context.window) {
    //     cfg : Config
    //     cfg.window_title = Core_Context.window.title
    //     cfg.window_w = Core_Context.window.w
    //     cfg.window_h = Core_Context.window.h

    //     reload(cfg)
    // }

    _begin_command_buffer(Core_Context.main_cmd_set, Core_Context.frame_index)

    _draw(Core_Context.main_cmd_set.buffers[Core_Context.frame_index], screen_image.image)

    _end_command_buffer(Core_Context.main_cmd_set, Core_Context.frame_index)

    queue_fam, _ := _find_queue_family(Core_Context.backend, {.GRAPHICS})

    _submit_command_buffer(
        Core_Context.backend,
        Core_Context.main_cmd_set.buffers[Core_Context.frame_index],
        queue_fam^,
        Core_Context.swapchain.sync[Core_Context.frame_index].image_acquired,
        Core_Context.swapchain.sync[screen_image.index].render_finished,
        Core_Context.swapchain.sync[Core_Context.frame_index].in_flight
    )

    present_swapchain_image(&Core_Context, &screen_image)

    Core_Context.frame_index = (Core_Context.frame_index + 1) % FRAMES_IN_FLIGHT

    return !core.check_quit_event(Core_Context.window)
}

shutdown :: proc() {
    _wait_for_idle(Core_Context.backend)

    _destroy_command_set(Core_Context.backend, &Core_Context.main_cmd_set)

    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)

    _destroy_context(Core_Context.backend)
    core.destroy_window(&Core_Context.window)
}
