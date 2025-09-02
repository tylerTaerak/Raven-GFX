#version 460

layout(std430, set = 0, binding = 0) readonly buffer position_buffer {
    vec4 positions[];
};

layout(std430, set = 0, binding = 1) readonly buffer texcoord_buffer {
    vec2 uvs[];
};

layout(std430, set = 0, binding = 2) readonly buffer color_buffer {
    vec4 colors[];
};

layout(std430, set = 0, binding = 3) readonly buffer normal_buffer {
    vec3 normals[];
};

layout(std430, set = 0, binding = 4) readonly buffer tangent_buffer {
    vec3 tangents[];
};

layout(std430, set = 0, binding = 5) readonly buffer instance_buffer {
    mat4 model_matrices[];
};

layout(std140, set = 0, binding = 6) readonly uniform camera {
    mat4 projection;
    mat4 view;
};

layout(location = 0) out vec4 fragColor;

void main() {
    mat4 instance_transform = model_matrices[gl_InstanceIndex];
    vec4 position = positions[gl_VertexIndex];

    vec4 worldPosition = instance_transform * position;
    vec4 viewPosition = view * worldPosition;
    gl_Position = projection * viewPosition;

    fragColor = colors[gl_VertexIndex];
}
