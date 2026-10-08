class_name Terrain
extends Node3D
## The baked desert floor (tools/bake_terrain.gd + tools/bake_ground.py) and the ground
## height query everything that lands on it uses. Nothing is generated at runtime.

const BAKE := "res://assets/terrain/bake/"
const GROUND := "res://assets/terrain/"

static var _grid := PackedFloat32Array()
static var _size := 0
static var _step := 4.0
static var _origin := -1152.0
static var _fallback_y := -0.6

func _ready() -> void:
	_load_heights()
	var scene: PackedScene = load(BAKE + "terrain.scn")
	if scene == null:
		push_error("Terrain: missing bake, run tools/bake_terrain.gd")
		return
	var mesh_root := scene.instantiate()
	add_child(mesh_root)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GROUND + "ground.json"))
	for level in info["levels"]:
		var n: String = level["name"]
		var size: float = level["size"]
		var c: Array = level["centre"]
		mat.set_shader_parameter("ground_" + n, load(GROUND + "ground_%s.png" % n))
		mat.set_shader_parameter(n + "_rect", Vector3(float(c[0]) - size * 0.5, float(c[1]) - size * 0.5, size))
	for mi in mesh_root.get_children():
		if mi is MeshInstance3D:
			mi.material_override = mat

static func _load_heights() -> void:
	if _size > 0:
		return
	var f := FileAccess.open(BAKE + "height.bin", FileAccess.READ)
	if f == null:
		push_error("Terrain: missing height.bin")
		return
	if f.get_buffer(4).get_string_from_ascii() != "HGT2":
		push_error("Terrain: bad height.bin, rebake with tools/bake_terrain.gd")
		return
	var size := f.get_32()
	_step = f.get_float()
	_origin = f.get_float()
	var packed := f.get_buffer(f.get_32())
	_grid = packed.decompress(size * size * 4, FileAccess.COMPRESSION_GZIP).to_float32_array()
	_size = size

## Ground height at a world XZ, bilinear on the baked grid. Off the map: the flat base.
static func height_at(x: float, z: float) -> float:
	if _size == 0:
		_load_heights()
		if _size == 0:
			return _fallback_y
	var u := (x - _origin) / _step
	var v := (z - _origin) / _step
	if u < 0.0 or v < 0.0 or u >= float(_size - 1) or v >= float(_size - 1):
		return _fallback_y
	var i := int(u)
	var j := int(v)
	var fu := u - float(i)
	var fv := v - float(j)
	var k := j * _size + i
	var a := lerpf(_grid[k], _grid[k + 1], fu)
	var b := lerpf(_grid[k + _size], _grid[k + _size + 1], fu)
	return lerpf(a, b, fv)
