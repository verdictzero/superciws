class_name Items
## Data tables for the Vampire-Survivors style progression.
## Weapons map onto the addon meshes in player_ciws.glb; passives are stat boosts.
## Every entry: name, kind, max, icon (1 glyph), color (palette index), desc[level-1].

const WEAPONS := {
	"vulcan": {
		"name": "VULCAN", "kind": "weapon", "max": 8, "icon": "V", "color": Palette.YELLOW,
		"node": "", "start": true,
		"desc": ["20MM AUTO CANNON", "+25% FIRE RATE", "+1 DAMAGE", "-40% SPREAD", "+25% FIRE RATE", "+1 DAMAGE", "TWIN FEED: 2 ROUNDS", "+30% FIRE RATE"],
	},
	"radar": {
		"name": "AESA RADAR", "kind": "weapon", "max": 5, "icon": "R", "color": Palette.GREEN,
		"node": "AESAradarEWaddon",
		"desc": ["TARGET BOXES + SCOPE", "LEAD RETICLE", "THREAT WARNING +RANGE", "AUTO TRACK 30%", "AUTO TRACK 60%"],
	},
	"laser": {
		"name": "DEW LASER", "kind": "weapon", "max": 6, "icon": "L", "color": Palette.CYAN,
		"node": "directedEnergyWeaponAddon",
		"desc": ["HOLD BUTTON: BEAM", "+50% BEAM DAMAGE", "+50% HEAT CAPACITY", "2X COOLING", "+100% BEAM DAMAGE", "WIDE BEAM"],
	},
	"missiles": {
		"name": "QUAD MISSILES", "kind": "weapon", "max": 6, "icon": "M", "color": Palette.ORANGE,
		"node": "quadMissileAddon",
		"desc": ["AUTO SALVO OF 2", "SALVO OF 4", "-25% RELOAD", "SPLASH WARHEADS", "SALVO OF 6", "-25% RELOAD"],
	},
}

const PASSIVES := {
	"armor": {"name": "ARMOR PLATING", "kind": "passive", "max": 5, "icon": "A", "color": Palette.LIGHT, "desc": ["+20% MAX HP"]},
	"nanites": {"name": "NANITE REPAIR", "kind": "passive", "max": 5, "icon": "N", "color": Palette.PINK, "desc": ["+1.5 HP/S REGEN"]},
	"hydraulics": {"name": "HYDRAULICS", "kind": "passive", "max": 4, "icon": "H", "color": Palette.PALE_BLUE, "desc": ["+20% TRAVERSE SPEED"]},
	"coolant": {"name": "COOLANT", "kind": "passive", "max": 5, "icon": "C", "color": Palette.LIGHT_BLUE, "desc": ["+8% FIRE RATE, +20% COOLING"]},
	"optics": {"name": "OPTICS", "kind": "passive", "max": 5, "icon": "O", "color": Palette.OFFWHITE, "desc": ["+15% ALL DAMAGE"]},
	"scavenger": {"name": "SCAVENGER", "kind": "passive", "max": 5, "icon": "S", "color": Palette.GREEN, "desc": ["+15% XP GAIN"]},
	"luck": {"name": "LUCKY CHARM", "kind": "passive", "max": 4, "icon": "7", "color": Palette.YELLOW, "desc": ["+ELITE SPAWNS, BETTER LOOT"]},
	"tracers": {"name": "TRACER ROUNDS", "kind": "passive", "max": 4, "icon": "T", "color": Palette.ORANGE, "desc": ["+20% ROUND VELOCITY"]},
}

## weapon at max level + passive owned -> evolved form (granted from a loot crate)
const EVOLUTIONS := {
	"vulcan": {"needs": "coolant", "name": "GATLING STORM", "desc": "X1.6 FIRE RATE, +1 DMG"},
	"missiles": {"needs": "optics", "name": "SWARM", "desc": "10 MISSILES, FAST RELOAD"},
	"laser": {"needs": "hydraulics", "name": "PRISM LANCE", "desc": "BEAM SPLITS TO 3, NO HEAT"},
	"radar": {"needs": "luck", "name": "ORACLE ARRAY", "desc": "ALL ENEMIES SLOWED 25%"},
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
