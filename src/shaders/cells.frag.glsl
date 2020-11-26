#version 460 core
layout(location = 0) out vec4 FragColor;
layout(location = 0) in vec2 f_uv;

layout(location = 0) uniform sampler2DArray tex;
layout(location = 3) uniform uint tex_idx;

void main() {
    FragColor = texture(tex, vec3(f_uv, tex_idx));
}