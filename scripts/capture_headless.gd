extends SceneTree
## Headless screenshot capture — loads main.tscn, waits for render init, captures 3 views.
## Before each capture it runs a forward-raycast sanity check to confirm the camera is
## not pressed against / inside geometry (nearest surface >= MIN_DIST). If it fails,
## the screenshot is skipped and the failure reported.
##
## Run (non-headless Vulkan renderer required for real pixels):
##     godot --path <proj> --script res://scripts/capture_headless.gd

const MIN_DIST := 1.5

var screenshot_dir := "user://verification_screenshots/"
var phase := 0
var wait_frames := 0
var wait_target := 0
var main_scene: Node


func _initialize() -> void:
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
	wait_frames = 0
	wait_target = 90
	_install_capture_aux()


func _process(_delta: float) -> bool:
	var player: Node = main_scene.get_node_or_null("Player") if main_scene else null
	var cam: Camera3D = (player.get_node_or_null("CameraPivot/Camera3D") as Camera3D) if player else null

	match phase:
		0:  # Wait for render/Vulkan init
			wait_frames += 1
			if wait_frames >= wait_target:
				var ss := main_scene.find_child("ScreenshotManager", true, false)
				if ss:
					ss.set("auto_done", true)
					ss.set("auto_timer", 999999.0)
					print("[Capture] Disabled ScreenshotManager auto-capture")
				else:
					print("[Capture] ScreenshotManager not found — will not disable")
				print("[Capture] Init done, capturing views...")
				phase = 10

		10:  # View 1: spawn facing room
			_pose(Vector3(0, 1.2, 6), Vector3(0, 1.2, 0))
			wait_frames = 0
			wait_target = 20
			phase = 11

		11:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-spawn")
				_capture_or_report("01_spawn_facing_room", Vector3(0, 1.2, 6), Vector3(0, 1.2, 0))
				phase = 20

		20:  # View 2: on top of platform, looking back into the room
			_pose(Vector3(-6, 2.8, -6), Vector3(0, 1.2, 4))
			wait_frames = 0
			wait_target = 20
			phase = 21

		21:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-platform")
				_capture_or_report("02_platform_looking_back", Vector3(-6, 2.8, -6), Vector3(0, 1.2, 4))
				phase = 30

		30:  # View 3: wall-run approach, mid-corridor, derived from wall geometry
			_pose(Vector3(0, 2.0, 4), Vector3(0, 2.0, -6))
			wait_frames = 0
			wait_target = 20
			phase = 31

		31:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-wallrun")
				_capture_or_report("03_wallrun_approach", Vector3(0, 2.0, 4), Vector3(0, 2.0, -6))
				phase = 40

		40:  # View 4: worst-case grazing angle, standing in the corridor looking down its length
			_pose(Vector3(0, 1.6, 9.0), Vector3(0, 1.6, -9.0))
			wait_frames = 0
			wait_target = 20
			phase = 41

		41:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-corridor")
				_capture_or_report("04_corridor_down_length", Vector3(0, 1.6, 9.0), Vector3(0, 1.6, -9.0))
				phase = 50

		50:  # View 5: Room 2 straightaway — barrier, gap and pit in one frame
			_pose(Vector3(20, 1.7, 14.5), Vector3(20, 1.6, 2))
			wait_frames = 0
			wait_target = 20
			phase = 51

		51:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-room2-straightaway")
				_capture_or_report("05_room2_straightaway", Vector3(20, 1.7, 14.5), Vector3(20, 1.6, 2))
				phase = 60

		60:  # View 6: Room 2 slide barrier close-up (clearance strip visible)
			_pose(Vector3(20, 1.5, 12.3), Vector3(20, 1.9, 8))
			wait_frames = 0
			wait_target = 20
			phase = 61

		61:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-room2-barrier")
				_capture_or_report("06_room2_barrier", Vector3(20, 1.5, 12.3), Vector3(20, 1.9, 8))
				phase = 70

		70:  # View 7: Room 3 wall-run channel, mid platform, gap and finish pad
			_pose(Vector3(42, 1.6, 1), Vector3(42, 2.0, -8))
			wait_frames = 0
			wait_target = 20
			phase = 71

		71:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-room3-channel")
				_capture_or_report("07_room3_channel", Vector3(42, 1.6, 1), Vector3(42, 2.0, -8))
				phase = 80

		80:  # View 8: Room 3 finish beacon, standing on the finish pad
			var fin := main_scene.get_node_or_null("TriggerFinish")
			if fin:
				fin.set("monitoring", false)
			_pose(Vector3(42, 4.1, -16.5), Vector3(42, 4.8, -18))
			wait_frames = 0
			wait_target = 20
			phase = 81

		81:
			wait_frames += 1
			if wait_frames >= wait_target:
				_debug_cam("before-room3-finish")
				_capture_or_report("08_room3_finish", Vector3(42, 4.1, -16.5), Vector3(42, 5.3, -18))
				print("[Capture] All captures done.")
				quit()
				return true

	return false


