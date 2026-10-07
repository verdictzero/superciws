class_name Explosion
extends Node3D
## Chunky particle burst: a handful of unshaded boxes thrown outward with gravity,
## plus an expanding flash sphere. Palette-safe colours only.

static var _box: BoxMesh
static var _mats: Dictionary = {}

var _parts: Array = []   # [MeshInstance3D, velocity]
var _flash: MeshInstance3D
var _t := 0.0
var _life := 0.7
var _size := 1.0

static func mat(idx: int) -> StandardMaterial3D:
	if not _mats.has(idx):
		_mats[idx] = World.flat_material(Palette.c(idx), true)
	return _mats[idx]

static func spawn(parent: Node, pos: Vector3, size: float = 1.0, colors: Array = [Palette.ORANGE, Palette.YELLOW, Palette.WHITE, Palette.RED], count: int = 10) -> Explosion:
	var e := Explosion.new()
	e._size = size
	e._life = 0.55 + 0.25 * size
	parent.add_child(e)
	e.global_position = pos
	e._build(colors, count)
	if size >= 3.0:
		sprite(parent, pos, "column", size * 0.45)
	elif size >= 1.5:
		sprite(parent, pos, "large", size * 0.8)
	else:
		sprite(parent, pos, "medium", 0.7 + size * 0.5)
	return e

func _build(colors: Array, count: int) -> void:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _box
		mi.material_override = mat(colors[i % colors.size()])
		var s := randf_range(0.6, 1.6) * _size
		mi.scale = Vector3(s, s, s)
		add_child(mi)
		var v := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.2), randf_range(-1, 1)).normalized() * randf_range(14, 34) * sqrt(_size)
		_parts.append([mi, v])
	_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	_flash.mesh = sm
	_flash.material_override = mat(colors[0])
	add_child(_flash)

func _process(delta: float) -> void:
	_t += delta
	var k := _t / _life
	if k >= 1.0:
		queue_free()
		return
	for p in _parts:
		var mi: MeshInstance3D = p[0]
		var v: Vector3 = p[1]
		v.y -= 40.0 * delta
		p[1] = v
		mi.position += v * delta
		var s := (1.0 - k) * _size
		mi.scale = Vector3(s, s, s) * 1.2
	var fs := (1.0 + k * 9.0) * _size * (1.0 - k)
	_flash.scale = Vector3(fs, fs, fs)
	_flash.visible = k < 0.5

## --- sprite explosions (frames from galvarius) ------------------------------
const SPRITE_SETS := {
	"small": {"prefix": "res://assets/sprites/explosions/explosion_small_A_%02d.png", "count": 6, "fps": 20.0, "px": 0.55},
	"medium": {"prefix": "res://assets/sprites/explosions/explosion_medium_A_%02d.png", "count": 10, "fps": 18.0, "px": 0.42},
	"large": {"prefix": "res://assets/sprites/explosions/explosion_large_B_%02d.png", "count": 9, "fps": 16.0, "px": 0.6},
	"column": {"prefix": "res://assets/sprites/explosions/bigger_explosion_%04d.png", "count": 30, "fps": 16.0, "px": 0.9},
}
static var _frames: Dictionary = {}

static func _load_frames(set_name: String) -> Array:
	if not _frames.has(set_name):
		var d: Dictionary = SPRITE_SETS[set_name]
		var arr: Array = []
		for i in d["count"]:
			arr.append(load(d["prefix"] % (i + 1)))
		_frames[set_name] = arr
	return _frames[set_name]

static func sprite(parent: Node, pos: Vector3, set_name: String, scale_mult: float = 1.0) -> void:
	var d: Dictionary = SPRITE_SETS[set_name]
	var s := SpriteExplosion.new()
	s.frames = _load_frames(set_name)
	s.fps = d["fps"]
	s.pixel_size = d["px"] * scale_mult
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.no_depth_test = false
	s.texture = s.frames[0]
	if set_name == "column":
		s.offset = Vector2(0, 64)   # anchor the column at its base
	parent.add_child(s)
	s.global_position = pos

class SpriteExplosion extends Sprite3D:
	var frames: Array = []
	var fps := 16.0
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		var i := int(_t * fps)
		if i >= frames.size():
			queue_free()
			return
		texture = frames[i]
