class_name TouchOverlay
extends Control
## On-screen touch controls, drawn in native window pixels outside the retro filter.
## Layout adapts to the window: landscape phones put the stick and buttons in the
## pillarbox bars (or over the game edges when the bars are thin); portrait or
## folded devices put the game at the top and the controls underneath.

var main: Node
var enabled := false
var ui := 100.0              # base unit: a tenth of the shorter window side
var stick_home := Vector2.ZERO
var stick_radius := 60.0
var btn1_center := Vector2.ZERO
var btn1_radius := 50.0
var btn2_center := Vector2.ZERO
var btn2_radius := 32.0
var game_rect := Rect2()
var portrait := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func layout(ws: Vector2, rect: Rect2, on: bool) -> void:
	enabled = on
	game_rect = rect
	ui = minf(ws.x, ws.y) / 10.0
	portrait = ws.y > ws.x
	stick_radius = ui * 1.1
	btn1_radius = ui * 0.95
	btn2_radius = ui * 0.6
	if portrait:
		var top := rect.end.y
		var mid := (top + ws.y) * 0.5
		if ws.y - top < ui * 3.0:
			mid = ws.y - ui * 2.0
		stick_home = Vector2(ws.x * 0.25, mid)
		btn1_center = Vector2(ws.x * 0.78, mid)
		btn2_center = Vector2(ws.x * 0.58, mid - ui * 1.4)
	else:
		var bar := rect.position.x
		var sx := bar * 0.5 if bar >= ui * 2.6 else ws.x * 0.15
		var bx := ws.x - bar * 0.5 if bar >= ui * 2.6 else ws.x * 0.85
		stick_home = Vector2(sx, ws.y * 0.66)
		btn1_center = Vector2(bx, ws.y * 0.70)
		btn2_center = Vector2(bx - ui * 1.4, ws.y * 0.70 - ui * 2.0)
	queue_redraw()

func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()

func _ring(center: Vector2, r: float, col: Color, width: float) -> void:
	draw_arc(center, r, 0.0, TAU, 40, col, width, true)

func _label(center: Vector2, text: String, col: Color) -> void:
	var sc := maxi(1, int(ui / 28.0))
	PixelFont.draw_centered(self, center.x, center.y - PixelFont.H * sc / 2.0, text, col, sc, true)

func _draw() -> void:
	if not enabled or main == null:
		return
	var playing: bool = main.state == main.State.PLAYING
	var dim := Color(1, 1, 1, 0.55)
	# virtual stick
	var base: Vector2 = stick_home
	var active := false
	for t in main.touches.values():
		if t["zone"] == "stick":
			base = t["start"]
			active = true
	_ring(base, stick_radius, Palette.c(Palette.CYAN) * (Color(1, 1, 1, 0.9) if active else dim), 3.0)
	draw_circle(base + main.touch_stick * stick_radius, ui * 0.35, Palette.c(Palette.WHITE) * (Color(1, 1, 1, 0.9) if active else dim))
	if not active:
		_label(base + Vector2(0, stick_radius + ui * 0.5), "AIM", Palette.c(Palette.OFFWHITE) * dim)
	# button 1
	var held: bool = main.touch_btn1_held
	var b1col := Palette.c(Palette.ORANGE) if held else Palette.c(Palette.YELLOW) * dim
	draw_circle(btn1_center, btn1_radius, Color(b1col.r, b1col.g, b1col.b, 0.35 if held else 0.18))
	_ring(btn1_center, btn1_radius, b1col, 3.0)
	var b1text := "BEAM" if (playing and Game.item_level("laser") > 0) else ("FIRE" if playing else "OK")
	_label(btn1_center, b1text, Palette.c(Palette.WHITE))
	# button 2 (missiles), only when the pod is owned
	if playing and Game.missile_count > 0:
		var ready: bool = main.missile_timer <= 0.0
		var b2col := Palette.c(Palette.ORANGE) if ready else Palette.c(Palette.SLATE)
		draw_circle(btn2_center, btn2_radius, Color(b2col.r, b2col.g, b2col.b, 0.2))
		_ring(btn2_center, btn2_radius, b2col * dim, 2.0)
		_label(btn2_center, "MSL", Palette.c(Palette.WHITE) if ready else Palette.c(Palette.LIGHT))
	if not playing:
		var hint := "TAP: SELECT   SWIPE: MOVE"
		var y: float = game_rect.end.y - ui * 0.6 if not portrait else game_rect.end.y + ui * 0.4
		_label(Vector2(game_rect.get_center().x, y), hint, Palette.c(Palette.OFFWHITE) * dim)
