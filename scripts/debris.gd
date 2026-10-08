class_name Debris
extends Node3D
## Tumbling wreckage: chunks thrown from a kill that fall, bounce on the sand,
## trail smoke and lie there for a while before sinking away.

static var _box: BoxMesh

var _chunks: Array = []   # [MeshInstance3D, velocity, angular_velocity, resting]
var _age := 0.0
var _life := 4.5
var _smoke_t := 0.0
var _size := 1.0

static func spawn(parent: Node, pos: Vector3, count: int, colors: Array, size: float = 1.0, boost: float = 1.0) -> Debris:
	var d := Debris.new()
	d._size = size
	d._life = 3.5 + size * 1.5
	parent.add_child(d)
	d.global_position = pos
	d._build(count, colors, boost)
	return d

func _build(count: int, colors: Array, boost: float) -> void:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _box
		mi.material_override = World.toon(Palette.c(colors[i % colors.size()]), 1.0, -0.5, 0.5)
		mi.scale = Vector3(randf_range(0.8, 2.6), randf_range(0.4, 1.2), randf_range(0.8, 3.0)) * _size
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(mi)
		var v := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized() * randf_range(10, 26) * boost
		var av := Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		_chunks.append([mi, v, av, false])

func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	var fade := clampf((_life - _age) / 0.6, 0.0, 1.0)
	_smoke_t -= delta
	var any_moving := false
	for c in _chunks:
		var mi: MeshInstance3D = c[0]
		if c[3]:
			if fade < 1.0:
				mi.position.y -= delta * 2.0   # sink into the sand
			continue
		any_moving = true
		var v: Vector3 = c[1]
		v.y -= 42.0 * delta
		var p := mi.global_position + v * delta
		var floor_y := mi.scale.y * 0.5 - 0.4
		if p.y <= floor_y:
			p.y = floor_y
			if absf(v.y) > 6.0:
				v.y = -v.y * 0.35
				v.x *= 0.6
				v.z *= 0.6
				c[2] = c[2] * 0.5
			else:
				v = Vector3.ZERO
				c[3] = true
				mi.rotation.x = roundf(mi.rotation.x / (PI * 0.5)) * PI * 0.5
				mi.rotation.z = roundf(mi.rotation.z / (PI * 0.5)) * PI * 0.5
		mi.global_position = p
		mi.rotation += c[2] * delta
		c[1] = v
	if any_moving and _smoke_t <= 0.0 and _age < 1.6:
		_smoke_t = 0.12
		var c = _chunks[randi() % _chunks.size()]
		if not c[3]:
			Explosion.sprite(get_parent(), c[0].global_position, "smoke", 0.5 * _size)
