extends SceneTree
## Quick structural verification — no movement simulation needed.
var main_scene: Node
var frames := 0
var done := false

func _init() -> void:
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)

func _process(_delta: float) -> bool:
	if done:
		return true
	frames += 1
	if frames < 5:
		return false
	done = true

	var checks := []

	# 1. Room geometry
	var room = main_scene.get_node_or_null("Room")
	if room:
		var children = room.get_children().size()
		checks.append("Room: %d children" % children)
	else:
		checks.append("Room: MISSING")

	# 2. Surface metadata
	for path in ["Room/Floor", "Room/WallNorth", "Room/WallRunLeft", "Room/WallRunRight", "Room/Platform", "Room/LedgeBlock"]:
		var node = main_scene.get_node_or_null(path)
		if node:
			var surf = node.get_meta("surface_type", "?")
			checks.append("  %s -> %s" % [path.get_file(), surf])
		else:
			checks.append("  %s -> MISSING" % path.get_file())

	# 2b. New rooms
	for rname in ["Room2", "Room3"]:
		var r = main_scene.get_node_or_null(rname)
		if r:
			checks.append("%s: OK (%d geometry nodes, pos=%s)" % [rname, r.get_children().size(), r.position])
		else:
			checks.append("%s: MISSING" % rname)
	for path in ["Room2/SlideBarrier", "Room2/FloorEntrance", "Room3/WallRunLeft", "Room3/MidPlatform", "Room3/FinishPad"]:
		var node = main_scene.get_node_or_null(path)
		if node:
			var surf = node.get_meta("surface_type", "?")
			var layer = node.collision_layer
			checks.append("  %s -> %s (layer=%d)" % [path, surf, layer])
		else:
			checks.append("  %s -> MISSING" % path)

	# 2c. Triggers
	for tname in ["TriggerRoom1Exit", "TriggerRoom2Exit", "TriggerRoom2PitReset", "TriggerFinish"]:
		var t = main_scene.get_node_or_null(tname)
		if t:
			checks.append("  Trigger %s: OK (dest=%s room=%d finish=%s)" % [tname, t.destination, t.target_room, t.is_finish])
		else:
			checks.append("  Trigger %s: MISSING" % tname)

	# 3. Lighting
	var sun = main_scene.get_node_or_null("SunKey")
	var fill = main_scene.get_node_or_null("FillLight")
	checks.append("Lighting: Sun=%s Fill=%s" % [
		"OK(energy=%.1f)" % sun.light_energy if sun else "MISSING",
		"OK" if fill else "MISSING"])

	# Spot lights
	var spot_count = 0
	for c in main_scene.get_children():
		if c is SpotLight3D:
			spot_count += 1
	var omni_count = 0
	for c in main_scene.get_children():
		if c is OmniLight3D:
			omni_count += 1
	checks.append("Spotlights: %d  OmniLights: %d" % [spot_count, omni_count])

	# 4. Particles
	var player = main_scene.get_node_or_null("Player")
	if player:
		for pname in ["DustMotes", "WallSparks", "LandingPuff", "SlideDust", "DashTrail"]:
			var p = player.get_node_or_null(pname)
			checks.append("Particle %s: %s" % [pname, "OK" if p else "MISSING"])
	else:
		checks.append("Player: MISSING")

	# 5. Managers
	for mname in ["FeedbackManager", "AmbientAudio", "ScreenshotManager"]:
		var m = main_scene.get_node_or_null(mname)
		checks.append("Manager %s: %s" % [mname, "OK" if m else "MISSING"])

	# 6. Environment
	var env_node = main_scene.get_node_or_null("WorldEnvironment")
	if env_node and env_node.environment:
		var e = env_node.environment
		checks.append("Env: glow=%s ssao=%s fog=%s vol_fog=%s tonemap=%d" % [
			str(e.glow_enabled), str(e.ssao_enabled),
			str(e.fog_enabled), str(e.volumetric_fog_enabled),
			e.tonemap_mode])
	else:
		checks.append("Env: MISSING")

	# 7. Player state
	if player:
		checks.append("Player state: %s  pos=(%.1f,%.1f,%.1f)" % [
			player.get_state_name(),
			player.global_position.x,
			player.global_position.y,
			player.global_position.z])

	# 8. Shader materials on room meshes
	if room:
		var has_shader = false
		for c in room.get_children():
			if c is StaticBody3D:
				var mi = c.get_node_or_null("MeshInstance3D")
				if mi and mi.get_surface_override_material(0) is ShaderMaterial:
					has_shader = true
					break
		checks.append("Shader materials: %s" % ("YES" if has_shader else "NO"))

	checks.append("")
	checks.append("=== VERIFICATION COMPLETE ===")

	for line in checks:
		print("[Verify] " + line)

	quit()
	return true
