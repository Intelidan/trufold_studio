#version 460 core

layout(location = 0) in vec3 v_viewNormal;
layout(location = 1) in vec3 v_viewPos;
layout(location = 2) in float v_ao; // 1.0 on outer surfaces, 0.72..0.86 inside holes/crevices

uniform vec3 u_baseColor;      // e.g. Onshape Blue vec3(0.455, 0.612, 0.745) or Teal vec3(0.055, 0.525, 0.510)
uniform float u_roughness;     // Default: 0.24 for Onshape satin-plastic / anodized feel
uniform float u_opacity;       // 1.0 for Solid mode (SS3/SS4), 0.28 for Translucent mode (SS5)

layout(location = 0) out vec4 fragColor;

const float PI = 3.14159265359;

// GGX / Trowbridge-Reitz Normal Distribution Function
float distributionGGX(vec3 N, vec3 H, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float NdotH = max(dot(N, H), 0.0);
  float NdotH2 = NdotH * NdotH;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  return a2 / max(PI * denom * denom, 0.0001);
}

// Schlick Fresnel approximation (gives edges that tactile solid/plastic rim sheen)
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
  return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

void main() {
  // Support two-sided normal orientation for thin walls and Translucent Mode (SS5)
  vec3 N = normalize(gl_FrontFacing ? v_viewNormal : -v_viewNormal);
  vec3 V = normalize(-v_viewPos);

  // 1. Two-sided normal guard for sheet metal & extruded walls
  if (dot(N, V) < 0.0) {
    N = -N;
  }

  // 1. View-Space Studio Lights (locked to camera so orbiting is always well-lit)
  vec3 L_key  = normalize(vec3(-0.32, 0.42, 0.85)); // Top-left studio key light
  vec3 L_fill = normalize(vec3(0.48, -0.25, 0.84)); // Soft bottom-right fill light
  vec3 L_rim  = normalize(vec3(0.0, 0.85, -0.52));  // Subtle top-back rim light

  vec3 H_key = normalize(V + L_key);

  float NdotV = max(dot(N, V), 0.001);
  float keyTerm = dot(N, L_key) * 0.5 + 0.5; // Half-Lambert wrapping prevents harsh black terminators
  float fillTerm = max(dot(N, L_fill), 0.0);
  float headlightTerm = max(dot(N, V), 0.0); // Camera headlight
  float rimTerm = max(dot(N, L_rim), 0.0);

  // 2. Studio Hemisphere Sky/Ground Ambient (eliminates flat dead-gray look)
  vec3 skyAmbient    = u_baseColor * vec3(1.06, 1.08, 1.12);
  vec3 groundAmbient = u_baseColor * vec3(0.62, 0.65, 0.70);
  vec3 hemiAmbient   = mix(groundAmbient, skyAmbient, N.y * 0.5 + 0.5) * 0.42;

  // 3. Wrap-Around Studio Diffuse with Camera Headlight (guaranteed >= 0.46 floor)
  float intensity = clamp(0.38 + keyTerm * 0.36 + fillTerm * 0.18 + headlightTerm * 0.18 + rimTerm * 0.08, 0.46, 1.08);
  vec3 diffuse   = u_baseColor * (intensity - 0.38);

  // 4. Energy-Conserving GGX Plastic/Anodized Specular (SS3 & SS4 glossy highlight)
  vec3 F0 = vec3(0.045); // Dielectric plastic/anodized coat reflectance
  vec3 F  = fresnelSchlick(max(dot(H_key, V), 0.0), F0);
  float D = distributionGGX(N, H_key, u_roughness);
  vec3 specular = (D * F * max(dot(N, L_key), 0.0)) * 0.28;

  // Subtle grazing Fresnel rim glow for tactile 3D volume
  float rimSheen = pow(1.0 - NdotV, 3.5) * 0.09;

  // Combine with Crevice Ambient Occlusion (v_ao) and Reinhard soft highlight roll-off
  vec3 litColor = (hemiAmbient + diffuse) * v_ao + specular + vec3(rimSheen);
  litColor = max(litColor, u_baseColor * 0.46);
  litColor = litColor / (litColor + vec3(0.18)) * 1.18; // Prevents harsh white clipping!

  // 5. Handle Solid Mode (SS3/SS4) vs. Onshape Translucent Mode (SS5)
  if (u_opacity < 0.99) {
    // In Translucent mode (SS5), boost opacity slightly at grazing angles like frosted glass
    float glassFresnel = mix(u_opacity, min(u_opacity * 1.85, 0.65), pow(1.0 - NdotV, 2.2));
    vec3 glassColor = mix(litColor, vec3(0.86, 0.92, 0.97), 0.35);
    fragColor = vec4(glassColor, glassFresnel);
  } else {
    fragColor = vec4(litColor, 1.0);
  }
}
