class_name Bullet
extends Node3D
## Vulcan round: fast tracer with a swept segment-vs-sphere hit test against enemies.

static var _mesh: BoxMesh
static var _mat: StandardMaterial3D

var velocity := Vector3.ZERO
var life := 2.2
var damage := 1.0

func _ready() -> void:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3(0.45, 0.45, 7.0)
		_mat = World.flat_material(Palette.c(Palette.YELLOW))
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	add_child(mi)
	_orient()

func _orient() -> void:
	if velocity.length_squared() > 0.001:
		var d := velocity.normalized()
		if abs(d.dot(Vector3.UP)) < 0.999:
			look_at(global_position + d, Vector3.UP)

func _physics_process(delta: float) -> void:
	var start := global_position
	var end := start + velocity * delta
	var seg := end - start
	var seg_len2 := seg.length_squared()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var p: Vector3 = e.global_position
		var t := 0.0
		if seg_len2 > 0.0:
			t = clampf((p - start).dot(seg) / seg_len2, 0.0, 1.0)
		var closest := start + seg * t
		if closest.distance_squared_to(p) <= e.radius * e.radius:
			e.hit(damage, closest)
			queue_free()
			return
	global_position = end
	life -= delta
	if life <= 0.0 or global_position.y < Terrain.height_at(global_position.x, global_position.z) - 0.5:
		queue_free()
