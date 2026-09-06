extends CanvasLayer
## ── Mobile touch controls (additive, Phase 6) ───────────────────────
## Autoloaded as `TouchUI`. Hidden and fully inert on platforms without touch
## input; while hidden it never writes a single input bit, so desktop
## keyboard/mouse behaviour is untouched.
##
## When active it drives the EXACT same named input actions the keyboard uses
## (jump / dash / slide / sprint / move_*) via Input.action_press() /
## action_release(), and feeds camera look through the SAME pipeline as the
## mouse by synthesizing InputEventMouseMotion — player_camera.gd applies its
## own tuned `sensitivity` and pitch clamp, so no separate sensitivity value
## exists here. player.gd's movement state machine is never modified.
##
## Layout is derived from the visible viewport as fractions of screen size
## (never fixed pixels), so it adapts to any phone aspect ratio / resolution.

const STICK_ZONE_FRAC_W := 0.45  ## joystick thumb zone: left 45% x bottom 40%
const STICK_ZONE_FRAC_H := 0.40
const LOOK_ZONE_FRAC_X  := 0.50  ## camera look: right half of the screen
const STICK_DEADZONE    := 0.15  ## fraction of stick radius before input starts

const ACTION_JUMP   := "jump"
const ACTION_DASH   := "dash"
const ACTION_SLIDE  := "slide"
const ACTION_SPRINT := "sprint"

var _enabled := false
var _test_forced := false

var _overlay: Control
var _stick_visual: JoystickVisual
var _buttons: Dictionary = {}
var _stick_radius := 110.0

var _stick_index := -1
var _stick_center := Vector2.ZERO
var _stick_offset := Vector2.ZERO
var _stick_owns := {}   ## move actions this stick currently holds (not the keyboard)

var _look_index := -1
var _debug_last_look_rel := Vector2.ZERO


## ── Platform detection ──────────────────────────────────────────────
## True when the OS/export reports a touch-capable platform. Never consulted
## for the desktop branch decision alone; a first real touch event also
## enables the UI, so touchscreen laptops / emulators work with both input
## types active simultaneously.
static func _detect_touch() -> bool:
	if OS.has_feature("mobile"):
		return true
	if DisplayServer.has_method("is_touchscreen_available") \
			and DisplayServer.is_touchscreen_available():
		return true
	return false


func _ready() -> void:
	layer = 100
	visible = false
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_stick_visual = JoystickVisual.new()
	_stick_visual.name = "Joystick"
	_stick_visual.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_stick_visual)

	_build_buttons()
	_refresh()
	get_viewport().size_changed.connect(_layout)


func _refresh() -> void:
	if _detect_touch() or _test_forced:
		_enable()
	else:
		_disable()


func _enable() -> void:
	if _enabled:
		return
	_enabled = true
	visible = true
	# Touch devices show no OS cursor. Keep the engine in CAPTURED mode so the
	# synthesized mouse-motion drives player_camera exactly like desktop mouse
	# look (player_camera._unhandled_input gates on MOUSE_MODE_CAPTURED).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_layout()


func _disable() -> void:
	_enabled = false
	_clear_stick()
	visible = false


## TEST/Debug hook — force touch mode so headless checks can exercise the
## mobile UI without a touchscreen. Never called by gameplay code.
func set_test_touch(on: bool) -> void:
	_test_forced = on
	if on:
		_enable()
	else:
		_disable()


func is_enabled_for_touch() -> bool:
	return _enabled and visible


func get_button(name: String) -> Button:
	return _buttons.get(name) as Button


func get_button_rect(name: String) -> Rect2:
	var b: Button = _buttons.get(name)
	return b.get_global_rect() if b else Rect2()


func get_stick_offset() -> Vector2:
	return _stick_offset


func get_stick_radius() -> float:
	return _stick_radius


## Testability helper: returns the most recent look-drag delta that was
## turned into an InputEventMouseMotion (Vector2.ZERO until a drag occurs).
func debug_last_look_rel() -> Vector2:
	return _debug_last_look_rel


func is_visible_to_user() -> bool:
	return _enabled and visible


## ── UI construction ─────────────────────────────────────────────────

