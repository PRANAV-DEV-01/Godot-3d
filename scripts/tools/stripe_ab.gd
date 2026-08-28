extends SceneTree
## Controlled A/B of the wallrun wall stripe density: same close-up camera,
## stripe_freq 12 (previous, reported "giant") vs 34 (fixed). Saves to user://stripe_test/.

var screenshot_dir := "user://stripe_test/"
var main_scene: Node
var phase := 0
var wait_frames := 0
var step := 0
var freqs := [12.0, 34.0]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var packed := load("res://scenes/main.tscn")
	main_scene = packed.instantiate()
	root.add_child(main_scene)


func _process(_delta: float) -> bool:
	if not main_scene:
		quit()
		return true
	var player: Node = main_scene.get_node_or_null("Player")
	var cam: Camera3D = (player.get_node_or_null("CameraPivot/Camera3D") as Camera3D) if player else null
	match phase:
		0:
			wait_frames += 1
			if wait_frames >= 120:
				var ss := main_scene.find_child("ScreenshotManager", true, false)
				if ss:
					ss.set("auto_done", true)
					ss.set("auto_timer", 999999.0)
				phase = 10
		10:
			_setup(freqs[step])
			wait_frames = 0
			phase = 11
		11:
			wait_frames += 1
			if wait_frames >= 40:
				RenderingServer.force_draw()
				var img := root.get_viewport().get_texture().get_image()
				var path: String = screenshot_dir + "wallrun_wall_freq%d.png" % int(freqs[step])
				if img:
					var err := img.save_png(path)
					print("[StripeTest] freq=%.0f saved=%s err=%d" % [freqs[step], ProjectSettings.globalize_path(path), err])
				step += 1
				if step < freqs.size():
					phase = 10
				else:
					print("[StripeTest] done.")
					quit()
					return true
	return false


func _setup(freq: float) -> void:
	var player: Node = main_scene.get_node_or_null("Player")
	if not player:
		return
	var cam: Camera3D = player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var pos := Vector3(4.6, 3.0, -2.0)
	var look := Vector3(2.2, 3.0, -2.0)
	player.global_position = pos
	var dir := look - pos
	cam.set("yaw", atan2(-dir.x, -dir.z))
	var hor := Vector2(dir.x, dir.z).length()
	cam.set("pitch", atan2(dir.y, hor))
	cam.set("slide_crouch", false)
	cam.set("current_roll", 0.0)
	cam.set("target_roll", 0.0)
	cam.set("landing_dip", 0.0)
	cam.set("landing_timer", 0.0)
	cam.position = Vector3.ZERO
	var found := _set_wallrun_freq(freq)
	print("[StripeTest] freq %.0f applied=%s" % [freq, found])


func _set_wallrun_freq(freq: float) -> bool:
	var found := false
	var stack: Array = [main_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var m := mi.get_surface_override_material(0)
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				if sm.get_shader_parameter("stripe_freq") != null:
					sm.set_shader_parameter("stripe_freq", freq)
					found = true
		var ch := n.get_children()
		for c in ch:
			stack.append(c)
	return found