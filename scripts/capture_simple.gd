extends SceneTree
var main_scene: Node
var phase := 0
var frames := 0
var wait_until := 0
var screenshot_dir := "/root/verification_screenshots/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	print("[Capture] Scene loaded, waiting 200 frames...")
	phase = 1

func _idle(_delta: float) -> bool:
	frames += 1
	match phase:
		1:
			if frames >= 200:
				_move(Vector3(0, 1.2, 6), 0.0)
				wait_until = frames + 60
				phase = 11
		11:
			if frames >= wait_until:
				_save("01_spawn_facing_room")
				_move(Vector3(-6, 3.2, -6), atan2(1.0, 1.0))
				wait_until = frames + 60
				phase = 12
		12:
			if frames >= wait_until:
				_save("02_platform_looking_back")
				_move(Vector3(-1.5, 2.0, -2), 0.0)
				wait_until = frames + 60
				phase = 13
		13:
			if frames >= wait_until:
				_save("03_wallrun_approach")
				print("[Capture] Done!")
				quit()
				return true
	return false

func _move(pos: Vector3, rot_y: float) -> void:
	var p = main_scene.get_node_or_null("Player")
	if p:
		p.global_position = pos
		p.rotation.y = rot_y

func _save(label: String) -> void:
	RenderingServer.force_draw()
	var img := root.get_viewport().get_texture().get_image()
	var path := screenshot_dir + label + ".png"
	var err := img.save_png(path)
	print("[Capture] %s -> %s (err=%d)" % [label, path, err])
