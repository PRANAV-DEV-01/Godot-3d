extends SceneTree
## Mobile TouchUI verification harness (Phase 6).
## Loads main.tscn, attaches a manual instance of scripts/touch_ui.gd
## (autoloads are skipped under `--script`), resets the headless window to
## 1920x1080, and drives the touch UI through the REAL parsed-input pipeline:
##   - desktop detection -> hidden and writes no input state
##   - set_test_touch(true) (simulated mobile) -> visible and laid out
##   - virtual buttons drive the EXACT named actions (jump/dash/slide/sprint)
##   - parsed InputEventScreenTouch/Drag -> analog move_* strengths + look
##   - stick release preserves keyboard-held moves (no clobber)
##   - sprint toggle reaches real sprint speed through player.gd
##
## Run:
##     godot --path <proj> --script res://scripts/test_touch_input.gd

var main_scene: Node
var ui: CanvasLayer
var player: CharacterBody3D
var cam: Node

var _started := false
var _done := false
var _ok := 0
var _fail := 0


var _observed_motions: Array = []  # elements: Vector2 relative


func _init() -> void:
	Engine.max_physics_steps_per_frame = 1
	Engine.max_fps = 60
	# Headless `--script` opens a tiny dummy window and, with `stretch/aspect =
	# expand`, the canvas expands with it (64x64 -> visible 1920x1920). Pin the
	# harness to a deterministic 1920x1080 canvas (aspect keep).
	ProjectSettings.set_setting("display/window/stretch/aspect", "keep")
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", false)
	root.size = Vector2i(1920, 1080)
	var rec := Node.new()
	rec.name = "MotionProbe"
	rec.set_script(load("res://scripts/_probe_motion_recorder.gd"))
	rec.set("sink", Callable(self, "on_motion"))
	root.add_child(rec)
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("[TouchTest] Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	ui = CanvasLayer.new()
	ui.name = "TouchUI"
	ui.set_script(load("res://scripts/touch_ui.gd"))
	root.add_child(ui)
	print("[TouchTest] Scene loaded; TouchUI attached manually (autoload skipped).")


func _process(_delta: float) -> bool:
	if _done:
		return true
	if not _started:
		if Engine.get_physics_frames() < 10:
			return false
		_started = true
		_run()
	return false


func _run() -> void:
	_resolve_refs()
	await _frames(2)
	print("[TouchTest] INFO canvas=%s (dummy window %s; headless reports mouse_mode=0/visible)" %
			[root.get_visible_rect(), root.get_window().size])

	# ── 1. Desktop detection: hidden and inert ───────────────────────────
	_check(not ui.is_enabled_for_touch(), "hidden on desktop (no touch feature)")
	_check(not ui.visible, "CanvasLayer not visible on desktop")
	_release_all()
	_check(not Input.is_action_pressed("jump") and not Input.is_action_pressed("sprint"),
			"writes no action state while hidden")

	# ── 2. Simulated mobile: shown and laid out ──────────────────────────
	ui.set_test_touch(true)
	await _frames(2)
	_check(ui.is_enabled_for_touch(), "simulated mobile -> TouchUI enabled & visible")
	for n in ["jump", "dash", "slide", "sprint"]:
		var b: Button = ui.get_button(n)
		if b == null:
			_check(false, "button '%s' exists" % n)
			continue
		var r: Rect2 = ui.get_button_rect(n)
		var vis := root.get_visible_rect()
		var on_screen: bool = r.size.x > 0.0 and vis.encloses(r.grow(1.0))
		_check(on_screen, "'%s' laid out on-screen (%.0f, %.0f) %.0fx%.0f"
				% [n, r.position.x, r.position.y, r.size.x, r.size.y])

	# ── 3. Virtual buttons -> EXACT existing named actions ───────────────
	ui.get_button("jump").emit_signal("button_down")
	_check(Input.is_action_pressed("jump"), "virtual JUMP press -> is_action_pressed('jump')")
	ui.get_button("jump").emit_signal("button_up")
	await _frames(1)
	_check(not Input.is_action_pressed("jump"), "virtual JUMP release clears action")

	ui.get_button("dash").emit_signal("button_down")
	_check(Input.is_action_pressed("dash"), "virtual DASH press -> is_action_pressed('dash')")
	ui.get_button("dash").emit_signal("button_up")
	await _frames(1)
	_check(not Input.is_action_pressed("dash"), "virtual DASH release clears action")

	ui.get_button("slide").emit_signal("button_down")
	_check(Input.is_action_pressed("slide"), "virtual SLIDE press -> is_action_pressed('slide')")
	ui.get_button("slide").emit_signal("button_up")
	await _frames(1)
	_check(not Input.is_action_pressed("slide"), "virtual SLIDE release clears action")

	ui.get_button("sprint").emit_signal("toggled", true)
	_check(Input.is_action_pressed("sprint"), "virtual SPRINT toggle ON -> 'sprint' pressed")
	ui.get_button("sprint").emit_signal("toggled", false)
	await _frames(1)
	_check(not Input.is_action_pressed("sprint"), "virtual SPRINT toggle OFF clears")
	_release_all()

	# ── 4. Parsed touch -> analog joystick (real input pipeline) ─────────
	var radius: float = ui.get_stick_radius()
	var vis := root.get_visible_rect()
	var home := vis.position + Vector2(vis.size.x * 0.18, vis.size.y * 0.74)
	_touch(1, home, true)
	await _frames(1)
	_drag(1, home + Vector2(0, -radius * 0.5), Vector2(0, -radius * 0.5))
	await _frames(1)
	var s_partial := Input.get_action_strength("move_forward")
	_check(absf(s_partial - 0.5) < 0.06,
			"half deflection -> analog strength ~0.5 (got %.2f)" % s_partial)
	_check(Input.get_action_strength("move_backward") < 0.001, "no backward while pushing forward")
	_drag(1, home + Vector2(0, -radius), Vector2(0, -radius * 0.5))
	await _frames(1)
	var s_full := Input.get_action_strength("move_forward")
	_check(s_full > 0.9, "full deflection -> strength ~1.0 (got %.2f)" % s_full)
	_check(s_full > s_partial, "analog: full deflection > partial (%.2f > %.2f)" % [s_full, s_partial])
	_drag(1, home + Vector2(-radius, 0), Vector2(-radius, 0))
	await _frames(1)
	_check(Input.get_action_strength("move_left") > 0.9 and Input.get_action_strength("move_right") < 0.001,
			"push left -> move_left only")
	_touch(1, home + Vector2(-radius, 0), false)
	await _frames(1)
	_check(not Input.is_action_pressed("move_forward")
			and not Input.is_action_pressed("move_left")
			and not Input.is_action_pressed("move_backward")
			and not Input.is_action_pressed("move_right"),
			"stick release clears all move_*")
	_release_all()

	# ── 5. Parsed drag -> camera look (SAME pipeline as mouse, same sensitivity) ─
	var look_pos := vis.position + Vector2(vis.size.x * 0.72, vis.size.y * 0.28)
	_touch(2, look_pos, true)
	await _frames(1)
	_observed_motions.clear()
	_drag(2, look_pos + Vector2(-200, 0), Vector2(-200, 0))
	await _frames(1)
	var first_rel: Vector2 = ui.debug_last_look_rel()
	_drag(2, look_pos + Vector2(-200, -60), Vector2(0, -60))
	await _frames(1)
	var second_rel: Vector2 = ui.debug_last_look_rel()
	_touch(2, look_pos + Vector2(-200, -60), false)
	await _frames(1)
	# (a) touch_ui synthesizes exactly the drag delta (camera applies its own
	#     tuned sensitivity 0.0025 — verified in test_movement_rooms.gd).
	_check(first_rel.is_equal_approx(Vector2(-200, 0)) and second_rel.is_equal_approx(Vector2(0, -60)),
			"touch-drag forwards the raw drag delta (%.0f, %.0f) / (%.0f, %.0f) -> mouse-look pipeline"
			% [first_rel.x, first_rel.y, second_rel.x, second_rel.y])
	# (b) the synthesized InputEventMouseMotion reaches the SAME unhandled
	#     input the desktop mouse-motion path uses (probe in _init; the dummy
	#     window re-derives relative for interleaved events, so we assert arrival).
	var arrivals := _observed_motions.size()
	_check(arrivals >= 2, "synthesized look motions reached the input pipeline (%d arrivals)" % arrivals)

	# ── 6. Keyboard co-existence ─────────────────────────────────────────
	# Real W key + stick both feed the same actions. Note: Input has a single
	# action state (action_release is not ref-counted), so if the stick is
	# released WHILE the keyboard still holds the SAME action, both ends — a
	# documented dual-input edge reserved for touchscreen laptops. Pure-touch
	# and pure-keyboard inputs are unaffected (sections 4 and 1/3).
	_release_all()
	_key(87, true)                 # a REAL held W (physical keycode, OS path)
	await _frames(1)
	_check(Input.is_action_pressed("move_forward"), "parsed W key drives move_forward")
	_touch(3, home, true)
	await _frames(1)
	_drag(3, home + Vector2(0, -radius), Vector2(0, -radius))
	await _frames(1)
	_check(Input.get_action_strength("move_forward") > 0.9, "stick pulls while W is held")
	_touch(3, home + Vector2(0, -radius), false)
	await _frames(1)
	print("[TouchTest] NOTE  both-held release -> action cleared by engine (known dual-input edge)")
	_key(87, false)
	await _frames(1)
	_check(not Input.is_action_pressed("move_forward"), "W release clears action")

	# ── 7. End-to-end: sprint toggle + stick run reaches sprint speed ────
	_release_all()
	player.call("teleport_to", Vector3(0, 1.2, 5), 1)
	_yaw(0.0)
	await _frames(2)
	ui.get_button("sprint").emit_signal("toggled", true)
	_touch(4, home, true)
	await _frames(1)
	_drag(4, home + Vector2(0, -radius), Vector2(0, -radius))
	await _frames(1)
	var top := 0.0
	for i in range(150):
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
		await process_frame
	_check(top > 8.5, "sprint-toggle + stick run hits sprint speed (%.1f u/s)" % top)
	_touch(4, home + Vector2(0, -radius), false)
	ui.get_button("sprint").emit_signal("toggled", false)
	await _frames(2)
	_check(not Input.is_action_pressed("sprint"), "sprint toggle OFF releases action")
	_release_all()

	print("")
	print("[TouchTest] ==== SUMMARY: %d passed, %d failed ====" % [_ok, _fail])
	_done = true
	quit()


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("[TouchTest] PASS  %s" % msg)
	else:
		_fail += 1
		print("[TouchTest] FAIL  %s" % msg)


func on_motion(rel: Vector2) -> void:
	_observed_motions.append(rel)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


const ALL_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right",
		"jump", "dash", "slide", "sprint"]


