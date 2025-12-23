package core

Descriptor_Data_Type :: enum {
    POSITION,
    TEXCOORD,
    COLOR,
    NORMAL,
    TANGENT
}

Descriptor_Type :: enum {
    STORAGE,
    UNIFORM
}

Image_Format :: enum {
    RGBA8_UNORM,        // 4 x 8-bit unsigned normmalized float
    RGBA8_SRGB,         // 4 x 8-bit sRGB
    RGBA16_FLOAT,       // 4 x 16 bit float (HDR)
    INT8,               // 1 x 8-bit float
    INT32,              // 1 x 32-bit float
    SHORT_U8,           // 1 x 8-bit unsigned int
    DEPTH32_FLOAT,      // 1 x 32-bit depth float
    DEPTH24_STENCIL8    // 1 x 24-bit depth float + 1 x 8-bit stencil float
}

Image_Usage :: enum {
    Color,
    Depth,
    Stencil,
    Depth_And_Stencil
}

Topology_Primitive :: enum {
    NONE,
    TRIANGLE_LIST
}

Front_Face :: enum {
    NONE,
    CLOCKWISE,
    COUNTERCLOCKWISE
}

Cull_Mode :: enum {
    NONE,
    BACK,
    FRONT
}

Compare_Operation :: enum {
    NONE,
    LESS,
    EQUAL,
    LEQUAL,
    GREATER,
    NOT_EQUAL,
    GEQUAL,
    ALWAYS
}

Stencil_Operation :: enum {
    NONE,
    KEEP,
    ZERO,
    REPLACE,
    INCREMENT_CLAMP,
    DECREMENT_CLAMP,
    INVERT,
    INCREMENT_WRAP,
    DECREMENT_WRAP
}

Blend_Operation :: enum {
    NONE,
    ADD,
    SUBTRACT,
    REVERSE_SUBTRACT,
    MIN,
    MAX
}
