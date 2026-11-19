shader_type canvas_item;
// [GLASS_UI] Polox's Liquid Glass (an original component inspired by iOS 26): what's behind, blurred
// (the screen copy's mipmaps), bent a little near the edge like a thick lens, tinted so text stays
// readable (more tint over a bright background, less over a dark one), with a light rim that catches
// the light at the top. Used by liquid_glass.gd on a ColorRect behind a control's contents; the contents
// draw normally on top, so text and icons stay sharp. Each glass has a BackBufferCopy just before it
// (Godot copies the screen once per copy), so overlapping glasses each see what is really under them.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2 size_px = vec2(200.0, 60.0);
uniform float radius = 24.0;
uniform float blur = 2.6;              // mip level: how frosted
uniform vec4 tint : source_color = vec4(0.11, 0.09, 0.21, 0.5);
uniform float refraction = 9.0;        // px the edge bends the background
uniform float edge_light = 0.5;
uniform float adapt = 1.0;             // how much the tint follows the background's brightness
uniform float round_bottom = 1.0;      // 0: square bottom corners (a sheet docked to the bottom edge)

float box_sdf(vec2 p, vec2 half_size, float r) {
	if (round_bottom < 0.5 && p.y > 0.0) {
		vec2 q = abs(p) - half_size;
		return max(q.x, q.y);
	}
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 half_size = size_px * 0.5;
	vec2 p = (UV - 0.5) * size_px;
	float r = min(radius, min(half_size.x, half_size.y));
	float d = box_sdf(p, half_size, r);
	float aa = max(fwidth(d), 0.0001);
	float mask = clamp(0.5 - d / aa, 0.0, 1.0);
	// The edge's normal (the SDF's slope) and how close to the edge we are (1 at the rim, 0 inside).
	vec2 e = vec2(1.0, 0.0);
	vec2 n = vec2(box_sdf(p + e.xy, half_size, r) - box_sdf(p - e.xy, half_size, r),
			box_sdf(p + e.yx, half_size, r) - box_sdf(p - e.yx, half_size, r));
	n = n / max(length(n), 0.0001);
	float lens = clamp(1.0 + d / max(r, 10.0), 0.0, 1.0);
	lens *= lens;
	vec2 offset = -n * lens * refraction * SCREEN_PIXEL_SIZE;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offset, blur).rgb;
	vec3 around = textureLod(screen_tex, SCREEN_UV, 6.0).rgb;
	float lum = dot(around, vec3(0.299, 0.587, 0.114));
	float k = clamp(tint.a + adapt * (smoothstep(0.32, 0.85, lum) * 0.36 - smoothstep(0.18, 0.0, lum) * 0.12), 0.0, 0.94);
	vec3 col = mix(behind, tint.rgb, k);
	// Light along the rim: strong where it faces up-left, faint on the far side.
	float rim = smoothstep(2.6, 0.0, abs(d + 1.2));
	float facing = dot(n, normalize(vec2(-0.45, -1.0)));
	col += vec3(rim * edge_light * (0.3 + 0.7 * max(facing, 0.0)));
	col += vec3(rim * 0.1 * max(-facing, 0.0));
	// A soft sheen in the top third.
	col += vec3(smoothstep(0.38, 0.0, UV.y) * 0.035);
	COLOR = vec4(col, mask);
}
