shader_type spatial;
// The desert floor. Colour comes from three nested baked ground textures
// (tools/bake_ground.py): fine near the battery, coarser toward the rim. Where one
// level hands over to the next the choice is Bayer-dithered on screen, so there is no
// visible seam and no blending mud. Lighting is the same hard toon terminator as the
// rest of the world; fog is the engine's.
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform sampler2D ground_near : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D ground_mid : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D ground_far : source_color, filter_nearest_mipmap, repeat_disable;
uniform vec3 near_rect = vec3(-256.0, -256.0, 512.0);    // x0, z0, size in metres
uniform vec3 mid_rect = vec3(-576.0, -576.0, 1152.0);
uniform vec3 far_rect = vec3(-1152.0, -1152.0, 2304.0);
uniform float handover = 0.12;   // fraction of a level's half-size spent dithering into the next

varying vec3 world_pos;

const float BAYER4[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 well inside the level, 0 at (and beyond) its edge
float coverage(vec3 rect, vec2 p) {
	vec2 uv = (p - rect.xy) / rect.z;
	vec2 e = min(uv, 1.0 - uv);
	return clamp(min(e.x, e.y) / (0.5 * handover), 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	int bi = int(mod(FRAGCOORD.y, 4.0)) * 4 + int(mod(FRAGCOORD.x, 4.0));
	float th = (BAYER4[bi] + 0.5) / 16.0;
	vec3 col;
	if (coverage(near_rect, p) > th) {
		col = texture(ground_near, (p - near_rect.xy) / near_rect.z).rgb;
	} else if (coverage(mid_rect, p) > th) {
		col = texture(ground_mid, (p - mid_rect.xy) / mid_rect.z).rgb;
	} else {
		col = texture(ground_far, clamp((p - far_rect.xy) / far_rect.z, 0.0, 1.0)).rgb;
	}
	ALBEDO = col;
	ROUGHNESS = 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
