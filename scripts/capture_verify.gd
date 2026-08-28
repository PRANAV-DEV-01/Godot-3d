extends SceneTree
var main_scene: Node
var phase := 0
var frames := 0
var wait_until := 0

func _init() -> void:
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	print("[Capture] Scene loaded")

func _idle(_delta: float) -> bool:
	frames += 1
	match phase:
		0:
			if frames >= 150:
				_move(Vector3(0, 1.2, 6), 0.0)
				_set_cam(Vector3(0, 1.2, 6), Vector3(0, 1.2, 0))
				wait_until = frames + 120
				phase = 1
		1:
			if frames >= wait_until:
				_take("01_spawn_facing_room")
				_move(Vector3(-6, 2.8, -6), atan2(1.0, 1.0))
				_set_cam(Vector3(-6, 2.8, -6), Vector3(0, 1.2, 4))
				wait_until = frames + 120
				phase = 2
		2:
			if frames >= wait_until:
				_take("02_platform_looking_back")
				_move(Vector3(0, 2.0, 4), 0.0)
				_set_cam(Vector3(0, 2.0, 4), Vector3(0, 2.0, -6))
				wait_until = frames + 120
				phase = 3
		3:
			if frames >= wait_until:
				_take("03_wallrun_approach")
				print("[Capture] ALL DONE")
				quit()
				return true
	return false

func _move(pos: Vector3, rot_y: float) -> void:
	var p = main_scene.get_node_or_null("Player")
	if p:
		p.global_position = pos
		p.rotation.y = rot_y

func _set_cam(_pos: Vector3, look_at: Vector3) -> void:
	var p = main_scene.get_node_or_null("Player")
	if p:
		var cam = p.get_node_or_null("Camera3D")
		if cam:
			cam.look_at(look_at)

func _take(label: String) -> void:
	RenderingServer.force_draw()
	var img := root.get_viewport().get_texture().get_image()
	var path := "/root/verification_screenshots/" + label + ".png"
	DirAccess.make_dir_recursive_absolute("/root/verification_screenshots/")
	var err := img.save_png(path)
	print("[Capture] %s -> %s (err=%d)" % [label, path, err])
