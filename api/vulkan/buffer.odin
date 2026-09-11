package game_vulkan

import vk "vendor:vulkan"

Buffer :: struct($Location: Allocation_Location) {
	vkbuf : vk.Buffer,
	size : int,
	memory : Allocation(Location)
}

create_buffer :: proc(
	device : Device,
	size : int,
	$Location : Allocation_Location,
	flags : vk.BufferUsageFlags,
	alignment : int = 1) -> (buf : Buffer(Location), ok : bool = true) {
	
	info : vk.BufferCreateInfo
	info.sType = .BUFFER_CREATE_INFO
	info.size = vk.DeviceSize(size)
	info.usage = flags

	if len(device.queues) < 2 {
		info.sharingMode = .EXCLUSIVE
	} else {
		info.sharingMode = .CONCURRENT
	}

	res := vk.CreateBuffer(device.core, &info, {}, &buf.vkbuf)

	if res != .SUCCESS {
		ok = false
		return
	}

	mem_reqs : vk.MemoryRequirements2

	mem_info : vk.BufferMemoryRequirementsInfo2
	mem_info.sType = .BUFFER_MEMORY_REQUIREMENTS_INFO_2
	mem_info.buffer = buf.vkbuf

	vk.GetBufferMemoryRequirements2(device.core, &mem_info, &mem_reqs)

	when Location == .HOST {
		buf.memory = memalloc(
			device,
			device.staging_memory,
			Allocation_Type.BUFFER,
			u32(mem_reqs.memoryRequirements.size),
			u32(max(int(mem_reqs.memoryRequirements.alignment), alignment))) or_return
	} else {
		buf.memory = memalloc(
			device,
			device.device_memory,
			Allocation_Type.BUFFER,
			u32(mem_reqs.memoryRequirements.size),
			u32(max(int(mem_reqs.memoryRequirements.alignment), alignment))) or_return
	}

	buf.size = size

	return
}

get_buffer_address :: proc(device : Device, buffer : $T/Buffer($L)) -> vk.DeviceAddress {
	info : vk.BufferDeviceAddressInfo
	info.sType = .BUFFER_DEVICE_ADDRESS_INFO
	info.buffer = buffer.vkbuf

	return vk.GetBufferDeviceAddress(device.core, &info)
}

copy_buffer :: proc(
	cmd : Command_Buffer,
	dst : $T/Buffer($L),
	src : $R/Buffer($E)) {

	copy_info : vk.BufferCopy
	copy_info.srcOffset = 0
	copy_info.dstOffset = 0
	copy_info.size = dst.memory.raw.size

	vk.CmdCopyBuffer(cmd, src.vkbuf, dst.vkbuf, 1, &copy_info)
}

copy_buffer_to_image :: proc(
	cmd : Command_Buffer,
	dst : Render_Image,
	src : $T/Buffer($L)) {
	copy_info : vk.BufferImageCopy
	copy_info.bufferOffset = 0
	copy_info.bufferRowLength = dst.size.x
	copy_info.bufferImageHeight = dst.size.y
	copy_info.imageOffset = {0, 0, 0}
	copy_info.imageExtent = {dst.size.x, dst.size.y, 0}
	copy_info.imageSubresource.mipLevel = 1
	copy_info.imageSubresource.layerCount = 1

	vk.CmdCopyBufferToImage(cmd, src, dst, .UNDEFINED, 1, &copy_info)
}

destroy_buffer :: proc(
	device : Device,
	buffer : ^$T/Buffer($L)) {
	memfree(&buffer.memory)
	vk.DestroyBuffer(device.core, buffer.vkbuf, {})
}
