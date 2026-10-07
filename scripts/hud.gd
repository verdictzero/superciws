class_name Hud
extends Control
## Every screen of the game, drawn at 256x192 with the 3x5 pixel font so it all
## goes through the palette + LCD filter. Reads state from Main.

var main: Node
var logo: Texture2D
var title_bg: Texture2D
var _time := 0.0

func _ready() -> void:
	logo = load("res://assets/textures/logo.png")
	title_bg = load("res://assets/textures/title_bg.png")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func c(i: int) -> Color:
	return Palette.c(i)

func txt(x: float, y: float, s: String, col: int, scale: int = 1, shadow: bool = true) -> void:
	PixelFont.draw(self, Vector2(x, y), s, c(col), scale, shadow)

func ctxt(y: float, s: String, col: int, scale: int = 1, shadow: bool = true) -> void:
	PixelFont.draw_centered(self, 128, y, s, c(col), scale, shadow)

func rtxt(right_x: float, y: float, s: String, col: int, scale: int = 1, shadow: bool = true) -> void:
	PixelFont.draw(self, Vector2(right_x - PixelFont.width(s, scale), y), s, c(col), scale, shadow)

func bar(x: float, y: float, w: float, h: float, frac: float, col: int, bg: int = Palette.NIGHT) -> void:
	draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), c(Palette.BLACK))
	draw_rect(Rect2(x, y, w, h), c(bg))
	var fw := floorf(w * clampf(frac, 0.0, 1.0))
	if fw > 0:
		draw_rect(Rect2(x, y, fw, h), c(col))

func panel(r: Rect2, border: int = Palette.LIGHT, fill: int = Palette.NIGHT) -> void:
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size), c(Palette.BLACK))
	draw_rect(r, c(border))
	draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), c(fill))

func dim() -> void:
	draw_rect(Rect2(0, 0, 256, 192), Color(0.06, 0.06, 0.2, 0.6))

func blink(period: float = 0.8) -> bool:
	return fmod(_time, period) < period * 0.6

func wrap_text(s: String, max_chars: int) -> Array:
	var lines: Array = []
	var cur := ""
	for word in s.split(" "):
		if cur.length() + word.length() + 1 > max_chars and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = word if cur == "" else cur + " " + word
	if cur != "":
		lines.append(cur)
	return lines

func _draw() -> void:
	if main == null:
		return
	match main.state:
		main.State.TITLE: _draw_title()
		main.State.SCORES: _draw_scores()
		main.State.PLAYING: _draw_playing()
		main.State.LEVELUP: _draw_playing(); _draw_levelup()
		main.State.SLOT: _draw_playing(); _draw_slot()
		main.State.DESTROYED: _draw_playing(); _draw_destroyed()
		main.State.CONTINUE: _draw_continue()
		main.State.GAMEOVER: _draw_gameover()
		main.State.NAME_ENTRY: _draw_name_entry()

# --- title / attract -------------------------------------------------------
func _draw_title() -> void:
	draw_texture(title_bg, Vector2.ZERO)
	draw_texture(logo, Vector2(floor((256 - logo.get_width()) / 2.0), 8))
	rtxt(252, 3, "HI %07d" % Game.top_score(), Palette.YELLOW)
	if blink():
		ctxt(134, "PRESS BUTTON TO START", Palette.WHITE, 1)
	ctxt(152, "STICK AIMS  -  GUN FIRES AUTO", Palette.LIGHT_SAND)
	ctxt(160, "HOLD BUTTON FOR BEAM WEAPON", Palette.LIGHT_SAND)
	ctxt(176, "SURVIVE. LEVEL UP. LOOT ELITES.", Palette.OFFWHITE)
	ctxt(184, "(C) 2026 VERDICTZERO", Palette.SLATE, 1, false)

