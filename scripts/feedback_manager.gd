extends Node
## Feedback Manager — polls player state, triggers VFX + audio.
## Zero changes to movement logic; only reads player.state + velocity.

var player: CharacterBody3D

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

# simple synth players
var sfx_player: AudioStreamPlayer

# Surface detection
var _last_surface := "concrete"


func _ready() -> void:
	player = get_node_or_null("/root/Main/Player")
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "Master"
	add_child(sfx_player)
	# Particle refs wired by scene_runtime_builder via meta
	if has_meta("player_ref"):
		player = get_meta("player_ref")
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


func _on_transition(old_s: int, new_s: int) -> void:
	match new_s:
		0:  # → GROUND
			if old_s in [1, 4]:
				_land_fx()
		1:  # → AIR
			if old_s == 0:
				_sfx("jump")
		2:  # → WALL_RUN
			_sfx("wallrun")
		3:  # → SLIDE
			_sfx("slide")
		4:  # → DASH
			_sfx("dash")
			_dash_fx()


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
		_sfx("step")


func _wall_spark_tick(delta: float) -> void:
	spark_cd -= delta
	if spark_cd <= 0.0:
		spark_cd = 0.08
		if wall_sparks and player:
			wall_sparks.global_position = player.global_position + Vector3(0, -0.7, 0)
			if player.wall_run_normal.length_squared() > 0.01:
				wall_sparks.global_position -= player.wall_run_normal * 0.3
			wall_sparks.restart()
		_sfx("wallloop")


func _slide_dust_tick() -> void:
	if slide_dust and player:
		slide_dust.emitting = true
		slide_dust.global_position = player.global_position + Vector3(0, -0.8, 0)


func _land_fx() -> void:
	if landing_puff and player:
		landing_puff.global_position = player.global_position + Vector3(0, -0.9, 0)
		landing_puff.restart()
	_last_surface = _detect_surface()
	_sfx("land")


func _dash_fx() -> void:
	if dash_trail and player:
		dash_trail.global_position = player.global_position
		dash_trail.restart()


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


# ── Procedural one-shot SFX via AudioStreamGenerator ────────────────
func _sfx(name: String, vol := 0.0) -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.25
	sfx_player.stream = gen
	sfx_player.volume_db = vol
	sfx_player.play()
	await get_tree().process_frame
	var pb = sfx_player.get_stream_playback()
	if not pb:
		return
	match name:
		"jump":
			_synth_sweep(pb, 200, 600, 0.08, 0.3)
		"land":
			_synth_surface_land(pb)
		"dash":
			_synth_sweep(pb, 800, 200, 0.1, 0.35)
		"slide":
			_synth_noise(pb, 0.1, 0.25)
		"wallrun":
			_synth_sweep(pb, 300, 500, 0.06, 0.2)
		"wallloop":
			_synth_noise(pb, 0.04, 0.15)
		"step":
			_synth_surface_step(pb)


func _synth_sweep(pb, f0: float, f1: float, dur: float, vol: float) -> void:
	var n := int(dur * 22050)
	for i in range(min(n, pb.get_frames_available() - 1)):
		var t := float(i) / 22050.0
		var frac := float(i) / float(n)
		var freq := lerpf(f0, f1, frac)
		var env := 1.0 - frac
		var s := sin(t * TAU * freq) * vol * env
		pb.push_frame(Vector2(s, s))


func _synth_noise(pb, dur: float, vol: float) -> void:
	var n := int(dur * 22050)
	for i in range(min(n, pb.get_frames_available() - 1)):
		var frac := float(i) / float(n)
		var env := 1.0 - frac * frac
		var s := (randf() * 2.0 - 1.0) * vol * env
		pb.push_frame(Vector2(s, s))


# ── Per-Surface Footstep Synth ─────────────────────────────────────
# Each surface has distinct dur, vol, and tonal character.
# "concrete": gritty mid-range crunch with slight low-end thump
# "metal":    sharp bright click with ringing high-frequency tail
# "wood":     warm hollow thump with soft low-frequency body

func _synth_surface_step(pb) -> void:
	match _last_surface:
		"metal":
			# Bright, sharp click — short noise burst + high sine ping
			var dur := 0.018
			var vol := 0.22
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac
				var noise_part := (randf() * 2.0 - 1.0) * vol * 0.6 * env
				var t := float(i) / 22050.0
				var ping := sin(t * TAU * 3200.0) * vol * 0.4 * env * (1.0 - frac)
				pb.push_frame(Vector2(noise_part + ping, noise_part + ping))
		"wood":
			# Warm hollow thump — longer noise + low sine body
			var dur := 0.05
			var vol := 0.13
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac * frac
				var noise_part := (randf() * 2.0 - 1.0) * vol * 0.4 * env
				var t := float(i) / 22050.0
				var thump := sin(t * TAU * 90.0) * vol * 0.6 * env * (1.0 - frac * 0.5)
				pb.push_frame(Vector2(noise_part + thump, noise_part + thump))
		_:  # "concrete" or unknown — default gritty crunch
			var dur := 0.03
			var vol := 0.18
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac * frac
				var noise_part := (randf() * 2.0 - 1.0) * vol * 0.7 * env
				var t := float(i) / 22050.0
				var thump := sin(t * TAU * 150.0) * vol * 0.3 * env * (1.0 - frac)
				pb.push_frame(Vector2(noise_part + thump, noise_part + thump))


func _synth_surface_land(pb) -> void:
	match _last_surface:
		"metal":
			var dur := 0.08
			var vol := 0.45
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac
				var noise_part := (randf() * 2.0 - 1.0) * vol * 0.5 * env
				var t := float(i) / 22050.0
				var ring := sin(t * TAU * 2400.0) * vol * 0.35 * env * (1.0 - frac * 0.8)
				pb.push_frame(Vector2(noise_part + ring, noise_part + ring))
		"wood":
			var dur := 0.09
			var vol := 0.38
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac * frac
				var noise_part := (randf() * 2.0 - 1.0) * vol * 0.35 * env
				var t := float(i) / 22050.0
				var thump := sin(t * TAU * 70.0) * vol * 0.65 * env * (1.0 - frac * 0.4)
				pb.push_frame(Vector2(noise_part + thump, noise_part + thump))
		_:  # concrete
			var dur := 0.06
			var vol := 0.5
			var n := int(dur * 22050)
			for i in range(min(n, pb.get_frames_available() - 1)):
				var frac := float(i) / float(n)
				var env := 1.0 - frac
				var s := (randf() * 2.0 - 1.0) * vol * env
				pb.push_frame(Vector2(s, s))
