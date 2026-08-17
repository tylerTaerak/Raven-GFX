package gfx

import core "core"
import sdl "vendor:sdl3"
import "core:log"
import "./api"

WINDOW_FLAGS : sdl.WindowFlags = {.VULKAN, .BORDERLESS}

SHADERS_PATH :: #directory + "shaders/gen/default_3d/"

FRAMES_IN_FLIGHT :: 3

// TODO)) I think I want to break this context down into smaller objects
Context :: struct {
	instance 		: api.Instance,
	device 			: api.Device,

    swapchain       : api.Swapchain(FRAMES_IN_FLIGHT),
    window          : core.Window,

	draw_ctx 		: Draw_Context(FRAMES_IN_FLIGHT),
}

Core_Context : Context

Config :: struct {
    window_title: string,
    window_w, window_h: int
}

initialize :: proc(cfg: Config) -> (ok : bool = true) {
	// TODO)) I'm not sure if I want to rely solely on SDL as a dependency - things get really tricky if I want to do WASM (which I do)
	// SDL only supports WASM through Emscripten, which is something I'd really like to avoid. Otherwise, it suits my needs well, but
	// I wonder if I should be creating my own windowing library to link into here
    sdl.Init({.EVENTS, .GAMEPAD, .VIDEO, .JOYSTICK}) or_return
	log.info("SDL Initialized")

    // TODO)) should probably expose a subset of window flags for a user
    Core_Context.window = core.create_window(
        cfg.window_title,
        cfg.window_w,
        cfg.window_h,
        WINDOW_FLAGS
    )

	log.info("SDL Window initialized")

	Core_Context.instance = api.create_instance() or_return
	log.info("Raven VK Instance created")
	Core_Context.device = api.create_device(Core_Context.instance) or_return
	log.info("Raven VK Device created")

	Core_Context.draw_ctx = create_draw_context(
		Core_Context.instance,
		Core_Context.device,
		Core_Context.window,
		FRAMES_IN_FLIGHT) or_return

	log.info("Raven Draw Context Created")

    return
}

update :: proc(frame : ^Draw_Frame) -> (keep_going : bool = true) {
	dctx := &Core_Context.draw_ctx

	// --- present the current frame
	if frame.acquired {
		api.prepare_image_present(dctx.command_set, int(frame.index_frame_ctx), frame.image)
		api.end_command_buffer(dctx.command_set, int(frame.index_frame_ctx))
		
		api.submit_command_buffer(
			Core_Context.device,
			dctx.command_set,
			int(frame.index_frame_ctx),
			frame.sem_acquired^,
			frame.sem_draw_complete^,
			dctx.fence_in_flight[frame.index_frame_ctx])

		present_frame(Core_Context.device, dctx, frame^)
	}

	// --- start the next frame

    core.refresh_frame_events(&Core_Context.window)
    if core.check_quit_event(Core_Context.window) {
        return false
    }

    api.wait_for_fence(Core_Context.device, dctx.fence_in_flight[dctx.frame_index])
    api.reset_fence(Core_Context.device, dctx.fence_in_flight[dctx.frame_index])

    frame^ = acquire_next_image(Core_Context.device, dctx)
	dctx.frame_index = (dctx.frame_index + 1) % FRAMES_IN_FLIGHT

    if frame.acquired {
		api.reset_command_buffer(dctx.command_set, int(frame.index_frame_ctx))
		api.begin_command_buffer(dctx.command_set, int(frame.index_frame_ctx))

		api.prepare_image_render(dctx.command_set, int(frame.index_frame_ctx), frame.image)
	} else {
		log.warn("Error acquiring next swapchain image")
	}

    return
}

shutdown :: proc() {
    api.device_wait_idle(Core_Context.device)

	destroy_draw_context(Core_Context.device, Core_Context.draw_ctx)

	api.destroy_device(Core_Context.device)
	api.destroy_instance(Core_Context.instance)

    core.destroy_window(&Core_Context.window)

	sdl.Quit()
}