func _build_buttons() -> void:
	var defs := {
		"sprint": {"label": "SPRINT", "toggle": true},
		"dash":   {"label": "DASH",   "toggle": false},
		"jump":   {"label": "JUMP",   "toggle": false},
		"slide":  {"label": "SLIDE",  "toggle": false},
	}
	for key: String in defs:
		var d: Dictionary = defs[key]
		var b := Button.new()
		b.name = "Btn%s" % key.capitalize()
		b.text = d.label
		b.toggle_mode = d.toggle
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		b.add_theme_stylebox_override("normal", _btn_style(Color(1, 1, 1, 0.14)))
		b.add_theme_stylebox_override("hover", _btn_style(Color(1, 1, 1, 0.22)))
		b.add_theme_stylebox_override("pressed", _btn_style(Color(1.0, 0.75, 0.25, 0.6)))
		b.add_theme_stylebox_override("focus", _btn_style(Color(1, 1, 1, 0.0)))
		match key:
			"jump":
				b.button_down.connect(func() -> void: Input.action_press(_action_from_name("jump")))
				b.button_up.connect(func() -> void: Input.action_release(_action_from_name("jump")))
			"dash":
				b.button_down.connect(func() -> void: Input.action_press(_action_from_name("dash")))
				b.button_up.connect(func() -> void: Input.action_release(_action_from_name("dash")))
			"slide":
				b.button_down.connect(func() -> void: Input.action_press(_action_from_name("slide")))
				b.button_up.connect(func() -> void: Input.action_release(_action_from_name("slide")))
			"sprint":
				b.toggled.connect(_on_sprint_toggled)
		_overlay.add_child(b)
		_buttons[key] = b


func _action_from_name(n: String) -> String:
	match n:
		"jump": return ACTION_JUMP
		"dash": return ACTION_DASH
		"slide": return ACTION_SLIDE
		"sprint": return ACTION_SPRINT
	return ""


func _on_sprint_toggled(on: bool) -> void:
	if on:
		Input.action_press(ACTION_SPRINT)
	else:
		Input.action_release(ACTION_SPRINT)


func _btn_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.5)
	return sb


## ── Percent-based layout ────────────────────────────────────────────
func _layout() -> void:
	if _overlay == null:
		return
	var vs := get_viewport().get_visible_rect()
	var w := vs.size.x
	var h := vs.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var short_side := minf(w, h)
	var margin := maxf(18.0, short_side * 0.045)
	var gap := maxf(10.0, short_side * 0.02)

	_stick_radius = maxf(92.0, short_side * 0.135)
	_stick_visual.radius = _stick_radius
	_stick_visual.home_center = Vector2(w * 0.18, h * 0.74)
	_stick_visual.center = _stick_visual.home_center
	_stick_visual.queue_redraw()

	# Thumb-cluster (bottom-right): Jump is the big corner button; Dash sits
	# above it, Slide to its left, and Sprint (toggle) above Slide.
	var jump_d := maxf(120.0, short_side * 0.155)
	var d := maxf(92.0, short_side * 0.115)
	var jx := w - margin - jump_d
	var jy := h - margin - jump_d
	_set_btn_rect("jump", jx, jy, jump_d)
	_set_btn_rect("slide", jx - d - gap, jy, d)
	_set_btn_rect("dash", jx, jy - d - gap, d)
	_set_btn_rect("sprint", jx - d - gap, jy - d - gap, d)


func _set_btn_rect(key: String, x: float, y: float, d: float) -> void:
	var b: Button = _buttons[key]
	b.position = Vector2(x, y)
	b.size = Vector2(d, d)
	b.add_theme_font_size_override("font_size", maxi(20, int(d * 0.24)))


func _stick_zone() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	return Rect2(0, s.y * (1.0 - STICK_ZONE_FRAC_H), s.x * STICK_ZONE_FRAC_W, s.y * STICK_ZONE_FRAC_H)


func _look_zone() -> Rect2:
	var s := get_viewport().get_visible_rect().size
	return Rect2(s.x * LOOK_ZONE_FRAC_X, 0.0, s.x * (1.0 - LOOK_ZONE_FRAC_X), s.y)


## ── Touch routing ───────────────────────────────────────────────────
## Touch is handled in `_input()` (BEFORE the GUI pass), because the lobby/room
## Control stacks use mouse_filter STOP and would otherwise consume every touch
## before it can reach unhandled input on the real device. A press that lands on
## one of OUR buttons is left to the button's own GUI handling.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# A real touch arriving is the strongest enable signal (touchscreen
		# laptops, emulators, ...). While not enabled no input state changes.
		if not _enabled:
			_enable()
			if event is InputEventScreenTouch and not event.pressed:
				return  # stray release after a missed press
		if event is InputEventScreenTouch:
			if event.pressed and _is_over_button(event.position):
				return  # finger is for a button, not the stick/look zone
			_handle_touch(event)
		else:
			_handle_drag(event)


