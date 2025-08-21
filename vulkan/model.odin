package game_vulkan

Vertex :: struct {
    position    : [3]f32,
    uv          : [2]f32,
    color       : [4]f32,
    normal      : [3]f32
}

Model :: struct {
    vertex_count    : u32,
    pose            : matrix[4, 4]f32
}

Draw_Data :: struct {
    vertices : #soa[dynamic]Vertex,
    instances : #soa[dynamic]Model
}
