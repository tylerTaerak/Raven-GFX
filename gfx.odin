package gfx

import core "core"
import sdl "vendor:sdl3"
import gvk "./vulkan"
import vk "vendor:vulkan"
import "core:log"

SHADERS_PATH :: #directory + "shaders/gen/default_3d/"

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
    main_shaders    : Graphics_Shader,
    pipeline_layout : vk.PipelineLayout,
    assets          : Asset_Handler,
    current_frame   : Frame,
    draw_commands   : gvk.Host_Buffer(vk.DrawIndexedIndirectCommand),
    instances       : [FRAMES_IN_FLIGHT]gvk.Host_Buffer(World_Transform),
    draws           : Draw_Map
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
    desc_cfg.count = FRAMES_IN_FLIGHT
    desc_cfg.type_count[.STORAGE] = 6
    desc_cfg.type_count[.UNIFORM] = 1

    Core_Context.descriptors = _create_descriptor_set(Core_Context.backend, desc_cfg) or_return

    log.info("Initialized Descriptor Sets")

    layout_info : vk.PipelineLayoutCreateInfo
    layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO
    layout_info.setLayoutCount = u32(len(Core_Context.descriptors.layout))
    layout_info.pSetLayouts = &Core_Context.descriptors.layout[0]
    layout_info.flags = {}

    vk.CreatePipelineLayout(Core_Context.backend.device, &layout_info, {}, &Core_Context.pipeline_layout)

    log.info("Created Pipeline Layout")

    vert_cfg : gvk.Shader_Config
    vert_cfg.filename = SHADERS_PATH + "vert.spv"
    vert_cfg.shader_name = "main"
    vert_cfg.stage = .VERTEX
    vert_cfg.descriptors = Core_Context.descriptors

    frag_cfg : gvk.Shader_Config
    frag_cfg.filename = SHADERS_PATH + "frag.spv"
    frag_cfg.shader_name = "main"
    frag_cfg.stage = .FRAGMENT
    frag_cfg.descriptors = Core_Context.descriptors

    Core_Context.main_shaders.vertex = gvk.create_shader(Core_Context.backend, &vert_cfg) or_return
    Core_Context.main_shaders.fragment = gvk.create_shader(Core_Context.backend, &frag_cfg) or_return

    log.info("Created Default Shader Objects")

    Core_Context.assets = create_asset_handler() or_return

    log.info("Created Asset Handler")

    fam := gvk.find_queue_family_by_type(Core_Context.backend, {.TRANSFER}) or_return
    Core_Context.draw_commands = gvk.create_host_buffer(Core_Context.backend, vk.DrawIndexedIndirectCommand, 2048000, {fam^}, {.INDIRECT_BUFFER})

    for i in 0..<FRAMES_IN_FLIGHT {
        Core_Context.instances[i] = gvk.create_host_buffer(Core_Context.backend, World_Transform, 2048000, {fam^}, {.STORAGE_BUFFER, .TRANSFER_DST})
        gvk.update_descriptor_set(Core_Context.backend, &Core_Context.descriptors, u32(i), 5, Core_Context.instances[i].internal_buffer)
    }

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

next_frame :: proc() -> (screen_image : Frame) {
    _wait_for_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)
    _reset_fence(Core_Context.backend, &Core_Context.swapchain.sync[Core_Context.frame_index].in_flight)

    clear_map(&Core_Context.draws)

    acquired : bool
    screen_image, acquired = get_next_frame(&Core_Context, Core_Context.frame_index)

    Core_Context.frame_index = (Core_Context.frame_index + 1) % FRAMES_IN_FLIGHT

    if !acquired {
        log.warn("Error acquiring swapchain image")
        screen_image.image.image = 0 // deliberately set to 0
        return
    }

    Core_Context.current_frame = screen_image

    vk.ResetCommandBuffer(Core_Context.main_cmd_set.buffers[screen_image.frame_index], {})
    buf := _begin_command_buffer(Core_Context.main_cmd_set, int(screen_image.frame_index))

    color_barrier : vk.ImageMemoryBarrier2KHR
    color_barrier.sType = .IMAGE_MEMORY_BARRIER_2_KHR
    color_barrier.image = screen_image.image.image
    color_barrier.oldLayout = .UNDEFINED
    color_barrier.newLayout = .COLOR_ATTACHMENT_OPTIMAL
    color_barrier.subresourceRange.aspectMask = {.COLOR}
    color_barrier.subresourceRange.layerCount = 1
    color_barrier.subresourceRange.levelCount = 1
    color_barrier.srcAccessMask = {}
    color_barrier.srcStageMask = {}
    color_barrier.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT_KHR}
    color_barrier.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}

    dependencies : vk.DependencyInfoKHR
    dependencies.sType = .DEPENDENCY_INFO_KHR
    dependencies.imageMemoryBarrierCount = 1
    dependencies.pImageMemoryBarriers = &color_barrier

    vk.CmdPipelineBarrier2KHR(buf, &dependencies)

    return
}