func _is_over_button(pos: Vector2) -> bool:
	var c := _canvas_pos(pos)
	for name in _buttons:
		var b: Button = _buttons[name]
		if b.visible and b.get_global_rect().has_point(c):
			return true
	return false


func _handle_touch(ev: InputEventScreenTouch) -> void:
	var pos := _canvas_pos(ev.position)
	if ev.pressed:
		if _stick_index == -1 and _stick_zone().has_point(pos):
			_stick_index = ev.index
			_stick_center = pos
			_stick_offset = Vector2.ZERO
			_stick_visual.center = pos
			_stick_visual.knob_offset = Vector2.ZERO
			_stick_visual.queue_redraw()
			return
		if _look_index == -1 and _look_zone().has_point(pos):
			_look_index = ev.index
			return
	else:
		if ev.index == _stick_index:
			_clear_stick()
		if ev.index == _look_index:
			_look_index = -1


func _handle_drag(ev: InputEventScreenDrag) -> void:
	var pos := _canvas_pos(ev.position)
	if ev.index == _stick_index:
		var off := pos - _stick_center
		if off.length() > _stick_radius:
			off = off.normalized() * _stick_radius
		_stick_offset = off
		_stick_visual.knob_offset = off
		_stick_visual.queue_redraw()
		_apply_stick()
		return
	if ev.index == _look_index:
		# Synthesize mouse motion so player_camera.gd applies the EXACT tuned
		# `sensitivity` (0.0025) and its own pitch clamp. No new constant here.
		# (Re-assert CAPTURED: player.gd's click handler toggles mouse mode,
		# and on touch devices the mode must stay captured for look to work.)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if ev.relative != Vector2.ZERO:
			_debug_last_look_rel = ev.relative
			var m := InputEventMouseMotion.new()
			m.position = ev.position
			m.global_position = ev.position
			m.relative = ev.relative
			Input.parse_input_event(m)


## Analog joystick → same move_* actions the keyboard uses. Strengths are
## proportional to stick deflection (magnitude x axis component); player.gd
## normalizes the direction exactly as it does for WASD, so nothing in the
## movement state machine changes.
func _apply_stick() -> void:
	var mag := clampf(_stick_offset.length() / _stick_radius, 0.0, 1.0)
	if mag < STICK_DEADZONE:
		_clear_stick_actions()
		return
	var dir := _stick_offset.normalized()
	var axes := {
		"move_forward": -dir.y,
		"move_backward": dir.y,
		"move_left": -dir.x,
		"move_right": dir.x,
	}
	for act: String in axes:
		var comp: float = axes[act]
		if comp > 0.0001:
			Input.action_press(act, clampf(comp * mag, 0.0, 1.0))
			_stick_owns[act] = true
		elif _stick_owns.has(act):
			Input.action_release(act)
			_stick_owns.erase(act)


func _clear_stick_actions() -> void:
	for act: String in _stick_owns.keys():
		Input.action_release(act)
	_stick_owns.clear()


func _clear_stick() -> void:
	_stick_index = -1
	_clear_stick_actions()
	_stick_offset = Vector2.ZERO
	_stick_visual.knob_offset = Vector2.ZERO
	_stick_visual.center = _stick_visual.home_center
	_stick_visual.queue_redraw()


## Map a window-space event position into canvas space under stretch.
func _canvas_pos(p: Vector2) -> Vector2:
	var ct := get_viewport().get_canvas_transform()
	if ct.is_equal_approx(Transform2D.IDENTITY):
		return p
	return ct.affine_inverse() * p


## ── Joystick visuals ────────────────────────────────────────────────
class JoystickVisual extends Control:
	var radius := 110.0
	var home_center := Vector2.ZERO
	var center := Vector2.ZERO
	var knob_offset := Vector2.ZERO

	func _draw() -> void:
		draw_circle(center, radius, Color(1, 1, 1, 0.10))
		draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(center + knob_offset, radius * 0.42, Color(1, 1, 1, 0.42))