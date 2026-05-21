#version 330 core

uniform sampler2D gtexture;
uniform sampler2D lightmap;

in vec2 texCoord;
in vec4 vertColor;
in vec2 lightCoord;

out vec4 fragColor;

void main() {
    vec4 col = texture(gtexture, texCoord) * vertColor;
    col.rgb  *= texture(lightmap, lightCoord / 256.0).rgb;
    if (col.a < 0.1) discard;
    fragColor = col;
}
