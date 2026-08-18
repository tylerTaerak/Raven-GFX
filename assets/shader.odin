package assets

import "shared:raven-gfx/api"
Shader :: struct {
}

load_shader_assets :: proc(
	device : api.Device,
	store : Asset_Store(Shader),
	data : []byte) -> (shader : []Shader, ok : bool = true) {

	return
}
