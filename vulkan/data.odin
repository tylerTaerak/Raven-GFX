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
    index_offset    : u32,
    index_count     : u32,
}

Primitive_Handle :: distinct u32

// instances come and go, so we need to leave some room for deletion there,
// with the assumption that we may re-add instances later
Mesh :: struct {
    primitives_offset   : u32,
    primitives_count    : u32,
    instance_offset     : u32,
    instance_count      : u32,
    instance_capacity   : u32
}

Mesh_Handle :: distinct u32

Data :: struct {
    index_buffer : vk.Buffer,
    vertex_descriptors : [core.Descriptor_Type]vk.Buffer,
    instance_descriptor : vk.Buffer,
    staging_buffer : vk.Buffer,
    staging_memory : vk.DeviceMemory,
    staging_ptr    : rawptr,

    meshes : [dynamic]Mesh,
    primitives : [dynamic]Primitive,
    // instances : [dynamic]Instance
}

init_data :: proc(ctx: ^Context) {
    // make sure that we can actually find a queue like this
    t_fam, tok := find_queue_family_by_type(ctx, {.GRAPHICS, .TRANSFER})

    idx_buf_ci : vk.BufferCreateInfo
    idx_buf_ci.sType = .BUFFER_CREATE_INFO
    idx_buf_ci.size = BUFFER_SIZE
    idx_buf_ci.usage = {.STORAGE_BUFFER, .TRANSFER_DST}
    idx_buf_ci.sharingMode = .EXCLUSIVE
    idx_buf_ci.queueFamilyIndexCount = 1
    idx_buf_ci.pQueueFamilyIndices = &t_fam.family_idx

    vk.CreateBuffer(ctx.device.logical, &idx_buf_ci, {}, &ctx.data.index_buffer)

    for i in core.Descriptor_Type {
        desc_buf_ci := idx_buf_ci

        vk.CreateBuffer(ctx.device.logical, &desc_buf_ci, {}, &ctx.data.vertex_descriptors[i])
    }

    inst_buf_ci := idx_buf_ci
    vk.CreateBuffer(ctx.device.logical, &inst_buf_ci, {}, &ctx.data.instance_descriptor)

    stag_buf_ci := idx_buf_ci
    vk.CreateBuffer(ctx.device.logical, &stag_buf_ci, {}, &ctx.data.staging_buffer)

    phys_mem_props : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(ctx.device.physical, &phys_mem_props)

    mem_index : u32
    for i in 0..<phys_mem_props.memoryTypeCount {
        mem_type := phys_mem_props.memoryTypes[i]
        if .HOST_VISIBLE in mem_type.propertyFlags && .HOST_COHERENT in mem_type.propertyFlags {
            mem_index = i
        }
    }

    mem_req : vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.device.logical, ctx.data.staging_buffer, &mem_req)

    mem_alloc_info : vk.MemoryAllocateInfo
    mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
    mem_alloc_info.allocationSize = mem_req.size
    mem_alloc_info.memoryTypeIndex = mem_index

    res := vk.AllocateMemory(ctx.device.logical, &mem_alloc_info, {}, &ctx.data.staging_memory)

    res = vk.BindBufferMemory(ctx.device.logical, ctx.data.staging_buffer, ctx.data.staging_memory, 0)

    vk.MapMemory(ctx.device.logical, ctx.data.staging_memory, 0, mem_req.size, {}, &ctx.data.staging_ptr)
}

