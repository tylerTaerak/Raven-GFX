package gfx

import gvk "vulkan"
import core "core"
import "core:log"

Context :: struct {
    vk_ctx : gvk.Context,
    window : core.Window
}

Core_Context : Context


init :: proc() -> (ok : bool = true) {
    Core_Context.window = core.create_window("Test Window", 500, 500, {.VULKAN, .BORDERLESS})

    Core_Context.vk_ctx = gvk.create_context(Core_Context.window) or_return
    
    log.info("initialized graphics context")

    gvk.create_pipeline(&Core_Context.vk_ctx, "gfx/shaders/vert.spv", "gfx/shaders/frag.spv") or_return

    log.info("created graphics pipeline")
    return
}

update :: proc() {
    gvk.run_frame(&Core_Context.vk_ctx)
}

destroy :: proc() {
    gvk.destroy_context(&Core_Context.vk_ctx)
    core.destroy_window(&Core_Context.window)
}
