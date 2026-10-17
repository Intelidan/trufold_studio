// shaders/cad_inverted_hull_outline.frag
#version 460 core

layout(location = 0) out vec4 fragColor;

// Default: Onshape Dark Charcoal-Slate (#1B242D -> Linear RGB: 0.011, 0.018, 0.026)
uniform vec4 uOutlineColor;

void main() {
    fragColor = uOutlineColor.a > 0.0
        ? uOutlineColor
        : vec4(0.011, 0.018, 0.026, 1.0);
}