func _draw_scores() -> void:
	draw_texture(title_bg, Vector2.ZERO)
	dim()
	panel(Rect2(28, 14, 200, 166))
	ctxt(20, "HIGH SCORES", Palette.YELLOW, 2)
	txt(40, 40, "RANK NAME   SCORE   LV", Palette.LIGHT)
	for i in Game.high_scores.size():
		var e: Dictionary = Game.high_scores[i]
		var y := 50 + i * 11
		var col := Palette.OFFWHITE
		if i == main.rank:
			col = Palette.YELLOW if blink(0.4) else Palette.ORANGE
		elif i == 0:
			col = Palette.CYAN
		txt(40, y, "%2d.  %-3s  %07d  %2d" % [i + 1, e["name"], int(e["score"]), int(e["level"])], col)
	if blink():
		ctxt(168, "PRESS BUTTON TO START", Palette.WHITE)

# --- gameplay --------------------------------------------------------------
func _draw_playing() -> void:
	var cam: Camera3D = main.turret.camera
	var enemies := get_tree().get_nodes_in_group("enemies")
	var radar: int = Game.radar_level

	# target brackets + lead reticle (AESA radar)
	if radar >= 1:
		for e in enemies:
			if e.dead:
				continue
			var p: Vector3 = e.global_position
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			var col := Palette.GREEN
			if e.type == e.Type.MISSILE: col = Palette.RED
			if e.elite == 1: col = Palette.YELLOW
			if e.elite == 2: col = Palette.PURPLE
			if e.is_boss: col = Palette.WHITE
			var onscreen := sp.x >= 0 and sp.x < 256 and sp.y >= 0 and sp.y < 192
			if not onscreen:
				if radar >= 3 and (e.type == e.Type.MISSILE or e.is_boss):
					var ep := Vector2(clampf(sp.x, 4, 251), clampf(sp.y, 4, 187))
					draw_rect(Rect2(ep - Vector2(2, 2), Vector2(4, 4)), c(col))
				continue
			var dist := p.distance_to(cam.global_position)
			var s := clampf(e.radius * 180.0 / max(dist, 1.0), 3.0, 14.0)
			_bracket(sp, s, c(col))
			if e.is_boss or e.elite > 0:
				bar(sp.x - 8, sp.y - s - 4, 16, 2, e.hp / e.max_hp, Palette.RED, Palette.DARK)
	if radar >= 2:
		var t = main.best_target()
		if t != null:
			var lp: Vector3 = main.lead_point(t)
			if not cam.is_position_behind(lp):
				var sp := cam.unproject_position(lp)
				_diamond(sp, 3, c(Palette.CYAN))
	if radar >= 1:
		_scope(enemies)

	# crosshair sits where the gun line projects, not the screen centre
	var aim_pt: Vector3 = main.turret.muzzle_pos() + main.turret.aim_dir() * 300.0
	var ap := cam.unproject_position(aim_pt)
	var cx := floorf(clampf(ap.x, 8, 248))
	var cy := floorf(clampf(ap.y, 8, 184))
	var wc := c(Palette.WHITE)
	draw_rect(Rect2(cx - 6, cy, 4, 1), wc)
	draw_rect(Rect2(cx + 3, cy, 4, 1), wc)
	draw_rect(Rect2(cx, cy - 6, 1, 4), wc)
	draw_rect(Rect2(cx, cy + 3, 1, 4), wc)

	# HP + lives
	txt(3, 3, "HP", Palette.OFFWHITE)
	var hf: float = Game.hp / Game.max_hp
	bar(14, 3, 50, 5, hf, Palette.GREEN if hf > 0.5 else (Palette.YELLOW if hf > 0.25 else Palette.RED))
	for i in Game.lives:
		draw_rect(Rect2(14 + i * 6, 11, 4, 4), c(Palette.LIGHT))
		draw_rect(Rect2(15 + i * 6, 10, 2, 1), c(Palette.LIGHT))
	if Game.continues_used > 0:
		txt(40, 10, "C%d" % Game.continues_used, Palette.SLATE)

	# XP + level
	bar(72, 3, 112, 3, float(Game.xp) / Game.xp_needed(), Palette.CYAN)
	txt(72, 9, "LV %d" % Game.level, Palette.CYAN)
	if main.laser_locked:
		pass

	# score / time
	rtxt(252, 3, "%07d" % Game.score, Palette.WHITE)
	rtxt(252, 10, "HI %07d" % Game.top_score(), Palette.YELLOW)
	rtxt(252, 17, Game.fmt_time(Game.run_time), Palette.LIGHT)
	if Game.multiplier > 1:
		rtxt(252, 26, "X%d" % Game.multiplier, Palette.ORANGE, 2)
		bar(232, 42, 20, 2, Game.combo_timer / 2.5, Palette.ORANGE)

	# weapon status (bottom centre)
	var by := 183.0
	if Game.laser_heat_cap > 0.0:
		txt(84, by, "HEAT", Palette.CYAN if not main.laser_locked else Palette.RED)
		bar(104, by, 48, 4, main.laser_heat / Game.laser_heat_cap, Palette.RED if main.laser_locked else Palette.CYAN)
		by -= 8
	elif Game.evolved.has("laser"):
		txt(84, by, "PRISM LANCE READY", Palette.CYAN)
		by -= 8
	if Game.missile_count > 0:
		var ready: bool = main.missile_timer <= 0.0
		txt(84, by, "MSL", Palette.ORANGE if ready else Palette.SLATE)
		bar(104, by, 48, 4, 1.0 - main.missile_timer / max(Game.missile_cooldown, 0.01), Palette.ORANGE)
		if ready and blink(0.5):
			txt(156, by, "READY", Palette.ORANGE)
		by -= 8

	# items (bottom right)
	var ids: Array = Game.items.keys()
	for i in ids.size():
		var id: String = ids[i]
		var d := Items.get_def(id)
		var col: int = d["color"]
		var row := i % 6
		var colx := 252 - (i / 6) * 18 - 14
		var y := 140 + row * 7
		var lvl := Game.item_level(id)
		var label := "%s%d" % [d["icon"], lvl]
		if Game.evolved.has(id):
			label = "%s*" % d["icon"]
		txt(colx, y, label, col)

	# messages / warnings
	if main.message_timer > 0.0:
		ctxt(58, main.message, Palette.YELLOW, 2)
	if main.threat and radar >= 3 and blink(0.3):
		ctxt(30, "!! MISSILE !!", Palette.RED, 1)
	if main.state == main.State.PLAYING and Game.run_time < 4.0 and blink(0.6):
		ctxt(120, "DEFEND THE BATTERY", Palette.OFFWHITE)

