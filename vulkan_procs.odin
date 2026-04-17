#+build windows, linux, freebsd, openbsd, netbsd
#+private
package gfx

import vulk "./vulkan"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "./core"

REQUIRED_DEVICE_EXTENSIONS : []string : {
    vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    vk.EXT_NESTED_COMMAND_BUFFER_EXTENSION_NAME,
    vk.KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME,
    vk.KHR_SYNCHRONIZATION_2_EXTENSION_NAME,
    vk.KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
    vk.KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME,
    vk.KHR_CREATE_RENDERPASS_2_EXTENSION_NAME,
    vk.KHR_MULTIVIEW_EXTENSION_NAME,
    vk.KHR_MAINTENANCE_2_EXTENSION_NAME,
    vk.EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME,
    vk.KHR_MAINTENANCE_3_EXTENSION_NAME,
    vk.EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME,
    vk.EXT_EXTENDED_DYNAMIC_STATE_2_EXTENSION_NAME,
    vk.EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME
}

WINDOW_FLAGS : sdl.WindowFlags = {.VULKAN, .BORDERLESS}

_create_context             :: proc(window: ^core.Window) -> (^Backend_Context, bool) {
    return vulk.create_context(window, REQUIRED_DEVICE_EXTENSIONS)
}
_destroy_context            :: vulk.destroy_context

_create_swapchain           :: vulk.create_swapchain
_destroy_swapchain          :: vulk.destroy_swapchain

_create_pipeline            :: vulk.create_pipeline
_destroy_pipeline           :: vulk.destroy_pipeline

_create_descriptor_set      :: vulk.create_descriptor_set
_destroy_descriptor_set     :: vulk.destroy_descriptor_set

_create_buffer              :: vulk.create_buffer
_create_host_buffer         :: vulk.create_host_buffer
_slice_buffer               :: vulk.make_slice
_copy_buffer                :: vulk.copy_buffer_data
_destroy_buffer             :: vulk.destroy_buffer
_destroy_host_buffer        :: vulk.destroy_host_buffer

_create_image               :: vulk.create_image
_destroy_image              :: vulk.destroy_image

_find_queue_family          :: vulk.find_queue_family_by_type
_find_queue_present         :: vulk.find_queue_family_present_support

_create_timeline            :: vulk.init_timeline
_destroy_timeline           :: vulk.destroy_timeline
_get_ticks                  :: vulk.get_current_ticks
_tick                       :: vulk.tick

_create_fence               :: vulk.init_fence
_wait_for_fence             :: vulk.wait_for_fence
_wait_for_fences            :: vulk.wait_for_fences
_reset_fence                :: vulk.reset_fence
_reset_fences               :: vulk.reset_fences
_destroy_fence              :: vulk.destroy_fence

_create_command_set         :: vulk.create_command_set
_destroy_command_set        :: vulk.destroy_command_set

_begin_command_buffer       :: vulk.begin_command_buffer
_end_command_buffer         :: vulk.end_command_buffer
_submit_command_buffer      :: vulk.submit_command_buffer

_acquire_swapchain_image    :: vulk.acquire_next_image_index
_draw                       :: vulk.draw_rendering
_present_image              :: vulk.present_image

_create_semaphore           :: vulk.init_semaphore
_destroy_semaphore          :: vulk.destroy_semaphore

_wait_for_idle              :: vulk.wait_for_idle
