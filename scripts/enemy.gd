class_name Enemy
extends Node3D
## Drones, missiles and the UFO boss. Behaviour is simple and readable on purpose.

enum Type { QUAD, FIXED, MISSILE, UFO }
const TARGET := Vector3(0, 14, 0)

static var _scenes: Dictionary = {}   # model name -> PackedScene
static var flash_mat: StandardMaterial3D
static var pulse_mat: StandardMaterial3D
static var outline_mats: Array = []   # per advanced level: inverted-hull silhouette shells

var type: int = Type.QUAD
var advanced := 0          # 0 normal, 1 gold, 2 purple
var hp := 3.0
var max_hp := 3.0
var speed := 20.0
var radius := 6.0
var points := 100
var xp_value := 2
var damage := 10.0
var dead := false
var age := 0.0
var phase := 0.0
var lateral := Vector3.ZERO
var model: Node3D
var flash_t := 0.0
var mesh_instances: Array = []
var spawn_timer := 4.0
var orbit_angle := 0.0
var is_boss := false
var velocity := Vector3.ZERO
# fixed-wing flight state
var diving := false
var bank := 0.0
var fw_speed := 0.0

static func _ensure_templates() -> void:
	if not _scenes.is_empty():
		return
	var en: PackedScene = load("res://assets/models/enemies.glb")
	var uf: PackedScene = load("res://assets/models/ufo.glb")
	for n in ["fixed_wing_drone", "quad_drone", "missile"]:
		_scenes[n] = en
	_scenes["ufo"] = uf
	flash_mat = World.flat_material(Palette.c(Palette.WHITE), true)
	pulse_mat = World.flat_material(Palette.c(Palette.RED))
	pulse_mat.emission_enabled = true
	pulse_mat.emission = Palette.c(Palette.ORANGE)
	pulse_mat.emission_energy_multiplier = 1.0
	pulse_mat.disable_fog = true
	for col in [Palette.BLACK, Palette.RED, Palette.WHITE]:
		var o := World.flat_material(Palette.c(col), true)
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.12
		o.disable_fog = true
		outline_mats.append(o)

func setup(t: int, advanced_level: int, difficulty: float) -> void:
	_ensure_templates()
	type = t
	advanced = advanced_level
	phase = randf() * TAU
	lateral = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var model_name := "quad_drone"
	var model_scale := 2.8
	match type:
		Type.QUAD:
			model_name = "quad_drone"; model_scale = 2.8
			hp = 3.0; speed = 21.0; radius = 6.0; points = 100; xp_value = 2; damage = 10.0
		Type.FIXED:
			model_name = "fixed_wing_drone"; model_scale = 1.35
			hp = 5.0; speed = 46.0; radius = 9.0; points = 150; xp_value = 3; damage = 15.0
		Type.MISSILE:
			model_name = "missile"; model_scale = 1.1
			hp = 1.0; speed = 95.0; radius = 5.0; points = 120; xp_value = 2; damage = 25.0
		Type.UFO:
			model_name = "ufo"; model_scale = 1.3
			hp = 140.0; speed = 28.0; radius = 15.0; points = 3000; xp_value = 40; damage = 0.0
			is_boss = true
	hp *= difficulty
	speed *= Game.enemy_speed_mult()
	damage *= Game.enemy_damage_mult()
	if advanced == 1:
		hp *= 6.0; model_scale *= 1.5; radius *= 1.5; speed *= 0.85; points *= 5; xp_value *= 4
	elif advanced == 2:
		hp *= 10.0; model_scale *= 1.6; radius *= 1.6; speed *= 0.8; points *= 8; xp_value *= 6
	max_hp = hp
	var inst: Node = _scenes[model_name].instantiate()
	model = inst.get_node(model_name)
	inst.remove_child(model)
	inst.queue_free()
	model.position = Vector3.ZERO
	model.rotation = Vector3(0, PI, 0)   # glTF +Z forward -> Godot -Z forward
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	_restyle(model)
	add_to_group("enemies")

func _restyle(root: Node) -> void:
	var tint := Palette.c(Palette.YELLOW) if advanced == 1 else (Palette.c(Palette.PURPLE) if advanced == 2 else Color.WHITE)
	var all: Array = [root] if root is MeshInstance3D else []
	all.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for mi in all:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		mesh_instances.append(mi)
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var nm: String = src.resource_name if src else ""
			if nm.to_lower().contains("flashing"):
				mi.set_surface_override_material(i, pulse_mat)
				continue
			var m := StandardMaterial3D.new()
			var base := Color(0.8, 0.8, 0.8)
			var glow := Color.BLACK
			if src is BaseMaterial3D:
				base = src.albedo_color
				if src.emission_enabled:
					glow = src.emission * 1.5
			if advanced > 0:
				base = base.lerp(tint, 0.75)
			# lift the hull so it reads against sand and sky: brighter albedo plus a self-lit floor
			base = base.lightened(0.2)
			m.albedo_color = base
			m.emission_enabled = true
			m.emission = glow + base * 0.35
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			m.disable_fog = true   # enemies stay crisp at any range
			if type != Type.UFO:
				m.next_pass = outline_mats[advanced]
			mi.set_surface_override_material(i, m)

