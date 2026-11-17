shader_type canvas_item;
// [GLASS_UI] The title's Frutiger Aero scene in Polox's violet night: an aqua glow on the horizon,
// glossy rolling hills (teal-green, lit along their tops), and a lake below them with soft ripples,
// the hills mirrored in it and slow glints of starlight. Drawn over the starfield on one full-screen
// ColorRect (title_screen.gd); `still` freezes it (Reduce motion).

uniform float horizon = 0.7;        // the waterline, 0..1 from the top
uniform float aspect = 1.78;        // width / height, so ripples stay round
uniform float still = 0.0;
uniform vec4 glow_col : source_color = vec4(0.5, 0.86, 0.94, 1.0);
uniform vec4 hill_far : source_color = vec4(0.16, 0.36, 0.45, 1.0);
uniform vec4 hill_near : source_color = vec4(0.14, 0.5, 0.45, 1.0);
uniform vec4 water_top : source_color = vec4(0.17, 0.33, 0.52, 1.0);
uniform vec4 water_deep : source_color = vec4(0.09, 0.07, 0.2, 1.0);

float hill(float x, float seed, float amp) {
	return amp * (0.55 + 0.25 * sin(x * 3.1 + seed) + 0.14 * sin(x * 7.7 + seed * 2.3) + 0.06 * sin(x * 17.0 + seed * 4.1));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The sky and hills above the line at height `y` (0..1 from the top); alpha = how much they cover.
vec4 land(vec2 uv) {
	float x = uv.x * aspect;
	vec4 c = vec4(0.0);
	// The horizon glow: strongest just above the water.
	float g = smoothstep(horizon - 0.32, horizon, uv.y);
	c = vec4(glow_col.rgb, g * g * 0.22);
	// Far hills (bluer, lower), then near hills (greener, taller), each with a glossy lit top edge.
	float hf = horizon - hill(x, 1.7, 0.07);
	if (uv.y > hf) {
		float t = clamp((uv.y - hf) / 0.08, 0.0, 1.0);
		vec3 col = mix(hill_far.rgb * 1.25, hill_far.rgb * 0.8, t);
		col += glow_col.rgb * smoothstep(0.012, 0.0, uv.y - hf) * 0.35;
		c = vec4(mix(c.rgb, col, 0.85), max(c.a, 0.85));
	}
	float hn = horizon - hill(x + 4.0, 5.2, 0.05) + 0.012;
	if (uv.y > hn) {
		float t = clamp((uv.y - hn) / 0.06, 0.0, 1.0);
		vec3 col = mix(hill_near.rgb * 1.3, hill_near.rgb * 0.75, t);
		col += vec3(0.75, 1.0, 0.85) * smoothstep(0.008, 0.0, uv.y - hn) * 0.45;
		c = vec4(col, 0.95);
	}
	return c;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * (1.0 - still);
	if (uv.y < horizon) {
		COLOR = land(uv);
	} else {
		float depth = (uv.y - horizon) / max(1.0 - horizon, 0.001);
		// Ripples: a few drifting waves, finer and closer together near the horizon.
		float w = sin((uv.x * aspect * 9.0 + t * 0.35) + sin(depth * 30.0 - t * 0.9) * 0.8) * 0.5
				+ sin(uv.x * aspect * 23.0 - t * 0.6 + depth * 12.0) * 0.25;
		float ripple = w * (0.003 + depth * 0.006);
		// The land mirrored in the water, wobbling with the ripples and fading with depth.
		vec2 m = vec2(uv.x + ripple, horizon - (uv.y - horizon) * 1.6 + ripple * 2.0);
		vec4 refl = land(m);
		vec3 water = mix(water_top.rgb, water_deep.rgb, smoothstep(0.0, 1.0, depth));
		water = mix(water, refl.rgb * 0.8, refl.a * 0.5 * (1.0 - depth));
		// Light on the ripples' crests, and a few glints of starlight.
		water += glow_col.rgb * smoothstep(0.55, 1.0, w) * 0.12 * (1.0 - depth);
		vec2 gp = vec2(uv.x * aspect * 60.0, depth * 40.0);
		vec2 cell = floor(gp);
		vec2 local = (fract(gp) - 0.5) * vec2(1.0, 2.2);   // (a soft dot, wider than tall: lying on the water)
		float glint = step(0.982, hash(cell)) * smoothstep(0.3, 0.0, length(local)) * (0.5 + 0.5 * sin(t * 2.0 + hash(cell + 3.0) * 6.28));
		water += vec3(glint) * 0.35 * (1.0 - depth);
		// The waterline itself: a thin bright edge.
		water += glow_col.rgb * smoothstep(0.006, 0.0, uv.y - horizon) * 0.5;
		COLOR = vec4(water, 1.0);
	}
}
