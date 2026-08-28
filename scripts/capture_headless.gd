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
				print("[Capture] All captures done.")
				quit()
				return true

	return false


func _pose(pos: Vector3, look_at: Vector3) -> void:
	var player: Node = main_scene.get_node_or_null("Player") if main_scene else null
	if not player:
		return
	player.global_position = pos
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
	q.collide_with_areas = false
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
	print("[Capture] sanity pos=(%.2f,%.2f,%.2f) fwd=%.2f left=%.2f right=%.2f" % [pos.x, pos.y, pos.z, d_fwd, d_left, d_right])
	return d_fwd >= MIN_DIST and min_side >= MIN_DIST


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
