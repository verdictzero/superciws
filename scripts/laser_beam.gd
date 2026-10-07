class_name LaserBeam
extends Node3D
## Directed energy weapon beam. Visual + continuous damage along a ray.

var outer: MeshInstance3D
var inner: MeshInstance3D
var extra: Array[MeshInstance3D] = []   # prism lance secondary beams

func _ready() -> void:
	outer = _make_beam(0.9, Palette.CYAN)
	inner = _make_beam(0.3, Palette.WHITE)
	for i in 2:
		extra.append(_make_beam(0.5, Palette.CYAN))
	visible = false

func _make_beam(width: float, color: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, 1.0)
	mi.mesh = bm
	mi.material_override = World.flat_material(Palette.c(color), true)
	mi.top_level = true
	add_child(mi)
	return mi

func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01 or abs(d.normalized().dot(Vector3.UP)) > 0.999:
		mi.visible = false
		return
	mi.visible = true
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	mi.scale = Vector3(1, 1, len)

## Fires for one frame. Returns the list of enemies hit.
func fire(origin: Vector3, dir: Vector3, delta: float, dps: float, wide: bool, prism: bool) -> void:
	visible = true
	var enemies := get_tree().get_nodes_in_group("enemies")
	var hits: Array = []   # [t, enemy]
	var w := 6.0 if wide else 2.5
	for e in enemies:
		if e.dead:
			continue
		var rel: Vector3 = e.global_position - origin
		var t := rel.dot(dir)
		if t < 0.0:
			continue
		var perp := (rel - dir * t).length()
		if perp < e.radius + w:
			hits.append([t, e])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var end := origin + dir * 900.0
	var primary: Node3D = null
	if hits.size() > 0:
		primary = hits[0][1]
		end = origin + dir * hits[0][0]
		if wide:
			for h in hits:
				h[1].hit(dps * delta, h[1].global_position)
		else:
			primary.hit(dps * delta, end)
	_place(outer, origin, end)
	_place(inner, origin, end)
	for mi in extra:
		mi.visible = false
	if prism and primary != null:
		# chain to the two nearest other enemies from the impact point
		var others := enemies.filter(func(e): return not e.dead and e != primary)
		others.sort_custom(func(a, b): return a.global_position.distance_squared_to(end) < b.global_position.distance_squared_to(end))
		for i in min(2, others.size()):
			var o = others[i]
			if o.global_position.distance_to(end) < 160.0:
				_place(extra[i], end, o.global_position)
				o.hit(dps * delta * 0.6, o.global_position)

func stop() -> void:
	visible = false
	outer.visible = false
	inner.visible = false
	for mi in extra:
		mi.visible = false
