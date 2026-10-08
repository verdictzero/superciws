class_name PixelFont
## Text for the HUD and overlays in Press Start 2P (SIL OFL, see assets/fonts), drawn at
## whole multiples of its native 8px grid: scale 1 = 8px, scale 2 = 16px, ...
## Positions are "logical" pixels; `unit` says how many canvas pixels one logical pixel is
## (the HUD draws at 2x so glyphs land on their native grids, overlays draw at 1x).

const FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const PX := 8
const H := 4      # approximate logical cap height of scale 1 text (layout helper)
const ADV := 4    # logical advance of scale 1 text (layout helper)

static var unit := 2.0
static var _font_file: FontFile

static func _ensure() -> void:
	if _font_file == null:
		_font_file = _prep(load(FONT_PATH))

static func _prep(f: FontFile) -> FontFile:
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	return f

static func _font(_scale: int) -> FontFile:
	return _font_file

static func _px(scale: int) -> int:
	return PX * maxi(scale, 1)

static func width(text: String, scale: int = 1) -> int:
	_ensure()
	return int(ceil(_font(scale).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(scale)).x / unit))

## Baseline offset (canvas px) so the cap height sits just below `pos.y`.
static func _baseline(scale: int) -> float:
	return floorf(float(_px(scale)) * 15.0 / 16.0)   # Press Start 2P fills the em

static func draw(ci: CanvasItem, pos: Vector2, text: String, color: Color, scale: int = 1, shadow: bool = false) -> void:
	_ensure()
	var f := _font(scale)
	var px := _px(scale)
	var p := (pos * unit).floor() + Vector2(0, _baseline(scale))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if shadow:
		ci.draw_string(f, p + Vector2(unit, unit), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Palette.c(Palette.BLACK))
	ci.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(unit, unit))

static func draw_centered(ci: CanvasItem, center_x: float, y: float, text: String, color: Color, scale: int = 1, shadow: bool = false) -> void:
	draw(ci, Vector2(floor(center_x - width(text, scale) / 2.0), y), text, color, scale, shadow)
