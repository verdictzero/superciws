extends Node
## Autoload: run state, score, lives, items/levels, derived stats, high scores.

signal stats_changed
signal score_changed

const MAX_WEAPONS := 4
const AIM_ASSIST := 0.25   # default aim assist strength (0 turns it off)
const MAX_PASSIVES := 6
const START_LIVES := 3
const SAVE_PATH := "user://highscores.json"

# --- run state -------------------------------------------------------------
var score: int = 0
var lives: int = START_LIVES
var continues_used: int = 0
var kills: int = 0
var level: int = 1
var xp: int = 0
var run_time: float = 0.0
var multiplier: int = 1
var combo_timer: float = 0.0
var items: Dictionary = {}       # id -> level
var evolved: Dictionary = {}     # id -> true
var hp: float = 100.0

# --- derived stats (recalc() fills these) ---------------------------------
var max_hp: float = 100.0
var regen: float = 0.0
var traverse_speed: float = 110.0   # degrees / second
var xp_mult: float = 1.0
var luck: int = 0
var dmg_mult: float = 1.0
var bullet_speed: float = 330.0
var vulcan_rof: float = 10.0
var vulcan_dmg: float = 1.0
var vulcan_spread: float = 2.0
var vulcan_rounds: int = 1
var laser_dps: float = 0.0
var laser_heat_cap: float = 0.0
var laser_cooling: float = 0.0
var laser_wide: bool = false
var missile_count: int = 0
var missile_cooldown: float = 0.0
var missile_splash: bool = false
var radar_level: int = 0
var auto_track: float = 0.0   # aim assist strength: how hard the gun drifts onto the nearest target
var slow_field: float = 0.0

var high_scores: Array = []   # [{name, score, level, time}]

func _ready() -> void:
	load_scores()
	new_run()

func new_run() -> void:
	score = 0
	lives = START_LIVES
	continues_used = 0
	kills = 0
	level = 1
	xp = 0
	run_time = 0.0
	multiplier = 1
	combo_timer = 0.0
	items = {"vulcan": 1}
	evolved = {}
	recalc()
	hp = max_hp
	score_changed.emit()

func continue_run() -> void:
	lives = START_LIVES
	continues_used += 1
	multiplier = 1
	hp = max_hp

## Enemies attack from a cone in front of the battery: 30 degrees at level 1,
## 5 degrees wider per level, up to the full circle.
func attack_arc() -> float:
	return minf(360.0, 30.0 + 5.0 * (level - 1))

func xp_needed() -> int:
	return 10 + level * 6 + int(pow(level, 1.35))

func add_xp(amount: int) -> bool:
	## returns true when a level-up happened
	xp += int(round(amount * xp_mult))
	if xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		add_score(250 * level)
		return true
	return false

func add_score(points: int) -> void:
	score += points * multiplier
	score_changed.emit()

func register_kill(base_points: int) -> void:
	kills += 1
	combo_timer = 2.5
	add_score(base_points)
	if kills % 4 == 0:
		multiplier = min(multiplier + 1, 8)

func tick(delta: float) -> void:
	run_time += delta
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			multiplier = 1
	if regen > 0.0 and hp < max_hp:
		hp = min(max_hp, hp + regen * delta)

## How many CIWS mounts are in the row (1 to 3).
func mount_count() -> int:
	return 1 + mini(item_level("linked"), 2)

func item_level(id: String) -> int:
	return items.get(id, 0)

func owned_weapons() -> Array:
	return items.keys().filter(func(k): return Items.WEAPONS.has(k))

func owned_passives() -> Array:
	return items.keys().filter(func(k): return Items.PASSIVES.has(k) and Items.PASSIVES[k]["kind"] == "passive")

func can_offer(id: String) -> bool:
	var d := Items.get_def(id)
	if d.is_empty():
		return false
	var lvl := item_level(id)
	if lvl >= int(d["max"]):
		return false
	if d.has("requires") and item_level(d["requires"]) == 0:
		return false
	if lvl == 0:
		if d["kind"] == "weapon" and owned_weapons().size() >= MAX_WEAPONS:
			return false
		if d["kind"] == "passive" and owned_passives().size() >= MAX_PASSIVES:
			return false
	return true

func offer_choices(count: int = 3) -> Array:
	## Weighted draw of upgrade choices for a level-up.
	var pool: Array = []
	for id in Items.all_ids():
		if can_offer(id):
			var w := 3 if item_level(id) > 0 else 2
			if id == "radar" and item_level(id) == 0:
				w = 4   # radar matters a lot with a joystick, surface it early
			for i in w:
				pool.append(id)
	var out: Array = []
	while out.size() < count and pool.size() > 0:
		var pick: String = pool[randi() % pool.size()]
		out.append(pick)
		pool = pool.filter(func(p): return p != pick)
	return out

func grant(id: String) -> void:
	var old_max := max_hp
	items[id] = item_level(id) + 1
	recalc()
	if max_hp > old_max:
		hp = minf(max_hp, hp + (max_hp - old_max))
	stats_changed.emit()

# --- difficulty ramp --------------------------------------------------------
## Enemy HP multiplier. Grows with run time and with player level.
func threat() -> float:
	return 1.0 + run_time / 120.0 * 0.45 + (level - 1) * 0.07

## Enemy speed multiplier, up to +60% over ten minutes.
func enemy_speed_mult() -> float:
	return 1.0 + minf(0.6, run_time / 600.0)

