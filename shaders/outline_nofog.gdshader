shader_type spatial;
// Same ink line as outline.gdshader, but unaffected by distance fog (used on enemies).
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 ink : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 1.0;
uniform float px_per_unit = 0.0034;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	v.xyz += n * width_px * px_per_unit * max(-v.z, 0.5);
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = ink.rgb;
}