func _bracket(p: Vector2, s: float, col: Color) -> void:
	var x := floorf(p.x)
	var y := floorf(p.y)
	var l := maxf(2.0, floorf(s / 2.0))
	draw_rect(Rect2(x - s, y - s, l, 1), col); draw_rect(Rect2(x - s, y - s, 1, l), col)
	draw_rect(Rect2(x + s - l + 1, y - s, l, 1), col); draw_rect(Rect2(x + s, y - s, 1, l), col)
	draw_rect(Rect2(x - s, y + s, l, 1), col); draw_rect(Rect2(x - s, y + s - l + 1, 1, l), col)
	draw_rect(Rect2(x + s - l + 1, y + s, l, 1), col); draw_rect(Rect2(x + s, y + s - l + 1, 1, l), col)

func _diamond(p: Vector2, r: int, col: Color) -> void:
	var x := floorf(p.x)
	var y := floorf(p.y)
	for i in r + 1:
		draw_rect(Rect2(x - i, y - r + i, 1, 1), col)
		draw_rect(Rect2(x + i, y - r + i, 1, 1), col)
		draw_rect(Rect2(x - i, y + r - i, 1, 1), col)
		draw_rect(Rect2(x + i, y + r - i, 1, 1), col)

func _scope(enemies: Array) -> void:
	var center := Vector2(24, 167)
	var r := 20.0
	draw_circle(center, r + 1, c(Palette.BLACK))
	draw_circle(center, r, Color(0.06, 0.2, 0.1, 0.9))
	draw_arc(center, r, 0, TAU, 20, c(Palette.GREEN), 1.0)
	draw_rect(Rect2(center.x, center.y - r, 1, r), Color(0.13, 0.75, 0.25, 0.5))
	draw_rect(Rect2(center - Vector2(1, 1), Vector2(2, 2)), c(Palette.OFFWHITE))
	var yaw: float = deg_to_rad(main.turret.yaw)
	var rng := 400.0 if Game.radar_level >= 3 else 300.0
	for e in enemies:
		if e.dead:
			continue
		var rel: Vector3 = e.global_position.rotated(Vector3.UP, -yaw)
		var v := Vector2(rel.x, -rel.z) / rng * r
		if v.length() > r:
			continue
		var col := Palette.GREEN
		if e.type == e.Type.MISSILE: col = Palette.RED
		if e.elite > 0: col = Palette.YELLOW
		if e.is_boss: col = Palette.WHITE
		var sz := 2 if (e.elite > 0 or e.is_boss) else 1
		draw_rect(Rect2(center + v - Vector2(sz / 2.0, sz / 2.0), Vector2(sz, sz)), c(col))

