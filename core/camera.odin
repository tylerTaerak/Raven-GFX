package core

import "core:math/linalg"

Camera :: struct {
    projection  : matrix[4,4]f32,
    view        : matrix[4,4]f32
}

create_perscpetive_camera :: proc(window : ^Window, fov, near, far: f32, initial_transform : matrix[4,4]f32 = 1) -> (cam : Camera) {
    assert(window.h > 0.0)
    aspect_ratio := f32(window.w) / f32(window.h)

    cam.projection  = linalg.matrix4_perspective(fov, aspect_ratio, near, far)
    cam.view        = linalg.inverse(initial_transform)
    return
}

create_ortho_camera :: proc(window : ^Window, near, far: f32, initial_transform : matrix[4,4]f32 = 1) -> (cam: Camera) {
    left : f32 = 0.0
    top : f32 = 0.0
    right := f32(window.w)
    bottom := f32(window.h)

    cam.projection  = linalg.matrix_ortho3d_f32(left, right, bottom, top, near, far)
    cam.view        = linalg.inverse(initial_transform)
    return
}

move_camera_transform :: proc(cam : ^Camera, transform : matrix[4,4]f32) {
    cam.view = linalg.inverse(transform)
}
