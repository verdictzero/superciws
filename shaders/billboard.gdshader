shader_type spatial;
// Camera-facing sprites for every plant and rock (one MultiMesh, one atlas).
// Y-axis billboards after mewd-engine's SHADER_veg_billboard: each quad turns about the
// vertical to face the camera, keeps its foot planted, and cuts its 1-bit alpha with a
// scissor so it draws opaque (no sorting). Colours are the sprites' own, palette-
// dithered at bake; the engine's fog still hazes them with distance.
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;

varying vec2 atlas_uv;

void vertex() {
	// instance basis carries width (x) and height (y); custom data is the atlas rect
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 world = origin + right * (VERTEX.x * w) + vec3(0.0, VERTEX.y * h, 0.0);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	vec4 r = INSTANCE_CUSTOM;
	atlas_uv = vec2(mix(r.x, r.z, UV.x), mix(r.y, r.w, UV.y));
}

void fragment() {
	vec4 c = texture(atlas, atlas_uv);
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb;
}
