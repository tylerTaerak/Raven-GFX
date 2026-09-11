package assets

import "core:strings"
import "shared:raven-gfx/core"
import "vendor:cgltf"
import "shared:raven-gfx/api"
import "core:mem"
import "core:log"

Model_Primitive :: struct {
	indices : api.Buffer(.DEVICE),
	vertex_data : map[string]api.Buffer(.DEVICE)
}

Model :: struct {
	primitives : []Model_Primitive
}

load_model_data :: proc(
	device : api.Device,
	store : ^Asset_Store,
	data : []byte,
	filepath : string) -> (handles : []Model, ok : bool = true) {
	options : cgltf.options
	gltf, res := cgltf.parse(options, raw_data(data), len(data))

	if res != .success {
		ok = false
		return
	}

	defer cgltf.free(gltf)

	res = cgltf.validate(gltf)

	if res != .success {
		ok = false
		return
	}

	v_cstr := strings.clone_to_cstring(filepath)
	defer delete(v_cstr)

	res = cgltf.load_buffers({}, gltf, v_cstr)

	if res != .success {
		ok = false
		return
	}

	models : [dynamic]Model
	defer delete(models)

	for &mesh in gltf.meshes {
		model : Model
		model.primitives = make([]Model_Primitive, len(mesh.primitives))

		for &primitive, idx in mesh.primitives {
			new_prim : Model_Primitive

			indices_accessor := primitive.indices

			{
				buffer := _make_bytes_from_accessor(indices_accessor)
				defer delete(buffer)

				slice := make_host_buffer(device, store, len(buffer)) or_return

				mem.copy(api.host_pointer(slice), rawptr(&buffer[0]), len(buffer))

				new_prim.indices = api.create_device_buffer(device, len(buffer)) or_return

				api.copy_buffer(store.cmd_set, 0, new_prim.indices, slice)
			}

			for &attr, i in primitive.attributes {
				accessor := attr.data

				bytes := _make_bytes_from_accessor(accessor)
				defer delete(bytes)

				slice := make_host_buffer(device, store, len(bytes)) or_return

				mem.copy(api.host_pointer(slice), rawptr(&bytes[0]), len(bytes))

				vdata := api.create_device_buffer(device, len(bytes)) or_return

				api.copy_buffer(store.cmd_set, 0, vdata, slice)

				new_prim.vertex_data[core.GLTF_Strings[attr.type]] = vdata
			}

			model.primitives[idx] = new_prim
		}

		append(&models, model)
	}

	handles = models[:]

	return
}

@(private)
_make_bytes_from_accessor :: proc(acc : ^cgltf.accessor) -> (data : []byte) {
    component_size := cgltf.component_size(acc.component_type)
    num_components := cgltf.num_components(acc.type)

    temp_buffer := make([]byte, acc.buffer_view.buffer.size)
    defer delete(temp_buffer)
    
    mem.copy(raw_data(temp_buffer), acc.buffer_view.buffer.data, int(acc.buffer_view.buffer.size))

    view_data := temp_buffer[acc.buffer_view.offset:acc.buffer_view.offset + acc.buffer_view.size]

    acc_data := view_data[acc.offset:]

    element_size := num_components * component_size

    data = make([]byte, element_size * acc.count)

    for i in 0..<acc.count {
        stride : uint = acc.buffer_view.stride
        if stride == 0 {
            stride = acc.stride
        }

        curr_stride := i * stride

        byte_data := acc_data[curr_stride:curr_stride + element_size]

        copy(data[i * element_size:(i + 1) * element_size], byte_data)
    }

    log.infof("Wrote data of type %d * %d of size %d (%d elements)", num_components, component_size, len(data), acc.count)

    return
}

destroy_model :: proc(device : api.Device, store : ^Asset_Store, model : Model_Handle) {
	model_data := store.models[int(model)]

	for &p in model_data.primitives {
		api.destroy_buffer(device, p.indices)

		for k, v in p.vertex_data {
			api.destroy_buffer(device, v)
		}

		delete_map(p.vertex_data)
	}
}
