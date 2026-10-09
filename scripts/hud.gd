class_name Hud
extends Control
## Every screen of the game, drawn at 256x192 with the 3x5 pixel font so it all
## goes through the palette + LCD filter. Reads state from Main.

var main: Node
var logo: Texture2D
var title_bg: Texture2D
var _time := 0.0

const S := 2.0   # viewport pixels per HUD pixel

func _ready() -> void:
	logo = load("res://assets/textures/logo.png")
	title_bg = load("res://assets/textures/title_bg.png")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# --- 2D particles for the upgrade and loot screens ----------------------------
var particles: Array = []     # {pos, vel, grav, life, max, col, size, kind, phase}
var _spark_acc := 0.0
var _last_state := -1
var _lvl_t := 0.0          # seconds since the level-up screen opened
var _last_cursor := -1

func _process(delta: float) -> void:
	_time += delta
	_update_particles(delta)
	queue_redraw()

func _add_particle(pos: Vector2, vel: Vector2, grav: float, life: float, col: int, size: Vector2, kind: String = "dot") -> void:
	particles.append({"pos": pos, "vel": vel, "grav": grav, "life": life, "max": life, "col": col, "size": size, "kind": kind, "phase": randf() * TAU})

func _confetti(n: int, from_top: bool = true) -> void:
	var cols := [Palette.YELLOW, Palette.ORANGE, Palette.CYAN, Palette.PINK, Palette.GREEN, Palette.WHITE, Palette.LIGHT_BLUE, Palette.PURPLE]
	for i in n:
		var p := Vector2(randf() * 256.0, randf_range(-20.0, -2.0) if from_top else randf_range(60.0, 120.0))
		var v := Vector2(randf_range(-12.0, 12.0), randf_range(18.0, 40.0) if from_top else randf_range(-70.0, -30.0))
		var sz := Vector2(3, 1) if randf() < 0.5 else Vector2(2, 2)
		_add_particle(p, v, 14.0, randf_range(3.0, 5.5), cols[randi() % cols.size()], sz, "confetti")

func _card_spark() -> void:
	var i: int = main.levelup_cursor
	var r := Rect2(8 + i * 82, 42, 76, 112)
	var t := randf() * 2.0 * (r.size.x + r.size.y)
	var p: Vector2
	var out: Vector2
	if t < r.size.x: p = Vector2(r.position.x + t, r.position.y); out = Vector2(0, -1)
	elif t < r.size.x + r.size.y: p = Vector2(r.end.x, r.position.y + t - r.size.x); out = Vector2(1, 0)
	elif t < 2.0 * r.size.x + r.size.y: p = Vector2(r.end.x - (t - r.size.x - r.size.y), r.end.y); out = Vector2(0, 1)
	else: p = Vector2(r.position.x, r.end.y - (t - 2.0 * r.size.x - r.size.y)); out = Vector2(-1, 0)
	var cols := [Palette.YELLOW, Palette.WHITE, Palette.ORANGE, Palette.GOLD]
	_add_particle(p, out * randf_range(6.0, 16.0) + Vector2(randf_range(-4, 4), randf_range(-6, 0)), -18.0, randf_range(0.4, 0.9), cols[randi() % cols.size()], Vector2.ONE * (1 if randf() < 0.6 else 2))

func _card_burst(i: int, n: int) -> void:
	var r := Rect2(8 + i * 82, 42, 76, 112)
	var cols := [Palette.YELLOW, Palette.WHITE, Palette.CYAN, Palette.ORANGE]
	for k in n:
		var a := randf() * TAU
		_add_particle(r.get_center() + Vector2(randf_range(-30, 30), randf_range(-50, 50)), Vector2(cos(a), sin(a)) * randf_range(30.0, 80.0), 40.0, randf_range(0.4, 0.8), cols[randi() % cols.size()], Vector2.ONE * (1 if randf() < 0.5 else 2))

## Called by main when a card is taken: big burst from that card.
func take_burst(i: int) -> void:
	_card_burst(i, 70)
	_confetti(30, false)

