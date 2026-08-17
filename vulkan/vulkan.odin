package game_vulkan

import vk "vendor:vulkan"
import "core:log"

acquire_next_image_and_index :: proc(
	device : Device,
	swapchain: ^$S/Swapchain($N),
	wait: Fence,
	signal: Semaphore) -> (image : Render_Image, index: u32, ok : bool = true) {
    res := vk.AcquireNextImageKHR(device.core, swapchain.chain, 500, signal, wait, &index)

    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
        log.info("Recreating swapchain")
        //ok = recreate_swapchain(ctx, swapchain)
		// TODO)) See below
    } else if res != .SUCCESS {
        // log.error("Error acquiring next swapchain image:", res)
        ok = false
    }

	if ok {
		image = swapchain.render_images[index]
		// log.info(swapchain)
	}

    return
}

present_image :: proc(device : Device, swapchain: ^$S/Swapchain($N), index: u32, wait_sem : Semaphore) -> (ok : bool = true) {
	index := index

    queue_fam := find_queue_family_present_support(device, device.queues, swapchain.surface) or_return

    queue : vk.Queue
    vk.GetDeviceQueue(device.core, u32(queue_fam), 0, &queue)

    info : vk.PresentInfoKHR
    info.sType = .PRESENT_INFO_KHR
    info.swapchainCount = 1
    info.pSwapchains = &swapchain.chain
    info.pImageIndices = &index
    info.waitSemaphoreCount = 1

	wait_sem := wait_sem
    info.pWaitSemaphores = &wait_sem

    res := vk.QueuePresentKHR(queue, &info)

    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR {
        log.info("recreating swapchain")
        // ok = recreate_swapchain(device, swapchain)
		// TODO)) We need an updated window width and height for this function,
		// but we don't really have a way to get one here
		// We should probably return an error enum, with one of the values indicating
		// that we need to resize, then the client would take care of that
    } else if res != .SUCCESS {
        log.error("Error Presenting Queue: ", res)
        ok = false
    }

    return
}

wait_for_idle :: proc(device : Device) {
    vk.DeviceWaitIdle(device.core)
}
