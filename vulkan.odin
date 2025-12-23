#+build linux, freebsd, openbsd, netbsd
#+private
package gfx

import vulk "./vulkan"
import vk "vendor:vulkan"
import "./core"

/**
  This file defines the types used in Raven for using a Vulkan backend
*/

// TODO)) Have this passed to this code from wrapping library
REQUIRED_DEVICE_EXTENSIONS : []string : {
    vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    vk.EXT_NESTED_COMMAND_BUFFER_EXTENSION_NAME,
    vk.KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME,
    vk.KHR_SYNCHRONIZATION_2_EXTENSION_NAME,
    vk.KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
    vk.KHR_DEPTH_STENCIL_RESOLVE_EXTENSION_NAME,
    vk.KHR_CREATE_RENDERPASS_2_EXTENSION_NAME,
    vk.KHR_MULTIVIEW_EXTENSION_NAME,
    vk.KHR_MAINTENANCE_2_EXTENSION_NAME
}


Backend_Context             :: vulk.Context
_create_context             :: proc(window: core.Window) -> (^Backend_Context, bool) {
    return vulk.create_context(window, REQUIRED_DEVICE_EXTENSIONS)
}
_destroy_context            :: vulk.destroy_context

Swapchain                   :: vulk.Swapchain
_create_swapchain           :: vulk.create_swapchain
_destroy_swapchain          :: vulk.destroy_swapchain

Pipeline                    :: vulk.Pipeline
Pipeline_Config             :: vulk.Pipeline_Config
_create_pipeline            :: vulk.create_pipeline
_destroy_pipeline           :: vulk.destroy_pipeline

Descriptor_Set              :: vulk.Descriptor_Collection
Descriptor_Config           :: vulk.Descriptor_Config
_create_descriptor_set      :: vulk.create_descriptor_set
_destroy_descriptor_set     :: vulk.destroy_descriptor_set

Buffer                      :: vulk.Buffer
Host_Buffer                 :: vulk.Host_Buffer
Buffer_Slice                :: vulk.Buffer_Slice
_create_buffer              :: vulk.create_buffer
_create_host_buffer         :: vulk.create_host_buffer
_slice_buffer               :: vulk.make_slice
_copy_buffer                :: vulk.copy_buffer_data
_destroy_buffer             :: vulk.destroy_buffer
_destroy_host_buffer        :: vulk.destroy_host_buffer

Image                       :: vulk.Render_Image
_create_image               :: vulk.create_image
_destroy_image              :: vulk.destroy_image

QueueTypes                  :: vulk.QueueTypes
QueueFamily                 :: vulk.QueueFamily
_find_queue_family          :: vulk.find_queue_family_by_type
_find_queue_present         :: vulk.find_queue_family_present_support

Timeline                    :: vulk.Timeline
_create_timeline            :: vulk.init_timeline
_destroy_timeline           :: vulk.destroy_timeline
_get_ticks                  :: vulk.get_current_ticks
_tick                       :: vulk.tick

// need AcquireNextImage, PresentImage
