// SUPER CIWS retro post filter.
// Runs at native window resolution over the low-res game viewport:
//  1. letterbox the 4:3 game area inside whatever shape the window is
//  2. nearest-neighbour fetch of the low-res frame
//  3. optional 2x2 ordered dither
//  4. quantise to the palette through a precomputed lookup table (one fetch)
//  5. LCD sub-pixel mask in screen pixels (R,G,B stripes) + row gap
shader_type canvas_item;

uniform sampler2D screen_tex : filter_nearest, repeat_disable;
uniform sampler2D lut_tex : filter_nearest, repeat_disable;
uniform vec2 low_res = vec2(512.0, 384.0);
uniform vec4 game_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x, y, w, h in window UV
uniform vec3 bezel = vec3(0.06, 0.06, 0.09);
uniform float mask_strength : hint_range(0.0, 1.0) = 0.55;
uniform float row_gap : hint_range(0.0, 1.0) = 0.30;
uniform float dither : hint_range(0.0, 1.0) = 0.0;
uniform float gain : hint_range(0.5, 2.0) = 1.30;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 guv = (UV - game_rect.xy) / game_rect.zw;
	if (guv.x < 0.0 || guv.x >= 1.0 || guv.y < 0.0 || guv.y >= 1.0) {
		COLOR = vec4(bezel, 1.0);
	} else {
		vec2 px = guv * low_res;
		vec2 cell = floor(px);
		vec3 c = texture(screen_tex, (cell + 0.5) / low_res).rgb;

		if (dither > 0.0) {
			float bx = mod(cell.x, 2.0);
			float by = mod(cell.y, 2.0);
			float b = (bx + by * 2.0 + (bx * by) * -1.0) / 4.0 - 0.375;
			c += b * dither * 0.12;
		}
		c += vec3(flash);
		c = mix(c, vec3(0.97, 0.22, 0.12), damage * 0.55);

		// palette lookup: 5 bits per channel into the 1024x32 LUT
		vec3 q = clamp(floor(c * 31.0 + 0.5), 0.0, 31.0);
		vec2 luv = vec2((q.b * 32.0 + q.r + 0.5) / 1024.0, (q.g + 0.5) / 32.0);
		vec3 bc = texture(lut_tex, luv).rgb;

		// LCD sub-pixel stripes in screen pixels: R|G|B triads like a real panel
		int s = int(mod(FRAGCOORD.x, 3.0));
		vec3 m = vec3(1.0 - mask_strength);
		if (s == 0) { m.r = 1.0; } else if (s == 1) { m.g = 1.0; } else { m.b = 1.0; }
		float gapf = mod(FRAGCOORD.y, 3.0) >= 2.0 ? (1.0 - row_gap) : 1.0;

		COLOR = vec4(bc * m * gapf * gain, 1.0);
	}
}
