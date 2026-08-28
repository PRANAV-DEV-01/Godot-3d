extends Node
## Screenshot tool — press F9 to capture current viewport to PNG.
## Also auto-captures 3 verification views 3 seconds after load.

var player: CharacterBody3D
var cam: Camera3D
var screenshot_dir := "user://verification_screenshots/"
var auto_timer := 3.0
var auto_done := false
var view_index := 0


func _ready() -> void:
	player = get_node_or_null("/root/Main/Player")
	cam = get_node_or_null("/root/Main/Player/CameraPivot/Camera3D")
	DirAccess.make_dir_recursive_absolute(screenshot_dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_capture("manual_%s" % Time.get_datetime_string_from_system().replace(":", "-"))


func _process(delta: float) -> void:
	if auto_done or not player or not cam:
		return
	auto_timer -= delta
	if auto_timer <= 0.0:
		auto_timer = 2.0
		view_index += 1
		match view_index:
			1:
				# Spawn point facing into room
				_snap_and_capture(Vector3(0, 1.2, 6), Vector3(0, 0, 0), "01_spawn_facing_room")
			2:
				# On platform looking back into the room (clear of geometry)
				_snap_and_capture(Vector3(-6, 2.8, -6), Vector3(0, 1.2, 4), "02_platform_looking_back")
			3:
				# Wall-run approach — mid-corridor, clear of both walls
				_snap_and_capture(Vector3(0, 2.0, 4), Vector3(0, 2.0, -6), "03_wallrun_approach")
				auto_done = true


func _snap_and_capture(pos: Vector3, look_target: Vector3, filename: String) -> void:
	player.global_position = pos
	var dir := look_target - pos
	var hor := Vector2(dir.x, dir.z).length()
	if hor > 0.01:
		cam.set("yaw", atan2(-dir.x, -dir.z))
		cam.set("pitch", atan2(dir.y, hor))
	# wait 2 frames for physics/camera to settle
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(filename)


func _capture(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[Screenshot] Skipping (no viewport image available)", label)
		return
	var path := screenshot_dir + label + ".png"
	img.save_png(path)
	print("[Screenshot] Saved: ", path)
