// Tile layers, see-through (a layer below 100 % opacity).
shader_type spatial;
render_mode cull_disabled, specular_disabled, depth_draw_never;

#include "res://shaders/tile_common.gdshaderinc"

void fragment() {
	vec4 c = texture(atlas, UV) * COLOR;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	ALPHA = c.a * opacity;
}
