class_name PixelFont
## Text for the HUD and overlays using two real pixel fonts (both SIL OFL, see assets/fonts):
##   Press Start 2P  - headings, prompts, icons (8px grid, scale 2+)
##   VT323           - body text and readouts (16px grid, scale 1)
## Positions are "logical" pixels; `unit` says how many canvas pixels one logical pixel is
## (the HUD draws at 2x so glyphs land on their native grids, overlays draw at 1x).

const BODY_PATH := "res://assets/fonts/VT323-Regular.ttf"
const HEAD_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const BODY_PX := 16
const HEAD_PX := 8
const H := 6      # approximate logical cap height of body text (layout helper)
const ADV := 4    # approximate logical advance of body text (layout helper)

static var unit := 2.0
static var _body: FontFile
static var _head: FontFile

static func _ensure() -> void:
	if _body != null:
		return
	_body = _prep(load(BODY_PATH))
	_head = _prep(load(HEAD_PATH))

static func _prep(f: FontFile) -> FontFile:
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	return f

static func _font(scale: int) -> FontFile:
	return _body if scale <= 1 else _head

static func _px(scale: int) -> int:
	return BODY_PX if scale <= 1 else HEAD_PX * scale

static func width(text: String, scale: int = 1) -> int:
	_ensure()
	return int(ceil(_font(scale).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px(scale)).x / unit))

## Baseline offset (canvas px) so the cap height sits just below `pos.y`.
static func _baseline(scale: int) -> float:
	if scale <= 1:
		return 12.0           # VT323 @16: caps are ~10px tall
	return float(HEAD_PX * scale) - float(scale) * 0.5   # Press Start 2P fills the em

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
