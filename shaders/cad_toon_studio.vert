// shaders/cad_toon_studio.vert
#version 460 core

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec4 aColor; // Linear RGB + baked Crevice AO

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;

layout(location = 0) out vec3 vWorldPos;
layout(location = 1) out vec3 vWorldNormal;
layout(location = 2) out vec3 vViewPos;
layout(location = 3) out vec3 vViewNormal;
layout(location = 4) out vec4 vVertexColor;

void main() {
    vec4 worldPos4 = uModelMatrix * vec4(aPosition, 1.0);
    mat3 normalMatrix = mat3(transpose(inverse(uModelMatrix)));

    vWorldPos = worldPos4.xyz;
    vWorldNormal = normalize(normalMatrix * aNormal);

    vec4 viewPos4 = uViewMatrix * worldPos4;
    vViewPos = viewPos4.xyz;
    vViewNormal = normalize(mat3(uViewMatrix) * vWorldNormal);
    vVertexColor = aColor;

    gl_Position = uProjectionMatrix * viewPos4;
}
