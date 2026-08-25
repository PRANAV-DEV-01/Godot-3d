extends SceneTree
## Automated movement test — simulates player inputs and checks states.
var main_scene: Node
var frames := 0
var phase := 0
var wait_until := 0
var results := []

func _init() -> void:
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	print("[MovementTest] Scene loaded, waiting for build...")

func _idle(_delta: float) -> bool:
	frames += 1
	var player = main_scene.get_node_or_null("Player")
	if not player:
		return false

	match phase:
		0:  # Wait for Phase2 runtime build
			if frames >= 30:
				phase = 1
				wait_until = frames + 10
		1:  # TEST 1: Check spawn state
			if frames >= wait_until:
				var st = player.get_state_name()
				var pos = player.global_position
				var spd = player.get_speed()
				_log("1. Spawn: state=%s pos=(%.1f,%.1f,%.1f) speed=%.1f" % [st, pos.x, pos.y, pos.z, spd])
				# Move forward
				_sim("move_forward", true)
				wait_until = frames + 60
				phase = 2
		2:  # TEST 2: Sprint
			_sim("move_forward", true)
			_sim("sprint", true)
			if frames >= wait_until:
				var st = player.get_state_name()
				var spd = player.get_speed()
				_log("2. Sprint: state=%s speed=%.1f (expect >7)" % [st, spd])
				_sim("sprint", false)
				_sim("move_forward", false)
				wait_until = frames + 10
				phase = 3
		3:  # TEST 3: Jump
			if frames >= wait_until:
				_sim("jump", true)
				wait_until = frames + 2
				phase = 4
		4:
			_sim("jump", false)
			if frames >= wait_until:
				var st = player.get_state_name()
				_log("3. Jump: state=%s (expect AIR)" % [st])
				wait_until = frames + 90
				phase = 5
		5:  # Wait for landing
			if frames >= wait_until:
				var st = player.get_state_name()
				_log("4. Land: state=%s (expect GROUND)" % [st])
				# Sprint toward wall-run wall
				_sim("move_forward", true)
				_sim("sprint", true)
				wait_until = frames + 80
				phase = 6
		6:
			_sim("move_forward", true)
			_sim("sprint", true)
			if frames >= wait_until:
				var st = player.get_state_name()
				var spd = player.get_speed()
				_log("5. WallRun attempt: state=%s speed=%.1f" % [st, spd])
				_sim("move_forward", false)
				_sim("sprint", false)
				# Test slide: sprint + slide
				_sim("move_backward", true)
				_sim("sprint", true)
				wait_until = frames + 40
				phase = 7
		7:
			_sim("move_backward", true)
			_sim("sprint", true)
			if frames >= wait_until:
				_sim("slide", true)
				wait_until = frames + 2
				phase = 8
		8:
			_sim("slide", false)
			_sim("move_backward", false)
			_sim("sprint", false)
			if frames >= wait_until:
				var st = player.get_state_name()
				_log("6. Slide: state=%s (may be SLIDE or GROUND)" % [st])
				wait_until = frames + 60
				phase = 9
		9:  # TEST: Dash
			_sim("move_forward", true)
			if frames >= wait_until:
				_sim("dash", true)
				wait_until = frames + 2
				phase = 10
		10:
			_sim("dash", false)
			_sim("move_forward", false)
			if frames >= wait_until:
				var st = player.get_state_name()
				_log("7. Dash: state=%s" % [st])
				# Check particle nodes
				var fb = main_scene.get_node_or_null("FeedbackManager")
				var amb = main_scene.get_node_or_null("AmbientAudio")
				var ss = main_scene.get_node_or_null("ScreenshotManager")
				_log("8. Managers: Feedback=%s Ambient=%s Screenshot=%s" % [
					"OK" if fb else "MISSING",
					"OK" if amb else "MISSING",
					"OK" if ss else "MISSING"
				])
				# Check particles
				var dust = player.get_node_or_null("DustMotes")
				var sparks = player.get_node_or_null("WallSparks")
				var puff = player.get_node_or_null("LandingPuff")
				var sdust = player.get_node_or_null("SlideDust")
				var dash = player.get_node_or_null("DashTrail")
				_log("9. Particles: Dust=%s Sparks=%s Puff=%s Slide=%s Dash=%s" % [
					"OK" if dust else "-",
					"OK" if sparks else "-",
					"OK" if puff else "-",
					"OK" if sdust else "-",
					"OK" if dash else "-"
				])
				# Check lighting
				var sun = main_scene.get_node_or_null("SunKey")
				var fill = main_scene.get_node_or_null("FillLight")
				_log("10. Lighting: Sun=%s Fill=%s" % [
					"OK" if sun else "MISSING",
					"OK" if fill else "MISSING"
				])
				# Check env
				var env_node = main_scene.get_node_or_null("WorldEnvironment")
				if env_node and env_node.environment:
					var e = env_node.environment
					_log("11. Env: glow=%s ssao=%s fog=%s vol_fog=%s tonemap=%d" % [
						str(e.glow_enabled), str(e.ssao_enabled),
						str(e.fog_enabled), str(e.volumetric_fog_enabled),
						e.tonemap_mode
					])
				# Check surface types
				var floor_node = main_scene.get_node_or_null("Room/Floor")
				var wallrun = main_scene.get_node_or_null("Room/WallRunLeft")
				var plat = main_scene.get_node_or_null("Room/Platform")
				_log("12. Surfaces: Floor=%s WallRun=%s Platform=%s" % [
					floor_node.get_meta("surface_type", "?") if floor_node else "?",
					wallrun.get_meta("surface_type", "?") if wallrun else "?",
					plat.get_meta("surface_type", "?") if plat else "?"
				])
				_log("")
				_log("=== MOVEMENT TEST COMPLETE ===")
				quit()
				return true
	return false


func _log(msg: String) -> void:
	print("[MovementTest] " + msg)
	results.append(msg)


func _sim(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