# --- level up --------------------------------------------------------------
func _draw_levelup() -> void:
	dim()
	ctxt(20, "LEVEL UP!  LV %d" % Game.level, Palette.YELLOW, 2)
	var choices: Array = main.levelup_choices
	for i in choices.size():
		var id: String = choices[i]
		var d := Items.get_def(id)
		var x := 8 + i * 82
		var y := 42
		var sel: bool = i == main.levelup_cursor
		panel(Rect2(x, y, 76, 112), Palette.YELLOW if sel else Palette.SLATE, Palette.NIGHT if not sel else Palette.DARK)
		PixelFont.draw_centered(self, x + 38, y + 6, d["icon"], c(d["color"]), 4, true)
		var lvl := Game.item_level(id)
		for li in wrap_text(d["name"], 18).size():
			PixelFont.draw_centered(self, x + 38, y + 32 + li * 7, wrap_text(d["name"], 18)[li], c(Palette.WHITE), 1, true)
		var tag := "NEW!" if lvl == 0 else "LV %d > %d" % [lvl, lvl + 1]
		PixelFont.draw_centered(self, x + 38, y + 48, tag, c(Palette.GREEN if lvl == 0 else Palette.CYAN), 1, true)
		var lines := wrap_text(Items.desc_for(id, lvl + 1), 18)
		for li in lines.size():
			PixelFont.draw_centered(self, x + 38, y + 62 + li * 7, lines[li], c(Palette.LIGHT_SAND), 1, true)
		if d["kind"] == "weapon":
			PixelFont.draw_centered(self, x + 38, y + 100, "WEAPON", c(Palette.ORANGE), 1, false)
		else:
			PixelFont.draw_centered(self, x + 38, y + 100, "PASSIVE", c(Palette.PALE_BLUE), 1, false)
	ctxt(162, "STICK: CHOOSE    BUTTON: TAKE", Palette.OFFWHITE)
	var ev := Game.evolution_available()
	if ev != "":
		ctxt(174, "EVOLUTION READY: FIND A CRATE", Palette.PINK if blink() else Palette.PURPLE)

