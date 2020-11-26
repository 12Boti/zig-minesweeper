#version 460 core
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 0) out vec2 f_uv;

layout(location = 1) uniform vec2 grid_pos;
layout(location = 2) uniform float size;

void main() {
    gl_Position = vec4(pos*size + grid_pos*size*2 + size, 0.0, 1.0);
    f_uv = uv;
}