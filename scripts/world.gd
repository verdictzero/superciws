class_name World
extends Node3D
## Procedural desert: flat sand, two rings of low-poly mountains, rocks, a sun.
## Everything is flat-coloured and vertex lit so the palette filter bands it.

var sun_dir := Vector3(-0.45, -0.55, 0.7).normalized()

static func flat_material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m

func _ready() -> void:
	seed(7)
	_build_environment()
	_build_ground()
	_build_mountains(820.0, 50.0, 170.0, 80, Palette.c(Palette.DARK), Palette.c(Palette.SLATE), 1)
	_build_mountains(540.0, 14.0, 70.0, 64, Palette.c(Palette.BROWN), Palette.c(Palette.OCHRE), 2)
	_build_rocks()
	_build_sun()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Hard-banded sunset: a constant-step gradient of exact palette colours,
	# wrapped as a panorama so bands follow elevation. Zero muddy blends.
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	grad.offsets = PackedFloat32Array([0.0, 0.14, 0.24, 0.33, 0.42, 0.455, 0.485, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Palette.c(Palette.NIGHT), Palette.c(Palette.DEEP_BLUE), Palette.c(Palette.BLUE),
		Palette.c(Palette.LIGHT_BLUE), Palette.c(Palette.PINK), Palette.c(Palette.ORANGE),
		Palette.c(Palette.YELLOW), Palette.c(Palette.SAND), Palette.c(Palette.OCHRE)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 512
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = gt
	mat.filter = false
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.c(Palette.LIGHT_SAND)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Palette.c(Palette.LIGHT_SAND)
	env.fog_density = 0.00035
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.light_color = Palette.c(Palette.LIGHT_SAND)
	light.light_energy = 1.15
	light.shadow_enabled = false
	light.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP)
	add_child(light)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3200, 3200)
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	mi.mesh = pm
	mi.material_override = flat_material(Palette.c(Palette.SAND))
	mi.position.y = -0.6
	add_child(mi)
	# a few darker dune streaks for scale
	for i in 14:
		var d := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(40, 140), randf_range(2, 5), randf_range(8, 20))
		d.mesh = bm
		d.material_override = flat_material(Palette.c(Palette.OCHRE))
		var a := randf() * TAU
		var r := randf_range(90, 380)
		d.position = Vector3(cos(a) * r, -0.2, sin(a) * r)
		d.rotation.y = randf() * TAU
		add_child(d)

func _build_mountains(radius: float, hmin: float, hmax: float, segments: int, lit: Color, shade: Color, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var base: Array[Vector3] = []
	for i in segments:
		var a := TAU * i / segments
		var r := radius + rng.randf_range(-40, 40)
		var h: float = rng.randf_range(hmin * 0.6, hmin * 1.6) if i % 2 == 1 else rng.randf_range(hmin + (hmax - hmin) * 0.45, hmax)
		pts.append(Vector3(cos(a) * r, h, sin(a) * r))
		base.append(Vector3(cos(a) * (r + 60), -1.0, sin(a) * (r + 60)))
	for i in segments:
		var j := (i + 1) % segments
		# two faces per segment, alternate colour so the ridge reads as faceted
		var c := lit if i % 2 == 0 else shade
		st.set_color(c)
		st.add_vertex(base[i]); st.add_vertex(pts[i]); st.add_vertex(pts[j])
		st.set_color(c)
		st.add_vertex(base[i]); st.add_vertex(pts[j]); st.add_vertex(base[j])
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := flat_material(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	add_child(mi)

func _build_rocks() -> void:
	var rock_mat := flat_material(Palette.c(Palette.BROWN))
	var cactus_mat := flat_material(Palette.c(Palette.GREEN))
	for i in 46:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var cactus := randf() < 0.3
		if cactus:
			bm.size = Vector3(randf_range(1.5, 2.5), randf_range(8, 16), randf_range(1.5, 2.5))
			mi.material_override = cactus_mat
		else:
			bm.size = Vector3(randf_range(4, 16), randf_range(3, 9), randf_range(4, 14))
			mi.material_override = rock_mat
		mi.mesh = bm
		var a := randf() * TAU
		var r := randf_range(40, 330)
		mi.position = Vector3(cos(a) * r, bm.size.y * 0.4 - 0.6, sin(a) * r)
		mi.rotation.y = randf() * TAU
		add_child(mi)

func _build_sun() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 38
	sm.height = 76
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = flat_material(Palette.c(Palette.YELLOW), true)
	mi.position = Vector3(-sun_dir.x, -0.2, -sun_dir.z).normalized() * 1100.0
	add_child(mi)
