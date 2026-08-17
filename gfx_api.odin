package gfx
import "./core"

// This file contains all of the functions needed by Raven for calling out to Graphics APIs
// Actual implementations are found in API-specific files and libraries

api_create_instance :: proc() -> (API_Instance, bool) {
	return _create_instance()
}

api_destroy_instance :: proc(instance : API_Instance) {
	_destroy_instance(instance)
}

api_create_device :: proc(instance : API_Instance) -> (API_Device, bool) {
	return _create_device(instance)
}

api_destroy_device :: proc(device : API_Device) {
	_destroy_device(device)
}

api_device_wait_idle :: proc(device : API_Device) {
	_device_wait_idle(device)
}

api_create_swapchain :: proc(instance : API_Instance, device : API_Device, window : core.Window) -> (API_Swapchain(FRAMES_IN_FLIGHT), bool) {
	return _create_swapchain(instance, device, window)
}

api_destroy_swapchain :: proc(device : API_Device, swapchain : API_Swapchain(FRAMES_IN_FLIGHT)) {
	_destroy_swapchain(device, swapchain)
}

api_create_command_buffers :: proc(
	device : API_Device,
	$Count : int,
	buffer_types : bit_set[core.Queue_Type]) -> (API_Command_Collection(Count), bool) {
	return _create_command_set(device, Count, buffer_types)
}

api_destroy_command_buffers :: proc(device : API_Device, commands : $T/API_Command_Collection($N)) {
	_destroy_command_set(device, commands)
}

api_begin_command_buffer :: proc(set : $T/API_Command_Collection($N), index : int) {
	_begin_command_buffer(set, index)
}

api_end_command_buffer :: proc(set : $T/API_Command_Collection($N), index : int) {
	_end_command_buffer(set, index)
}

api_submit_command_buffer :: proc(
	device : API_Device,
	cmd_set : $T/API_Command_Collection($N),
	buffer_index : int,
	sem_wait, sem_signal : API_Binary_Semaphore,
	fence_signal : API_Fence
	) {
	_submit_command_buffer(device, cmd_set, buffer_index, sem_wait, sem_signal, fence_signal)
}

api_reset_command_buffer :: proc(set : $T/API_Command_Collection($N), index : int) {
	_reset_command_buffer(set, index)
}

api_acquire_next_swapchain_image_index :: proc(device : API_Device, swapchain : ^API_Swapchain(FRAMES_IN_FLIGHT), wait : API_Fence, signal : API_Binary_Semaphore) -> (API_Image, u32, bool){
	return _acquire_swapchain_image(device, swapchain, wait, signal)
}

api_present_image :: proc(device : API_Device, swapchain : ^API_Swapchain(FRAMES_IN_FLIGHT), index : int, wait : API_Binary_Semaphore) -> bool {
	return _present_image(device, swapchain, u32(index), wait)
}

api_create_fence :: proc(device : API_Device) -> (API_Fence) {
	return _create_fence(device)
}

api_destroy_fence :: proc(device : API_Device, fence : API_Fence) {
	_destroy_fence(device, fence)
}

api_create_semaphore :: proc(device : API_Device) -> (API_Binary_Semaphore) {
	return _create_semaphore(device)
}

api_destroy_semaphore :: proc(device : API_Device, sem : API_Binary_Semaphore) {
	_destroy_semaphore(device, sem)
}

api_wait_for_fence :: proc(device : API_Device, fence : API_Fence) {
	_wait_for_fence(device, fence)
}

api_reset_fence :: proc(device : API_Device, fence : API_Fence) {
	_reset_fence(device, fence)
}

api_create_descriptor_sets :: proc() {
}

api_destroy_descriptor_sets :: proc() {
}

api_bind_descriptor_sets :: proc() {
}

api_create_shader :: proc() {
}

api_destroy_shader :: proc() {
}

api_bind_shader :: proc() {
}

api_create_image :: proc() {
}

api_destroy_image :: proc() {
}

// TODO)) I think we can do something a little more extensive than just this, but this
// will be a good stop-gap for now
// TODO)) on the other hand, it might be nice to limit the number of operations we can
// do with memory barriers - I'll have to think on that
api_prepare_image_render :: proc(cmd : $T/API_Command_Collection($N), index : int, image : API_Image) {
	_image_barrier_render(cmd, index, image)
}

api_prepare_image_present :: proc(cmd : $T/API_Command_Collection($N), index : int, image : API_Image) {
	_image_barrier_present(cmd, index, image)
}

api_bind_image :: proc() {
}
