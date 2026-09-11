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

create_image :: proc(device : Device, size : [2]u32, format : core.Image_Format) -> (Image, bool) {
	return _create_image(device, size, format)
}

destroy_image :: proc(device : Device, img : ^Image) {
	_destroy_image(device, img)
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

cmd_transition_image_usage :: proc(
	cmd : $T/Command_Collection($N),
	index : int,
	image : Image,
	old, new : core.Image_Usage) {
}

bind_image :: proc() {
}

create_host_buffer :: proc(device : Device, size : int) -> (Buffer(.HOST), bool) {
	return _create_host_buffer(device, size)
}

create_device_buffer :: proc(device : Device, size : int) -> (Buffer(.DEVICE), bool) {
	return _create_device_buffer(device, size)
}

destroy_buffer :: proc(device : Device, buffer : $T/Buffer($L)) {
	_destroy_buffer(device, buffer)
}

copy_buffer :: proc(
	cmd_set : $T/Command_Collection($N),
	index : int,
	dst : $Q/Buffer($L),
	src : $R/Buffer($E)) {
	_copy_buffer(cmd_set, index, dst, src)
}

copy_buffer_to_image :: proc(
	 cmd_set : $T/Command_Collection($N),
	 index : int,
	 dst : Image,
	 src : $E/Buffer($L)) {
	_copy_buffer_image(cmd_set, index, dst, src)
}

host_pointer :: proc(buffer : Buffer(.HOST)) -> rawptr {
	return _host_pointer(buffer)
}

create_shader_schema :: proc(device : Device, parameters : []Shader_Element) -> (Shader_Schema, bool) {
	return _create_descriptor_layout(device, parameters)
}

destroy_shader_schema :: proc(device : Device, schema : Shader_Schema) {
	_destroy_descriptor_layout(device, schema)
}

write_shader_data :: proc(device : Device, data : Shader_Data, field_name : string, write : $T/Buffer($L)) {
}

create_shader :: proc(device : Device, data : []byte, cfg : ^Shader_Config) -> (Shader, bool) {
	return _create_shader(device, data, cfg)
}

destroy_shader :: proc(device : Device, shader : Shader) {
	_destroy_shader(device, shader)
}

bind_shader :: proc(
	device : Device,
	cmd : $T/Command_Collection($N),
	index : int,
	shaders : [core.Shader_Stage]Shader,
	data : []Shader_Data) {
	_bind_shader(device, cmd, index, shaders, data)
}

unbind_shader :: proc(
	cmd : $T/Command_Collection($N),
	index : int,
	shader : [core.Shader_Stage]Shader) {
	_unbind_shader(cmd, index, shaders)
}

