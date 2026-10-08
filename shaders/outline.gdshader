shader_type spatial;
// Inverted-hull ink line for the toon look. The shell is pushed out along the
// normal in view space, scaled by depth, so the line stays `width_px` low-res
// pixels wide no matter how far away the object is.
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width_px = 1.0;
uniform float px_per_unit = 0.0034;   // 2 * tan(fov / 2) / view height in pixels

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	v.xyz += n * width_px * px_per_unit * max(-v.z, 0.5);
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = ink.rgb;
}
