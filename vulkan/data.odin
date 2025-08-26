package game_vulkan

import "core:mem"
import vk "vendor:vulkan"
import "../core"

// This file contains data types and loading mechanisms for each of these types


// Data is a megastruct that contains all data objects for all loaded Vulkan objects
// See DescriptorSets for how to utilize SSBO's for storing data for everything we
// load in

/*

    DrawIndexedIndirectCommand :: struct {
        indexCount:    u32,
        instanceCount: u32,
        firstIndex:    u32,
        vertexOffset:  i32,
        firstInstance: u32,
    }

*/

// How are we going to handle instances in this setup? The vertex data has basically written itself,
// but instances are something that I intend to have change frame-by-frame (such as with the model matrix)
// So just having them in a descriptor or something like that, I'm not sure if that will work quite as well,
// especially in scenarios when entities are getting spawned and stuff like that... Maybe just a large buffer?

// So Instances are completely different from Assets. Each asset has a set of vertex data that applies to it,
// but each instance can differ. I'm thinking I'll kind of need to implement my own sort of GPU-based vector

// We also need a mapped staging buffer for instance data, since instances are something we want to assume
// can change often

BUFFER_SIZE :: 1_048_576 // 1 MiB
DEFAULT_INSTANCE_COUNT :: 10

Material :: struct {
}

Material_Handle :: distinct u32

// I don't know if we actually need a struct for an instance
// Instance :: struct {
// }

Instance_Handle :: distinct u32

// Primitives do not come and go, so we just need an offset and count
Primitive :: struct {
    indices     : Buffer_Slice,
    descriptors : [core.Descriptor_Type]Buffer_Slice,
}

Primitive_Handle :: distinct u32

// instances come and go, so we need to leave some room for deletion there,
// with the assumption that we may re-add instances later
Mesh :: struct {
    primitives  : []Primitive,
    instances   : Buffer_Slice,
    instance_count : u32
}

Mesh_Handle :: distinct u32

Data :: struct {
    index_buffer : Buffer,
    vertex_descriptors : [core.Descriptor_Type]Buffer,
    instance_descriptor : Buffer,

    meshes : [dynamic]Mesh,
    // instances : [dynamic]Instance
}

init_data :: proc(ctx: ^Context) {
    g_fam, tok := find_queue_family_by_type(ctx, {.GRAPHICS})

    ctx.data.index_buffer = create_buffer(ctx, BUFFER_SIZE, {g_fam^}, {.INDEX_BUFFER})

    for i in core.Descriptor_Type {
        ctx.data.vertex_descriptors[i] = create_buffer(ctx, BUFFER_SIZE, {g_fam^})
    }

    ctx.data.instance_descriptor = create_buffer(ctx, BUFFER_SIZE, {g_fam^})
}

load_mesh :: proc(ctx: ^Context, mesh_data: core.Model_Data, initial_instance_count : u32 = DEFAULT_INSTANCE_COUNT) -> Mesh_Handle {
    // Load Mesh Data
    mesh : Mesh
    mesh.primitives = make([]Primitive, len(mesh_data.primitives))

    // Load Primitives Data
    for &p, i in mesh_data.primitives {
        primitive : Primitive

        start_idx : vk.DeviceSize
        for &m in ctx.data.meshes {
            for &prim in m.primitives {
                idx := prim.indices.offset + prim.indices.size
                if idx > start_idx {
                    start_idx = idx
                }
            }
        }

        primitive.indices =  make_slice_from_size_and_offset(&ctx.data.index_buffer, vk.DeviceSize(start_idx), vk.DeviceSize(len(p.indices)))

        for descriptor in core.Descriptor_Type {
            start_idx = 0
            for &m in ctx.data.meshes {
                for &prim in m.primitives {
                    idx := prim.descriptors[descriptor].offset + prim.descriptors[descriptor].size
                    if idx > start_idx {
                        start_idx = idx
                    }
                }
            }

            primitive.descriptors[descriptor] = make_slice_from_size_and_offset(&ctx.data.vertex_descriptors[descriptor], start_idx, vk.DeviceSize(len(p.descriptor_data[descriptor])))
        }

        mesh.primitives[i] = primitive
    }

    start_idx : vk.DeviceSize
    for &m in ctx.data.meshes {
        idx := m.instances.offset + m.instances.size
        if idx > start_idx {
            start_idx = idx
        }
    }

    mesh.instances = make_slice_from_size_and_offset(&ctx.data.instance_descriptor, start_idx, vk.DeviceSize(initial_instance_count))

    append(&ctx.data.meshes, mesh)

    return Mesh_Handle(len(ctx.data.meshes)-1)
}

unload_mesh :: proc(ctx: ^Context, handle: Mesh_Handle) {
    // TODO)) This one is the trickier one
}

load_material :: proc(ctx: ^Context) -> Material_Handle {
    // TODO)) Not yet implemented
    return 0
}

unload_material :: proc(ctx: ^Context, handle: Material_Handle) {
    // TODO))
}

create_graphics_object :: proc(ctx: ^Context, mesh: Mesh_Handle, model_matrix: matrix[4, 4]f32 = 1) -> Instance_Handle{
    handle := ctx.data.meshes[mesh].instance_count
    ctx.data.meshes[mesh].instance_count += 1

    return Instance_Handle(handle)
}

delete_graphics_object :: proc(ctx: ^Context, handle: Instance_Handle) {
    // TODO)) This one is the trickier one
}

delete_data :: proc(ctx: ^Context) {
    destroy_buffer(ctx, ctx.data.instance_descriptor)
    destroy_buffer(ctx, ctx.data.index_buffer)

    for i in core.Descriptor_Type {
        destroy_buffer(ctx, ctx.data.vertex_descriptors[i])
    }

    delete(ctx.data.meshes)
}
