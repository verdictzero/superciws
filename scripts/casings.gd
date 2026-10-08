class_name Casings
extends MultiMeshInstance3D
## Spent brass from the vulcan. One MultiMesh holds every casing; each one is thrown out of
## the gun's right side, tumbles, bounces off the mount and the sand, lies there a while and
## sinks away. The oldest casing is recycled when the pool is full.

const POOL := 240
const GRAVITY := 32.0
const GROUND_Y := -0.6
const RADIUS := 0.24
const LIFE := 5.0
# the CIWS mount: a tapered block centred on the origin
const MOUNT_TOP := 10.76
const MOUNT_HALF_BASE := 6.56
const MOUNT_HALF_TOP := 4.2

var pos: Array[Vector3] = []
var vel: Array[Vector3] = []
var axis: Array[Vector3] = []
var angle: Array[float] = []
var spin: Array[float] = []
var age: Array[float] = []
var resting: Array[bool] = []
var count := 0
var mount_xs: Array[float] = [0.0]   # x of each CIWS mount in the row
var next := 0

func _ready() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS * 0.85
	cm.bottom_radius = RADIUS
	cm.height = 0.95
	cm.radial_segments = 6
	cm.rings = 1
	var brass := World.toon(Palette.c(Palette.GOLD), 0.0, -0.5, 0.5)
	World.set_emission(brass, Palette.c(Palette.ORANGE) * 0.35)   # a little glint so the brass reads against the sand
	cm.material = brass
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cm
	multimesh.instance_count = POOL
	multimesh.visible_instance_count = 0
	pos.resize(POOL); vel.resize(POOL); axis.resize(POOL); angle.resize(POOL)
	spin.resize(POOL); age.resize(POOL); resting.resize(POOL)
	extra_cull_margin = 64.0

## Eject one casing from `from`, thrown toward `right` (the gun's right-hand side).
func eject(from: Vector3, right: Vector3, back: Vector3) -> void:
	var i := count
	if count < POOL:
		count += 1
	else:
		i = next
		next = (next + 1) % POOL
	pos[i] = from
	vel[i] = right * randf_range(6.0, 10.0) + Vector3.UP * randf_range(3.0, 7.0) + back * randf_range(0.0, 3.0) \
		+ Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	axis[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	angle[i] = randf() * TAU
	spin[i] = randf_range(14.0, 26.0)
	age[i] = 0.0
	resting[i] = false

func _mount_half(y: float) -> float:
	return lerpf(MOUNT_HALF_BASE, MOUNT_HALF_TOP, clampf((y - GROUND_Y) / (MOUNT_TOP - GROUND_Y), 0.0, 1.0))

func _physics_process(delta: float) -> void:
	var i := 0
	while i < count:
		age[i] += delta
		if age[i] > LIFE:
			_remove(i)
			continue
		if not resting[i]:
			var v := vel[i]
			v.y -= GRAVITY * delta
			var p := pos[i] + v * delta
			var half := _mount_half(p.y)
			var mx := _nearest_mount(p.x)
			p.x -= mx   # collide in the nearest mount's local frame
			if absf(p.x) < half and absf(p.z) < half and p.y < MOUNT_TOP + RADIUS:
				if pos[i].y >= MOUNT_TOP + RADIUS - 0.01:
					# landed on top of the mount
					p.y = MOUNT_TOP + RADIUS
					v = _bounce(v, i)
				else:
					# hit the sloped side: knock it back outward
					if absf(p.x) > absf(p.z):
						p.x = signf(p.x) * half
						v.x = absf(v.x) * signf(p.x) * 0.5
					else:
						p.z = signf(p.z) * half
						v.z = absf(v.z) * signf(p.z) * 0.5
					spin[i] *= 0.7
			elif p.y < GROUND_Y + RADIUS:
				p.y = GROUND_Y + RADIUS
				v = _bounce(v, i)
			p.x += mx
			pos[i] = p
			vel[i] = v
			angle[i] += spin[i] * delta
		var t := Transform3D(Basis(axis[i], angle[i]), pos[i])
		if resting[i]:
			# lying on its side, sinking into the sand at the end of its life
			t = Transform3D(Basis(Vector3.UP, angle[i]) * Basis(Vector3.RIGHT, PI * 0.5), pos[i])
			var sink := clampf((age[i] - (LIFE - 0.8)) / 0.8, 0.0, 1.0)
			t.origin.y -= sink * RADIUS * 2.5
		multimesh.set_instance_transform(i, t)
		i += 1
	multimesh.visible_instance_count = count

func _nearest_mount(x: float) -> float:
	var best := 0.0
	for mx in mount_xs:
		if absf(x - mx) < absf(x - best):
			best = mx
	return best

func _bounce(v: Vector3, i: int) -> Vector3:
	if absf(v.y) < 2.5:
		resting[i] = true
		return Vector3.ZERO
	spin[i] *= 0.6
	axis[i] = (axis[i] + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))).normalized()
	return Vector3(v.x * 0.45, -v.y * 0.35, v.z * 0.45)

func _remove(i: int) -> void:
	count -= 1
	if i != count:
		pos[i] = pos[count]; vel[i] = vel[count]; axis[i] = axis[count]; angle[i] = angle[count]
		spin[i] = spin[count]; age[i] = age[count]; resting[i] = resting[count]
	if next > count:
		next = 0
