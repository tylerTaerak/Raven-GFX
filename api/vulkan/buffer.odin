package game_vulkan

import vk "vendor:vulkan"

Buffer :: vk.Buffer

create_buffer :: proc(
	device : Device,
	size : int,
	flags : vk.BufferUsageFlags) -> (buf : Buffer, ok : bool = true) {
	
	info : vk.BufferCreateInfo
	info.sType = .BUFFER_CREATE_INFO
	info.size = vk.DeviceSize(size)
	info.usage = flags

	if len(device.queues) < 2 {
		info.sharingMode = .EXCLUSIVE
	} else {
		info.sharingMode = .CONCURRENT
	}

	res := vk.CreateBuffer(device.core, &info, {}, &buf)

	ok = res == .SUCCESS

	return
}

destroy_buffer :: proc(
	device : Device,
	buffer : Buffer) {
	vk.DestroyBuffer(device.core, buffer, {})
}
