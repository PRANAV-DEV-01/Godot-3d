extends SceneTree
## Minimal screenshot capture — loads main.tscn, waits for Vulkan, captures 3 views.

var screenshot_dir := "user://verification_screenshots/"
var phase := 0
var wait_frames := 0
var wait_target := 0
var main_scene: Node


func _init() -> void:
	print("[Capture] Starting...")
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("[Capture] Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	print("[Capture] Scene loaded, waiting for render init...")
	phase = 1
	wait_frames = 0
	wait_target = 300


func _idle(_delta: float) -> bool:
	match phase:
		1:  # Wait for Vulkan to fully initialize
			wait_frames += 1
			if wait_frames >= wait_target:
				print("[Capture] Init done, capturing views...")
				phase = 10

		10:  # View 1: spawn facing room
			_move_player(Vector3(0, 1.2, 6), 0.0)
			wait_frames = 0
			wait_target = 90
			phase = 11

		11:
			wait_frames += 1
			if wait_frames >= wait_target:
				_capture("01_spawn_facing_room")
				phase = 20

		20:  # View 2: platform looking back
			_move_player(Vector3(-6, 3.2, -6), atan2(1.0, 1.0))
			wait_frames = 0
			wait_target = 90
			phase = 21

		21:
			wait_frames += 1
			if wait_frames >= wait_target:
				_capture("02_platform_looking_back")
				phase = 30

		30:  # View 3: wall-run approach
			_move_player(Vector3(-1.5, 2.0, -2), 0.0)
			wait_frames = 0
			wait_target = 90
			phase = 31

		31:
			wait_frames += 1
			if wait_frames >= wait_target:
				_capture("03_wallrun_approach")
				print("[Capture] All captures done.")
				quit()
				return true

	return false


func _move_player(pos: Vector3, rot_y: float) -> void:
	if not main_scene:
		return
	var player: Node = main_scene.get_node_or_null("Player")
	if player:
		player.global_position = pos
		player.rotation.y = rot_y


func _capture(label: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path: String = screenshot_dir + label + ".png"
	var err := img.save_png(path)
	if err == OK:
		var full_path: String = ProjectSettings.globalize_path(path)
		print("[Capture] Saved: %s" % full_path)
	else:
		push_error("[Capture] Failed: %s" % error_string(err))
