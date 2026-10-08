extends Node
## SUPER CIWS - root node. Builds the low-res 3D viewport, the retro post filter
## and runs the arcade state machine (title / play / level-up / loot / lives / continue / scores).

enum State { TITLE, SCORES, PLAYING, LEVELUP, SLOT, DESTROYED, CONTINUE, GAMEOVER, NAME_ENTRY }

const VIEW_W := 512
const VIEW_H := 384
const WING_SPACING := 17.0   # metres between linked CIWS mounts
const HUD_SCALE := 2
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ. "

var state: int = State.TITLE
var view: SubViewport
var screen: ColorRect
var screen_mat: ShaderMaterial
var world: World
var turret: Turret                 # main mount: camera + player input
var wings: Array[Turret] = []      # LINKED MOUNT wing guns, shown as the upgrade levels up
var enemies: Node3D
var projectiles: Node3D
var fx: Node3D
var casings: Casings
var hud: Hud
var laser: LaserBeam
var lasers: Array[LaserBeam] = []  # one beam per mount, lasers[0] == laser

var mouse_delta := Vector2.ZERO
var state_timer := 0.0
var attract_timer := 0.0
var spawn_timer := 2.0
var next_boss_time := 240.0
var fire_accum := 0.0
var laser_heat := 0.0
var laser_locked := false
var missile_timer := 0.0
var levelup_choices: Array = []
var levelup_cursor := 0
var pending_levelups := 0
var slot: Dictionary = {}
var continue_timer := 0.0
var name_letters: Array = [0, 0, 0]
var name_cursor := 0
var rank := -1
var message := ""
var message_timer := 0.0
var flash := 0.0
var damage_flash := 0.0
var threat := false
var invuln := 0.0
var _time := 0.0

