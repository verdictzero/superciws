class_name HomingMissile
extends Node3D
## Auto-launched homing missile from the quad missile addon.

var target: Node3D
var dir := Vector3.UP
var speed := 115.0
var turn := 3.6
var life := 7.0
var damage := 6.0
var splash := false
var _age := 0.0

func _ready() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.9, 4.5)
	body.mesh = bm
	body.material_override = World.toon(Palette.c(Palette.OFFWHITE), 1.0)
	add_child(body)
	var flame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.7, 0.7, 1.6)
	flame.mesh = fm
	flame.material_override = World.flat_material(Palette.c(Palette.ORANGE))
	flame.position = Vector3(0, 0, 3.0)
	add_child(flame)

func _physics_process(delta: float) -> void:
	_age += delta
	life -= delta
	var main := get_tree().current_scene
	if not is_instance_valid(target) or target.dead:
		target = main.nearest_enemy(global_position)
	if is_instance_valid(target) and _age > 0.25:
		var want := (target.global_position - global_position).normalized()
		dir = dir.lerp(want, clampf(turn * delta, 0.0, 1.0)).normalized()
	global_position += dir * speed * delta
	if abs(dir.dot(Vector3.UP)) < 0.999:
		look_at(global_position + dir, Vector3.UP)
	if is_instance_valid(target) and global_position.distance_to(target.global_position) < target.radius + 2.5:
		_detonate(main)
		return
	if life <= 0.0 or global_position.y < -2.0:
		_detonate(main)

func _detonate(main: Node) -> void:
	Explosion.spawn(main.fx, global_position, 1.6 if splash else 0.9, [Palette.ORANGE, Palette.YELLOW, Palette.WHITE], 8)
	Sfx.play("explode", -6.0, 1.3)
	if splash:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.dead and e.global_position.distance_to(global_position) < 22.0:
				e.hit(damage, global_position)
	elif is_instance_valid(target) and not target.dead:
		target.hit(damage, global_position)
	queue_free()
