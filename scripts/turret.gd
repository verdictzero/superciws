class_name Turret
extends Node3D
## The player's stationary CIWS. Built from player_ciws.glb using its node names:
##   CIWSunit1 > ciwsLeftRightAxis (yaw) > ciwsUpDownAxis (pitch) > barrel + 3 addon meshes.
## The main mount carries the camera and takes the player's input. LINKED MOUNT upgrades add
## wing mounts (`linked = true`) that slave to it, converging their guns on its aim point.

const MODEL := "res://assets/models/player_ciws.glb"
const PITCH_MIN := -8.0
const PITCH_MAX := 82.0
# The camera does not ride the gun's elevation: it holds a framing angle that shows the
# mount and the horizon, and only follows the barrel part of the way up so high targets
# stay on screen. The crosshair is drawn where the barrel really points.
const CAM_PITCH_BASE := -25.0     # camera pitch with the barrel level
const CAM_PITCH_FOLLOW := 0.65    # how much of the barrel's elevation the camera takes
const CAM_PITCH_MAX := 22.0
const IDLE_PITCH := 6.0           # where the barrel rests with nothing to track
const YAW_MARGIN := 25.0   # degrees of traverse allowed beyond the attack cone
const ASSIST_WINDOW := 20.0   # degrees of heading error inside which aim assist pulls
const TRACK_WINDOW := 30.0    # degrees of heading error inside which elevation locks on
const CONVERGE := 300.0    # metres down range where linked guns cross the main gun's line

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
var cam_pitch := CAM_PITCH_BASE
var firing := false
var fire_accum := 0.0
var hidden_for_death := false
var linked := false        # wing mount: no camera, follows the main mount
var linked_dir := Vector3.FORWARD

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

	if not linked:
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
	muzzle_flash.material_override = World.flat_material(Palette.c(Palette.YELLOW))
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
			var col := Color(0.8, 0.8, 0.8)
			if src is BaseMaterial3D:
				col = src.albedo_color
			# darker gunmetal, one gradient over the whole mount from the sand up to the gun
			var m := World.toon(col * Color(0.55, 0.55, 0.6), 1.0, -0.6, 18.0, true)
			mi.set_surface_override_material(i, m)

## Pull the camera back and up for each linked mount so the whole row stays in view;
## `center_x` slides it sideways (world x at yaw 0) to the middle of the row.
func frame_mounts(count: int, center_x: float) -> void:
	if camera:
		var n := float(count - 1)
		camera.position = Vector3(center_x, 29.0 + 4.0 * n, -34.0 - 8.0 * n)

func refresh_addons() -> void:
	for id in addons.keys():
		addons[id].visible = Game.item_level(id) > 0

## The player only traverses: steer is -1..1 (right = +1), mouse is a pixel delta.
## Yaw grows toward world +X, which is screen LEFT from behind the gun, hence the minus.
func aim(steer: float, mouse_x: float, delta: float) -> void:
	target_yaw -= steer * Game.traverse_speed * delta
	target_yaw -= mouse_x * 0.14

## Yaw and pitch (degrees) the barrel needs to point at a world point.
func angles_to(world_point: Vector3) -> Vector2:
	var p := world_point - gun_pos()
	return Vector2(rad_to_deg(atan2(p.x, p.z)), rad_to_deg(atan2(p.y, Vector2(p.x, p.z).length())))

## Degrees between the gun's current heading and a world point, signed like yaw.
func yaw_error(world_point: Vector3) -> float:
	return wrapf(angles_to(world_point).x - yaw, -180.0, 180.0)

## Elevation is automatic: the barrel lays itself onto the tracked point.
func track_pitch(world_point: Vector3) -> void:
	target_pitch = clampf(angles_to(world_point).y, PITCH_MIN, PITCH_MAX)

func idle_pitch() -> void:
	target_pitch = IDLE_PITCH

## Aim assist on traverse: drift the heading onto a point near the crosshair.
## strength 1 = full lock (debug autoaim).
func assist_yaw(world_point: Vector3, strength: float, delta: float) -> void:
	var dy := wrapf(angles_to(world_point).x - target_yaw, -180.0, 180.0)
	if strength >= 1.0 or absf(dy) < ASSIST_WINDOW:
		target_yaw += dy * minf(strength * delta * 5.0, 1.0)

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
	var want_cam := clampf(CAM_PITCH_BASE + pitch * CAM_PITCH_FOLLOW, CAM_PITCH_BASE, CAM_PITCH_MAX)
	cam_pitch = lerpf(cam_pitch, want_cam, minf(delta * 3.0, 1.0))
	if firing:
		spin += delta * 22.0
	_apply_rotation()
	barrel.rotation.z = spin
	muzzle_flash.visible = firing and (Engine.get_frames_drawn() % 2 == 0)

## Wing mount: swing to the point the main gun is aimed at, at the main gun's traverse speed.
func follow(main_mount: Turret, delta: float) -> void:
	var goal := main_mount.muzzle_pos() + main_mount.aim_dir() * CONVERGE
	var p := goal - gun_pos()
	linked_dir = p.normalized()
	target_yaw = rad_to_deg(atan2(p.x, p.z))
	target_pitch = clampf(rad_to_deg(atan2(p.y, Vector2(p.x, p.z).length())), PITCH_MIN, PITCH_MAX)
	firing = main_mount.firing
	var rate := Game.traverse_speed * 1.5 * delta
	yaw += clampf(wrapf(target_yaw - yaw, -180.0, 180.0), -rate, rate)
	pitch += clampf(target_pitch - pitch, -rate, rate)
	if firing:
		spin += delta * 22.0
	_apply_rotation()
	barrel.rotation.z = spin
	muzzle_flash.visible = firing and visible and (Engine.get_frames_drawn() % 2 == 0)

func _apply_rotation() -> void:
	yaw_node.rotation.y = deg_to_rad(yaw)
	pitch_node.rotation.x = -deg_to_rad(pitch)
	if camera:
		camera.rotation = Vector3(deg_to_rad(cam_pitch), PI, 0)

## Where the rounds go: straight down the barrel.
func aim_dir() -> Vector3:
	if linked:
		return linked_dir
	return barrel.global_basis.z.normalized()

func muzzle_pos() -> Vector3:
	return barrel.global_transform * Vector3(0, 0, 2.4)

## Where spent casings leave the gun: the housing's right-hand side as seen from the camera.
func eject_pos(right: Vector3) -> Vector3:
	return pitch_node.global_position + right * 2.6 + Vector3.UP * 0.4

func gun_pos() -> Vector3:
	return pitch_node.global_position

func set_destroyed(d: bool) -> void:
	hidden_for_death = d
	pitch_node.visible = not d
