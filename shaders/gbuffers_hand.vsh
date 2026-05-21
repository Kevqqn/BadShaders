#version 330 core

in vec3 Position;
in vec2 UV0;
in vec4 Color;
in vec2 UV2;

uniform mat4 ModelViewMatrix;
uniform mat4 ProjMat;
uniform mat4 TextureMat;

out vec2 texCoord;
out vec4 vertColor;
out vec2 lightCoord;

void main() {
    gl_Position = ProjMat * ModelViewMatrix * vec4(Position, 1.0);
    texCoord    = (TextureMat * vec4(UV0, 0.0, 1.0)).xy;
    lightCoord  = UV2;
    vertColor   = Color;
}