func hit(dmg: float, _at: Vector3) -> void:
	if dead:
		return
	hp -= dmg * Game.dmg_mult
	flash_t = 0.07
	if randf() < 0.5:
		Explosion.sprite(get_tree().current_scene.fx, _at, "small", 0.8)
	for mi in mesh_instances:
		mi.material_override = flash_mat
	if hp <= 0.0:
		die(true)

func die(by_player: bool) -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemies")
	get_tree().current_scene.on_enemy_killed(self, by_player)
	queue_free()

func _physics_process(delta: float) -> void:
	if dead:
		return
	age += delta
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			for mi in mesh_instances:
				mi.material_override = null
	var main := get_tree().current_scene
	var to_t := TARGET - global_position
	var dist := to_t.length()
	var dir := to_t / maxf(dist, 0.001)
	var vel := Vector3.ZERO
	match type:
		Type.QUAD:
			if dist > 85.0:
				var alt_fix := Vector3(0, clampf(28.0 - global_position.y, -1, 1) * 0.25, 0)
				vel = (dir + lateral * sin(age * 2.0 + phase) * 0.55 + alt_fix).normalized() * speed
			else:
				vel = dir * speed * 1.5
		Type.FIXED:
			vel = _fly_fixed_wing(delta, to_t)
		Type.MISSILE:
			vel = dir * speed
		Type.UFO:
			# sweep back and forth across the attack cone instead of a full orbit
			orbit_angle += delta * speed / 150.0
			var half := deg_to_rad(Game.attack_arc() * 0.5)
			var bearing := sin(orbit_angle) * half if half < PI else orbit_angle
			var want := Vector3(sin(bearing) * 150.0, 75.0 + sin(age * 0.7) * 8.0, cos(bearing) * 150.0)
			var d := want - global_position
			vel = d.normalized() * min(speed * 1.6, d.length() / delta)
			model.rotation.y += delta * 2.0
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				spawn_timer = 4.5
				main.spawn_from_boss(global_position)
	vel *= 1.0 - Game.slow_field
	velocity = vel
	global_position += vel * delta
	if type == Type.FIXED:
		_orient_aircraft(vel)
	elif type != Type.UFO and vel.length_squared() > 0.01:
		var d := vel.normalized()
		if abs(d.dot(Vector3.UP)) < 0.999:
			look_at(global_position + d, Vector3.UP)
	if type != Type.UFO and dist < radius + 7.0:
		main.player_hit(damage, global_position)
		die(false)

## Loitering-munition style attack: cruise in at altitude weaving gently, then roll into a
## steep terminal dive. Heading changes are limited by a turn rate so the drone flies arcs,
## and a missed dive turns into a climbing go-around for another pass.
func _fly_fixed_wing(delta: float, to_t: Vector3) -> Vector3:
	if velocity == Vector3.ZERO:
		var flat := Vector3(to_t.x, 0, to_t.z).normalized()
		velocity = flat.rotated(Vector3.UP, randf_range(-0.45, 0.45)) * speed
		fw_speed = speed
	var hdist := Vector2(to_t.x, to_t.z).length()
	var want: Vector3
	var turn_rate := deg_to_rad(42.0)
	var target_speed := speed
	if not diving:
		# cruise toward a point beside the battery that drifts side to side (S-turns)
		var flat := Vector3(to_t.x, 0, to_t.z) / maxf(hdist, 0.001)
		var side := flat.cross(Vector3.UP)
		var weave := sin(age * 0.55 + phase) * minf(55.0, hdist * 0.22)
		var cruise_alt := 38.0 + sin(phase) * 10.0
		var aim := TARGET + side * weave
		aim.y = cruise_alt
		want = (aim - global_position).normalized()
		if hdist < 150.0 and Vector2(velocity.x, velocity.z).normalized().dot(Vector2(to_t.x, to_t.z).normalized()) > 0.8:
			diving = true
	else:
		want = to_t.normalized()
		turn_rate = deg_to_rad(65.0)
		target_speed = speed * 1.45
		# overshot the battery: pull up and come around
		if velocity.normalized().dot(want) < -0.2 and hdist > 30.0:
			diving = false
		if global_position.y < 6.0:
			want.y = maxf(want.y, 0.3)
	fw_speed = move_toward(fw_speed, target_speed, speed * 0.8 * delta)
	var cur := velocity.normalized()
	var ang := cur.angle_to(want)
	var new_dir := want
	if ang > 0.0001:
		var axis := cur.cross(want)
		if axis.length_squared() < 1e-8:
			axis = Vector3.UP
		new_dir = cur.rotated(axis.normalized(), minf(ang, turn_rate * delta))
	return new_dir * fw_speed

## Nose along the flight path, wings banked into the turn.
func _orient_aircraft(vel: Vector3) -> void:
	if vel.length_squared() < 0.01:
		return
	var d := vel.normalized()
	var prev := Vector3(-global_basis.z.x, 0, -global_basis.z.z)
	var now := Vector3(d.x, 0, d.z)
	var yaw_rate := 0.0
	if age > 0.1 and prev.length_squared() > 1e-4 and now.length_squared() > 1e-4:
		yaw_rate = prev.normalized().signed_angle_to(now.normalized(), Vector3.UP) / maxf(get_physics_process_delta_time(), 0.001)
	bank = lerpf(bank, clampf(yaw_rate * 0.9, -1.2, 1.2), 0.12)
	if absf(d.dot(Vector3.UP)) > 0.999:
		return
	global_basis = Basis.looking_at(d, Vector3.UP) * Basis(Vector3.BACK, bank)

