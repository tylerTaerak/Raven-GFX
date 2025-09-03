package game_vulkan

import "../core"
import "core:mem"
import vk "vendor:vulkan"

// this is just a vulkan wrapper for the core.Camera object,
// Each of these buffers just contains one Mat4 for each
// matrix
Camera :: struct {
    data_buffer : Buffer,
    projection  : Buffer_Slice,
    view        : Buffer_Slice
}

create_camera :: proc(ctx: ^Context) -> (cam : Camera) {
    q_family, _ := find_queue_family_by_type(ctx, {.GRAPHICS, .COMPUTE})
    cam.data_buffer = create_buffer(ctx, 2 * size_of(matrix[4,4]f32), {q_family^}, {.UNIFORM_BUFFER, .TRANSFER_DST})
    cam.projection = Buffer_Slice{
        buffer = &cam.data_buffer,
        offset = 0,
        size = size_of(matrix[4,4]f32)
    }

    cam.view = Buffer_Slice{
        buffer = &cam.data_buffer,
        offset = size_of(matrix[4,4]f32),
        size = size_of(matrix[4,4]f32)
    }
    return
}

set_camera_data :: proc(ctx: ^Context, cam : ^Camera, core_cam : core.Camera) {
    proj_data := core_cam.projection
    view_data := core_cam.view

    cam_data : []matrix[4,4]f32 = {proj_data, view_data}

    mem.copy(cam.data_buffer.host_data, &cam_data[0], size_of(matrix[4,4]f32) * len(cam_data))

    push(&ctx.job_queue, Transfer_Job{
        src_buffer = Raw_Buffer_Slice{
            buffer  = cam.data_buffer.staging_buffer,
            offset  = 0,
            size    = vk.DeviceSize(size_of(matrix[4,4]f32) * len(cam_data))
        },
        dest_buffer = Raw_Buffer_Slice{
            buffer  = cam.data_buffer.buf,
            offset  = 0,
            size    = vk.DeviceSize(size_of(matrix[4,4]f32) * len(cam_data))
        }
    })
}

destroy_camera :: proc(ctx: ^Context, cam : ^Camera) {
    destroy_buffer(ctx, cam.data_buffer)
}
