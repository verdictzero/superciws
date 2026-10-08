class_name World
extends Node3D
## The desert: baked terrain (scripts/terrain), sky, sun and the shared material helpers.
## Everything is toon lit (hard lit/shadow split) with a vertical colour gradient that the
## post filter Bayer-dithers, plus ink outlines on props.

var sun_dir := Vector3(-0.45, -0.55, 0.7).normalized()

static var _outlines: Dictionary = {}

## Unlit solid colour: bullets, flashes, beams, glows.
static func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.roughness = 1.0
	return m

## Lit toon material with a vertical gradient from y0 (dark) to y1 (bright), in model space
## or world space. outline_px > 0 adds an ink line; fog = false keeps it crisp at range.
static func toon(color: Color, outline_px: float = 0.0, y0: float = -1.0, y1: float = 1.0,
		world_space: bool = false, fog: bool = true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon.gdshader" if fog else "res://shaders/toon_nofog.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("grad_y0", y0)
	m.set_shader_parameter("grad_y1", y1)
	m.set_shader_parameter("world_space", world_space)
	if outline_px > 0.0:
		m.next_pass = outline(outline_px, Color.BLACK, fog)
	return m

static func set_albedo(m: ShaderMaterial, color: Color) -> void:
	m.set_shader_parameter("albedo", color)

static func set_emission(m: ShaderMaterial, color: Color) -> void:
	m.set_shader_parameter("emission", color)

## Shared ink-line shell material (constant on-screen width), cached per style.
static func outline(width_px: float = 1.0, ink: Color = Color.BLACK, fog: bool = true) -> ShaderMaterial:
	var key := "%s|%s|%s" % [width_px, ink.to_html(), fog]
	if not _outlines.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/outline.gdshader" if fog else "res://shaders/outline_nofog.gdshader")
		sm.set_shader_parameter("ink", ink)
		sm.set_shader_parameter("width_px", width_px)
		_outlines[key] = sm
	return _outlines[key]

func _ready() -> void:
	seed(7)
	_build_environment()
	add_child(Terrain.new())
	add_child(Scatter.new())
	_build_sun()
	add_child(HorizonRing.new())

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Sunset: a smooth gradient between palette colours, wrapped as a panorama so it
	# follows elevation. The post filter Bayer-dithers the blends into the palette.
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
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
	mat.filter = true
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.c(Palette.LIGHT_SAND)
	env.ambient_light_energy = 0.55
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
	light.light_color = Color(1.0, 0.94, 0.84)
	light.light_energy = 0.95
	light.shadow_enabled = false
	light.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP)
	add_child(light)

func _build_sun() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 80
	sm.height = 160
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = flat_material(Palette.c(Palette.YELLOW))
	mi.material_override.disable_fog = true
	# past the horizon ring's shell (0.75 x camera far) so the mountains stand in front
	# of the setting sun, its lower half sunk behind the far range
	var flat := Vector3(-sun_dir.x, 0.0, -sun_dir.z).normalized()
	mi.position = flat * 2300.0 + Vector3(0, 2300.0 * 0.07, 0)
	add_child(mi)
