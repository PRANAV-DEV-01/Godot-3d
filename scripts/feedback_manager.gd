extends Node
## Feedback Manager — polls player state, triggers VFX + audio.
## Zero changes to movement logic; only reads player.state + velocity.
##
## Particle wiring stays exactly as before. All SFX now route to the
## SoundManager node (3D-spatial baked WAVs). Hit-stop is added on hard
## landings and dash end via the Hitstop node. Per-event counters let the
## headless particle/audio test assert that each effect actually fires on
## its real gameplay event (not just "present in the scene tree").

var player: CharacterBody3D
var sound: Node
var hitstop: Node

# Particle refs (set by scene_runtime_builder via meta)
var dust_motes: GPUParticles3D
var dash_trail: GPUParticles3D
var wall_sparks: GPUParticles3D
var landing_puff: GPUParticles3D
var slide_dust: GPUParticles3D

var prev_state := -1
var footstep_cd := 0.0
var spark_cd := 0.0
const WALK_STEP := 0.42
const SPRINT_STEP := 0.28

# Surface detection
var _last_surface := "concrete"

# Verification counters — incremented at the exact call site that fires the
# particle, so the test can prove firing, not just presence.
var hard_landings := 0
var wall_spark_pulses := 0
var dash_trail_restarts := 0
var dust_ledger_frames := 0


func _ready() -> void:
	if has_meta("player_ref"):
		player = get_meta("player_ref")
	else:
		player = _find_local_player()
	if has_meta("sound_ref"):
		sound = get_meta("sound_ref")
	if has_meta("hitstop_ref"):
		hitstop = get_meta("hitstop_ref")
	if has_meta("dust_motes_ref"):
		dust_motes = get_meta("dust_motes_ref")
	if has_meta("dash_trail_ref"):
		dash_trail = get_meta("dash_trail_ref")
	if has_meta("wall_sparks_ref"):
		wall_sparks = get_meta("wall_sparks_ref")
	if has_meta("landing_puff_ref"):
		landing_puff = get_meta("landing_puff_ref")
	if has_meta("slide_dust_ref"):
		slide_dust = get_meta("slide_dust_ref")
	if player and player.has_signal("landed"):
		player.landed.connect(_on_player_landed)


func _find_local_player():
	var p := get_node_or_null("/root/Main/Players")
	if p:
		for c in p.get_children():
			if c is CharacterBody3D:
				return c
	return null


func _process(delta: float) -> void:
	if not player:
		return

	var s: int = player.state
	if s != prev_state:
		_on_transition(prev_state, s)
		prev_state = s

	# per-frame
	match s:
		0:
			_step_timer(delta)
			if wall_sparks: wall_sparks.emitting = false
		1:
			if wall_sparks: wall_sparks.emitting = false
		2:
			_wall_spark_tick(delta)
		3:
			_slide_dust_tick()
			if wall_sparks: wall_sparks.emitting = false
		4:
			if wall_sparks: wall_sparks.emitting = false

	if dust_motes:
		dust_motes.emitting = true
		dust_ledger_frames += 1


func _on_transition(old_s: int, new_s: int) -> void:
	match new_s:
		0:  # → GROUND
			# Real landing puffs + severity-scaled sound arrive via the
			# player.landed signal (carries the true impact velocity).
			pass
		1:  # → AIR
			if old_s == 0 and sound:
				sound.on_jump(_last_surface)
		2:  # → WALL_RUN
			if sound:
				sound.start_wall_run()
		3:  # → SLIDE
			if sound:
				sound.start_slide()
		4:  # → DASH
			if sound:
				sound.on_dash()
			_dash_fx()

	# "Leaving a looping state" cues
	if old_s == 2 and new_s != 2 and sound:
		sound.stop_wall_run()
	if old_s == 4 and new_s != 4:
		if sound:
			sound.on_dash_end()
		if hitstop:
			hitstop.hit(0.05, 2)
		if new_s == 0:
			_land_fx()   # dash-charged dust puff on a floor stop
	if old_s == 3 and new_s != 3 and sound:
		sound.stop_slide()


func _on_player_landed(impact_velocity: float) -> void:
	_land_fx()
	if sound:
		sound.on_land(impact_velocity)
	if impact_velocity < -8.0:
		hard_landings += 1
		if hitstop:
			hitstop.hit(0.05, 2)


func _step_timer(delta: float) -> void:
	if not player:
		return
	var spd: float = player.get_speed()
	if spd < 1.5:
		footstep_cd = 0.0
		return
	var interval := SPRINT_STEP if Input.is_action_pressed("sprint") else WALK_STEP
	footstep_cd -= delta
	if footstep_cd <= 0.0:
		footstep_cd = interval
		_last_surface = _detect_surface()
		if sound:
			sound.on_footstep(spd, _last_surface)


func _wall_spark_tick(delta: float) -> void:
	spark_cd -= delta
	if spark_cd <= 0.0:
		spark_cd = 0.08
		if wall_sparks and player:
			wall_sparks.global_position = player.global_position + Vector3(0, -0.7, 0)
			if player.wall_run_normal.length_squared() > 0.01:
				wall_sparks.global_position -= player.wall_run_normal * 0.3
			wall_sparks.restart()
			wall_spark_pulses += 1


func _slide_dust_tick() -> void:
	if slide_dust and player:
		slide_dust.emitting = true
		slide_dust.global_position = player.global_position + Vector3(0, -0.8, 0)


func _land_fx() -> void:
	if landing_puff and player:
		landing_puff.global_position = player.global_position + Vector3(0, -0.9, 0)
		landing_puff.restart()
	_last_surface = _detect_surface()


func _dash_fx() -> void:
	if dash_trail and player:
		dash_trail.global_position = player.global_position
		dash_trail.restart()
		dash_trail_restarts += 1


# ── Surface Detection ──────────────────────────────────────────────
func _detect_surface() -> String:
	if not player:
		return "concrete"
	var space_state := player.get_world_3d().direct_space_state
	var origin := player.global_position + Vector3(0, 0.1, 0)
	var end := player.global_position + Vector3(0, -1.5, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	if result and result.collider is StaticBody3D:
		if result.collider.has_meta("surface_type"):
			return result.collider.get_meta("surface_type")
	return "concrete"