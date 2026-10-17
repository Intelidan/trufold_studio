// shaders/cad_inverted_hull_outline.vert
#version 460 core

// Incoming vertex data from Flutter Scene / Mesh
// Supply vertex-averaged smooth normals in location 1 so 90° CAD corners expand uniformly!
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;

uniform vec2 uViewportSize;            // e.g. vec2(1920.0, 1080.0)
uniform float uOutlineThicknessPx;     // e.g. 1.5 (pixels)
uniform float uWorldThicknessFallback; // e.g. 0.45 (mm fallback)

void main() {
    vec4 worldPos4 = uModelMatrix * vec4(aPosition, 1.0);
    vec3 worldNormal = normalize(mat3(transpose(inverse(uModelMatrix))) * aNormal);

    mat4 vpMatrix = uProjectionMatrix * uViewMatrix;
    vec4 clipPos = vpMatrix * worldPos4;

    vec3 viewNormal = normalize(mat3(uViewMatrix) * worldNormal);
    vec2 ndcNormal = normalize((uProjectionMatrix * vec4(viewNormal, 0.0)).xy + vec2(1e-6));

    if (uViewportSize.x > 1.0 && uViewportSize.y > 1.0) {
        // Constant screen-pixel outline thickness at any zoom!
        vec2 pixelOffset = (ndcNormal * uOutlineThicknessPx * 2.0) / uViewportSize;
        clipPos.xy += pixelOffset * clipPos.w;
    } else {
        vec3 extrudedWorld = worldPos4.xyz + (worldNormal * uWorldThicknessFallback);
        clipPos = vpMatrix * vec4(extrudedWorld, 1.0);
    }

    // Push hull depth slightly back (+z bias) so Pass 2 (SolidCadBody) covers interior faces
    clipPos.z += 0.0008 * clipPos.w;
    gl_Position = clipPos;
}
