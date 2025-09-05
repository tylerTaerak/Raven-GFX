package gfx

import gvk "vulkan"
import core "core"
import "core:log"

Context :: struct {
    vk_ctx : ^gvk.Context,
    window : core.Window,
    camera : core.Camera
}

Core_Context : Context

Mesh :: gvk.Mesh_Handle


init :: proc() -> (ok : bool = true) {
    Core_Context.window = core.create_window("Test Window", 500, 500, {.VULKAN, .BORDERLESS})

    Core_Context.vk_ctx = gvk.create_context(Core_Context.window) or_return
    
    log.info("initialized graphics context")

    shader_path :: #directory + "shaders/gen/default_3d/"

    log.info(shader_path)

    gvk.create_pipeline(Core_Context.vk_ctx, shader_path + "vert.spv", shader_path + "frag.spv") or_return

    log.info("created graphics pipeline")
    return
}

update :: proc() {
    gvk.run_frame(Core_Context.vk_ctx)
}

load_mesh :: proc(filepath : string) -> Mesh{
    model_data := core.load_model(filepath)
    if len(model_data) > 0 {
        return gvk.load_mesh(Core_Context.vk_ctx, model_data[0])
    } else {
        return 0
    }
}

add_camera :: proc() {
    core_cam := core.create_perscpetive_camera(&Core_Context.window, 60.0, 0.1, 100.0)
    Core_Context.camera = core_cam
    cam := gvk.create_camera(Core_Context.vk_ctx)
    for i in 0..<gvk.FRAMES_IN_FLIGHT {
        Core_Context.vk_ctx.data[i].camera = cam
        gvk.set_camera_data(Core_Context.vk_ctx, &Core_Context.vk_ctx.data[i].camera, core_cam)
    }
}

move_camera :: proc(transform : matrix[4,4]f32) {
    core.move_camera_transform(&Core_Context.camera, transform)
    for i in 0..<gvk.FRAMES_IN_FLIGHT {
        gvk.set_camera_data(Core_Context.vk_ctx, &Core_Context.vk_ctx.data[i].camera, Core_Context.camera)
    }
}

draw :: proc(mesh : Mesh, transform : matrix[4,4]f32) {
    gvk.draw_mesh(Core_Context.vk_ctx, mesh, transform)
}

destroy :: proc() {
    gvk.destroy_context(Core_Context.vk_ctx)
    core.destroy_window(&Core_Context.window)
}
