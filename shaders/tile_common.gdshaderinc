// Shared by tile.gdshader (opaque pixel art) and tile_alpha.gdshader (see-through layers).
// Per vertex: UV = frame 0 in the set's atlas, COLOR = tint,
// CUSTOM0 = quad centre (xyz) + 1 if it stands and turns to face the camera (w),
// CUSTOM1 = frames, frames per second, atlas width of one frame (for animation).

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	if (CUSTOM0.w > 0.5) {
		vec3 c = CUSTOM0.xyz;
		vec3 off = VERTEX - c;
		vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		vec2 d = cam.xz - c.xz;
		float len = length(d);
		d = len > 0.0001 ? d / len : vec2(0.0, 1.0);
		vec3 right = vec3(d.y, 0.0, -d.x);
		VERTEX = c + right * off.x + vec3(0.0, off.y, 0.0);
		NORMAL = vec3(d.x, 0.0, d.y);
	}
	if (CUSTOM1.x > 1.5) {
		UV.x += floor(mod(TIME * CUSTOM1.y, CUSTOM1.x)) * CUSTOM1.z;
	}
}
