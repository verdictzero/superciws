class_name HorizonRing
extends Node3D
## The backdrop around the desert: drifting cloud bands behind two rings of mountains,
## each an open cylinder that follows the camera and paints by view direction
## (shaders/horizon_band.gdshader, ported from mewd-engine's HorizonClouds).
##
## The mountain rings are opaque from their peaks down past the terrain's rim, so the
## edge of the baked desert is never seen; the clouds fade softly into the haze.

const SHADER := "res://shaders/horizon_band.gdshader"
const FAR_FRACTION := 0.75   # shell radius as a fraction of the camera's far plane

## [texture, render priority, params]. Lower priority draws first (further back).
var layers := [
	["res://assets/sky/clouds/clouds_band_mewd.png", -4, {
		"tiles": 5.0, "height": 0.42, "base": 0.02, "distance": 16000.0,
		"drift": 0.0017453, "phase": 0.0, "opacity": 0.45, "cutout": false,
		"tint": Color(1.35, 1.1, 1.05), "saturation": 0.5, "art_fade_in": 0.08,
		"art_solid_end": 0.75, "haze_strength": 1.0}],
	["res://assets/sky/clouds/clouds_band_mewd.png", -3, {
		"tiles": 8.0, "height": 0.26, "base": 0.0, "distance": 4500.0,
		"drift": 0.0034907, "phase": 0.37, "opacity": 0.6, "cutout": false,
		"tint": Color(1.4, 1.05, 0.9), "saturation": 0.55, "art_fade_in": 0.08,
		"art_solid_end": 0.75, "haze_strength": 1.0}],
	["res://assets/sky/mountains_far.png", -2, {
		"tiles": 3.0, "height": 0.16, "base": -0.045, "distance": 30000.0, "phase": 0.21,
		"tint": Color(0.92, 0.9, 1.0), "solid_below": true, "fade_end": -0.25,
		"haze_strength": 0.75}],
	["res://assets/sky/mountains_near.png", -1, {
		"tiles": 2.0, "height": 0.2, "base": -0.06, "distance": 9000.0, "phase": 0.0,
		"tint": Color(1.08, 0.98, 0.86), "solid_below": true, "fade_end": -0.25,
		"haze_strength": 0.45}],
]
var haze := Color(0.97, 0.86, 0.6)
var _shells: Array[MeshInstance3D] = []
var _radius := 0.0

func _ready() -> void:
	process_priority = 100   # after the camera has moved this frame
	var shader: Shader = load(SHADER)
	for spec in layers:
		var tex: Texture2D = load(spec[0])
		if tex == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = shader
		m.render_priority = spec[1]
		m.set_shader_parameter("band", tex)
		m.set_shader_parameter("haze_color", haze)
		for key in spec[2]:
			m.set_shader_parameter(key, spec[2][key])
		var mi := MeshInstance3D.new()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_shells.append(mi)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var want := cam.far * FAR_FRACTION
	if absf(want - _radius) > 1.0:
		_radius = want
		_build(want)
	global_position = cam.global_position

## One open tube shared by every layer, tall enough for the highest strip and deep
## enough for the opaque mountain foot (tan elevations +0.6 / -0.3).
func _build(r: float) -> void:
	var up := 0.6
	var down := 0.3
	var cm := CylinderMesh.new()
	cm.cap_top = false
	cm.cap_bottom = false
	cm.rings = 0
	cm.radial_segments = 64
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = r * (up + down)
	for mi in _shells:
		mi.mesh = cm
		mi.position.y = r * (up - down) * 0.5
		mi.custom_aabb = AABB(Vector3(-r, -cm.height * 0.5, -r), Vector3(r * 2.0, cm.height, r * 2.0))
