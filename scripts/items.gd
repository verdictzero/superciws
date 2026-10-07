class_name Items
## Data tables for the Vampire-Survivors style progression.
## Weapons map onto the addon meshes in player_ciws.glb; passives are stat boosts
## that stack per level. desc[level-1] is what the level-up card shows for that level.

const WEAPONS := {
	"vulcan": {
		"name": "VULCAN", "kind": "weapon", "max": 8, "icon": "V", "color": Palette.YELLOW,
		"node": "", "start": true,
		"desc": [
			"20MM AUTO CANNON. ALWAYS FIRING.",
			"FIRES 25% FASTER",
			"+1 DAMAGE PER ROUND",
			"TIGHTER SPREAD: ROUNDS GROUP 40% CLOSER",
			"FIRES 25% FASTER",
			"+1 DAMAGE PER ROUND",
			"TWIN FEED: FIRES 2 ROUNDS AT ONCE",
			"FIRES 30% FASTER",
		],
	},
	"radar": {
		"name": "AESA RADAR", "kind": "weapon", "max": 5, "icon": "R", "color": Palette.GREEN,
		"node": "AESAradarEWaddon",
		"desc": [
			"BOXES AROUND ENEMIES + RADAR SCOPE",
			"LEAD RETICLE: SHOWS WHERE TO AIM",
			"MISSILE ALARM, SCOPE SEES FARTHER",
			"AUTO-AIM: GUN DRIFTS ONTO TARGETS",
			"AUTO-AIM TWICE AS STRONG",
		],
	},
	"missiles": {
		"name": "QUAD MISSILES", "kind": "weapon", "max": 6, "icon": "M", "color": Palette.ORANGE,
		"node": "quadMissileAddon",
		"desc": [
			"AUTO-FIRES 2 HOMING MISSILES EVERY 5S",
			"SALVO OF 4 MISSILES",
			"RELOADS 25% FASTER",
			"SPLASH: EACH HIT ALSO DAMAGES NEARBY",
			"SALVO OF 6 MISSILES",
			"RELOADS 25% FASTER",
		],
	},
	"laser": {
		"name": "DEW LASER", "kind": "weapon", "max": 6, "icon": "L", "color": Palette.CYAN,
		"node": "directedEnergyWeaponAddon", "requires": "missiles",
		"desc": [
			"HOLD BUTTON: LASER BEAM. BUILDS HEAT",
			"BEAM DAMAGE +50%",
			"50% MORE HEAT BEFORE OVERHEATING",
			"COOLS DOWN TWICE AS FAST",
			"BEAM DAMAGE DOUBLED",
			"WIDE BEAM: HITS ALL IN ITS PATH",
		],
	},
}

const PASSIVES := {
	"armor": {"name": "ARMOR PLATING", "kind": "passive", "max": 5, "icon": "A", "color": Palette.LIGHT,
		"desc": ["+20% MAX HP AND REPAIRS THAT MUCH"]},
	"nanites": {"name": "NANITE REPAIR", "kind": "passive", "max": 5, "icon": "N", "color": Palette.PINK,
		"desc": ["REPAIRS 1.5 HP EVERY SECOND"]},
	"hydraulics": {"name": "HYDRAULICS", "kind": "passive", "max": 4, "icon": "H", "color": Palette.PALE_BLUE,
		"desc": ["TURRET TURNS 20% FASTER"]},
	"coolant": {"name": "COOLANT", "kind": "passive", "max": 5, "icon": "C", "color": Palette.LIGHT_BLUE,
		"desc": ["GUN FIRES 8% FASTER, LASER COOLS 20% FASTER"]},
	"optics": {"name": "OPTICS", "kind": "passive", "max": 5, "icon": "O", "color": Palette.OFFWHITE,
		"desc": ["ALL WEAPONS DEAL 15% MORE DAMAGE"]},
	"scavenger": {"name": "SCAVENGER", "kind": "passive", "max": 5, "icon": "S", "color": Palette.GREEN,
		"desc": ["KILLS GIVE 15% MORE XP"]},
	"luck": {"name": "LUCKY CHARM", "kind": "passive", "max": 4, "icon": "7", "color": Palette.YELLOW,
		"desc": ["MORE ELITES SPAWN, CRATES PAY OUT MORE"]},
	"tracers": {"name": "TRACER ROUNDS", "kind": "passive", "max": 4, "icon": "T", "color": Palette.ORANGE,
		"desc": ["ROUNDS FLY 20% FASTER: EASIER TO HIT"]},
}

## weapon at max level + passive owned -> evolved form (granted by the next loot crate)
const EVOLUTIONS := {
	"vulcan": {"needs": "coolant", "name": "GATLING STORM", "desc": "FIRES 60% FASTER, +1 DAMAGE"},
	"missiles": {"needs": "optics", "name": "SWARM", "desc": "10 MISSILES, RELOADS 40% FASTER"},
	"laser": {"needs": "hydraulics", "name": "PRISM LANCE", "desc": "NO HEAT, BEAM SPLITS TO 3 TARGETS"},
	"radar": {"needs": "luck", "name": "ORACLE ARRAY", "desc": "ALL ENEMIES MOVE 25% SLOWER"},
}

static func get_def(id: String) -> Dictionary:
	if WEAPONS.has(id):
		return WEAPONS[id]
	return PASSIVES.get(id, {})

static func desc_for(id: String, level: int) -> String:
	var d: Dictionary = get_def(id)
	var arr: Array = d["desc"]
	return arr[min(level - 1, arr.size() - 1)]

static func all_ids() -> Array:
	var a := WEAPONS.keys()
	a.append_array(PASSIVES.keys())
	return a