func _title_star() -> void:
	_add_particle(Vector2(randf_range(50.0, 206.0), randf_range(26.0, 34.0)), Vector2(randf_range(-3, 3), -randf_range(8.0, 16.0)), 0.0, randf_range(0.8, 1.6), Palette.WHITE if randf() < 0.5 else Palette.YELLOW, Vector2.ONE, "star")

func _update_particles(delta: float) -> void:
	var st: int = main.state if main != null else -1
	if st != _last_state:
		_last_state = st
		if st == main.State.LEVELUP:
			_confetti(70)
			_lvl_t = 0.0
			_last_cursor = main.levelup_cursor
	if st == main.State.LEVELUP:
		_lvl_t += delta
		if main.levelup_cursor != _last_cursor:
			_last_cursor = main.levelup_cursor
			_card_burst(main.levelup_cursor, 18)
		_spark_acc += delta * 40.0
		while _spark_acc >= 1.0:
			_spark_acc -= 1.0
			_card_spark()
		if randf() < delta * 7.0:
			_title_star()
		if randf() < delta * 12.0:
			_confetti(1)
	elif st == main.State.SLOT and main.slot.get("done", false) and int(main.slot.get("count", 1)) >= 3:
		if not main.slot.get("_burst", false):
			main.slot["_burst"] = true
			_confetti(90, false)
			_confetti(40, true)
		if randf() < delta * 25.0:
			_confetti(1)
	elif particles.is_empty():
		return
	for p in particles:
		p["vel"].y += p["grav"] * delta
		p["pos"] += p["vel"] * delta
		if p["kind"] == "confetti":
			p["pos"].x += sin(_time * 4.0 + p["phase"]) * 20.0 * delta
		p["life"] -= delta
	particles = particles.filter(func(p): return p["life"] > 0.0 and p["pos"].y < 200.0)
	if st != main.State.LEVELUP and st != main.State.SLOT:
		particles.clear()

