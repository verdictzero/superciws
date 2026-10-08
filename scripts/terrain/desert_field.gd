class_name DesertField
extends RefCounted
## The desert's height function: a pure function of world XZ plus a seed, read from
## assets/terrain/desert.json (shared with tools/bake_ground.py).
##
## Ported from mewd-engine's IslandField.base_height (verdictzero/golf lineage):
## sparsified simplex hills (most ground dead flat, the top of the distribution rises),
## ridged crests riding the hills, and a fine micro term. The island mask, coastline,
## cliffs, zones and craters are dropped: this desert has no edge to fall off, it just
## runs out behind the mountain ring. Two additions for SUPER CIWS: relief that grows
## with distance from the battery (flat around the guns, rolling toward the horizon) and
## the asphalt pad the CIWS row stands on, which the terrain eases down into.

const CONFIG := "res://assets/terrain/desert.json"

var cfg: Dictionary
var seed_value := 1337
var base_y := -0.6
var radius := 1152.0
var _hill: FastNoiseLite
var _ridge: FastNoiseLite
var _micro: FastNoiseLite
var _h: Dictionary
var _r: Dictionary
var _m: Dictionary
var _relief: Dictionary
var _pad: Dictionary

static func load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		push_error("DesertField: cannot read " + CONFIG)
		return {}
	return JSON.parse_string(f.get_as_text())

func _init(config: Dictionary = {}) -> void:
	cfg = config if not config.is_empty() else load_config()
	seed_value = int(cfg.get("seed", 1337))
	base_y = float(cfg.get("base_y", -0.6))
	radius = float(cfg.get("radius", 1152.0))
	_h = cfg["hill"]
	_r = cfg["ridge"]
	_m = cfg["micro"]
	_relief = cfg["relief"]
	_pad = cfg["pad"]
	_hill = _make_noise(0x2002, FastNoiseLite.TYPE_SIMPLEX, _h["scale"], int(_h["octaves"]))
	_ridge = _make_noise(0x3003, FastNoiseLite.TYPE_SIMPLEX, _r["scale"], int(_r["octaves"]))
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_micro = _make_noise(0x4004, FastNoiseLite.TYPE_SIMPLEX, _m["scale"], 2)

func _make_noise(salt: int, type: int, scale: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value ^ salt
	n.noise_type = type
	n.frequency = 1.0 / maxf(scale, 0.001)
	n.fractal_octaves = octaves
	return n

## Signed distance (metres) from the asphalt pad's rounded rectangle; negative inside.
func pad_sdf(x: float, z: float) -> float:
	var c: float = _pad["corner"]
	var qx := absf(x) - (float(_pad["half_x"]) - c)
	var qz := absf(z) - (float(_pad["half_z"]) - c)
	var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
	return outside + minf(maxf(qx, qz), 0.0) - c

## Natural ground before the pad is cut in.
func natural_height(x: float, z: float) -> float:
	var sp: float = _h["sparsity"]
	var hills := smoothstep(sp, minf(sp + float(_h["ramp"]), 1.0), _hill.get_noise_2d(x, z) * 0.5 + 0.5)
	var ridges := (_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * lerpf(1.0, hills, float(_r["on_hills"]))
	var micro := _micro.get_noise_2d(x, z)
	var d := Vector2(x, z).length()
	var grow := lerpf(float(_relief["near"]), 1.0,
			smoothstep(float(_relief["start"]), float(_relief["full"]), d))
	var relief := (float(_h["height"]) * hills + float(_r["height"]) * ridges) * grow
	return base_y + relief + float(_m["height"]) * micro

## The finished surface: natural ground eased down onto the level pad.
func height(x: float, z: float) -> float:
	var h := natural_height(x, z)
	var s := pad_sdf(x, z)
	var k := 1.0 - smoothstep(0.0, float(_pad["flatten"]), s)
	return lerpf(h, base_y, k * k * (3.0 - 2.0 * k))
