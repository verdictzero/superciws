// Builds a 32x32x32 colour lookup table (laid out as 32 slices of 32x32 in a
// 1024x32 texture) that maps any RGB to its nearest palette entry. Rendered once.
shader_type canvas_item;

uniform int palette_size = 128;
uniform vec4 palette[128];

void fragment() {
	vec2 px = floor(UV * vec2(1024.0, 32.0));
	float r = mod(px.x, 32.0);
	float b = floor(px.x / 32.0);
	float g = px.y;
	vec3 c = vec3(r, g, b) / 31.0;
	vec3 w = vec3(0.30, 0.59, 0.11);
	float best = 1e9;
	vec3 bc = c;
	for (int i = 0; i < palette_size; i++) {
		vec3 d = (c - palette[i].rgb) * w;
		float dd = dot(d, d);
		if (dd < best) {
			best = dd;
			bc = palette[i].rgb;
		}
	}
	COLOR = vec4(bc, 1.0);
}
