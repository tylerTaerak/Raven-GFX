#+build windows, linux, freebsd, openbsd, netbsd
#+private
package api

import "base:runtime"
import "core:strings"
import vmem "core:mem/virtual"
import vulk "./vulkan"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import gmem "shared:gpu-memory"
import "shared:raven-gfx/core"

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
    vk.EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME,
    vk.EXT_SHADER_OBJECT_EXTENSION_NAME,
    vk.KHR_MAINTENANCE_6_EXTENSION_NAME,
    vk.EXT_MESH_SHADER_EXTENSION_NAME,
    vk.EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
    vk.KHR_SHADER_UNTYPED_POINTERS_EXTENSION_NAME,
}

WINDOW_FLAGS : sdl.WindowFlags = {.VULKAN, .BORDERLESS}

_create_instance 			:: proc() -> (Instance, bool) {
	ext_count : u32
	sdl_ext := sdl.Vulkan_GetInstanceExtensions(&ext_count)

	extensions := make([]string, ext_count)
	defer delete(extensions)

	// dump all the strings together in an arena and destroy them together after initialization
	cstring_arena : vmem.Arena

	err := vmem.arena_init_growing(&cstring_arena)
	if err != .None {
		return {}, false
	}

	defer vmem.arena_free_all(&cstring_arena)

	arena_alloc := vmem.arena_allocator(&cstring_arena) 
	
	for i in 0..<ext_count {
		err : runtime.Allocator_Error
		extensions[i], err = strings.clone_from_cstring(sdl_ext[i], arena_alloc)

		if err != .None {
			return {}, false
		}
	}

	return vulk.create_vulkan_instance(extensions)
}
_destroy_instance 			:: vulk.destroy_instance

_create_device 				:: proc(instance : Instance) -> (Device, bool) {
	return vulk.create_device(instance, {.GRAPHICS, .COMPUTE, .TRANSFER}, REQUIRED_DEVICE_EXTENSIONS)
}

// TODO)) There should be a way to only pass in certain queues in per usage reqs
_allocate_gmem_device 			:: proc(device : Device) -> (gpu_dev : gmem.Device) {
	gpu_dev.logical = device.core
	gpu_dev.physical = device.physical


	gpu_dev.queue_family_indicies = make([]u32, len(device.queues))
	for i in 0..<len(device.queues) {
		gpu_dev.queue_family_indicies[i] = device.queues[i].family_idx
	}

	return
}

_free_gmem_device 			:: proc(gpu_dev : gmem.Device) {
	delete(gpu_dev.queue_family_indicies)
}

_destroy_device 			:: vulk.destroy_device

_device_wait_idle 			:: vulk.wait_for_idle

_create_swapchain           :: proc(instance : Instance, device : Device, window : core.Window, $Frame_Count : int) -> (sw : Swapchain(Frame_Count), ok : bool) {
	surface : vk.SurfaceKHR

	sdl.Vulkan_CreateSurface(window.window_ptr, instance.core, nil, &surface) or_return

	return vulk.create_swapchain(device, surface, u32(window.w), u32(window.h), Frame_Count, nil)
}

_destroy_swapchain          :: vulk.destroy_swapchain

_create_image               :: vulk.create_image
_destroy_image              :: vulk.destroy_image
_image_barrier_render 		:: proc(
	set : $T/Command_Collection($N),
	index : int,
	image : Image) {
	vulk.image_barrier(set.buffers[index], image, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL,
		{}, {.COLOR_ATTACHMENT_WRITE}, {}, {.COLOR_ATTACHMENT_OUTPUT_KHR})
}

_image_barrier_present 		:: proc(
	set : $T/Command_Collection($N),
	index : int,
	image : Image) {
	vulk.image_barrier(set.buffers[index], image, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_WRITE}, {}, {.COLOR_ATTACHMENT_OUTPUT_KHR}, {})
}

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

_create_command_set         :: proc(
	device : Device,
	$Count : int,
	types : vulk.QueueTypes) -> (cmd : Command_Collection(Count), ok : bool) {

	fam := vulk.find_queue_family_by_type(device.queues, types) or_return
	return vulk.create_command_set(device, Count, device.queues[fam])
}
_destroy_command_set        :: vulk.destroy_command_set

_begin_command_buffer       :: proc(set : $T/Command_Collection($N), index : int) {
	
	vulk.begin_command_buffer(set.buffers[index])
}
_end_command_buffer         :: proc(set : $T/Command_Collection($N), index : int) {

	vulk.end_command_buffer(set.buffers[index])
}
_submit_command_buffer      :: proc(device : Device, set : $T/Command_Collection($N),
	buffer_index : int, wait, signal : vulk.Semaphore, fence : vulk.Fence) {

	vulk.submit_command_buffer(device, set.buffers[buffer_index], set.family, wait, signal, fence)
}
_reset_command_buffer 		:: proc(set : $T/Command_Collection($N), index : int) {
	vulk.reset_command_buffer(set.buffers[index])
}

_acquire_swapchain_image    :: vulk.acquire_next_image_and_index
_present_image              :: vulk.present_image

_create_semaphore           :: vulk.init_semaphore
_destroy_semaphore          :: vulk.destroy_semaphore

_wait_for_idle              :: vulk.wait_for_idle
