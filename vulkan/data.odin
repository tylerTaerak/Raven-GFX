package game_vulkan

import "core:mem"
import "core:log"
import vk "vendor:vulkan"
import "../core"

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
    index_buffer        : Buffer,
    vertex_buffers      : [core.Descriptor_Type]Buffer,
    instance_buffer     : Buffer,

    meshes              : [dynamic]Mesh,

    camera              : Camera,

    draw_commands       : Buffer
}

init_data :: proc(ctx: ^Context) {
    g_fam, tok := find_queue_family_by_type(ctx, {.GRAPHICS})

    for i in 0..<FRAMES_IN_FLIGHT {
        ctx.data[i].index_buffer = create_buffer(ctx, BUFFER_SIZE, {g_fam^}, {.INDEX_BUFFER})

        for j in core.Descriptor_Type {
            ctx.data[i].vertex_buffers[j] = create_buffer(ctx, BUFFER_SIZE, {g_fam^})
        }

        ctx.data[i].instance_buffer = create_buffer(ctx, BUFFER_SIZE, {g_fam^})

        ctx.data[i].draw_commands = create_buffer(ctx, BUFFER_SIZE, {g_fam^})
    }
}

initialize_descriptor_sets :: proc(ctx: ^Context) {
    pool_sizes : []vk.DescriptorPoolSize = {
        {
            // vertex descriptors
            type = .STORAGE_BUFFER,
            descriptorCount = u32(len(core.Descriptor_Type)) * FRAMES_IN_FLIGHT
        },
        {
            // instance descriptor
            type = .STORAGE_BUFFER,
            descriptorCount = 1 * FRAMES_IN_FLIGHT
        },
        {
            // camera uniform
            type = .UNIFORM_BUFFER,
            descriptorCount = 1 * FRAMES_IN_FLIGHT
        }
    }


    pool_create_info : vk.DescriptorPoolCreateInfo
    pool_create_info.sType = .DESCRIPTOR_POOL_CREATE_INFO
    pool_create_info.maxSets = FRAMES_IN_FLIGHT
    pool_create_info.poolSizeCount = u32(len(pool_sizes))
    pool_create_info.pPoolSizes = &pool_sizes[0]

    vk.CreateDescriptorPool(ctx.device.logical, &pool_create_info, {}, &ctx.descriptor_pool)

    for i in 0..<FRAMES_IN_FLIGHT {
        bindings : []vk.DescriptorSetLayoutBinding = {
            {
                // position
                binding = 0,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // texcoord
                binding = 1,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // color
                binding = 2,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // normal
                binding = 3,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // tangent
                binding = 4,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // model_matrices
                binding = 5,
                descriptorType = .STORAGE_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
            {
                // camera data
                binding = 6,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                stageFlags = {.VERTEX}
            },
        }

        create_info : vk.DescriptorSetLayoutCreateInfo
        create_info.sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        create_info.bindingCount = u32(len(bindings))
        create_info.pBindings = &bindings[0]

        layout : vk.DescriptorSetLayout
        vk.CreateDescriptorSetLayout(ctx.device.logical, &create_info, {}, &layout)

        ctx.descriptor_layouts[i] = layout
    }

    alloc_info : vk.DescriptorSetAllocateInfo
    alloc_info.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
    alloc_info.descriptorPool = ctx.descriptor_pool
    alloc_info.descriptorSetCount = FRAMES_IN_FLIGHT
    alloc_info.pSetLayouts = &ctx.descriptor_layouts[0]

    vk.AllocateDescriptorSets(ctx.device.logical, &alloc_info, &ctx.descriptor_sets[0])

    // point to buffer data for descriptors
    for i in 0..<FRAMES_IN_FLIGHT {
        position_info,
        texcoord_info,
        color_info,
        normal_info,
        tangent_info,
        transform_info,
        camera_info : vk.DescriptorBufferInfo

        buffer_infos : [7]vk.DescriptorBufferInfo = {
            {
                buffer    = ctx.data[i].vertex_buffers[.POSITION].buf,
                offset    = 0,
                range     = ctx.data[i].vertex_buffers[.POSITION].size,
            },
            {
                buffer    = ctx.data[i].vertex_buffers[.TEXCOORD].buf,
                offset    = 0,
                range     = ctx.data[i].vertex_buffers[.TEXCOORD].size,
            },
            {
                buffer       = ctx.data[i].vertex_buffers[.COLOR].buf,
                offset       = 0,
                range        = ctx.data[i].vertex_buffers[.COLOR].size,
            },
            {
                buffer      = ctx.data[i].vertex_buffers[.NORMAL].buf,
                offset      = 0,
                range       = ctx.data[i].vertex_buffers[.NORMAL].size,
            },
            {
                buffer     = ctx.data[i].vertex_buffers[.TANGENT].buf,
                offset     = 0,
                range      = ctx.data[i].vertex_buffers[.TANGENT].size,
            },
            {
                buffer   = ctx.data[i].instance_buffer.buf,
                offset   = 0,
                range    = ctx.data[i].instance_buffer.size,
            },
            {
                buffer      = ctx.data[i].camera.data_buffer.buf,
                offset      = 0,
                range       = ctx.data[i].camera.data_buffer.size,
            }
        }

        writes : [7]vk.WriteDescriptorSet

        for j in 0..<len(writes) {
            write_info : vk.WriteDescriptorSet
            write_info.sType = .WRITE_DESCRIPTOR_SET
            write_info.dstSet = ctx.descriptor_sets[i]
            write_info.dstBinding = u32(j)
            write_info.dstArrayElement = 0

            switch j {
                case 6:
                    write_info.descriptorType = .UNIFORM_BUFFER
                case:
                    write_info.descriptorType = .STORAGE_BUFFER
            }

            write_info.descriptorCount = 1
            write_info.pBufferInfo = &buffer_infos[j]

            writes[j] = write_info
        }

        vk.UpdateDescriptorSets(ctx.device.logical, u32(len(writes)), &writes[0], 0, {})
    }
}

load_mesh :: proc(ctx: ^Context, mesh_data: core.Model_Data, initial_instance_count : u32 = DEFAULT_INSTANCE_COUNT) -> Mesh_Handle {
    for i in 0..<FRAMES_IN_FLIGHT {
        // Load Mesh Data
        mesh : Mesh
        mesh.primitives = make([]Primitive, len(mesh_data.primitives))

        // Load Primitives Data
        for &p, i in mesh_data.primitives {
            primitive : Primitive

            start_idx : vk.DeviceSize
            for &m in ctx.data[i].meshes {
                for &prim in m.primitives {
                    idx := prim.indices.offset + prim.indices.size
                    if idx > start_idx {
                        start_idx = idx
                    }
                }
            }

            primitive.indices =  make_slice_from_size_and_offset(&ctx.data[i].index_buffer, vk.DeviceSize(start_idx), vk.DeviceSize(len(p.indices)))

            for descriptor in core.Descriptor_Type {
                start_idx = 0
                for &m in ctx.data[i].meshes {
                    for &prim in m.primitives {
                        idx := prim.descriptors[descriptor].offset + prim.descriptors[descriptor].size
                        if idx > start_idx {
                            start_idx = idx
                        }
                    }
                }

                primitive.descriptors[descriptor] = make_slice_from_size_and_offset(&ctx.data[i].vertex_buffers[descriptor], start_idx, vk.DeviceSize(len(p.descriptor_data[descriptor])))
            }

            primitive.vertex_count = p.vertex_count

            mesh.primitives[i] = primitive
        }

        append(&ctx.data[i].meshes, mesh)
    }

    return Mesh_Handle(len(ctx.data[0].meshes)-1)
}

draw_mesh :: proc(ctx: ^Context, mesh: Mesh_Handle, transform: matrix[4,4]f32) {
    local_mesh := ctx.data[ctx.frame_idx].meshes[mesh]

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

    draw_commands : [dynamic]vk.DrawIndexedIndirectCommand
    defer delete(draw_commands)

    for &mesh in ctx.data[ctx.frame_idx].meshes {
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

            append(&draw_commands, cmd)

            start_idx += len(prim.instances)
            vertex_start_idx += int(prim.vertex_count)
        }
    }


    mem.copy(ctx.data[ctx.frame_idx].instance_buffer.host_data, raw_data(instances), 4 * 4 * 4 * len(instances))

    push(&ctx.job_queue, Transfer_Job{
        src_buffer = Raw_Buffer_Slice{
            buffer = ctx.data[ctx.frame_idx].instance_buffer.staging_buffer,
            offset = 0,
            size   = vk.DeviceSize(size_of(Instance) * len(instances))
        },
        dest_buffer = Raw_Buffer_Slice{
            buffer = ctx.data[ctx.frame_idx].instance_buffer.buf,
            offset = 0,
            size   = vk.DeviceSize(size_of(Instance) * len(instances))
        }
    })

    log.info(len(draw_commands))

    mem.copy(ctx.data[ctx.frame_idx].draw_commands.host_data, raw_data(draw_commands), size_of(vk.DrawIndexedIndirectCommand) * len(draw_commands))

    push(&ctx.job_queue, Transfer_Job{
        src_buffer = Raw_Buffer_Slice{
            buffer = ctx.data[ctx.frame_idx].draw_commands.staging_buffer,
            offset = 0,
            size   = vk.DeviceSize(size_of(vk.DrawIndexedIndirectCommand) * len(draw_commands))
        },
        dest_buffer = {
            buffer = ctx.data[ctx.frame_idx].draw_commands.buf,
            offset = 0,
            size   = vk.DeviceSize(size_of(vk.DrawIndexedIndirectCommand) * len(draw_commands))
        }
    })
}

load_material :: proc(ctx: ^Context) -> Material_Handle {
    // TODO)) Not yet implemented
    return 0
}

delete_data :: proc(ctx: ^Context) {
    for i in 0..<FRAMES_IN_FLIGHT {
        destroy_buffer(ctx, ctx.data[i].instance_buffer)
        destroy_buffer(ctx, ctx.data[i].index_buffer)

        for t in core.Descriptor_Type {
            destroy_buffer(ctx, ctx.data[i].vertex_buffers[t])
        }

        delete(ctx.data[i].meshes)
    }
}