func _draw_particles() -> void:
	for p in particles:
		var k: float = p["life"] / p["max"]
		var col: Color = c(p["col"])
		var pos: Vector2 = p["pos"].floor()
		match p["kind"]:
			"star":
				if fmod(_time * 10.0 + p["phase"], 2.0) < 1.0:
					draw_rect(Rect2(pos - Vector2(1, 0), Vector2(3, 1)), col)
					draw_rect(Rect2(pos - Vector2(0, 1), Vector2(1, 3)), col)
				else:
					draw_rect(Rect2(pos, Vector2(1, 1)), col)
			"confetti":
				if k < 0.3 and fmod(_time * 12.0 + p["phase"], 2.0) < 1.0:
					continue
				var sz: Vector2 = p["size"] if fmod(_time * 3.0 + p["phase"], 2.0) < 1.0 else Vector2(p["size"].y, p["size"].x)
				draw_rect(Rect2(pos, sz), col)
			_:
				if k < 0.35 and fmod(_time * 16.0 + p["phase"], 2.0) < 1.0:
					continue
				draw_rect(Rect2(pos, p["size"]), col)

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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(S, S))
	PixelFont.unit = S
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
	if blink(1.0):
		ctxt(146, "- INSERT COIN -", Palette.YELLOW, 2)
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
	if blink(1.0):
		ctxt(168, "- INSERT COIN -", Palette.YELLOW)

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
			var sp := cam.unproject_position(p) / S
			var col := Palette.GREEN
			if e.type == e.Type.MISSILE: col = Palette.RED
			if e.advanced == 1: col = Palette.YELLOW
			if e.advanced == 2: col = Palette.PURPLE
			if e.is_boss: col = Palette.WHITE
			var onscreen := sp.x >= 0 and sp.x < 256 and sp.y >= 0 and sp.y < 192
			if not onscreen:
				if radar >= 3 and (e.type == e.Type.MISSILE or e.is_boss):
					var ep := Vector2(clampf(sp.x, 4, 251), clampf(sp.y, 4, 187))
					draw_rect(Rect2(ep - Vector2(2, 2), Vector2(4, 4)), c(col))
				continue
			var dist := p.distance_to(cam.global_position)
			var s := clampf(e.radius * 180.0 / maxf(dist, 1.0), 3.0, 14.0)
			_bracket(sp, s, c(col))
			if e.is_boss or e.advanced > 0:
				bar(sp.x - 8, sp.y - s - 4, 16, 2, e.hp / e.max_hp, Palette.RED, Palette.DARK)
	if radar >= 2:
		var t = main.best_target()
		if t != null:
			var lp: Vector3 = main.lead_point(t)
			if not cam.is_position_behind(lp):
				var sp := cam.unproject_position(lp) / S
				_diamond(sp, 3, c(Palette.CYAN))
	if radar >= 1:
		_scope(enemies)

	# crosshair sits where the gun line projects, not the screen centre
	var aim_pt: Vector3 = main.turret.muzzle_pos() + main.turret.aim_dir() * 300.0
	var ap := cam.unproject_position(aim_pt) / S
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
	var th: float = Game.threat()
	rtxt(252, 24, "THREAT X%.1f" % th, Palette.GREEN if th < 1.8 else (Palette.YELLOW if th < 3.0 else Palette.RED))
	if Game.multiplier > 1:
		rtxt(252, 33, "X%d" % Game.multiplier, Palette.ORANGE, 2)
		bar(232, 49, 20, 2, Game.combo_timer / 2.5, Palette.ORANGE)

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
	var half: float = deg_to_rad(Game.attack_arc() * 0.5)
	if half < PI:
		for sgn in [-1.0, 1.0]:
			var b: float = sgn * half - yaw
			# world +X is screen left from behind the gun, so the scope mirrors x
			draw_line(center, center + Vector2(-sin(b), -cos(b)) * r, c(Palette.YELLOW), 1.0)
	var rng := 400.0 if Game.radar_level >= 3 else 300.0
	for e in enemies:
		if e.dead:
			continue
		var rel: Vector3 = e.global_position.rotated(Vector3.UP, -yaw)
		var v := Vector2(-rel.x, -rel.z) / rng * r
		if v.length() > r:
			continue
		var col := Palette.GREEN
		if e.type == e.Type.MISSILE: col = Palette.RED
		if e.advanced > 0: col = Palette.YELLOW
		if e.is_boss: col = Palette.WHITE
		var sz := 2 if (e.advanced > 0 or e.is_boss) else 1
		draw_rect(Rect2(center + v - Vector2(sz / 2.0, sz / 2.0), Vector2(sz, sz)), c(col))

# --- level up --------------------------------------------------------------
func _ease_out_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var s := 1.7
	t -= 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0

func _sunburst(center: Vector2, rays: int, len: float, col: Color, speed: float) -> void:
	for i in rays:
		var a := _time * speed + i * TAU / rays
		var w := 0.06 + 0.04 * sin(_time * 2.0 + i)
		var p1 := center + Vector2(cos(a - w), sin(a - w)) * len
		var p2 := center + Vector2(cos(a + w), sin(a + w)) * len
		draw_colored_polygon(PackedVector2Array([center, p1, p2]), col)

