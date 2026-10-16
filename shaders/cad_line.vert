#version 460 core

layout(location = 0) in vec3 a_posA;
layout(location = 1) in vec3 a_posB;
layout(location = 2) in float a_code; // -1,+1 for endpoint A; -2,+2 for endpoint B

uniform mat4 u_mvp;
uniform vec2 u_viewportSize; // e.g. vec2(1920.0, 1080.0)
uniform float u_lineWidthPx; // Default Onshape hairline: 1.25

layout(location = 0) out float v_edgeCoord;

void main() {
  vec4 clipA = u_mvp * vec4(a_posA, 1.0);
  vec4 clipB = u_mvp * vec4(a_posB, 1.0);

  vec2 ndcA = clipA.xy / max(clipA.w, 0.0001);
  vec2 ndcB = clipB.xy / max(clipB.w, 0.0001);

  vec2 screenDelta = (ndcB - ndcA) * (u_viewportSize * 0.5);
  float segLen = length(screenDelta);
  vec2 dir = (segLen > 0.001) ? (screenDelta / segLen) : vec2(1.0, 0.0);
  vec2 normal2D = vec2(-dir.y, dir.x);

  bool isEndB = abs(a_code) > 1.5;
  float side = sign(a_code); // -1.0 or +1.0

  vec4 activeClip = isEndB ? clipB : clipA;

  // Sub-pixel cap extension (0.35px) so segments join seamlessly at corners without ears!
  vec2 capExtend = dir * (isEndB ? 0.35 : -0.35);
  vec2 pixelOffset = (normal2D * (side * u_lineWidthPx * 0.5)) + capExtend;

  // Convert pixel offset back to clip space
  activeClip.xy += (pixelOffset / (u_viewportSize * 0.5)) * activeClip.w;

  // Pull line slightly toward camera to prevent Z-fighting on flat plates and hole rims
  activeClip.z -= 0.00045 * activeClip.w;

  v_edgeCoord = side;
  gl_Position = activeClip;
}
