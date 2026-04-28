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
    indices : []u16,
    descriptor_data : [Descriptor_Data_Type][]f32,
    vertex_count : u32
    // material data too
}

load_models_from_file :: proc(filepath : string) -> (models: []Model_Data) {
    buffer, _ := os.read_entire_file(filepath, context.temp_allocator)
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

            descriptor_data : [Descriptor_Data_Type][]f32
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
                log.info("Loading data for ", attr.type)
                log.info("byte stride: ", accessor.stride)

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

                float_data := _convert_bytes(byte_buffer, f32)
                float_data = _pad_to_vec4(float_data, int(cgltf.num_components(accessor.type)))

                log.info("Padded data:", float_data)

                descriptor_data[core_type] = float_data
            }

            // now we need to load the stuff into the GPU, I think having an externally defined loader proc should
            // be used to load the bytes

            primitive : Primitive_Data
            primitive.indices = _convert_bytes(vert_idx_data, u16)
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

@(private)
_convert_bytes_to_u16s :: proc(bytes : []byte) -> (data : []u16) {
    assert(len(bytes) % 2 == 0)
    data = make([]u16, len(bytes) / 2)

    for i in 0..<len(data) {
        datum : u16
        subslice := bytes[i * 2:(i+1) * 2]

        datum = u16(subslice[0])
        datum |= u16(subslice[1]) << 8

        data[i] = datum
    }

    return
}

@(private)
_convert_bytes :: proc(bytes : []byte, $T: typeid) -> (data : []T) {
    assert(len(bytes) % size_of(T) == 0)
    data = make([]T, len(bytes) / size_of(T))

    for i in 0..<len(data) {
        datum : T
        subslice := bytes[i * size_of(T):(i+1) * size_of(T)]

        mem.copy(&datum, raw_data(subslice), len(subslice))

        // for j in 0..<size_of(T) {
        //     datum |= T(subslice[u32(j)]) << u32(j * 8)
        // }

        data[i] = datum
    }

    return
}

/// NOTE: Consumes the original slice
@(private)
_pad_to_vec4 :: proc(elements : []f32, count_per_element : int) -> (padded : []f32) {
    assert(len(elements) % count_per_element == 0)

    count := len(elements) / count_per_element

    // we're turning everything into a vec4
    padded = make([]f32, count * 4)

    for i in 0..<count {
        padded_start := i * 4
        pre_start := i * count_per_element

        for j in 0..<4 {
            if j < count_per_element {
                padded[padded_start + j] = elements[pre_start + j]
            } else {
                padded[padded_start + j] = 1.0
            }
        }
    }

    delete(elements)

    return
}
