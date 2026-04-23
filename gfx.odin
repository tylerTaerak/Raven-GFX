package gfx

import core "core"
import sdl "vendor:sdl3"
import gvk "./vulkan"
import "core:log"

SHADERS_PATH :: #directory + "shaders/gen/practice/"

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
    main_cmd_set    : CommandSet,
    descriptors     : Descriptor_Set,
    main_pipeline   : Pipeline,
    assets          : Asset_Handler
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

    desc_cfg : Descriptor_Config
    desc_cfg.count = 1
    desc_cfg.type_count[.STORAGE] = 1
    desc_cfg.type_count[.UNIFORM] = 1

    Core_Context.descriptors = _create_descriptor_set(Core_Context.backend, desc_cfg) or_return

    log.info("Initialized Descriptor Sets")

    pipeline_cfg : Pipeline_Config
    pipeline_cfg.vertex_shader_path = SHADERS_PATH + "vert.spv"
    pipeline_cfg.fragment_shader_path = SHADERS_PATH + "frag.spv"
    pipeline_cfg.descriptor_sets = Core_Context.descriptors
    pipeline_cfg.color_formats = {.BGRA8_UNORM}
    pipeline_cfg.topology = .TRIANGLE_LIST

    Core_Context.main_pipeline = _create_pipeline(Core_Context.backend, pipeline_cfg) or_return

    log.info("Created Default Pipeline")

    Core_Context.assets = create_asset_handler() or_return

    log.info("Created Asset Handler")

    return
}

/**
  So what I'm imagining for the API now is something like:

    next_frame : Frame

    for next_frame = update(next_frame) {
        // do update and drawing
    }

    where we kind of invert the loop and do basically:

    update(frame) {
        present(frame)

        if quit do return {}, false

        return next_frame()
    }

    And we can just check that a valid frame was passed to present() so we don't draw to a null image
    We'd be beginning the primary command buffer at the end of update with next_frame, and ending it with
    present()
  */

next_frame :: proc() -> (screen_image : Frame, ok : bool = true){
    if core.check_quit_event(Core_Context.window) {
        ok = false
        return
    }

    core.refresh_frame_events(&Core_Context.window)

    _wait_for_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)
    _reset_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)

    acquired : bool
    screen_image, acquired = get_next_frame(&Core_Context, Core_Context.frame_index)

    Core_Context.frame_index = (Core_Context.frame_index + 1) % FRAMES_IN_FLIGHT

    if !acquired {
        log.warn("Error acquiring swapchain image")
    }

    // likewise, this would be a good place to begin the command buffer

    return
}

present :: proc(frame: Frame) {
    if frame.image.image == 0 {
        // don't try to render a null frame
        return
    }

    // this would probably also be a good place to submit the primary command buffer
    present_frame(&Core_Context, frame)
}

update :: proc() -> bool {
    /** begin update() **/
    core.refresh_frame_events(&Core_Context.window)

    _wait_for_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)
    _reset_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)

    screen_image, acquired := get_next_frame(&Core_Context, Core_Context.frame_index)

    Core_Context.frame_index = (Core_Context.frame_index + 1) % FRAMES_IN_FLIGHT

    if !acquired {
        log.warn("Error acquiring swapchain image")
        return true
    }
    /** end update() **/

    /** begin in-flight draw commands **/

    buf := _begin_command_buffer(Core_Context.main_cmd_set, int(screen_image.frame_index))

    _draw(Core_Context.main_cmd_set.buffers[screen_image.frame_index], Core_Context.main_pipeline, screen_image.image)

    _end_command_buffer(buf)

    queue_fam, _ := _find_queue_family(Core_Context.backend, {.GRAPHICS})

    _submit_command_buffer(
        Core_Context.backend,
        Core_Context.main_cmd_set.buffers[screen_image.frame_index],
        queue_fam^,
        Core_Context.swapchain.sync[screen_image.frame_index].image_acquired,
        Core_Context.swapchain.sync[screen_image.image_index].render_finished,
        Core_Context.swapchain.sync[screen_image.frame_index].in_flight
    )

    /** end in-flight draw commands -- these should all be stored, then processed before the end of frame, all wrapped in present() **/

    // although right now, it may make the most sense to just do everything single threaded and make sure that works, and then we can play around
    // with a multithreaded job system later. I think that's an okay way to get started

    /** begin end of frame - this will look like process all jobs and then present the image **/
    present_frame(&Core_Context, screen_image)
    /** end end of frame **/

    return !core.check_quit_event(Core_Context.window)
}

shutdown :: proc() {
    _wait_for_idle(Core_Context.backend)

    destroy_asset_handler(&Core_Context.assets)

    _destroy_pipeline(Core_Context.backend, &Core_Context.main_pipeline)

    _destroy_descriptor_set(Core_Context.backend, &Core_Context.descriptors)

    _destroy_command_set(Core_Context.backend, &Core_Context.main_cmd_set)

    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)

    _destroy_context(Core_Context.backend)
    core.destroy_window(&Core_Context.window)
}
