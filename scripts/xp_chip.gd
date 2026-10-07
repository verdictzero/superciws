class_name XpChip
extends Node3D
## XP dropped by a kill. Flies to the turret (the player cannot walk to it).

static var _mesh: BoxMesh
static var _mat_green: StandardMaterial3D
static var _mat_cyan: StandardMaterial3D

var value := 1
var _t := 0.0
var _start := Vector3.ZERO
var _delay := 0.0

func _ready() -> void:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3(1.6, 1.6, 1.6)
		_mat_green = World.flat_material(Palette.c(Palette.GREEN), true)
		_mat_cyan = World.flat_material(Palette.c(Palette.CYAN), true)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat_cyan if value >= 5 else _mat_green
	mi.rotation = Vector3(PI / 4, PI / 4, 0)
	add_child(mi)
	_start = global_position
	_delay = randf_range(0.1, 0.45)

func _process(delta: float) -> void:
	_delay -= delta
	rotate_y(delta * 6.0)
	if _delay > 0.0:
		position.y += delta * 6.0
		_start = global_position
		return
	_t += delta * 1.6
	var k := clampf(_t, 0.0, 1.0)
	k = k * k
	var goal: Vector3 = get_tree().current_scene.turret.gun_pos()
	global_position = _start.lerp(goal, k) + Vector3(0, sin(k * PI) * 12.0, 0)
	if k >= 1.0:
		get_tree().current_scene.collect_xp(value)
		queue_free()
