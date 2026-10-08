class_name Turret
extends Node3D
## The player's stationary CIWS. Built from player_ciws.glb using its node names:
##   CIWSunit1 > ciwsLeftRightAxis (yaw) > ciwsUpDownAxis (pitch) > barrel + 3 addon meshes.

const MODEL := "res://assets/models/player_ciws.glb"
const PITCH_MIN := -8.0
const PITCH_MAX := 82.0
const CAMERA_TILT := 25.0   # degrees the camera looks below the gun line
const YAW_MARGIN := 25.0   # degrees of traverse allowed beyond the attack cone   # degrees the camera looks below the gun line

var yaw_node: Node3D
var pitch_node: Node3D
var barrel: Node3D
var addons: Dictionary = {}   # item id -> Node3D
var camera: Camera3D
var muzzle_flash: MeshInstance3D

var yaw := 0.0            # degrees, current
var pitch := 10.0
var target_yaw := 0.0
var target_pitch := 10.0
var spin := 0.0
var firing := false
var fire_accum := 0.0
var hidden_for_death := false

func _ready() -> void:
	var scene: PackedScene = load(MODEL)
	var model: Node3D = scene.instantiate()
	add_child(model)
	yaw_node = model.find_child("ciwsLeftRightAxis", true, false)
	pitch_node = model.find_child("ciwsUpDownAxis", true, false)
	barrel = model.find_child("ciwsBarrngelROTATEthisWHENfiri", true, false)
	if barrel == null:
		for n in pitch_node.get_children():
			if n.name.to_lower().contains("barr"):
				barrel = n
	for id in Items.WEAPONS.keys():
		var node_name: String = Items.WEAPONS[id]["node"]
		if node_name != "":
			var n := model.find_child(node_name, true, false)
			if n:
				addons[id] = n
	_restyle(model)
	refresh_addons()

	camera = Camera3D.new()
	camera.fov = 66.0
	camera.near = 0.5
	camera.far = 2500.0
	camera.position = Vector3(0, 29.0, -34.0)
	yaw_node.add_child(camera)
	camera.current = true

	muzzle_flash = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 2.2
	sm.radial_segments = 6
	sm.rings = 3
	muzzle_flash.mesh = sm
	muzzle_flash.material_override = World.flat_material(Palette.c(Palette.YELLOW), true)
	muzzle_flash.visible = false
	barrel.add_child(muzzle_flash)
	muzzle_flash.position = Vector3(0, 0, 2.4)
	_apply_rotation()

func _restyle(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var m := StandardMaterial3D.new()
			if src is BaseMaterial3D:
				m.albedo_color = src.albedo_color * Color(0.55, 0.55, 0.6)   # darker gunmetal
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			mi.set_surface_override_material(i, m)

func refresh_addons() -> void:
	for id in addons.keys():
		addons[id].visible = Game.item_level(id) > 0

## Called by main with the joystick/mouse aim input for this frame.
## stick: -1..1 per axis (x = right, y = up), mouse: pixel delta.
func aim(stick: Vector2, mouse: Vector2, delta: float) -> void:
	var rate := Game.traverse_speed
	target_yaw += stick.x * rate * delta
	target_pitch += stick.y * rate * delta
	target_yaw += mouse.x * 0.14
	target_pitch -= mouse.y * 0.14
	target_pitch = clampf(target_pitch, PITCH_MIN, PITCH_MAX)

func track_toward(world_point: Vector3, strength: float, delta: float) -> void:
	## Radar auto-track nudges the aim toward a lead point if it is close to the reticle.
	var p := world_point - camera.global_position
	var want_yaw := rad_to_deg(atan2(p.x, p.z))
	var want_pitch := rad_to_deg(atan2(p.y, Vector2(p.x, p.z).length()))
	var dy := wrapf(want_yaw - target_yaw, -180.0, 180.0)
	var dp := want_pitch - target_pitch
	if strength >= 1.0 or (abs(dy) < 14.0 and abs(dp) < 14.0):
		target_yaw += dy * strength * delta * 5.0
		target_pitch += dp * strength * delta * 5.0

func update(delta: float) -> void:
	var rate := Game.traverse_speed * delta
	# traverse is limited to the attack cone plus a margin, so the player
	# can never aim away from where the enemies come from
	var lim := Game.attack_arc() * 0.5 + YAW_MARGIN
	if lim < 180.0:
		target_yaw = clampf(wrapf(target_yaw, -180.0, 180.0), -lim, lim)
		yaw = clampf(yaw, -lim, lim)
	var dy := wrapf(target_yaw - yaw, -180.0, 180.0)
	yaw += clampf(dy, -rate, rate)
	yaw = wrapf(yaw, -180.0, 180.0)
	target_yaw = wrapf(target_yaw, -180.0, 180.0)
	var dp := target_pitch - pitch
	pitch += clampf(dp, -rate, rate)
	pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	if firing:
		spin += delta * 22.0
	_apply_rotation()
	barrel.rotation.z = spin
	muzzle_flash.visible = firing and (Engine.get_frames_drawn() % 2 == 0)

func _apply_rotation() -> void:
	yaw_node.rotation.y = deg_to_rad(yaw)
	pitch_node.rotation.x = -deg_to_rad(pitch)
	camera.rotation = Vector3(deg_to_rad(pitch - CAMERA_TILT), PI, 0)

func aim_dir() -> Vector3:
	return -camera.global_basis.z

func muzzle_pos() -> Vector3:
	return barrel.global_transform * Vector3(0, 0, 2.4)

func gun_pos() -> Vector3:
	return pitch_node.global_position

func set_destroyed(d: bool) -> void:
	hidden_for_death = d
	pitch_node.visible = not d
