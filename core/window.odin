package core

import sdl "vendor:sdl3"
import "core:strings"

Window :: struct {
    window_ptr : ^sdl.Window,
    w, h : int,
    title : string
}

WindowCreateFlags :: sdl.WindowFlags
WindowCreateFlag :: sdl.WindowFlag


create_window :: proc(title : string, w, h : int, flags: WindowCreateFlags) -> (window : Window) {
    window.w = w
    window.h = h
    window.title = title

    window.window_ptr = sdl.CreateWindow(strings.clone_to_cstring(title), i32(w), i32(h), flags)
    return
}

update_window_data :: proc(window : ^Window, title : string, w, h : int) {
    if title != window.title{
        sdl.SetWindowTitle(window.window_ptr, strings.clone_to_cstring(title))
        window.title = title
    }

    if w != window.w || h != window.h{
        sdl.SetWindowSize(window.window_ptr, i32(w), i32(h))
        window.w = w
        window.h = h
    }

}

destroy_window :: proc(window: ^Window) {
    sdl.DestroyWindow(window.window_ptr)
}
