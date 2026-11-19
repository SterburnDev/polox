// Tile layers, opaque: crisp pixel art, cut out where the picture is transparent.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://shaders/tile_common.gdshaderinc"

void fragment() {
	vec4 c = texture(atlas, UV) * COLOR;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}
