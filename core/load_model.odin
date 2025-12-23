package core

import "core:strings"
import "core:mem"
import "core:os"
import "core:log"
import "core:math/linalg"
import "vendor:cgltf"

Model_Data :: struct {
    primitives : []Primitive_Data
}

Primitive_Data :: struct {
    indices : []u32,
    descriptor_data : [Descriptor_Data_Type][]byte,
    vertex_count : u32
    // material data too
}

load_models_from_file :: proc(filepath : string) -> (models: []Model_Data) {
    buffer, ok := os.read_entire_file_from_filename(filepath)
    models = load_models_from_bytes(buffer, filepath)
    return
}

load_models_from_bytes :: proc(bytes : []byte, filepath: string) -> (models: []Model_Data) {
    options : cgltf.options
    data, res := cgltf.parse(options, raw_data(bytes), len(bytes))

    if res != .success {
        log.error("Error loading gltf file")
        return
    }

    defer cgltf.free(data)

    res = cgltf.validate(data)

    if res != .success {
        log.error("Validation error in glTF")
    }

    res = cgltf.load_buffers({}, data, strings.clone_to_cstring(filepath))

    if res != .success {
        log.error("failed to load buffers")
    }

    models_local : [dynamic]Model_Data
    defer delete(models_local)

    for &mesh in data.meshes {
        primitives : [dynamic]Primitive_Data
        defer delete(primitives)

        for &primitive in mesh.primitives {
            // TODO)) Now we just need to handle materials for each subpass. This should be good for initial testing though

            vert_idx_data       : []byte

            descriptor_data : [Descriptor_Data_Type][]byte
            indices_acc := primitive.indices

            {
                byte_buffer := _make_bytes_from_accessor(indices_acc)
                defer delete(byte_buffer)

                vert_idx_data = make([]byte, len(byte_buffer))

                copy(vert_idx_data, byte_buffer)
            }

            vertex_count : u32
            for &attr in primitive.attributes {
                accessor := attr.data

                byte_buffer := _make_bytes_from_accessor(accessor)
                defer delete(byte_buffer)

                core_type : Descriptor_Data_Type

                #partial switch attr.type {
                    case .position:
                        core_type = .POSITION
                        vertex_count = u32(accessor.count)
                    case .texcoord:
                        core_type = .TEXCOORD
                    case .color:
                        core_type = .COLOR
                    case .normal:
                        core_type = .NORMAL
                    case .tangent:
                        core_type = .TANGENT
                }

                descriptor_data[core_type] = make([]byte, len(byte_buffer))
                copy(descriptor_data[core_type], byte_buffer)
            }

            // now we need to load the stuff into the GPU, I think having an externally defined loader proc should
            // be used to load the bytes

            primitive : Primitive_Data
            primitive.indices = _convert_bytes_to_u32s(vert_idx_data)
            primitive.descriptor_data = descriptor_data
            primitive.vertex_count = vertex_count

            append(&primitives, primitive)
        }

        model : Model_Data
        model.primitives = make([]Primitive_Data, len(primitives))
        copy(model.primitives, primitives[:])

        append(&models_local, model)
    }

    models = make([]Model_Data, len(models_local))
    copy(models, models_local[:])

    return
}

load_model :: proc {load_models_from_file, load_models_from_bytes}


@(private)
_make_bytes_from_accessor :: proc(acc : ^cgltf.accessor) -> (data : []byte) {
    component_size := cgltf.component_size(acc.component_type)
    num_components := cgltf.num_components(acc.type)

    temp_buffer := make([]byte, acc.buffer_view.buffer.size)
    defer delete(temp_buffer)
    
    log.infof("copying %d bytes to temp buffer", acc.buffer_view.buffer.size)
    log.info(len(temp_buffer))
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

    return
}

@(private)
_convert_bytes_to_u32s :: proc(bytes : []byte) -> (data : []u32) {
    assert(len(bytes) % 4 == 0)
    data = make([]u32, len(bytes) / 4)

    for i in 0..<len(data) {
        datum : u32
        subslice := bytes[i * 4:(i+1) * 4]

        datum = u32(subslice[0])
        datum |= u32(subslice[1]) << 8
        datum |= u32(subslice[2]) << 16
        datum |= u32(subslice[3]) << 24

        data[i] = datum
    }

    return
}
