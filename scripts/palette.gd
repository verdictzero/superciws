class_name Palette
## The whole game is quantised to this list by the post shader.
## 32 colours, SNES / SuperFX flavoured. Swap entries here to restyle the game.

const COLORS: PackedColorArray = [
	Color("#000000"), # 0 black
	Color("#202038"), # 1 night
	Color("#404060"), # 2 dark slate
	Color("#707090"), # 3 slate
	Color("#a0a0b8"), # 4 light slate
	Color("#e0e0e8"), # 5 off white
	Color("#ffffff"), # 6 white
	Color("#101060"), # 7 deep blue
	Color("#2838a8"), # 8 blue
	Color("#4878e0"), # 9 light blue
	Color("#80c0f8"), # 10 pale blue
	Color("#c08040"), # 11 ochre
	Color("#e0b068"), # 12 sand
	Color("#f8e0a0"), # 13 light sand
	Color("#804020"), # 14 brown
	Color("#f83820"), # 15 red
	Color("#f88820"), # 16 orange
	Color("#f8e020"), # 17 yellow
	Color("#20c040"), # 18 green
	Color("#40e8f8"), # 19 cyan
	Color("#c040e0"), # 20 purple
	Color("#f8a0d0"), # 21 pink
	Color("#c05020"), # 22 rust
	Color("#f8c060"), # 23 gold
	Color("#a08060"), # 24 dusty tan
	Color("#104020"), # 25 dark green
	Color("#60a040"), # 26 mid green
	Color("#206080"), # 27 teal
	Color("#602080"), # 28 dark purple
	Color("#d8c8b0"), # 29 bone
	Color("#503020"), # 30 dark brown
	Color("#e86040"), # 31 salmon
]

# Named handles used by code so the HUD and world pick palette-safe colours.
const BLACK = 0
const NIGHT = 1
const DARK = 2
const SLATE = 3
const LIGHT = 4
const OFFWHITE = 5
const WHITE = 6
const DEEP_BLUE = 7
const BLUE = 8
const LIGHT_BLUE = 9
const PALE_BLUE = 10
const OCHRE = 11
const SAND = 12
const LIGHT_SAND = 13
const BROWN = 14
const RED = 15
const ORANGE = 16
const YELLOW = 17
const GREEN = 18
const CYAN = 19
const PURPLE = 20
const PINK = 21
const RUST = 22
const GOLD = 23
const TAN = 24
const DARK_GREEN = 25
const MID_GREEN = 26
const TEAL = 27
const DARK_PURPLE = 28
const BONE = 29
const DARK_BROWN = 30
const SALMON = 31

static func c(i: int) -> Color:
	return COLORS[i]
