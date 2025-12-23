package game_vulkan

import "../core"
import vk "vendor:vulkan"

_to_vk_descriptor_type :: proc(type: core.Descriptor_Type) -> vk.DescriptorType {
    switch (type) {
        case .STORAGE:
            return .STORAGE_BUFFER
        case .UNIFORM:
            return .UNIFORM_BUFFER
    }

    return .STORAGE_BUFFER
}

_to_vk_image_format :: proc(fmt: core.Image_Format) -> vk.Format {
    switch (fmt) {
        case .RGBA8_UNORM:
            return .R8G8B8A8_UNORM
        case .RGBA8_SRGB:
            return .R8G8B8A8_SRGB
        case .RGBA16_FLOAT:
            return .R16G16B16A16_SFLOAT
        case .INT8:
            return .R8_UINT
        case .INT32:
            return .R32_UINT
        case .SHORT_U8:
            return .R8_UINT
        case .DEPTH32_FLOAT:
            return .D32_SFLOAT
        case .DEPTH24_STENCIL8:
            return .D24_UNORM_S8_UINT
    }

    return .R8G8B8A8_UNORM
}

_to_vk_image_aspect :: proc(usage: core.Image_Usage) -> vk.ImageAspectFlags {
    switch (usage) {
        case .Color:
            return {.COLOR}
        case .Depth:
            return {.DEPTH}
        case .Stencil:
            return {.STENCIL}
        case .Depth_And_Stencil:
            return {.DEPTH, .STENCIL}
            
    }

    return {.COLOR}
}

_to_vk_topology :: proc(top: core.Topology_Primitive) -> vk.PrimitiveTopology {
    switch (top) {
        case .NONE:
        case .TRIANGLE_LIST:
            return .TRIANGLE_LIST
    }

    return .TRIANGLE_LIST
}

_to_vk_front_face :: proc(face: core.Front_Face) -> vk.FrontFace {
    switch (face) {
        case .NONE:
        case .COUNTERCLOCKWISE:
            return .COUNTER_CLOCKWISE
        case .CLOCKWISE:
            return .CLOCKWISE
    }

    return .COUNTER_CLOCKWISE
}

_to_vk_cull_mode :: proc(mode: core.Cull_Mode) -> vk.CullModeFlag {
    switch (mode) {
        case .NONE:
        case .BACK:
            return .BACK
        case .FRONT:
            return .FRONT
    }

    return .BACK
}

_to_vk_compare_op :: proc(op: core.Compare_Operation) -> vk.CompareOp {
    switch (op) {
        case .NONE:
        case .LESS:
            return .LESS
        case .EQUAL:
            return .EQUAL
        case .LEQUAL:
            return .LESS_OR_EQUAL
        case .GREATER:
            return .GREATER
        case .NOT_EQUAL:
            return .NOT_EQUAL
        case .GEQUAL:
            return .GREATER_OR_EQUAL
        case .ALWAYS:
            return .ALWAYS
    }

    return .LESS
}

_to_vk_stencil_op :: proc(op: core.Stencil_Operation) -> vk.StencilOp {
    switch (op) {
        case .NONE:
        case .ZERO:
            return .ZERO
        case .KEEP:
            return .KEEP
        case .REPLACE:
            return .REPLACE
        case .INCREMENT_CLAMP:
            return .INCREMENT_AND_CLAMP
        case .DECREMENT_CLAMP:
            return .DECREMENT_AND_CLAMP
        case .INVERT:
            return .INVERT
        case .INCREMENT_WRAP:
            return .INCREMENT_AND_WRAP
        case .DECREMENT_WRAP:
            return .DECREMENT_AND_WRAP
    }

    return .ZERO
}

_to_vk_blend_op :: proc(op: core.Blend_Operation) -> vk.BlendOp {
    switch (op) {
        case .NONE:
        case .ADD:
            return .ADD
        case .SUBTRACT:
            return .SUBTRACT
        case .REVERSE_SUBTRACT:
            return .REVERSE_SUBTRACT
        case .MIN:
            return .MIN
        case .MAX:
            return .MAX
    }

    return .ADD
}
