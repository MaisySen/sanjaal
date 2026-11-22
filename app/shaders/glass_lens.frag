#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter owns these two uniforms. Canvas fixture supplies them manually.
uniform vec2 u_size;
uniform sampler2D u_input;
// Lens bounds in INPUT TEXTURE pixels, not assumed widget-local coordinates.
uniform vec4 u_rect;
uniform float u_radius;
uniform float u_strength;
uniform float u_edge;
out vec4 frag_color;

void main() {
  vec2 size = max(u_size, vec2(1.0));
  vec2 p = FlutterFragCoord().xy;
  vec2 half_size = max((u_rect.zw - u_rect.xy) * 0.5, vec2(1.0));
  vec2 center = (u_rect.xy + u_rect.zw) * 0.5;
  float radius = clamp(u_radius, 0.0, min(half_size.x, half_size.y));
  vec2 local = p - center;
  vec2 q = abs(local) - (half_size - vec2(radius));
  vec2 outer = max(q, vec2(0.0));
  float distance_to_edge = length(outer) + min(max(q.x, q.y), 0.0) - radius;
  vec2 normal = vec2(0.0);
  if (length(outer) > 0.001) {
    normal = normalize(outer) * sign(local);
  } else if (q.x > q.y) {
    normal = vec2(sign(local.x), 0.0);
  } else {
    normal = vec2(0.0, sign(local.y));
  }
  float inside = 1.0 - step(0.0, distance_to_edge);
  float edge_weight = 1.0 - smoothstep(0.0, max(u_edge, 0.5), -distance_to_edge);
  // Bounded inward displacement changes source sampling. No fake overlay image.
  vec2 sample_point = p - normal * clamp(u_strength, 0.0, 16.0) * edge_weight * inside;
  vec2 uv = clamp(sample_point / size, vec2(0.5) / size, vec2(1.0) - vec2(0.5) / size);
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  frag_color = texture(u_input, uv);
}