func _install_capture_aux() -> void:
	# Invisible pad so the Room 3 finish vantage has a solid floor to stand on.
	var pad := StaticBody3D.new()
	pad.name = "CaptureAuxPad"
	pad.position = Vector3(42, 3.2, -17)
	pad.collision_layer = 1
	pad.collision_mask = 1
	main_scene.add_child(pad)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 0.2, 6)
	col.shape = shape
	pad.add_child(col)


func _pose(pos: Vector3, look_at: Vector3) -> void:
	var player: Node = main_scene.get_node_or_null("Player") if main_scene else null
	if not player:
		return
	player.global_position = pos
	player.set("velocity", Vector3.ZERO)
	player.set("state", 0)
	var cam: Camera3D = (player.get_node_or_null("CameraPivot/Camera3D") as Camera3D)
	if cam:
		var dir := look_at - pos
		var yaw := atan2(-dir.x, -dir.z)
		var hor := Vector2(dir.x, dir.z).length()
		var pitch := atan2(dir.y, hor)
		cam.set("yaw", yaw)
		cam.set("pitch", pitch)
		cam.set("slide_crouch", false)
		cam.set("current_roll", 0.0)
		cam.set("target_roll", 0.0)
		cam.set("landing_dip", 0.0)
		cam.set("landing_timer", 0.0)
		cam.position = Vector3.ZERO


func _ray_dist(from: Vector3, dir: Vector3) -> float:
	var space := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = from
	q.to = from + dir.normalized() * 60.0
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit["position"])


func _sanity_ok(pos: Vector3, look_at: Vector3) -> bool:
	var fwd := (look_at - pos).normalized()
	var d_fwd := _ray_dist(pos, fwd)
	var d_left := _ray_dist(pos, Vector3(-fwd.z, 0.0, fwd.x))
	var d_right := _ray_dist(pos, Vector3(fwd.z, 0.0, -fwd.x))
	var min_side: float = min(min(d_left, d_right), d_fwd)
	# A negative distance means the ray were no obstruction — that's open
	# (safe) space. Only short positive hits indicate a clipping camera.
	var fwd_ok := d_fwd < 0.0 or d_fwd >= MIN_DIST
	var side_ok := d_left < 0.0 or d_right < 0.0 or (d_left >= MIN_DIST and d_right >= MIN_DIST)
	print("[Capture] sanity pos=(%.2f,%.2f,%.2f) fwd=%.2f left=%.2f right=%.2f" % [pos.x, pos.y, pos.z, d_fwd, d_left, d_right])
	return fwd_ok and side_ok


func _debug_cam(label: String) -> void:
	var player: Node = main_scene.get_node_or_null("Player") if main_scene else null
	if not player:
		print("[Capture] debug: no player")
		return
	var cam: Camera3D = (player.get_node_or_null("CameraPivot/Camera3D") as Camera3D)
	if not cam:
		print("[Capture] debug: no cam")
		return
	var gp: Vector3 = player.global_position
	var yaw: float = cam.get("yaw")
	var pitch: float = cam.get("pitch")
	var origin: Vector3 = cam.global_transform.origin
	var arrow := -cam.global_transform.basis.z
	var d := _ray_dist(origin, arrow)
	print("[Capture] debug %s: player=%s cam_origin=%s yaw=%.2f pitch=%.2f fwd_hit=%.2f" % [
		label, gp, origin, yaw, pitch, d])


func _capture_or_report(label: String, pos: Vector3, look_at: Vector3) -> void:
	if not _sanity_ok(pos, look_at):
		print("[Capture] FAIL: %s skipped — camera within %.1f units of geometry." % [label, MIN_DIST])
		return
	_capture(label)


func _capture(label: String) -> void:
	RenderingServer.force_draw()
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("[Capture] WARN: no viewport image for ", label)
		return
	var path: String = screenshot_dir + label + ".png"
	var err := img.save_png(path)
	if err == OK:
		print("[Capture] Saved: %s" % ProjectSettings.globalize_path(path))
	else:
		print("[Capture] Failed to save %s: err=%d" % [path, err])
