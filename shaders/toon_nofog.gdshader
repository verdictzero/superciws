shader_type spatial;
// toon.gdshader without distance fog (enemies stay crisp at any range)
render_mode cull_disabled, diffuse_toon, specular_disabled, fog_disabled;
#include "res://shaders/toon.gdshaderinc"
