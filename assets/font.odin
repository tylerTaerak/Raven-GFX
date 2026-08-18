package assets

import "shared:raven-gfx/api"
Font :: struct {
}

load_font_assets :: proc(
	device : api.Device,
	store : Asset_Store(Font),
	data : []byte) -> (font : []Font, ok : bool = true) {

	return
}
