// SUPER CIWS retro post filter.
// Runs at native window resolution over the low-res game viewport:
//  1. nearest-neighbour fetch of the 256x192 frame
//  2. optional 2x2 ordered dither
//  3. quantise to a fixed limited palette
//  4. LCD sub-pixel mask (R,G,B stripes, 3 per source pixel) + row gap
shader_type canvas_item;

uniform sampler2D screen_tex : filter_nearest, repeat_disable;
uniform vec2 low_res = vec2(256.0, 192.0);
uniform int palette_size = 22;
uniform vec4 palette[32];
uniform float mask_strength : hint_range(0.0, 1.0) = 0.55;
uniform float row_gap : hint_range(0.0, 1.0) = 0.30;
uniform float dither : hint_range(0.0, 1.0) = 0.0;
uniform float gain : hint_range(0.5, 2.0) = 1.30;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 px = UV * low_res;
	vec2 cell = floor(px);
	vec3 c = texture(screen_tex, (cell + 0.5) / low_res).rgb;

	// 2x2 Bayer dither, pushes gradients into neighbouring palette entries.
	if (dither > 0.0) {
		float bx = mod(cell.x, 2.0);
		float by = mod(cell.y, 2.0);
		float b = (bx + by * 2.0 + (bx * by) * -1.0) / 4.0 - 0.375;
		c += b * dither * 0.12;
	}
	c += vec3(flash);
	c = mix(c, vec3(0.97, 0.22, 0.12), damage * 0.55);

	// Nearest palette colour (perceptually weighted).
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

	// LCD sub-pixel stripes: each source pixel = one R|G|B triad.
	float sub = fract(px.x) * 3.0;
	int s = int(floor(sub));
	vec3 m = vec3(1.0 - mask_strength);
	if (s == 0) { m.r = 1.0; } else if (s == 1) { m.g = 1.0; } else { m.b = 1.0; }
	// soften stripe edge a touch so it reads as glass, not a grid of dots
	float edge = smoothstep(0.0, 0.15, fract(sub)) * smoothstep(1.0, 0.85, fract(sub));
	m = mix(vec3(1.0 - mask_strength * 0.5), m, 0.6 + 0.4 * edge);

	// horizontal row gap between pixel rows
	float row = fract(px.y);
	float gapf = row > 0.78 ? (1.0 - row_gap) : 1.0;

	COLOR = vec4(bc * m * gapf * gain, 1.0);
}
