// SUPER CIWS retro post filter.
// Runs at native window resolution over the low-res game viewport:
//  1. letterbox the 4:3 game area inside whatever shape the window is
//  2. nearest-neighbour fetch of the low-res frame
//  3. quantise to the palette through a precomputed lookup table, with palette-aware
//     4x4 Bayer ordered dithering: find the nearest palette colour and the next one in the
//     direction of the error, then let the Bayer threshold pick between the two. Colours
//     that are exactly in the palette (HUD, flat fills) stay solid; gradients and shading
//     break into classic cross-hatch patterns without hue noise.
//  5. LCD sub-pixel mask in screen pixels (R,G,B stripes) + row gap
shader_type canvas_item;

uniform sampler2D screen_tex : filter_nearest, repeat_disable;
uniform sampler2D lut_tex : filter_nearest, repeat_disable;
uniform vec2 low_res = vec2(512.0, 384.0);
uniform vec4 game_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x, y, w, h in window UV
uniform vec3 bezel = vec3(0.06, 0.06, 0.09);
uniform float mask_strength : hint_range(0.0, 1.0) = 0.55;
uniform float row_gap : hint_range(0.0, 1.0) = 0.30;
uniform float dither : hint_range(0.0, 1.0) = 1.0;
uniform float dither_reach : hint_range(0.02, 0.4) = 0.16;   // how far to look for the second colour
uniform float gain : hint_range(0.5, 2.0) = 1.30;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float damage : hint_range(0.0, 1.0) = 0.0;

const float BAYER4[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

vec3 lut(vec3 c) {
	// 5 bits per channel into the 1024x32 LUT
	vec3 q = clamp(floor(c * 31.0 + 0.5), 0.0, 31.0);
	vec2 luv = vec2((q.b * 32.0 + q.r + 0.5) / 1024.0, (q.g + 0.5) / 32.0);
	return texture(lut_tex, luv).rgb;
}

void fragment() {
	vec2 guv = (UV - game_rect.xy) / game_rect.zw;
	if (guv.x < 0.0 || guv.x >= 1.0 || guv.y < 0.0 || guv.y >= 1.0) {
		COLOR = vec4(bezel, 1.0);
	} else {
		vec2 px = guv * low_res;
		vec2 cell = floor(px);
		vec3 c = texture(screen_tex, (cell + 0.5) / low_res).rgb;

		c += vec3(flash);
		c = mix(c, vec3(0.97, 0.22, 0.12), damage * 0.55);
		c = clamp(c, 0.0, 1.0);
		vec3 bc = lut(c);
		vec3 err = c - bc;
		float el = length(err);
		if (dither > 0.0 && el > 0.004) {
			vec3 q1 = lut(c + err / el * dither_reach);
			vec3 span = q1 - bc;
			float sl = dot(span, span);
			if (sl > 1e-5) {
				float t = clamp(dot(err, span) / sl, 0.0, 1.0) * dither;
				int bi = int(mod(cell.y, 4.0)) * 4 + int(mod(cell.x, 4.0));
				if (t > (BAYER4[bi] + 0.5) / 16.0) {
					bc = q1;
				}
			}
		}

		// LCD sub-pixel stripes in screen pixels: R|G|B triads like a real panel
		int s = int(mod(FRAGCOORD.x, 3.0));
		vec3 m = vec3(1.0 - mask_strength);
		if (s == 0) { m.r = 1.0; } else if (s == 1) { m.g = 1.0; } else { m.b = 1.0; }
		float gapf = mod(FRAGCOORD.y, 3.0) >= 2.0 ? (1.0 - row_gap) : 1.0;

		COLOR = vec4(bc * m * gapf * gain, 1.0);
	}
}
