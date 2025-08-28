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

BUFFER_SIZE :: 1_048_576 // 1 MiB
DEFAULT_INSTANCE_COUNT :: 10

Material :: struct {
}

Material_Handle :: distinct u32

// I don't know if we actually need a struct for an instance
Instance :: struct {
    model_matrix : matrix[4, 4]f32
}

// Primitives do not come and go, so we just need an offset and count
Primitive :: struct {
    indices         : Buffer_Slice,
    vertex_count    : u32,
    descriptors     : [core.Descriptor_Type]Buffer_Slice,
    instances       : [dynamic]Instance
}

Mesh :: struct {
    primitives  : []Primitive,
}

Mesh_Handle :: distinct u32

Data :: struct {
    index_buffer : Buffer,
    vertex_descriptors : [core.Descriptor_Type]Buffer,
    instance_descriptor : Buffer,

    meshes : [dynamic]Mesh,

    draw_commands : [dynamic]vk.DrawIndexedIndirectCommand
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

        primitive.vertex_count = p.vertex_count

        mesh.primitives[i] = primitive
    }

    append(&ctx.data.meshes, mesh)

    return Mesh_Handle(len(ctx.data.meshes)-1)
}

draw_mesh :: proc(ctx: ^Context, mesh: Mesh_Handle, transform: matrix[4,4]f32) {
    local_mesh := ctx.data.meshes[mesh]

    for &prim in local_mesh.primitives {
        append(&prim.instances, Instance{
            model_matrix=transform
        })
    }
}

commit_draws :: proc(ctx: ^Context) {
    start_idx, vertex_start_idx : int

    instances : [dynamic]Instance
    defer delete(instances)

    for &mesh in ctx.data.meshes {
        for &prim in mesh.primitives {
            if len(prim.instances) == 0 do continue
            append(&instances, ..prim.instances[:])
            clear(&prim.instances)

            cmd : vk.DrawIndexedIndirectCommand
            cmd.indexCount = u32(prim.indices.size)
            cmd.firstIndex = u32(prim.indices.offset)
            cmd.vertexOffset = i32(vertex_start_idx)
            cmd.firstInstance = u32(start_idx)
            cmd.instanceCount = u32(len(prim.instances))

            // these draw commands get cleared out after 
            append(&ctx.data.draw_commands, cmd)

            start_idx += len(prim.instances)
            vertex_start_idx += int(prim.vertex_count)
        }
    }

    mem.copy(ctx.data.instance_descriptor.host_data, raw_data(instances), size_of(Instance) * len(instances))

    push(&ctx.job_queue, Transfer_Job{
        src_buffer = Raw_Buffer_Slice{
            buffer = ctx.data.instance_descriptor.staging_buffer,
            offset = 0,
            size   = vk.DeviceSize(size_of(Instance) * len(instances))
        },
        dest_buffer = Raw_Buffer_Slice{
            buffer = ctx.data.instance_descriptor.buf,
            offset = 0,
            size   = vk.DeviceSize(size_of(Instance) * len(instances))
        }
    })
}

load_material :: proc(ctx: ^Context) -> Material_Handle {
    // TODO)) Not yet implemented
    return 0
}

delete_data :: proc(ctx: ^Context) {
    destroy_buffer(ctx, ctx.data.instance_descriptor)
    destroy_buffer(ctx, ctx.data.index_buffer)

    for i in core.Descriptor_Type {
        destroy_buffer(ctx, ctx.data.vertex_descriptors[i])
    }

    delete(ctx.data.meshes)
}