func _draw_levelup() -> void:
	dim()
	# rotating sunburst behind everything, like a slot-machine win
	_sunburst(Vector2(128, 26), 14, 300.0, Color(1.0, 0.85, 0.2, 0.10), 0.25)
	_sunburst(Vector2(128, 26), 10, 300.0, Color(1.0, 0.5, 0.1, 0.07), -0.17)
	var bob := sin(_time * 5.0) * 2.0
	ctxt(20 + int(bob), "LEVEL UP!  LV %d" % Game.level, Palette.YELLOW if blink(0.3) else Palette.LIGHT_YELLOW, 2)
	var choices: Array = main.levelup_choices
	for i in choices.size():
		var id: String = choices[i]
		var d := Items.get_def(id)
		var sel: bool = i == main.levelup_cursor
		# cards bounce in from below, staggered
		var k := _ease_out_back((_lvl_t - i * 0.12) / 0.45)
		var x := 8 + i * 82
		var y := int(42 + (1.0 - k) * 160.0)
		if sel:
			y -= 4
		var lvl := Game.item_level(id)
		var frame := Palette.SLATE
		if d["kind"] == "weapon": frame = Palette.RUST
		if d["kind"] == "mount": frame = Palette.GOLD
		if sel:
			frame = Palette.YELLOW if blink(0.25) else Palette.WHITE
		panel(Rect2(x, y, 76, 112), frame, Palette.NIGHT if not sel else Palette.DARK)
		if sel:
			# second pulsing border and a shine sweep across the card
			var pulse := 1 + int(fmod(_time * 6.0, 2.0))
			draw_rect(Rect2(x - pulse, y - pulse, 76 + pulse * 2, 112 + pulse * 2), c(Palette.YELLOW), false, 1.0)
			var sx := fmod(_time * 90.0, 190.0) - 60.0
			for row in 112:
				var px := x + int(sx + row * 0.5)
				if px >= x + 1 and px + 4 <= x + 75:
					draw_rect(Rect2(px, y + row, 4, 1), Color(1, 1, 1, 0.16))
					draw_rect(Rect2(px + 1, y + row, 2, 1), Color(1, 1, 1, 0.22))
		var icon_bob := int(sin(_time * 4.0 + i) * 1.5) if sel else 0
		PixelFont.draw_centered(self, x + 38, y + 6 + icon_bob, d["icon"], c(d["color"]), 4, true)
		for li in wrap_text(d["name"], 18).size():
			PixelFont.draw_centered(self, x + 38, y + 32 + li * 7, wrap_text(d["name"], 18)[li], c(Palette.WHITE), 1, true)
		if lvl == 0:
			var nc := Palette.GREEN if blink(0.3) else Palette.LEAF
			PixelFont.draw_centered(self, x + 38, y + 47, "* NEW! *", c(nc), 1, true)
		else:
			var arrow := ">" if blink(0.4) else ">>"
			PixelFont.draw_centered(self, x + 38, y + 48, "LV %d %s %d" % [lvl, arrow, lvl + 1], c(Palette.CYAN), 1, true)
		var lines := wrap_text(Items.desc_for(id, lvl + 1), 18)
		for li in lines.size():
			PixelFont.draw_centered(self, x + 38, y + 62 + li * 7, lines[li], c(Palette.LIGHT_SAND), 1, true)
		if d["kind"] == "weapon":
			PixelFont.draw_centered(self, x + 38, y + 100, "WEAPON", c(Palette.ORANGE), 1, false)
		elif d["kind"] == "mount":
			PixelFont.draw_centered(self, x + 38, y + 100, "MOUNT", c(Palette.GOLD), 1, false)
		else:
			PixelFont.draw_centered(self, x + 38, y + 100, "PASSIVE", c(Palette.PALE_BLUE), 1, false)
		if lvl + 1 >= int(d["max"]):
			PixelFont.draw_centered(self, x + 38, y + 92, "MAX", c(Palette.PINK), 1, false)
	_draw_particles()
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
	ctxt(20, title, tcol, 2)
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
		var y := 96
		for i in rewards.size():
			var r: Dictionary = rewards[i]
			if r.has("evolve"):
				var ev: Dictionary = Items.EVOLUTIONS[r["id"]]
				ctxt(y, "EVOLVED > " + ev["name"], Palette.PINK)
				y += 8
				ctxt(y, ev["desc"], Palette.LIGHT_PINK if Palette.COLORS.size() > 61 else Palette.PINK)
			elif r["id"] == "repair":
				ctxt(y, "FULL REPAIR +1000", Palette.GREEN)
			else:
				var lvl: int = r["level"]
				ctxt(y, "%s LV %d: %s" % [Items.get_def(r["id"])["name"], lvl, Items.desc_for(r["id"], lvl)], Palette.WHITE)
			y += 8
	else:
		ctxt(100, "SPINNING...", Palette.LIGHT)
	_draw_particles()

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
	ctxt(156, "SCORE %07d   LV %d" % [Game.score, Game.level], Palette.LIGHT)

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
