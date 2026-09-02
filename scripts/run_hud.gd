extends CanvasLayer
## Player-facing run HUD — a live run timer up top and a minimal results
## panel after hitting the finish beacon. The debug readout (DebugHUD) stays
## untouched; this layer only ADDS the timer + results.
##
## Timer starts the moment the player leaves Room 1's spawn (either by
## changing room or moving > 4 m from the spawn point) and freezes on finish.
## Restart reuses the exact same Room-1 reset teleport the finish beacon
## itself uses — no second reset path.

const SPAWN := Vector3(0, 0, 6)

var player: CharacterBody3D

var _elapsed := 0.0
var _running := false
var _finished := false

## Screenshot-only seed so a verification capture can show a realistic total.
var initial_elapsed := 0.0

var _timer_label: Label
var _panel: PanelContainer
var _result_time: Label


func _ready() -> void:
	layer = 20
	player = get_node_or_null("/root/Main/Player")
	add_to_group("finish_listeners")
	_build()
	if initial_elapsed > 0.0:
		_elapsed = initial_elapsed


func _build() -> void:
	_timer_label = Label.new()
	_timer_label.name = "RunTimer"
	_timer_label.text = "00:00.00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 32)
	_timer_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_timer_label.add_theme_constant_override("outline_size", 8)
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_top = 14.0
	_timer_label.offset_bottom = 62.0
	_timer_label.offset_left = -200.0
	_timer_label.offset_right = 200.0
	add_child(_timer_label)

	_panel = PanelContainer.new()
	_panel.name = "ResultsPanel"
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "RUN COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(title)

	_result_time = Label.new()
	_result_time.text = "Total time: 00:00.00"
	_result_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_time.add_theme_font_size_override("font_size", 34)
	vb.add_child(_result_time)

	var prompt := Label.new()
	prompt.text = "Press R to restart"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.95))
	vb.add_child(prompt)


func _process(delta: float) -> void:
	if not player:
		return
	if _finished:
		return
	if _running:
		_elapsed += delta
		_timer_label.text = fmt(_elapsed)
	elif player.current_room != 1 or player.global_position.distance_to(SPAWN) > 4.0:
		_running = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
		and event.keycode == KEY_R and _finished:
		_restart()


func _restart() -> void:
	if player:
		player.call("teleport_to", Vector3(0, 1.2, 6), 1)
	_finished = false
	_running = false
	_elapsed = 0.0
	_panel.visible = false
	_timer_label.visible = true
	_timer_label.text = fmt(0.0)


func on_finish() -> void:
	_finished = true
	_running = false
	_result_time.text = "Total time: %s" % fmt(_elapsed)
	_panel.visible = true


func get_timer_text() -> String:
	return _timer_label.text if _timer_label else ""


func get_elapsed() -> float:
	return _elapsed


func fmt(t: float) -> String:
	var m := int(t) / 60
	var s := t - float(m) * 60.0
	return "%02d:%05.2f" % [m, s]