## Damage enemies deal when they reach the battery, up to +80%.
func enemy_damage_mult() -> float:
	return 1.0 + minf(0.8, run_time / 900.0)

## Seconds between spawns: shorter over time and with level.
func spawn_interval() -> float:
	return clampf(2.4 - run_time / 60.0 * 0.2 - (level - 1) * 0.04, 0.4, 2.4)

## Chance a spawn is an advanced: time, level and luck all raise it.
func advanced_chance() -> float:
	if run_time < 45.0:
		return 0.0
	return minf(0.3, 0.04 + 0.02 * luck + run_time / 1500.0 + (level - 1) * 0.004)

func evolution_available() -> String:
	for wid in Items.EVOLUTIONS.keys():
		if evolved.has(wid):
			continue
		var ev: Dictionary = Items.EVOLUTIONS[wid]
		if item_level(wid) >= int(Items.WEAPONS[wid]["max"]) and item_level(ev["needs"]) > 0:
			return wid
	return ""

func evolve(wid: String) -> void:
	evolved[wid] = true
	recalc()
	stats_changed.emit()

func upgradable_owned() -> Array:
	return items.keys().filter(func(k): return can_offer(k))

func display_name(id: String) -> String:
	if evolved.has(id):
		return Items.EVOLUTIONS[id]["name"]
	return Items.get_def(id)["name"]

func recalc() -> void:
	var l := func(id: String) -> int: return item_level(id)
	max_hp = 100.0 * (1.0 + 0.2 * l.call("armor"))
	regen = 1.5 * l.call("nanites")
	traverse_speed = 110.0 * (1.0 + 0.2 * l.call("hydraulics"))
	xp_mult = 1.0 + 0.15 * l.call("scavenger")
	luck = l.call("luck")
	dmg_mult = 1.0 + 0.15 * l.call("optics")
	bullet_speed = 330.0 * (1.0 + 0.2 * l.call("tracers"))

	var v: int = l.call("vulcan")
	vulcan_rof = 10.0
	vulcan_dmg = 1.0
	vulcan_spread = 2.0
	vulcan_rounds = 1
	if v >= 2: vulcan_rof *= 1.25
	if v >= 3: vulcan_dmg += 1.0
	if v >= 4: vulcan_spread *= 0.6
	if v >= 5: vulcan_rof *= 1.25
	if v >= 6: vulcan_dmg += 1.0
	if v >= 7: vulcan_rounds = 2
	if v >= 8: vulcan_rof *= 1.3
	vulcan_rof *= 1.0 + 0.08 * l.call("coolant")
	if evolved.has("vulcan"):
		vulcan_rof *= 1.6
		vulcan_dmg += 1.0

	var la: int = l.call("laser")
	laser_dps = 0.0
	laser_heat_cap = 0.0
	laser_cooling = 0.0
	laser_wide = false
	if la >= 1:
		laser_dps = 8.0
		laser_heat_cap = 100.0
		laser_cooling = 22.0
	if la >= 2: laser_dps *= 1.5
	if la >= 3: laser_heat_cap *= 1.5
	if la >= 4: laser_cooling *= 2.0
	if la >= 5: laser_dps *= 2.0
	if la >= 6: laser_wide = true
	laser_cooling *= 1.0 + 0.2 * l.call("coolant")
	if evolved.has("laser"):
		laser_heat_cap = 0.0  # no heat

	var m: int = l.call("missiles")
	missile_count = 0
	missile_cooldown = 0.0
	missile_splash = false
	if m >= 1:
		missile_count = 2
		missile_cooldown = 5.0
	if m >= 2: missile_count = 4
	if m >= 3: missile_cooldown *= 0.75
	if m >= 4: missile_splash = true
	if m >= 5: missile_count = 6
	if m >= 6: missile_cooldown *= 0.75
	if evolved.has("missiles"):
		missile_count = 10
		missile_cooldown *= 0.6

	radar_level = l.call("radar")
	# aim assist is always on; radar levels 4 and 5 make it pull harder
	auto_track = AIM_ASSIST
	if radar_level >= 4: auto_track = 0.45
	if radar_level >= 5: auto_track = 0.7
	slow_field = 0.25 if evolved.has("radar") else 0.0

	if hp > max_hp:
		hp = max_hp

# --- high scores -----------------------------------------------------------
func load_scores() -> void:
	high_scores = []
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				high_scores = parsed
	if high_scores.is_empty():
		var defaults := [["ACE", 50000], ["ZAP", 30000], ["RGB", 20000], ["LCD", 12000], ["FOX", 8000], ["GUN", 5000], ["SKY", 3000], ["SND", 2000], ["BIT", 1000], ["NEW", 500]]
		for d in defaults:
			high_scores.append({"name": d[0], "score": d[1], "level": 1, "time": 0})

func qualifies() -> bool:
	return high_scores.size() < 10 or score > int(high_scores[-1]["score"])

func submit_score(initials: String) -> int:
	## returns rank index (0 based)
	var entry := {"name": initials, "score": score, "level": level, "time": int(run_time), "continues": continues_used}
	high_scores.append(entry)
	high_scores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if high_scores.size() > 10:
		high_scores.resize(10)
	save_scores()
	return high_scores.find(entry)

func save_scores() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(high_scores))

func top_score() -> int:
	if high_scores.is_empty():
		return 0
	return max(int(high_scores[0]["score"]), score)

static func fmt_time(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]
