#version 430 compatibility

uniform sampler2D colortex0;

in vec2 uv;

void main() {
    gl_FragColor = texture(colortex0, uv);
}