# --- touch ---------------------------------------------------------------
var touch_enabled := false
var touches: Dictionary = {}        # finger index -> {zone, start, pos, t}
var touch_stick := Vector2.ZERO     # virtual stick vector, -1..1
var touch_btn1_held := false
var touch_tap := false              # one-frame edge: a short tap was released
var touch_tap_pos := Vector2.ZERO
var touch_btn2_tap := false
var touch_nav := Vector2i.ZERO      # swipe direction released this frame
var game_rect := Rect2()
var overlay: TouchOverlay
var lut_view: SubViewport

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_build_scene()
	if OS.has_feature("template") and not OS.has_feature("editor"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_enter(State.TITLE)
	_apply_debug_args()

## Command line (after "--"): --autostart  --fast-forward=SECONDS  --state=levelup|slot|scores|continue|nameentry|destroyed  --autoaim  --touch  --mounts=1..3
func _apply_debug_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	for a in args:
		if a == "--autostart" or a.begins_with("--fast-forward") or a.begins_with("--state"):
			start_run()
			break
	for a in args:
		if a.begins_with("--fast-forward="):
			var secs := float(a.get_slice("=", 1))
			Game.run_time = secs
			for i in 10:
				var lvl_up := Game.add_xp(Game.xp_needed())
				if lvl_up:
					var ch := Game.offer_choices(1)
					if not ch.is_empty():
						Game.grant(ch[0])
			for id in ["radar", "laser", "missiles"]:
				if Game.item_level(id) == 0:
					Game.grant(id)
			_refresh_mounts()
			for i in 12:
				spawn_enemy(Enemy.Type.values()[i % 3], 1 if i == 3 else 0)
			for e in enemies.get_children():
				e.global_position *= 0.45
				e.global_position.y = max(e.global_position.y, 12.0)
			pending_levelups = 0
		elif a.begins_with("--mounts="):
			while Game.mount_count() < clampi(int(a.get_slice("=", 1)), 1, 3):
				Game.grant("linked")
			_refresh_mounts()
		elif a == "--autoaim":
			debug_autoaim = true
		elif a == "--touch":
			touch_enabled = true
			_layout()
		elif a.begins_with("--state="):
			match a.get_slice("=", 1):
				"levelup": _enter(State.LEVELUP)
				"slot": _start_slot("purple")
				"scores": rank = 2; _enter(State.SCORES)
				"continue": Game.lives = 0; _enter(State.CONTINUE)
				"nameentry": _enter(State.NAME_ENTRY)
				"destroyed": _enter(State.DESTROYED)

var debug_autoaim := false

# --- scene -----------------------------------------------------------------
func _build_scene() -> void:
	view = SubViewport.new()
	view.size = Vector2i(VIEW_W, VIEW_H)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	view.handle_input_locally = false
	view.oversampling = false   # keep pixel fonts on their native grids
	# Main is PROCESS_MODE_ALWAYS so menus keep running; the game world must not inherit that.
	view.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(view)

	world = World.new()
	view.add_child(world)
	turret = Turret.new()
	view.add_child(turret)
	# wing mounts stand in a row beside the main gun: first to its right on screen, then left
	for x in [-WING_SPACING, WING_SPACING]:
		var w := Turret.new()
		w.linked = true
		w.position = Vector3(x, 0, 0)
		w.visible = false
		view.add_child(w)
		wings.append(w)
	enemies = Node3D.new()
	view.add_child(enemies)
	projectiles = Node3D.new()
	view.add_child(projectiles)
	fx = Node3D.new()
	view.add_child(fx)
	casings = Casings.new()
	view.add_child(casings)
	laser = LaserBeam.new()
	view.add_child(laser)
	lasers.append(laser)
	for i in wings.size():
		var lb := LaserBeam.new()
		view.add_child(lb)
		lasers.append(lb)

	var layer := CanvasLayer.new()
	# HUD draws in 256x192 logical pixels at 2x (shapes scaled, fonts on their native grids)
	view.add_child(layer)
	hud = Hud.new()
	hud.main = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.size = Vector2(VIEW_W, VIEW_H)
	layer.add_child(hud)

	screen = ColorRect.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_mat = ShaderMaterial.new()
	screen_mat.shader = load("res://shaders/retro.gdshader")
	var pal := PackedColorArray(Palette.COLORS)
	while pal.size() < 128:
		pal.append(Color.BLACK)
	screen_mat.set_shader_parameter("palette", pal)
	screen_mat.set_shader_parameter("palette_size", Palette.COLORS.size())
	screen_mat.set_shader_parameter("low_res", Vector2(VIEW_W, VIEW_H))
	screen_mat.set_shader_parameter("screen_tex", view.get_texture())
	screen.material = screen_mat
	add_child(screen)

	# palette lookup table, rendered once on the GPU
	lut_view = SubViewport.new()
	lut_view.size = Vector2i(1024, 32)
	lut_view.disable_3d = true
	lut_view.transparent_bg = false
	lut_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lut_rect := ColorRect.new()
	lut_rect.size = Vector2(1024, 32)
	var lut_mat := ShaderMaterial.new()
	lut_mat.shader = load("res://shaders/palette_lut.gdshader")
	lut_mat.set_shader_parameter("palette", pal)
	lut_mat.set_shader_parameter("palette_size", Palette.COLORS.size())
	lut_rect.material = lut_mat
	lut_view.add_child(lut_rect)
	add_child(lut_view)
	screen_mat.set_shader_parameter("lut_tex", lut_view.get_texture())

	overlay = TouchOverlay.new()
	overlay.main = self
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	touch_enabled = DisplayServer.is_touchscreen_available()
	get_tree().root.size_changed.connect(_layout)
	_layout()

## Fit the 4:3 game inside whatever window shape we have. On touch devices in
## portrait (phones, folded foldables) the game sits at the top so the
## controls get the space underneath.
func _layout() -> void:
	var ws := Vector2(get_viewport().size)
	if ws.x < 1.0 or ws.y < 1.0:
		return
	var w: float
	var h: float
	if ws.x / ws.y >= 4.0 / 3.0:
		h = ws.y
		w = h * 4.0 / 3.0
	else:
		w = ws.x
		h = w * 3.0 / 4.0
	var pos := Vector2((ws.x - w) * 0.5, (ws.y - h) * 0.5)
	if ws.y > ws.x and touch_enabled:
		pos.y = 0.0
	game_rect = Rect2(pos, Vector2(w, h))
	screen_mat.set_shader_parameter("game_rect", Vector4(pos.x / ws.x, pos.y / ws.y, w / ws.x, h / ws.y))
	overlay.layout(ws, game_rect, touch_enabled)

## Window position -> HUD (256x192) coordinates, or (-1,-1) when outside the game.
func window_to_hud(p: Vector2) -> Vector2:
	if not game_rect.has_point(p):
		return Vector2(-1, -1)
	return (p - game_rect.position) / game_rect.size * Vector2(VIEW_W / HUD_SCALE, VIEW_H / HUD_SCALE)

# --- input -----------------------------------------------------------------
func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e

func _joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e

func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e

func _action(name: String, events: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.4)
	for e in events:
		InputMap.action_add_event(name, e)

func _setup_input() -> void:
	# Button 1: the one arcade button. Button 2: optional second button.
	_action("btn1", [_key(KEY_SPACE), _key(KEY_ENTER), _key(KEY_Z), _key(KEY_CTRL), _joy(JOY_BUTTON_A), _joy(JOY_BUTTON_START), _mouse(MOUSE_BUTTON_LEFT)])
	_action("btn2", [_key(KEY_X), _key(KEY_SHIFT), _key(KEY_ALT), _joy(JOY_BUTTON_B), _joy(JOY_BUTTON_X), _mouse(MOUSE_BUTTON_RIGHT)])
	_action("aim_left", [_key(KEY_LEFT), _key(KEY_A), _joy(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("aim_right", [_key(KEY_RIGHT), _key(KEY_D), _joy(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("aim_up", [_key(KEY_UP), _key(KEY_W), _joy(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("aim_down", [_key(KEY_DOWN), _key(KEY_S), _joy(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	# menu navigation re-uses the built-in ui_* actions; add WASD to them
	_action("ui_left", [_key(KEY_A)])
	_action("ui_right", [_key(KEY_D)])
	_action("ui_up", [_key(KEY_W)])
	_action("ui_down", [_key(KEY_S)])
	_action("fullscreen", [_key(KEY_F11)])
	_action("quit", [_key(KEY_ESCAPE)])

func _touch_zone(p: Vector2) -> String:
	if p.distance_to(overlay.btn2_center) <= overlay.btn2_radius * 1.3 and state == State.PLAYING and Game.missile_count > 0:
		return "btn2"
	if p.x < get_viewport().size.x * 0.5:
		return "stick"
	return "btn1"

func _handle_touch(event: InputEvent) -> void:
	if not touch_enabled:
		touch_enabled = true
		_layout()
	if event is InputEventScreenTouch:
		if event.pressed:
			var zone := _touch_zone(event.position)
			touches[event.index] = {"zone": zone, "start": event.position, "pos": event.position, "t": _time}
			if zone == "btn2":
				touch_btn2_tap = true
		elif touches.has(event.index):
			var t: Dictionary = touches[event.index]
			var d: Vector2 = event.position - t["start"]
			var ui: float = overlay.ui
			if _time - t["t"] < 0.4 and d.length() < ui * 0.35:
				touch_tap = true
				touch_tap_pos = event.position
			elif d.length() > ui * 0.8 and state != State.PLAYING:
				if absf(d.x) > absf(d.y):
					touch_nav = Vector2i(signi(int(d.x)), 0)
				else:
					touch_nav = Vector2i(0, signi(int(d.y)))
			touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.has(event.index):
		var t: Dictionary = touches[event.index]
		t["pos"] = event.position
		if t["zone"] == "stick":
			var v: Vector2 = (event.position - t["start"]) / overlay.stick_radius
			touch_stick = v.limit_length(1.0)
	# derived states
	touch_btn1_held = false
	var stick_active := false
	for t in touches.values():
		if t["zone"] == "btn1":
			touch_btn1_held = true
		if t["zone"] == "stick":
			stick_active = true
	if not stick_active:
		touch_stick = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch(event)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative
	if event.is_action_pressed("fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("quit"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif OS.has_feature("template"):
			get_tree().quit()
	if event is InputEventMouseButton and event.pressed and state == State.PLAYING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func btn1() -> bool:
	return Input.is_action_just_pressed("btn1") or touch_tap

func btn1_held() -> bool:
	return Input.is_action_pressed("btn1") or touch_btn1_held

func btn2() -> bool:
	return Input.is_action_just_pressed("btn2") or touch_btn2_tap

func nav_left() -> bool:
	return Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("aim_left") or touch_nav.x < 0

func nav_right() -> bool:
	return Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("aim_right") or touch_nav.x > 0

func nav_up() -> bool:
	return Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("aim_up") or touch_nav.y < 0

func nav_down() -> bool:
	return Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("aim_down") or touch_nav.y > 0

# --- state machine ---------------------------------------------------------
func _enter(s: int) -> void:
	state = s
	state_timer = 0.0
	get_tree().paused = state != State.PLAYING
	_stop_lasers()
	Sfx.loop("laser", false)
	turret.firing = state == State.PLAYING
	match state:
		State.TITLE:
			attract_timer = 9.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if not OS.has_feature("template") else Input.MOUSE_MODE_HIDDEN
		State.SCORES:
			attract_timer = 7.0
		State.PLAYING:
			if OS.has_feature("template"):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		State.LEVELUP:
			levelup_choices = Game.offer_choices(3)
			levelup_cursor = 0
			if levelup_choices.is_empty():
				Game.hp = Game.max_hp
				Game.add_score(1000)
				pending_levelups = 0
				_enter(State.PLAYING)
				return
			Sfx.play("levelup")
		State.DESTROYED:
			state_timer = 3.0
			Sfx.play("explode_big")
			Sfx.play("lost_life")
			Input.vibrate_handheld(400)
			for m in mounts():
				Explosion.spawn(fx, m.gun_pos(), 4.0, [Palette.ORANGE, Palette.YELLOW, Palette.WHITE, Palette.RED], 18)
				Debris.spawn(fx, m.gun_pos(), 16, [Palette.SLATE, Palette.LIGHT, Palette.STEEL, Palette.DARK, Palette.RUST], 1.6, 1.4)
			_set_destroyed(true)
			Game.lives -= 1
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.global_position.distance_to(Vector3.ZERO) < 170.0 and not e.is_boss:
					e.die(false)
			for p in projectiles.get_children():
				p.queue_free()
		State.CONTINUE:
			continue_timer = 10.0
			Sfx.play("countdown")
		State.GAMEOVER:
			state_timer = 3.5
		State.NAME_ENTRY:
			name_letters = [0, 0, 0]
			name_cursor = 0
			Sfx.play("jackpot")

func start_run() -> void:
	Game.new_run()
	for n in enemies.get_children(): n.queue_free()
	for n in projectiles.get_children(): n.queue_free()
	for n in fx.get_children(): n.queue_free()
	turret.yaw = 0.0; turret.target_yaw = 0.0
	turret.pitch = 10.0; turret.target_pitch = 10.0
	_set_destroyed(false)
	_refresh_mounts()
	spawn_timer = 1.5
	next_boss_time = 240.0
	fire_accum = 0.0
	laser_heat = 0.0
	laser_locked = false
	missile_timer = 0.0
	pending_levelups = 0
	rank = -1
	invuln = 2.0
	Sfx.play("coin")
	_enter(State.PLAYING)

func show_message(m: String, t: float = 2.0) -> void:
	message = m
	message_timer = t

func _process(delta: float) -> void:
	_time += delta
	if message_timer > 0.0:
		message_timer -= delta
	flash = max(0.0, flash - delta * 4.0)
	damage_flash = max(0.0, damage_flash - delta * 2.5)
	screen_mat.set_shader_parameter("flash", flash)
	screen_mat.set_shader_parameter("damage", damage_flash)
	if Enemy.pulse_mat:
		Enemy.pulse_mat.emission_energy_multiplier = 1.0 + 3.0 * max(0.0, sin(_time * 9.0))
	match state:
		State.TITLE:
			attract_timer -= delta
			if btn1():
				start_run()
			elif attract_timer <= 0.0:
				_enter(State.SCORES)
		State.SCORES:
			attract_timer -= delta
			if btn1():
				start_run()
			elif attract_timer <= 0.0:
				_enter(State.TITLE)
		State.PLAYING:
			_update_playing(delta)
		State.LEVELUP:
			_update_levelup()
		State.SLOT:
			_update_slot(delta)
		State.DESTROYED:
			state_timer -= delta
			if state_timer <= 0.0:
				if Game.lives > 0:
					Game.hp = Game.max_hp
					_set_destroyed(false)
					invuln = 3.0
					show_message("BACKUP UNIT ONLINE", 2.0)
					_enter(State.PLAYING)
				else:
					_enter(State.CONTINUE)
		State.CONTINUE:
			var before := int(ceil(continue_timer))
			continue_timer -= delta
			if int(ceil(continue_timer)) != before and continue_timer > 0.0:
				Sfx.play("countdown", 0.0, 1.0 if continue_timer > 3.0 else 1.4)
			if btn1():
				Game.continue_run()
				_set_destroyed(false)
				invuln = 3.0
				Sfx.play("coin")
				show_message("CONTINUE %d" % Game.continues_used, 2.0)
				_enter(State.PLAYING)
			elif continue_timer <= 0.0:
				_enter(State.GAMEOVER)
		State.GAMEOVER:
			state_timer -= delta
			if state_timer <= 0.0 or btn1():
				if Game.qualifies():
					_enter(State.NAME_ENTRY)
				else:
					rank = -1
					_enter(State.SCORES)
		State.NAME_ENTRY:
			_update_name_entry()
	mouse_delta = Vector2.ZERO
	touch_tap = false
	touch_btn2_tap = false
	touch_nav = Vector2i.ZERO

# --- gameplay --------------------------------------------------------------
func _update_playing(delta: float) -> void:
	Game.tick(delta)
	invuln = max(0.0, invuln - delta)
	var stick := Input.get_vector("aim_left", "aim_right", "aim_down", "aim_up")
	stick = (stick + Vector2(touch_stick.x, -touch_stick.y)).limit_length(1.0)
	turret.aim(stick, mouse_delta, delta)
	if debug_autoaim:
		var ne := nearest_enemy(turret.gun_pos())
		if ne != null:
			turret.track_toward(lead_point(ne), 1.0, delta)
			turret.target_yaw = wrapf(turret.target_yaw, -180.0, 180.0)
	if Game.auto_track > 0.0:
		var t := best_target()
		if t != null:
			turret.track_toward(lead_point(t), Game.auto_track, delta)
	turret.update(delta)
	for w in mounts().slice(1):
		w.follow(turret, delta)

	# the gun never stops
	fire_accum += delta * Game.vulcan_rof
	while fire_accum >= 1.0:
		fire_accum -= 1.0
		_fire_round()

	# beam weapon on the button
	if Game.item_level("laser") > 0:
		var want := btn1_held() and not laser_locked
		if want:
			var ms := mounts()
			for i in ms.size():
				lasers[i].fire(ms[i].muzzle_pos(), ms[i].aim_dir(), delta, Game.laser_dps, Game.laser_wide, Game.evolved.has("laser"))
			Sfx.loop("laser", true)
			if Game.laser_heat_cap > 0.0:
				laser_heat += 30.0 * delta
				if laser_heat >= Game.laser_heat_cap:
					laser_heat = Game.laser_heat_cap
					laser_locked = true
					Sfx.play("warning")
		else:
			_stop_lasers()
			Sfx.loop("laser", false)
			laser_heat = max(0.0, laser_heat - Game.laser_cooling * delta)
			if laser_locked and laser_heat < Game.laser_heat_cap * 0.3:
				laser_locked = false

	# missiles: auto when ready and something is in range, button 2 fires early
	if Game.missile_count > 0:
		missile_timer -= delta
		if missile_timer <= 0.0:
			var near := nearest_enemy(Vector3(0, 14, 0))
			var manual := btn2()
			if near != null and (manual or near.global_position.length() < 230.0):
				_launch_salvo()
				missile_timer = Game.missile_cooldown

	_spawn_director(delta)
	threat = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.type == e.Type.MISSILE and e.global_position.length() < 140.0:
			threat = true
			break

	if Game.hp <= 0.0:
		_enter(State.DESTROYED)

func _fire_round() -> void:
	var right := turret.camera.global_basis.x
	var back := turret.camera.global_basis.z
	for m in mounts():
		_fire_mount(m, right, back)
	if randi() % 2 == 0:
		Sfx.play("shot" if randf() < 0.5 else "shot2", -12.0, randf_range(0.9, 1.15))

func _fire_mount(mount: Turret, right: Vector3, back: Vector3) -> void:
	var base := mount.aim_dir()
	for i in Game.vulcan_rounds:
		var spread := deg_to_rad(Game.vulcan_spread)
		var axis := base.cross(Vector3.UP).normalized()
		if axis.length_squared() < 0.001:
			axis = Vector3.RIGHT
		var d := base.rotated(axis, randf_range(-spread, spread)).rotated(base, randf() * TAU)
		var b := Bullet.new()
		b.velocity = d * Game.bullet_speed
		b.damage = Game.vulcan_dmg
		projectiles.add_child(b)
		b.global_position = mount.muzzle_pos() + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0) + (axis * (i - 0.5) * 1.6 if Game.vulcan_rounds > 1 else Vector3.ZERO)
		casings.eject(mount.eject_pos(right), right, back)

func _launch_salvo() -> void:
	var list := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.dead)
	list.sort_custom(func(a, b): return a.global_position.length() < b.global_position.length())
	if list.is_empty():
		return
	var k := 0
	for mount in mounts():
		for i in Game.missile_count:
			var m := HomingMissile.new()
			m.target = list[k % list.size()]
			k += 1
			m.damage = 6.0
			m.splash = Game.missile_splash
			projectiles.add_child(m)
			var side := -1.0 if i % 2 == 0 else 1.0
			m.global_position = mount.gun_pos() + mount.yaw_node.global_basis.x * side * 3.0 + Vector3(0, 2, 0)
			m.dir = (Vector3.UP * 1.2 + mount.yaw_node.global_basis.x * side * 0.6 + mount.aim_dir() * 0.4).normalized()
	Sfx.play("missile", 0.0, randf_range(0.9, 1.1))

func _spawn_director(delta: float) -> void:
	var t: float = Game.run_time
	spawn_timer -= delta
	var alive := get_tree().get_nodes_in_group("enemies").size()
	if spawn_timer <= 0.0 and alive < 36:
		spawn_timer = Game.spawn_interval() * randf_range(0.7, 1.3)
		var weights := {Enemy.Type.QUAD: 5.0}
		if t > 40.0: weights[Enemy.Type.FIXED] = 3.0
		if t > 90.0: weights[Enemy.Type.MISSILE] = 1.5 + t / 240.0
		var total := 0.0
		for w in weights.values(): total += w
		var r := randf() * total
		var type: int = Enemy.Type.QUAD
		for k in weights.keys():
			r -= weights[k]
			if r <= 0.0:
				type = k
				break
		var advanced := 0
		if randf() < Game.advanced_chance():
			advanced = 2 if randf() < 0.25 else 1
		spawn_enemy(type, advanced)
		# extra spawns per tick as the threat climbs
		if Game.threat() > 1.8 and randf() < 0.35:
			spawn_enemy(Enemy.Type.QUAD, 0)
		if Game.threat() > 3.0 and randf() < 0.35:
			spawn_enemy(Enemy.Type.FIXED, 0)
	if t >= next_boss_time:
		next_boss_time += 300.0
		spawn_enemy(Enemy.Type.UFO, 0)
		show_message("WARNING: UFO CONTACT", 3.0)
		Sfx.play("warning")

func difficulty() -> float:
	return Game.threat()

func spawn_enemy(type: int, advanced: int, at: Vector3 = Vector3.INF) -> Enemy:
	var e := Enemy.new()
	e.setup(type, advanced, difficulty())
	enemies.add_child(e)
	if at != Vector3.INF:
		e.global_position = at
	else:
		# bearing inside the attack cone, measured from the battery's forward (+Z)
		var half := deg_to_rad(Game.attack_arc() * 0.5)
		var a := randf_range(-half, half)
		var r := 300.0
		var alt := 30.0
		match type:
			Enemy.Type.QUAD: r = randf_range(260, 320); alt = randf_range(15, 45)
			Enemy.Type.FIXED: r = randf_range(330, 390); alt = randf_range(25, 60)
			Enemy.Type.MISSILE: r = randf_range(380, 450); alt = randf_range(60, 130)
			Enemy.Type.UFO: r = 320.0; alt = 75.0
		e.global_position = Vector3(sin(a) * r, alt, cos(a) * r)
	if advanced > 0:
		show_message("ADVANCED CONTACT!", 1.5)
	return e

func spawn_from_boss(pos: Vector3) -> void:
	if get_tree().get_nodes_in_group("enemies").size() < 40:
		var e := spawn_enemy(Enemy.Type.QUAD, 0, pos + Vector3(randf_range(-10, 10), -8, randf_range(-10, 10)))
		e.position.y = max(e.position.y, 10.0)

func nearest_enemy(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_squared_to(from)
		if d < bd:
			bd = d
			best = e
	return best

func best_target() -> Node3D:
	## The enemy closest to the reticle, favouring missiles.
	var best: Node3D = null
	var bs := INF
	var dir := turret.aim_dir()
	var origin := turret.camera.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var rel: Vector3 = e.global_position - origin
		var ang := dir.angle_to(rel)
		if ang > deg_to_rad(20.0):
			continue
		var s := ang * (0.5 if e.type == e.Type.MISSILE else 1.0) * (0.7 if e.is_boss else 1.0)
		if s < bs:
			bs = s
			best = e
	return best

func lead_point(e: Node3D) -> Vector3:
	var m := turret.muzzle_pos()
	var p: Vector3 = e.global_position
	var v: Vector3 = e.velocity
	var s := Game.bullet_speed
	var t := p.distance_to(m) / s
	for i in 3:
		t = (p + v * t).distance_to(m) / s
	return p + v * t

# --- linked mounts ----------------------------------------------------------
## Every CIWS in the row, main mount first.
func mounts() -> Array[Turret]:
	var out: Array[Turret] = [turret]
	for w in wings:
		if w.visible:
			out.append(w)
	return out

## Show as many wing mounts as LINKED MOUNT allows; every mount shows the addons you own.
func _refresh_mounts() -> void:
	turret.refresh_addons()
	var xs: Array[float] = [0.0]
	for i in wings.size():
		var w := wings[i]
		var on := i < Game.mount_count() - 1
		if on and not w.visible:
			w.yaw = turret.yaw
			w.pitch = turret.pitch
			w.set_destroyed(turret.hidden_for_death)
			if state == State.LEVELUP or state == State.SLOT:
				show_message("LINKED MOUNT ONLINE", 2.0)
		w.visible = on
		w.refresh_addons()
		if on:
			xs.append(w.position.x)
	casings.mount_xs = xs
	var center := 0.0
	for x in xs:
		center += x / xs.size()
	turret.frame_mounts(Game.mount_count(), center)

func _set_destroyed(d: bool) -> void:
	turret.set_destroyed(d)
	for w in wings:
		w.set_destroyed(d)

func _stop_lasers() -> void:
	for lb in lasers:
		lb.stop()

# --- callbacks from entities ----------------------------------------------
func on_enemy_killed(e: Node3D, by_player: bool) -> void:
	var size := 1.0
	if e.advanced > 0: size = 1.8
	if e.is_boss: size = 3.2
	Explosion.spawn(fx, e.global_position, size, [Palette.ORANGE, Palette.YELLOW, Palette.WHITE, Palette.RED], 8 + int(size * 4))
	var wreck_cols := [Palette.RED, Palette.DARK, Palette.STEEL, Palette.RUST]
	if e.advanced == 1: wreck_cols.append(Palette.GOLD)
	if e.advanced == 2: wreck_cols.append(Palette.PURPLE)
	Debris.spawn(fx, e.global_position, 4 + int(size * 3), wreck_cols, 0.7 + size * 0.4)
	Sfx.play("explode_big" if e.is_boss else "explode", 0.0 if size > 1.0 else -4.0, randf_range(0.9, 1.2))
	if not by_player:
		return
	Game.register_kill(e.points)
	var chips := 1
	if e.advanced > 0: chips = 4
	if e.is_boss: chips = 8
	for i in chips:
		var c := XpChip.new()
		c.value = max(1, int(round(float(e.xp_value) / chips)))
		fx.add_child(c)
		c.global_position = e.global_position + Vector3(randf_range(-4, 4), randf_range(-2, 4), randf_range(-4, 4))
	if e.advanced > 0 or e.is_boss:
		var crate := Crate.new()
		crate.kind = "ufo" if e.is_boss else ("purple" if e.advanced == 2 else "advanced")
		fx.add_child(crate)
		crate.global_position = e.global_position
		flash = 0.5
		if e.is_boss:
			show_message("UFO DESTROYED  +%d" % e.points, 3.0)

func player_hit(dmg: float, at: Vector3) -> void:
	if state != State.PLAYING or invuln > 0.0:
		Explosion.spawn(fx, at, 1.0)
		return
	Game.hp -= dmg
	damage_flash = 1.0
	Sfx.play("damage")
	Input.vibrate_handheld(90)
	Explosion.spawn(fx, at, 1.4, [Palette.RED, Palette.ORANGE, Palette.WHITE], 10)
	Game.multiplier = 1

func collect_xp(v: int) -> void:
	Sfx.play("xp", -10.0, randf_range(0.95, 1.2))
	if Game.add_xp(v):
		pending_levelups += 1
		if state == State.PLAYING:
			_enter(State.LEVELUP)

func open_crate(kind: String) -> void:
	if state != State.PLAYING:
		return
	_start_slot(kind)

# --- level up --------------------------------------------------------------
func _card_at(window_pos: Vector2) -> int:
	var hp := window_to_hud(window_pos)
	if hp.x < 0:
		return -1
	for i in levelup_choices.size():
		if Rect2(8 + i * 82, 42, 76, 112).has_point(hp):
			return i
	return -1

func _update_levelup() -> void:
	if touch_tap:
		# tap a card to select it; tap the selected card (or OK) to take it
		var idx := _card_at(touch_tap_pos)
		if idx >= 0 and idx != levelup_cursor:
			levelup_cursor = idx
			Sfx.play("select")
			touch_tap = false
		elif idx < 0 and game_rect.has_point(touch_tap_pos):
			touch_tap = false
	if nav_left():
		levelup_cursor = (levelup_cursor - 1 + levelup_choices.size()) % levelup_choices.size()
		Sfx.play("select")
	if nav_right():
		levelup_cursor = (levelup_cursor + 1) % levelup_choices.size()
		Sfx.play("select")
	if btn1():
		var id: String = levelup_choices[levelup_cursor]
		Game.grant(id)
		_refresh_mounts()
		Sfx.play("confirm")
		Sfx.play("jackpot", -8.0, 1.6)
		hud.take_burst(levelup_cursor)
		flash = 0.35
		pending_levelups = max(0, pending_levelups - 1)
		if pending_levelups > 0:
			_enter(State.LEVELUP)
		else:
			_enter(State.PLAYING)

# --- loot slot machine -----------------------------------------------------
func _start_slot(kind: String) -> void:
	var r := randf()
	var p5 := 0.08 + 0.03 * Game.luck
	var p3 := 0.25 + 0.04 * Game.luck
	var count := 1
	match kind:
		"ufo": count = 5
		"purple": count = 5 if r < p5 * 2.0 else 3
		_: count = 5 if r < p5 else (3 if r < p5 + p3 else 1)
	var rewards: Array = []
	var ev := Game.evolution_available()
	if ev != "":
		Game.evolve(ev)
		rewards.append({"id": ev, "evolve": true})
	while rewards.size() < count:
		var ups := Game.upgradable_owned()
		if ups.is_empty():
			Game.hp = Game.max_hp
			Game.add_score(1000)
			rewards.append({"id": "repair"})
		else:
			var id: String = ups[randi() % ups.size()]
			Game.grant(id)
			rewards.append({"id": id, "level": Game.item_level(id)})
	_refresh_mounts()
	var ids := Items.all_ids()
	var symbols: Array = []
	var first: String = rewards[0]["id"] if rewards[0]["id"] != "repair" else "armor"
	if count >= 3:
		symbols = [first, first, first]
	else:
		var others := ids.filter(func(i): return i != first)
		others.shuffle()
		symbols = [first, others[0], others[1]]
	slot = {"kind": kind, "count": count, "rewards": rewards, "t": 0.0, "stops": [1.1, 1.9, 2.7], "symbols": symbols, "done": false, "tick": 0.0, "stopped": 0}
	Sfx.play("crate")
	_enter(State.SLOT)

func _update_slot(delta: float) -> void:
	slot["t"] += delta
	var t: float = slot["t"]
	if not slot["done"]:
		slot["tick"] -= delta
		if slot["tick"] <= 0.0 and t < slot["stops"][2]:
			slot["tick"] = 0.08
			Sfx.play("tick", -6.0)
		var stopped := 0
		for s in slot["stops"]:
			if t >= s:
				stopped += 1
		if stopped > slot["stopped"]:
			slot["stopped"] = stopped
			Sfx.play("reel_stop")
		if t > slot["stops"][2] + 0.3:
			slot["done"] = true
			var count: int = slot["count"]
			if count >= 5:
				Sfx.play("jackpot")
				flash = 1.0
				Game.add_score(5000)
			elif count >= 3:
				Sfx.play("levelup")
				Game.add_score(1500)
			else:
				Sfx.play("confirm")
	elif t > slot["stops"][2] + 0.8 and btn1():
		if pending_levelups > 0:
			_enter(State.LEVELUP)
		else:
			_enter(State.PLAYING)

# --- initials --------------------------------------------------------------
func _update_name_entry() -> void:
	var n := ALPHABET.length()
	if nav_up():
		name_letters[name_cursor] = (name_letters[name_cursor] + 1) % n
		Sfx.play("select")
	if nav_down():
		name_letters[name_cursor] = (name_letters[name_cursor] - 1 + n) % n
		Sfx.play("select")
	if nav_left():
		name_cursor = max(0, name_cursor - 1)
	if btn1():
		Sfx.play("confirm")
		name_cursor += 1
		if name_cursor >= 3:
			var initials := ""
			for i in 3:
				initials += ALPHABET[name_letters[i]]
			rank = Game.submit_score(initials)
			_enter(State.SCORES)