# --- loot slot machine -----------------------------------------------------
func _draw_slot() -> void:
	dim()
	var s: Dictionary = main.slot
	var count: int = s["count"]
	var done: bool = s["done"]
	var title := "LOOT CRATE"
	var tcol := Palette.YELLOW
	if done and count >= 5:
		title = "JACKPOT!!!"
		tcol = Palette.YELLOW if blink(0.25) else Palette.PINK
	elif done and count >= 3:
		title = "TRIPLE!"
		tcol = Palette.CYAN
	ctxt(14, title, tcol, 2)
	panel(Rect2(40, 36, 176, 52), Palette.LIGHT, Palette.DARK)
	var ids: Array = Items.all_ids()
	for i in 3:
		var x := 128 - 56 + i * 38 - 17
		var y := 44
		var spinning: bool = s["t"] < s["stops"][i]
		panel(Rect2(x, y, 34, 36), Palette.OFFWHITE if not spinning else Palette.SLATE, Palette.NIGHT)
		var id: String
		if spinning:
			id = ids[(int(s["t"] / 0.07) * 7 + i * 3) % ids.size()]
		else:
			id = s["symbols"][i]
		var d := Items.get_def(id)
		var icon: String = d["icon"] if not d.is_empty() else "+"
		var col: int = d["color"] if not d.is_empty() else Palette.GREEN
		var jitter := 0.0
		if spinning:
			jitter = float((int(s["t"] * 30.0) % 3) - 1)
		PixelFont.draw_centered(self, x + 17, y + 8 + jitter, icon, c(col), 4, true)
	if done:
		var rewards: Array = s["rewards"]
		for i in rewards.size():
			var r: Dictionary = rewards[i]
			var line := ""
			var col := Palette.WHITE
			if r.has("evolve"):
				line = "EVOLVED > " + Items.EVOLUTIONS[r["id"]]["name"]
				col = Palette.PINK
			elif r["id"] == "repair":
				line = "FULL REPAIR +1000"
				col = Palette.GREEN
			else:
				line = "%s  LV %d" % [Items.get_def(r["id"])["name"], r["level"]]
			ctxt(96 + i * 8, line, col)
		if s["t"] > s["stops"][2] + 0.8 and blink():
			ctxt(172, "PRESS BUTTON", Palette.OFFWHITE)
	else:
		ctxt(100, "SPINNING...", Palette.LIGHT)

# --- death / continue / game over ------------------------------------------
func _draw_destroyed() -> void:
	dim()
	ctxt(70, "UNIT DESTROYED", Palette.RED, 2)
	if Game.lives > 0:
		ctxt(96, "LIVES LEFT: %d" % Game.lives, Palette.WHITE)
		ctxt(106, "BACKUP UNIT ONLINE IN %d" % int(ceil(main.state_timer)), Palette.LIGHT)
	else:
		ctxt(96, "NO UNITS LEFT", Palette.ORANGE)

func _draw_continue() -> void:
	draw_rect(Rect2(0, 0, 256, 192), c(Palette.NIGHT))
	ctxt(40, "CONTINUE?", Palette.YELLOW, 3)
	var n := int(ceil(main.continue_timer))
	ctxt(80, "%d" % n, Palette.WHITE if n > 3 else Palette.RED, 6)
	if blink(0.5):
		ctxt(140, "PRESS BUTTON", Palette.OFFWHITE, 1)
	ctxt(156, "SCORE %07d   LV %d" % [Game.score, Game.level], Palette.LIGHT)
	ctxt(166, "KEEP ALL UPGRADES, +3 UNITS", Palette.SLATE)

func _draw_gameover() -> void:
	draw_rect(Rect2(0, 0, 256, 192), c(Palette.BLACK))
	ctxt(56, "GAME OVER", Palette.RED, 3)
	ctxt(100, "SCORE %07d" % Game.score, Palette.WHITE)
	ctxt(110, "LEVEL %d   TIME %s   KILLS %d" % [Game.level, Game.fmt_time(Game.run_time), Game.kills], Palette.LIGHT)

func _draw_name_entry() -> void:
	draw_texture(title_bg, Vector2.ZERO)
	dim()
	panel(Rect2(32, 24, 192, 144))
	ctxt(32, "NEW HIGH SCORE!", Palette.YELLOW if blink(0.5) else Palette.ORANGE, 2)
	ctxt(54, "SCORE %07d" % Game.score, Palette.WHITE)
	ctxt(70, "ENTER YOUR INITIALS", Palette.LIGHT)
	for i in 3:
		var x := 128 - 36 + i * 24
		var ch: String = main.ALPHABET[main.name_letters[i]]
		var col := Palette.WHITE
		if i == main.name_cursor:
			col = Palette.CYAN
			if blink(0.5):
				draw_rect(Rect2(x - 2, 118, 16, 2), c(Palette.CYAN))
			_diamond(Vector2(x + 6, 84), 2, c(Palette.CYAN))
			_diamond(Vector2(x + 6, 116), 2, c(Palette.CYAN))
		PixelFont.draw(self, Vector2(x, 90), ch, c(col), 4, true)
	ctxt(134, "STICK UP/DOWN: LETTER", Palette.OFFWHITE)
	ctxt(144, "BUTTON: NEXT", Palette.OFFWHITE)
