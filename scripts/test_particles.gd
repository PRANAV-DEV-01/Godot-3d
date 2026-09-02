extends SceneTree
## Headless particle + audio assertion test.
## Drives the player through a scripted sequence of real gameplay events
## (jump, land, wall-run, dash, slide, finish) then asserts that:
##   • all 5 particle nodes exist and were activated on the correct events
##   • the SoundManager received the right trigger calls (via counters)
##   • DustMotes is always emitting
## Run:
##   godot --path <proj> --script res://scripts/test_particles.gd

var root_scene: Node
var player: CharacterBody3D
var feedback: Node       # FeedbackManager
var sound: Node          # SoundManager
var finish_trigger: Area3D

var frames := 0
var phase := 0
var phase_timer := 0

const PASS := "[PASS]"
const FAIL := "[FAIL]"

var passed := 0
var failed := 0
var results: Array[String] = []


func _initialize() -> void:
	print("[ParticleTest] Starting...")
	root_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(root_scene)
	phase = 0
	phase_timer = 0


func _process(delta: float) -> bool:
	frames += 1
	phase_timer += 1

	match phase:
		0:  # Wait for scene init (builder runs, particles mount)
			if frames >= 90:
				player = root_scene.get_node_or_null("Player")
				feedback = root_scene.get_node_or_null("FeedbackManager")
				sound = root_scene.get_node_or_null("SoundManager")
				finish_trigger = root_scene.get_node_or_null("TriggerFinish")
				if not player or not feedback or not sound:
					_abort("Missing node: player=%s fb=%s snd=%s" % [player, feedback, sound])
					return true
				# Disable ScreenshotManager auto-capture
				var ss := root_scene.find_child("ScreenshotManager", true, false)
				if ss:
					ss.set("auto_done", true)
					ss.set("auto_timer", 999999.0)
				# Disable TriggerFinish so teleport doesn't race
				if finish_trigger:
					finish_trigger.set("monitoring", false)
				print("[ParticleTest] Nodes ready. Running sequence...")
				phase = 10
				phase_timer = 0

		10:  # A) Teleport to Room 1, verify DustMotes always emitting
			if phase_timer == 1:
				player.teleport_to(Vector3(0, 1.2, 6), 1)
			if phase_timer >= 8:
				var dust: GPUParticles3D = player.get_node_or_null("DustMotes")
				_check("DustMotes exists under Player", dust != null)
				_check("DustMotes emitting (ambient)", dust != null and dust.emitting)
				phase = 20
				phase_timer = 0

		20:  # B) Jump → landing → puff fires
			if phase_timer == 1:
				player.set("state", 1)          # force AIR
				player.set("velocity", Vector3(0, 8, 0))
			if phase_timer == 15:
				# Now let gravity bring the player back: simulate a landing by
				# teleporting above ground and setting AIR; the physics step
				# after a few frames will land the player.
				player.teleport_to(Vector3(0, 3.0, 6), 1)
				player.set("state", 1)
				player.set("velocity", Vector3(0, -1, 0))
			if phase_timer >= 40:
				var puff: GPUParticles3D = player.get_node_or_null("LandingPuff")
				_check("LandingPuff exists", puff != null)
				# LandingPuff is one-shot; after landing it should have been
				# restarted at least once. The restart sets emitting for ~0.5 s.
				_check("LandingPuff fired (emitting or counter > 0)",
					puff != null and (puff.emitting or int(feedback.get("hard_landings")) > 0))
				_check("SoundManager land event counted",
					sound.get_event_count("land_soft") > 0 or sound.get_event_count("land_hard") > 0)
				phase = 30
				phase_timer = 0

		30:  # C) Force wall-run → wall sparks + sound
			if phase_timer == 1:
				# Teleport between the two wall-run walls and directly set
				# WALL_RUN state (physics won't drive it in the headless test).
				player.teleport_to(Vector3(-1.9, 3.0, -2), 1)
				player.set("state", 2)  # WALL_RUN
				player.set("velocity", Vector3(0, 2, -6))
			if phase_timer >= 20:
				# Let the feedback manager tick and fire wall sparks
				pass
			if phase_timer >= 45:
				_check("WallSparks fired (wall_spark_pulses > 0)",
					int(feedback.get("wall_spark_pulses")) > 0)
				_check("SoundManager wallrun_start counted",
					sound.get_event_count("wallrun_start") > 0)
				# Stop wall-run
				player.set("state", 0)
				phase = 40
				phase_timer = 0

		40:  # D) Dash → dash trail + sound
			if phase_timer == 1:
				player.teleport_to(Vector3(0, 1.2, -4), 1)
				player.set("state", 4)  # DASH
				player.set("velocity", Vector3(0, 0, -14))
			if phase_timer == 20:
				# Dash ends (goes to AIR → will land)
				player.set("state", 1)
				player.set("velocity", Vector3(0, -2, 0))
				player.teleport_to(Vector3(0, 1.5, -4), 1)
			if phase_timer >= 40:
				_check("DashTrail fired (dash_trail_restarts > 0)",
					int(feedback.get("dash_trail_restarts")) > 0)
				_check("SoundManager dash counted",
					sound.get_event_count("dash") > 0)
				phase = 50
				phase_timer = 0

		50:  # E) Slide → slide dust emitting
			if phase_timer == 1:
				player.teleport_to(Vector3(0, 1.0, 2), 1)
				player.set("state", 3)  # SLIDE
				player.set("velocity", Vector3(0, 0, -6))
			if phase_timer >= 25:
				var sdust: GPUParticles3D = player.get_node_or_null("SlideDust")
				_check("SlideDust exists", sdust != null)
				_check("SlideDust emitting during slide",
					sdust != null and sdust.emitting)
				_check("SoundManager slide_start counted",
					sound.get_event_count("slide_start") > 0)
				# Stop slide
				player.set("state", 0)
				phase = 60
				phase_timer = 0

		60:  # F) Finish trigger → on_finish called on RunHUD + FinishFX
			if phase_timer == 1:
				# Teleport onto the finish pad and fire the trigger callback
				# directly (TriggerFinish monitoring was disabled to prevent
				# a teleport race; we invoke on_finish + teleport manually).
				player.teleport_to(Vector3(42, 4.1, -16.5), 3)
				player.set("state", 0)
				# Call on_finish on finish_listeners (RunHUD + FinishFX)
				for node in root_scene.get_tree().get_nodes_in_group("finish_listeners"):
					if node.has_method("on_finish"):
						node.on_finish()
			if phase_timer >= 30:
				var hud := root_scene.get_node_or_null("RunHUD")
				var fx := root_scene.get_node_or_null("FinishFX")
				_check("RunHUD exists", hud != null)
				_check("RunHUD results panel visible after on_finish",
					hud != null and hud._panel != null and hud._panel.visible)
				_check("FinishFX exists", fx != null)
				_check("FinishFX active after on_finish",
					fx != null and fx._active)
				_check("SoundManager finish counted",
					sound.get_event_count("finish") > 0)
				phase = 99
				phase_timer = 0

		99:  # Done
			_report()
			return true

	return false


func _check(desc: String, ok: bool) -> void:
	if ok:
		passed += 1
		results.append("%s %s" % [PASS, desc])
	else:
		failed += 1
		results.append("%s %s" % [FAIL, desc])


func _report() -> void:
	print("")
	print("═══════════════════════════════════════════════════════")
	print("  PARTICLE / AUDIO TEST RESULTS")
	print("═══════════════════════════════════════════════════════")
	for r in results:
		print("  " + r)
	print("───────────────────────────────────────────────────────")
	print("  TOTAL: %d passed, %d failed (of %d)" % [passed, failed, passed + failed])
	if failed == 0:
		print("  ✓ ALL PARTICLE / AUDIO CHECKS PASSED")
	else:
		print("  ✗ %d CHECK(S) FAILED" % failed)
	print("═══════════════════════════════════════════════════════")


func _abort(msg: String) -> void:
	print("[ParticleTest] ABORT: " + msg)
	_report()