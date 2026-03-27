#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float rgbOffset;   // normalised UV offset (pixels / screen_width)
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv  = qt_TexCoord0;
    float off = ubuf.rgbOffset;

    float r = texture(source, uv + vec2( off, 0.0)).r;
    float g = texture(source, uv               ).g;
    float b = texture(source, uv - vec2( off, 0.0)).b;
    float a = texture(source, uv               ).a;

    fragColor = vec4(r, g, b, a) * ubuf.qt_Opacity;
}
