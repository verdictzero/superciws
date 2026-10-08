class_name Scatter
extends MultiMeshInstance3D
## Every plant and rock on the desert as one MultiMesh of camera-facing quads, read from
## the bake (tools/bake_vegetation.py). One draw call, nothing generated at runtime.

const BAKE := "res://assets/terrain/bake/scatter.bin"
const ATLAS := "res://assets/terrain/scatter_atlas.png"

func _ready() -> void:
	var f := FileAccess.open(BAKE, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "SCT1":
		push_error("Scatter: missing bake, run tools/bake_vegetation.py")
		return
	var count := f.get_32()
	var stride := f.get_32()
	var data := f.get_buffer(count * stride * 4).to_float32_array()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0, 0.5, 0)   # pivot at the foot
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	# 12 floats of transform + 4 of custom data per instance, built in one buffer
	var buf := PackedFloat32Array()
	buf.resize(count * 16)
	for i in count:
		var o := i * stride
		var b := i * 16
		var w := data[o + 3]
		var h := data[o + 4]
		buf[b + 0] = w;   buf[b + 1] = 0.0; buf[b + 2] = 0.0;  buf[b + 3] = data[o]
		buf[b + 4] = 0.0; buf[b + 5] = h;   buf[b + 6] = 0.0;  buf[b + 7] = data[o + 1]
		buf[b + 8] = 0.0; buf[b + 9] = 0.0; buf[b + 10] = 1.0; buf[b + 11] = data[o + 2]
		buf[b + 12] = data[o + 5]; buf[b + 13] = data[o + 6]; buf[b + 14] = data[o + 7]; buf[b + 15] = data[o + 8]
	mm.buffer = buf
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/billboard.gdshader")
	mat.set_shader_parameter("atlas", load(ATLAS))
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the whole disc, so the one instance is never culled
	custom_aabb = AABB(Vector3(-1200, -10, -1200), Vector3(2400, 60, 2400))
