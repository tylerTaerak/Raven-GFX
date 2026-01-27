package core

import sdl "vendor:sdl3"

refresh_frame_events :: proc(window: ^Window) {
    clear(&window.frame_events)

    ev : sdl.Event

    for sdl.PollEvent(&ev) {
        append(&window.frame_events, ev)
    }
}

check_quit_event :: proc(window: Window) -> bool {
    for ev in window.frame_events {
        if ev.type == .QUIT do return true
    }

    return false
}

check_resize_event :: proc(window: Window) -> bool {
    for ev in window.frame_events {
        if ev.type == .WINDOW_RESIZED do return true
    }

    return false
}

manual_quit :: proc() -> bool {
    quit : sdl.Event
    quit.type = .QUIT
    quit.quit.type = .QUIT
    quit.quit.timestamp = sdl.GetTicksNS()

    return sdl.PushEvent(&quit)
}
