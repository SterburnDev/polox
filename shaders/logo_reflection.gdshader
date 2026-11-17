shader_type canvas_item;
// The logo's reflection on the title's lake: drawn on a full-size copy of the logo seen through a short
// window under it (title_screen.gd), so this samples the logo upside down at its true size and fades it
// out over `span` (the window's share of the logo's height), with a gentle ripple and an aqua tint.
uniform float still = 0.0;
uniform float span = 0.34;
void fragment() {
	float down = UV.y / span;   // 0 at the waterline, 1 at the window's bottom
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	uv.x += (1.0 - still) * sin(UV.y * 90.0 + TIME * 1.6) * 0.004 * down;
	vec4 c = texture(TEXTURE, uv);
	float fade = clamp(1.0 - down, 0.0, 1.0);
	COLOR = vec4(mix(c.rgb, vec3(0.5, 0.86, 0.94), 0.45), c.a * 0.34 * fade * fade);
}
