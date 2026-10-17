// shaders/cad_toon_studio.frag
#version 460 core

layout(location = 0) in vec3 vWorldPos;
layout(location = 1) in vec3 vWorldNormal;
layout(location = 2) in vec3 vViewPos;
layout(location = 3) in vec3 vViewNormal;
layout(location = 4) in vec4 vVertexColor;

uniform vec4 baseColorFactor;   // Multiplier on vVertexColor
uniform float roughnessFactor;  // 0.12..0.75 (from Shininess slider)
uniform float toonStepMix;      // 0.0 = Smooth Onshape Studio, 1.0 = Hard Step-Lighting (Toon)
uniform float rimBorderWidth;   // Grazing-angle Fresnel ink border width (e.g. 0.18)

layout(location = 0) out vec4 fragColor;

// Quantizes continuous lighting [0..1] into 3 crisp, anti-aliased toon/CAD steps
// (Shadow Band -> Midtone Band -> Key-Lit Band) using fwidth() for zero pixel aliasing!
float quantizeLightingStep(float ndotl) {
    float fw = max(fwidth(ndotl), 0.015);
    float band1 = smoothstep(0.25 - fw, 0.25 + fw, ndotl);
    float band2 = smoothstep(0.68 - fw, 0.68 + fw, ndotl);
    return mix(0.48, 0.78, band1) + (band2 * 0.28);
}

void main() {
    vec3 N = normalize(gl_FrontFacing ? vViewNormal : -vViewNormal);
    vec3 V = normalize(-vViewPos);

    vec3 L_key  = normalize(vec3(-0.42, 0.58, 0.70));
    vec3 L_fill = normalize(vec3( 0.60, -0.45, 0.66));
    vec3 H_key  = normalize(V + L_key);

    float NdotL = max(dot(N, L_key), 0.0);
    float wrapNdotL = clamp((dot(N, L_key) + 0.30) / 1.30, 0.0, 1.0);
    float NdotFill = max(dot(N, L_fill), 0.0);
    float NdotH = max(dot(N, H_key), 0.0);
    float NdotV = max(dot(N, V), 0.001);

    float smoothTone = 0.50 + wrapNdotL * 0.42 + NdotFill * 0.14;
    float steppedTone = quantizeLightingStep(wrapNdotL);
    float finalLightTone = mix(smoothTone, steppedTone, clamp(toonStepMix, 0.0, 1.0));

    // Hard-Stepped Specular Highlight Band (Anodized / Cel-Shaded Sheen)
    float specPower = mix(96.0, 16.0, clamp(roughnessFactor, 0.1, 0.9));
    float rawSpec = pow(NdotH, specPower) * step(0.05, NdotL);
    float specFw = max(fwidth(rawSpec), 0.02);
    float steppedSpec = smoothstep(0.38 - specFw, 0.38 + specFw, rawSpec) * 0.24;
    float finalSpec = mix(rawSpec * 0.20, steppedSpec, clamp(toonStepMix, 0.0, 1.0));

    vec3 baseLinear = vVertexColor.rgb * baseColorFactor.rgb;
    vec3 litColor = baseLinear * finalLightTone + vec3(finalSpec);

    if (rimBorderWidth > 0.01) {
        float fresnel = 1.0 - NdotV;
        float rimFw = max(fwidth(fresnel), 0.02);
        float rimInk = smoothstep((1.0 - rimBorderWidth) - rimFw, (1.0 - rimBorderWidth) + rimFw, fresnel);
        vec3 inkColor = vec3(0.011, 0.018, 0.026); // Onshape #1B242D
        litColor = mix(litColor, inkColor, rimInk * 0.65);
    }

    fragColor = vec4(litColor, vVertexColor.a * baseColorFactor.a);
}
