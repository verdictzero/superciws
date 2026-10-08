// Builds a 32x32x32 colour lookup table (laid out as 32 slices of 32x32 in a
// 1024x32 texture) that maps any RGB to its nearest palette entry. Rendered once.
shader_type canvas_item;

uniform int palette_size = 128;
uniform vec4 palette[128];

// Nearest palette colour is judged in Oklab, a perceptual space, so warm tans and
// browns stay warm instead of sliding to slate greys (tools/build_assets.py matches it).
vec3 oklab(vec3 c) {
	c = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	l = pow(max(l, 0.0), 1.0 / 3.0);
	m = pow(max(m, 0.0), 1.0 / 3.0);
	s = pow(max(s, 0.0), 1.0 / 3.0);
	return vec3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
			1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
			0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

void fragment() {
	vec2 px = floor(UV * vec2(1024.0, 32.0));
	float r = mod(px.x, 32.0);
	float b = floor(px.x / 32.0);
	float g = px.y;
	vec3 c = vec3(r, g, b) / 31.0;
	vec3 lc = oklab(c);
	float best = 1e9;
	vec3 bc = c;
	for (int i = 0; i < palette_size; i++) {
		vec3 d = lc - oklab(palette[i].rgb);
		float dd = dot(d, d);
		if (dd < best) {
			best = dd;
			bc = palette[i].rgb;
		}
	}
	COLOR = vec4(bc, 1.0);
}
