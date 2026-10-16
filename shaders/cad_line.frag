#version 460 core

layout(location = 0) in float v_edgeCoord;
uniform float u_opacity; // 0.88 in opaque mode, 0.55 for translucent back-edges

layout(location = 0) out vec4 fragColor;

void main() {
  float dist = abs(v_edgeCoord);
  float aa = fwidth(dist);
  float alpha = (1.0 - smoothstep(1.0 - aa * 1.4, 1.0, dist)) * u_opacity;

  // Onshape dark slate-charcoal border color (#1E2730 — softer & cleaner than #000000)
  fragColor = vec4(0.118, 0.153, 0.188, alpha);
}
