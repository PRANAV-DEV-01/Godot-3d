extends Node
## Dev-only touch probe for real-window verification (xvfb / real device).
## No-op unless launched with `-- --touchprobe` (user args). Runs the GUI
## hit-test path on the real main loop, prints PASS/FAIL, then quits.

const MAIN_VERIFY := [
	["jump", "jump"],
	["dash", "dash"],
	["slide", "slide"],
]

var _ok := 0
var _fail := 0


func _ready() -> void:
	if not ("--touchprobe" in OS.get_cmdline_user_args()):
		queue_free()
		return
	set_process_mode(Node.PROCESS_MODE_DISABLED)  # driven manually below
	call_deferred("_start_all")


func _start_all() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_start()


func _start() -> void:
	var ui: CanvasLayer = get_node_or_null("/root/TouchUI")
	if ui == null:
		print("FAIL  TouchUI autoload missing")
		_quit()
		return
	if ui.is_enabled_for_touch():
		print("FAIL  TouchUI visible before touch enabled")
		_quit()
		return
	_check(true, "TouchUI hidden at start")
	ui.set_test_touch(true)
	for i in 3:
		await get_tree().process_frame
	_check(ui.is_enabled_for_touch(), "TouchUI visible after enable")
	for pair in MAIN_VERIFY:
		var name: String = pair[0]
		var action: String = pair[1]
		var c: Vector2 = ui.get_button_rect(name).get_center()
		var b: Button = ui.get_button(name)
		_tap(c)
		await _frames(2)
		_check(b.is_pressed(), "'%s' button pressed by real touch (GUI hit-test @%s)" % [name, str(collapse(c))])
		_check(Input.is_action_pressed(action), "touch '%s' -> action '%s' ON" % [name, action])
		_tap_up(c)
		await _frames(2)
		_check(not Input.is_action_pressed(action), "'%s' release clears action" % action)
		b.set_pressed_no_signal(false)
	var rel_before: Vector2 = ui.debug_last_look_rel()
	print("DBG  content_scale=", get_tree().get_root().get_content_scale_factor(),
			" win=", get_tree().get_root().get_window().size,
			" visible=", get_viewport().get_visible_rect().size)
	var right: Vector2 = get_viewport().get_visible_rect().size
	var look: Vector2 = Vector2(right.x * 0.72, right.y * 0.28)
	print("DBG  look press at ", collapse(look))
	Input.parse_input_event(_pressed(9, look))
	await _frames(1)
	print("DBG  after press: look_index=", ui.get("_look_index"),
			" stick_index=", ui.get("_stick_index"))
	var ev := InputEventScreenDrag.new()
	ev.index = 9
	ev.position = look + Vector2(-200, 0)
	ev.relative = Vector2(-200, 0)
	Input.parse_input_event(ev)
	await _frames(1)
	print("DBG  after drag: look_index=", ui.get("_look_index"),
			" last_look_rel=", ui.debug_last_look_rel())
	var rel_now: Vector2 = ui.debug_last_look_rel()
	_check(rel_now != rel_before and rel_now.y > -1.0,
			"real-window drag forwarded to look delta (%s)" % str(rel_now))
	Input.parse_input_event(_released(9, look + Vector2(-200, 0)))
	await _frames(1)
	# A press on the JUMP button must NOT engage stick/look tracking.
	Input.parse_input_event(_pressed(7, ui.get_button_rect("jump").get_center()))
	await _frames(1)
	_check(ui.get("_stick_index") == -1 and ui.get("_look_index") == -1,
			"button-zone press does not engage stick/look")
	Input.parse_input_event(_released(7, ui.get_button_rect("jump").get_center()))
	await _frames(1)
	await _stick_probe(ui, ui.get_stick_radius(), ui.get_viewport().get_visible_rect().size)
	print("==== SUMMARY: %d passed, %d failed ====" % [_ok, _fail])
	_quit()


func _stick_probe(ui: CanvasLayer, radius: float, vis: Vector2) -> void:
	var home := Vector2(vis.x * 0.18, vis.y * 0.74)
	print("DBG  stick probe radius=", radius, " home=", collapse(home), " vis=", collapse(vis))
	Input.parse_input_event(_pressed(5, home))
	await _frames(1)
	var ev := InputEventScreenDrag.new()
	ev.index = 5
	ev.position = home + Vector2(0, -radius * 0.5)
	ev.relative = Vector2(0, -radius * 0.5)
	Input.parse_input_event(ev)
	await _frames(1)
	var s: float = Input.get_action_strength("move_forward")
	_check(absf(s - 0.5) < 0.08, "real-window stick half-deflection -> ~0.5 (%.2f)" % s)
	Input.parse_input_event(_released(5, home + Vector2(0, -radius * 0.5)))
	await _frames(1)
	_check(Input.get_action_strength("move_forward") < 0.01, "real-window stick release clears")


func collapse(v: Vector2) -> Vector2:
	return Vector2(round(v.x), round(v.y))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _tap(p: Vector2) -> void:
	Input.parse_input_event(_pressed(1, p))


func _tap_up(p: Vector2) -> void:
	Input.parse_input_event(_released(1, p))


func _pressed(idx: int, p: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = p
	ev.pressed = true
	return ev


func _released(idx: int, p: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = p
	ev.pressed = false
	return ev


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("PASS  %s" % msg)
	else:
		_fail += 1
		print("FAIL  %s" % msg)


func _quit() -> void:
	get_tree().quit(1 if _fail > 0 else 0)