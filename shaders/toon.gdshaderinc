// Shared body of the toon materials: hard-terminator cel lighting plus a vertical
// gradient (dark at the base, bright at the top) that the post filter Bayer-dithers
// into the palette. The gradient runs over model-space Y, or world-space Y when
// `world_space` is set (used for scenery and the CIWS mounts so a whole object shares it).

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool use_vertex_color = false;
uniform bool world_space = false;
uniform float grad_y0 = -1.0;
uniform float grad_y1 = 1.0;
uniform float grad_lo = 0.6;
uniform float grad_hi = 1.15;

varying float grad_t;
varying vec3 vcol;

void vertex() {
	float y = world_space ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).y : VERTEX.y;
	grad_t = clamp((y - grad_y0) / max(grad_y1 - grad_y0, 0.001), 0.0, 1.0);
	vcol = use_vertex_color ? COLOR.rgb : vec3(1.0);
}

void fragment() {
	ALBEDO = albedo.rgb * vcol * mix(grad_lo, grad_hi, grad_t);
	EMISSION = emission.rgb;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
