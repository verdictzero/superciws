class_name Crate
extends Node3D
## Loot crate dropped by advanced enemies. Parachutes down, then opens the slot machine.

var kind := "advanced"
var _sway := 0.0
var _landed := false

func _ready() -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 4, 4)
	box.mesh = bm
	box.material_override = World.toon(Palette.c(Palette.OCHRE), 1.0)
	add_child(box)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(4.2, 1.2, 4.2)
	stripe.mesh = sm
	stripe.material_override = World.flat_material(Palette.c(Palette.YELLOW if kind != "purple" else Palette.PURPLE))
	add_child(stripe)
	var chute := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 7.0
	cm.height = 5.0
	cm.radial_segments = 8
	cm.rings = 1
	chute.mesh = cm
	chute.material_override = World.toon(Palette.c(Palette.OFFWHITE if kind != "purple" else Palette.PINK), 1.0)
	chute.position = Vector3(0, 9.0, 0)
	add_child(chute)
	_sway = randf() * TAU
	if global_position.y < 30.0:
		global_position.y = 30.0 + randf() * 20.0

func _process(delta: float) -> void:
	if _landed:
		return
	_sway += delta * 1.5
	global_position.y -= 11.0 * delta
	global_position.x += sin(_sway) * 3.0 * delta
	rotation.z = sin(_sway) * 0.15
	if global_position.y <= Terrain.height_at(global_position.x, global_position.z) + 2.6:
		_landed = true
		Sfx.play("crate")
		get_tree().current_scene.open_crate(kind)
		queue_free()
