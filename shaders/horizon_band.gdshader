shader_type spatial;
// One layer of the horizon backdrop: a strip of art wrapped around the view, sampled by
// view DIRECTION rather than by the mesh's UVs, so it sits at infinity, never shows a
// seam and needs no geometry beyond an open cylinder that follows the camera.
//
// Ported from mewd-engine's SHADER_horizon_clouds (verdictzero/golf lineage), one layer
// per material instead of two, the thermal/golf-wall hooks removed, and two switches
// for SUPER CIWS:
//   cutout       - 1-bit alpha (the art is pre-dithered to the palette with hard edges)
//   solid_below  - the strip's bottom row carries on down to `fade_end` fully opaque, so
//                  the mountain ring hides wherever the terrain runs out
// Parallax from camera translation is kept (the turret's camera orbits a little as it
// traverses), wind drift wraps a whole number of tiles per hour as in the original.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded,
		shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D band : source_color, filter_nearest_mipmap, repeat_enable;
uniform float tiles = 2.0;          // repeats around the full circle
uniform float height = 0.2;         // strip height, in tan(elevation)
uniform float base = -0.04;         // tan(elevation) of the strip's bottom edge
uniform float distance = 20000.0;   // metres, for parallax only
uniform float parallax_limit = 0.5;
uniform float drift = 0.0;          // rad/s of wind
uniform float phase = 0.0;
uniform float opacity = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float saturation = 1.0;
uniform bool cutout = true;
uniform bool solid_below = false;
uniform float art_fade_in = 0.0;    // soft top edge (clouds), in strip v units
uniform float art_solid_end = 2.0;  // strip v where the art starts fading out again (clouds)
uniform float fade_start = 0.04;    // tan(elevation) above which the art is unhazed
uniform float fade_end = -0.06;     // ... and where it is all haze (and where solid_below stops)
uniform vec3 haze_color : source_color = vec3(0.97, 0.88, 0.63);
uniform float haze_strength = 0.6;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = wp - CAMERA_POSITION_WORLD;
	float l = max(length(dir.xz), 1e-6);
	vec2 p = dir.xz / l;
	float phi = atan(p.x, p.y);
	float t = dir.y / l;
	if (t > base + height || t < fade_end) {
		discard;
	}
	// analytic d(phi) so the atan branch cut never picks a tiny mip (mewd)
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec2 d_phi = vec2(p.y * dpx.x - p.x * dpx.y, p.y * dpy.x - p.x * dpy.y);
	vec2 d_t = vec2(dFdx(t), dFdy(t));

	vec2 eye = CAMERA_POSITION_WORLD.xz;
	float d_safe = max(distance, 1.0);
	float lim = max(d_safe * parallax_limit, 1.0);
	float e = length(eye) / lim;
	vec2 off = eye * inversesqrt(1.0 + e * e);
	float cross_c = off.x * p.y - off.y * p.x;
	float k = tiles / TAU;
	float u = (phi + cross_c / d_safe + drift * TIME) * k + phase;
	float inv_h = 1.0 / max(height, 1e-3);
	float v = (base + height - t) * inv_h;
	float inset = 0.5 / float(textureSize(band, 0).y);
	vec2 uv = vec2(u, clamp(v, inset, 1.0 - inset));
	vec4 c = textureGrad(band, uv, vec2(d_phi.x * k, -d_t.x * inv_h), vec2(d_phi.y * k, -d_t.y * inv_h));
	if (solid_below && v > 1.0) {
		c.a = 1.0;
	}
	c.a *= opacity * smoothstep(0.0, max(art_fade_in, 1e-4), v)
			* (1.0 - smoothstep(art_solid_end, art_solid_end + 0.3, v));
	if (cutout) {
		c.a = c.a > 0.5 ? 1.0 : 0.0;
	}
	vec3 col = c.rgb * tint;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);
	float fade = smoothstep(fade_end, fade_start, t);
	col = mix(haze_color, col, mix(1.0, fade, haze_strength));
	if (!solid_below) {
		c.a *= fade;
	}
	if (c.a < 0.004) {
		discard;
	}
	ALBEDO = col;
	ALPHA = c.a;
}