present :: proc(frame: Frame) {
    if frame.image.image == 0 {
        // don't try to render a null frame
        return
    }

    draw_count := write_draw_command_buffer(Core_Context.draws, &Core_Context.draw_commands)

    commit_draw_commands(Core_Context.main_cmd_set.buffers[frame.frame_index], Core_Context.draw_commands, draw_count, Core_Context.draws)

    present_barrier : vk.ImageMemoryBarrier2KHR
    present_barrier.sType = .IMAGE_MEMORY_BARRIER_2_KHR
    present_barrier.image = frame.image.image
    present_barrier.oldLayout = .COLOR_ATTACHMENT_OPTIMAL
    present_barrier.newLayout = .PRESENT_SRC_KHR
    present_barrier.subresourceRange.aspectMask = {.COLOR}
    present_barrier.subresourceRange.layerCount = 1
    present_barrier.subresourceRange.levelCount = 1
    present_barrier.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT_KHR}
    present_barrier.srcAccessMask = {.COLOR_ATTACHMENT_WRITE}
    present_barrier.dstStageMask = {}
    present_barrier.dstAccessMask = {}

    dependencies : vk.DependencyInfo
    dependencies.sType = .DEPENDENCY_INFO_KHR
    dependencies.imageMemoryBarrierCount = 1
    dependencies.pImageMemoryBarriers = &present_barrier

    vk.CmdPipelineBarrier2KHR(Core_Context.main_cmd_set.buffers[frame.frame_index], &dependencies)

    _end_command_buffer(Core_Context.main_cmd_set.buffers[frame.frame_index])

    queue_fam, _ := _find_queue_family(Core_Context.backend, {.GRAPHICS})

    _submit_command_buffer(
        Core_Context.backend,
        Core_Context.main_cmd_set.buffers[frame.frame_index],
        queue_fam^,
        Core_Context.swapchain.sync[frame.frame_index].image_acquired,
        Core_Context.swapchain.sync[frame.image_index].render_finished,
        Core_Context.swapchain.sync[frame.frame_index].in_flight
    )

    // this would probably also be a good place to submit the primary command buffer
    present_frame(&Core_Context, frame)
}

update :: proc() -> bool {
    present(Core_Context.current_frame)


    core.refresh_frame_events(&Core_Context.window)
    if core.check_quit_event(Core_Context.window) {
        return false
    }

    Core_Context.current_frame = next_frame()

    return true
}

shutdown :: proc() {
    _wait_for_idle(Core_Context.backend)

    for i in 0..<FRAMES_IN_FLIGHT {
        gvk.destroy_host_buffer(Core_Context.backend, Core_Context.instances[i])
    }
    gvk.destroy_host_buffer(Core_Context.backend, Core_Context.draw_commands)

    vk.DestroyPipelineLayout(Core_Context.backend.device, Core_Context.pipeline_layout, {})

    destroy_asset_handler(&Core_Context.assets)

    gvk.destroy_shader(Core_Context.backend, Core_Context.main_shaders.vertex)
    gvk.destroy_shader(Core_Context.backend, Core_Context.main_shaders.fragment)

    _destroy_descriptor_set(Core_Context.backend, &Core_Context.descriptors)

    _destroy_command_set(Core_Context.backend, &Core_Context.main_cmd_set)

    _destroy_swapchain(Core_Context.backend, &Core_Context.swapchain)

    _destroy_context(Core_Context.backend)
    core.destroy_window(&Core_Context.window)
}