load_mesh :: proc(ctx: ^Context, mesh_data: core.Model_Data, initial_instance_count : u32 = DEFAULT_INSTANCE_COUNT) -> Mesh_Handle {
    // Load Mesh Data
    mesh : Mesh
    mesh.primitives_count = u32(len(mesh_data.primitives))
    
    current_mesh_count := len(ctx.data.meshes)
    if current_mesh_count != 0 {
        last_mesh := ctx.data.meshes[current_mesh_count-1]
        mesh.primitives_offset = last_mesh.primitives_offset + last_mesh.primitives_count
        mesh.instance_offset = last_mesh.instance_offset + last_mesh.instance_capacity
    }

    mesh.instance_count = initial_instance_count

    append(&ctx.data.meshes, mesh)

    mesh_idx := Mesh_Handle(len(ctx.data.meshes) - 1)

    // Load Primitives Data
    for &primitive in mesh_data.primitives {
        current_primitives := len(ctx.data.primitives)

        new_prim : Primitive
        new_prim.index_count = u32(len(primitive.indices))
        if current_primitives != 0 {
            last_primitive := ctx.data.primitives[current_primitives-1]
            new_prim.index_offset = last_primitive.index_offset + last_primitive.index_count
        }

        append(&ctx.data.primitives, new_prim)

        // Now load the byte data

        for t in core.Descriptor_Type {
            buf : vk.Buffer

            q_fam, _ := find_queue_family_by_type(ctx, {.TRANSFER})

            buf_create_info : vk.BufferCreateInfo
            buf_create_info.sType = .BUFFER_CREATE_INFO
            buf_create_info.size = vk.DeviceSize(len(primitive.descriptor_data[t]))
            buf_create_info.usage = {.TRANSFER_SRC}
            buf_create_info.queueFamilyIndexCount = 1
            buf_create_info.pQueueFamilyIndices = &q_fam.family_idx
            buf_create_info.sharingMode = .EXCLUSIVE

            vk.CreateBuffer(ctx.device.logical, &buf_create_info, {}, &buf)
            defer vk.DestroyBuffer(ctx.device.logical, buf, {})

            mem_req : vk.MemoryRequirements
            vk.GetBufferMemoryRequirements(ctx.device.logical, buf, &mem_req)

            phys_mem_props : vk.PhysicalDeviceMemoryProperties
            vk.GetPhysicalDeviceMemoryProperties(ctx.device.physical, &phys_mem_props)

            mem_index : u32
            for i in 0..<phys_mem_props.memoryTypeCount {
                mem_type := phys_mem_props.memoryTypes[i]
                if .HOST_VISIBLE in mem_type.propertyFlags && .HOST_COHERENT in mem_type.propertyFlags {
                    mem_index = i
                }
            }

            mem_alloc_info : vk.MemoryAllocateInfo
            mem_alloc_info.sType = .MEMORY_ALLOCATE_INFO
            mem_alloc_info.allocationSize = mem_req.size
            mem_alloc_info.memoryTypeIndex = mem_index

            mem_block : vk.DeviceMemory

            vk.AllocateMemory(ctx.device.logical, &mem_alloc_info, {}, &mem_block)

            data : rawptr
            vk.MapMemory(ctx.device.logical, mem_block, {}, vk.DeviceSize(len(primitive.descriptor_data[t])), {}, &data)

            mem.copy(data, raw_data(primitive.descriptor_data[t]), len(primitive.descriptor_data[t]))

            // TODO))  get starting offset for each descriptor type
        }
    }

    return mesh_idx
}

unload_mesh :: proc(ctx: ^Context, handle: Mesh_Handle) {
    // TODO))
}

load_material :: proc(ctx: ^Context) -> Material_Handle {
    // TODO)) Not yet implemented
    return 0
}

unload_material :: proc(ctx: ^Context, handle: Material_Handle) {
    // TODO))
}

create_graphics_object :: proc(ctx: ^Context, mesh: Mesh_Handle, model_matrix: matrix[4, 4]f32 = 1) -> Instance_Handle{
    // TODO))
    return 0
}

delete_graphics_object :: proc(ctx: ^Context, handle: Instance_Handle) {
    // TODO))
}

delete_data :: proc(ctx: ^Context) {
    vk.UnmapMemory(ctx.device.logical, ctx.data.staging_memory)
    vk.DestroyBuffer(ctx.device.logical, ctx.data.staging_buffer, {})
    vk.FreeMemory(ctx.device.logical, ctx.data.staging_memory, {})

    vk.DestroyBuffer(ctx.device.logical, ctx.data.index_buffer, {})
    for buf in ctx.data.vertex_descriptors {
        vk.DestroyBuffer(ctx.device.logical, buf, {})
    }
    vk.DestroyBuffer(ctx.device.logical, ctx.data.instance_descriptor, {})

    delete(ctx.data.meshes)
    delete(ctx.data.primitives)
    delete(ctx.data.instances)
}
