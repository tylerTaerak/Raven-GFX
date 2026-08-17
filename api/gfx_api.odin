package api
import "shared:raven-gfx/core"

// This file contains all of the functions needed by Raven for calling out to Graphics APIs
// Actual implementations are found in API-specific files and libraries

create_instance :: proc() -> (Instance, bool) {
	return _create_instance()
}

destroy_instance :: proc(instance : Instance) {
	_destroy_instance(instance)
}

create_device :: proc(instance : Instance) -> (Device, bool) {
	return _create_device(instance)
}

destroy_device :: proc(device : Device) {
	_destroy_device(device)
}

device_wait_idle :: proc(device : Device) {
	_device_wait_idle(device)
}

create_swapchain :: proc(instance : Instance, device : Device, window : core.Window, $Frame_Count : int) -> (Swapchain(Frame_Count), bool) {
	return _create_swapchain(instance, device, window, Frame_Count)
}

destroy_swapchain :: proc(device : Device, swapchain : $T/Swapchain($N)) {
	_destroy_swapchain(device, swapchain)
}

create_command_buffers :: proc(
	device : Device,
	$Count : int,
	buffer_types : bit_set[core.Queue_Type]) -> (Command_Collection(Count), bool) {
	return _create_command_set(device, Count, buffer_types)
}

destroy_command_buffers :: proc(device : Device, commands : $T/Command_Collection($N)) {
	_destroy_command_set(device, commands)
}

begin_command_buffer :: proc(set : $T/Command_Collection($N), index : int) {
	_begin_command_buffer(set, index)
}

end_command_buffer :: proc(set : $T/Command_Collection($N), index : int) {
	_end_command_buffer(set, index)
}

submit_command_buffer :: proc(
	device : Device,
	cmd_set : $T/Command_Collection($N),
	buffer_index : int,
	sem_wait, sem_signal : Binary_Semaphore,
	fence_signal : Fence
	) {
	_submit_command_buffer(device, cmd_set, buffer_index, sem_wait, sem_signal, fence_signal)
}

reset_command_buffer :: proc(set : $T/Command_Collection($N), index : int) {
	_reset_command_buffer(set, index)
}

acquire_next_swapchain_image_index :: proc(device : Device, swapchain : ^$T/Swapchain($N), wait : Fence, signal : Binary_Semaphore) -> (Image, u32, bool){
	return _acquire_swapchain_image(device, swapchain, wait, signal)
}

present_image :: proc(device : Device, swapchain : ^$T/Swapchain($N), index : int, wait : Binary_Semaphore) -> bool {
	return _present_image(device, swapchain, u32(index), wait)
}

create_fence :: proc(device : Device) -> (Fence) {
	return _create_fence(device)
}

destroy_fence :: proc(device : Device, fence : Fence) {
	_destroy_fence(device, fence)
}

create_semaphore :: proc(device : Device) -> (Binary_Semaphore) {
	return _create_semaphore(device)
}

destroy_semaphore :: proc(device : Device, sem : Binary_Semaphore) {
	_destroy_semaphore(device, sem)
}

wait_for_fence :: proc(device : Device, fence : Fence) {
	_wait_for_fence(device, fence)
}

reset_fence :: proc(device : Device, fence : Fence) {
	_reset_fence(device, fence)
}

create_descriptor_sets :: proc() {
}

destroy_descriptor_sets :: proc() {
}

bind_descriptor_sets :: proc() {
}

create_shader :: proc() {
}

destroy_shader :: proc() {
}

bind_shader :: proc() {
}

create_image :: proc() {
}

destroy_image :: proc() {
}

// TODO)) I think we can do something a little more extensive than just this, but this
// will be a good stop-gap for now
// TODO)) on the other hand, it might be nice to limit the number of operations we can
// do with memory barriers - I'll have to think on that
prepare_image_render :: proc(cmd : $T/Command_Collection($N), index : int, image : Image) {
	_image_barrier_render(cmd, index, image)
}

prepare_image_present :: proc(cmd : $T/Command_Collection($N), index : int, image : Image) {
	_image_barrier_present(cmd, index, image)
}

bind_image :: proc() {
}