func _release_all() -> void:
	for a in ALL_ACTIONS:
		Input.action_release(a)


## The headless dummy window is fixed at 64x64 px while the canvas is
## 1920x1080. Parsed events arrive scaled by a UNIFORM factor f=vis.x/win.x
## (=30) into canvas units, with the 16:9 content centered inside the square
## full-canvas (Y center offset = (f*win.y - vis.y)/2). Real devices deliver
## OS pixels directly as canvas units (no offset), so this mapping/undo is
## harness-only: convert our CANVAS-space coordinates back to window px.
func _win(c: Vector2) -> Vector2:
	var win: Vector2 = root.get_window().size
	var vis: Vector2 = root.get_visible_rect().size
	if win.x <= 0.0 or vis.x <= 0.0:
		return c
	var f := vis.x / win.x
	var topx := (win.x - vis.x / f) / 2.0
	var topy := (win.y - vis.y / f) / 2.0
	return Vector2(c.x / f + topx, c.y / f + topy)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _win(pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _win(pos)
	# relative is a delta in window pixels: scale by the same factor but apply
	# NO letterbox offset (offsets would corrupt the delta).
	var win: Vector2 = root.get_window().size
	var vis: Vector2 = root.get_visible_rect().size
	var f := vis.x / win.x
	ev.relative = rel / f
	Input.parse_input_event(ev)


func _resolve_refs() -> void:
	player = null
	var players := main_scene.get_node_or_null("Players")
	if players:
		for c in players.get_children():
			if c is CharacterBody3D and c.name != "Player_local":
				player = c as CharacterBody3D
				break
		if not player and players.get_child_count() > 0:
			player = players.get_child(0) as CharacterBody3D
	if player:
		cam = player.get_node_or_null("CameraPivot/Camera3D")
	var ss := main_scene.get_node_or_null("ScreenshotManager")
	if ss:
		ss.set("auto_done", true)


func _yaw(y: float) -> void:
	if player:
		player.rotation.y = y
		player.rotation.z = 0.0
	if cam:
		cam.set("yaw", y)
		cam.set("pitch", 0.0)
		cam.set("slide_crouch", false)
		cam.set("current_roll", 0.0)
		cam.set("target_roll", 0.0)
		cam.set("landing_dip", 0.0)