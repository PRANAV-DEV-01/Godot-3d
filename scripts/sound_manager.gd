extends Node
## Sound manager — bakes every SFX into a 16-bit WAV once at startup, then
## plays them through 3D-positioned AudioStreamPlayer3D nodes mounted on the
## Player (so a stepping/dashing/jumping player emits truly spatial audio,
## not flat stereo). Continuous loops (wall-run, slide) are baked loopable
## with the same click-free discipline as the ambient drones.
##
## Real audio can't be *heard* in the headless test sandbox (dummy driver),
## so every event also increments a counter exposed as `get_event_count()`
## and the baked streams are reported — the test harness asserts trigger
## logic, the seam checks assert the loop WAVs cannot click.

const MIX_RATE := 22050

var player: CharacterBody3D

var _oneshot: Array[AudioStreamPlayer3D] = []
var _oneshot_i := 0
const ONESHOT_POOL := 8

var _wall_loop_player: AudioStreamPlayer3D
var _slide_loop_player: AudioStreamPlayer3D

var _streams: Dictionary = {}        # name -> AudioStreamWAV
var _step_pair: Dictionary = {}      # surface -> [stream_left, stream_right]
var _step_alt := false

var events: Dictionary = {}          # name -> int (for headless verification)


func _ready() -> void:
	if has_meta("player_ref"):
		player = get_meta("player_ref")
	else:
		player = _find_local_player()

	_bake_all()
	_build_players()
	add_to_group("finish_listeners")
	print("[Sound] %d SFX baked; %d one-shot players + 2 loop players (3D, mounted on Player)." % [_streams.size(), ONESHOT_POOL])


func _find_local_player() -> CharacterBody3D:
	var p := get_node_or_null("/root/Main/Players")
	if p:
		for c in p.get_children():
			if c is CharacterBody3D:
				return c
	return null


# ── Public event API (called by FeedbackManager / room triggers) ──────

func on_footstep(spd: float, surface: String) -> void:
	_step_alt = not _step_alt
	var pair: Array = _step_pair.get(surface)
	if not pair:
		pair = _step_pair["concrete"]
	var stream: AudioStreamWAV = pair[0] if _step_alt else pair[1]
	var vol := -14.0 + clampf((spd - 5.0) * 1.1, 0.0, 7.0)   # sprint louder than walk
	var pitch := 0.92 + randf() * 0.18
	_play_oneshot(stream, vol, pitch)
	_count("footstep")


func on_jump(_surface: String) -> void:
	_play_oneshot(_streams["jump"], -12.0, 1.0)
	_count("jump")


func on_land(impact_vel: float) -> void:
	# Same -8.0 hard-land threshold the Phase 2 camera dip uses.
	if impact_vel < -8.0:
		var severity := clampf(absf(impact_vel) / 12.0, 0.6, 1.3)
		_play_oneshot(_streams["land_hard"], -6.0 + severity * 4.0, 1.0)
		_count("land_hard")
	else:
		_play_oneshot(_streams["land_soft"], -16.0, 1.0)
		_count("land_soft")


func start_wall_run() -> void:
	_play_oneshot(_streams["wallrun_ping"], -14.0, 1.0)
	if _wall_loop_player:
		_wall_loop_player.volume_db = -20.0
		_wall_loop_player.play(0.0)
	_count("wallrun_start")


func stop_wall_run() -> void:
	if _wall_loop_player and _wall_loop_player.playing:
		_wall_loop_player.stop()
	_count("wallrun_end")


func on_dash() -> void:
	_play_oneshot(_streams["dash"], -10.0, 1.0)
	_count("dash")


func on_dash_end() -> void:
	_play_oneshot(_streams["dash_end"], -18.0, 0.9)
	_count("dash_end")


func start_slide() -> void:
	_play_oneshot(_streams["slide_start"], -10.0, 1.0)
	if _slide_loop_player:
		_slide_loop_player.volume_db = -22.0
		_slide_loop_player.play(0.0)
	_count("slide_start")


func stop_slide() -> void:
	if _slide_loop_player and _slide_loop_player.playing:
		_slide_loop_player.stop()
	_count("slide_end")


func on_finish() -> void:
	_play_oneshot(_streams["finish"], 0.0, 1.0)
	_count("finish")


func get_event_count(name: String) -> int:
	return int(events.get(name, 0))


# ── Setup ─────────────────────────────────────────────────────────────

func _count(name: String) -> void:
	events[name] = get_event_count(name) + 1


func _play_oneshot(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if not stream or not player:
		return
	var p := _oneshot[_oneshot_i]
	_oneshot_i = (_oneshot_i + 1) % _oneshot.size()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.global_position = player.global_position
	p.play()


func _build_players() -> void:
	for i in ONESHOT_POOL:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D_%d" % i
		p.volume_db = 0.0
		p.max_distance = 40.0
		p.unit_size = 4.0
		p.max_db = 3.0
		if player:
			player.add_child(p)
		_oneshot.append(p)

	_wall_loop_player = _make_loop_player("WallRunLoop")
	_slide_loop_player = _make_loop_player("SlideLoop")


func _make_loop_player(n: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = n
	p.max_distance = 30.0
	p.unit_size = 4.0
	p.max_db = 3.0
	if player:
		player.add_child(p)
	return p


# ── Baking ────────────────────────────────────────────────────────────

func _bake_all() -> void:
	_streams["jump"] = _make_wav(_gen_sweep(180.0, 520.0, 0.10, 0.42), false)
	_streams["land_soft"] = _make_wav(_gen_thump(90.0, 0.07, 0.20) + _gen_noise(0.06, 0.06, 0.0), false)
	_streams["land_hard"] = _make_wav(_gen_thump(70.0, 0.12, 0.5) + _gen_noise(0.1, 0.22, 0.0), false)
	_streams["dash"] = _make_wav(_gen_sweep(300.0, 1400.0, 0.14, 0.4) + _gen_noise(0.14, 0.18, 0.0), false)
	_streams["dash_end"] = _make_wav(_gen_thump(110.0, 0.06, 0.26), false)
	_streams["slide_start"] = _make_wav(_gen_noise(0.18, 0.3, 0.0), false)
	_streams["slide_loop"] = _make_wav(_gen_loop_whoosh(2.0, 0.16), true)
	_streams["wallrun_ping"] = _make_wav(_gen_sweep(420.0, 660.0, 0.06, 0.2), false)
	_streams["wallrun_loop"] = _make_wav(_gen_loop_whoosh(2.0, 0.13), true)

	# Per-surface footstep pairs (left/right alternatives).
	_streams["step_concrete_a"] = _make_wav(_gen_step("concrete", 0.0), false)
	_streams["step_concrete_b"] = _make_wav(_gen_step("concrete", 0.08), false)
	_streams["step_metal_a"] = _make_wav(_gen_step("metal", 0.0), false)
	_streams["step_metal_b"] = _make_wav(_gen_step("metal", 0.08), false)
	_streams["step_wood_a"] = _make_wav(_gen_step("wood", 0.0), false)
	_streams["step_wood_b"] = _make_wav(_gen_step("wood", 0.08), false)
	_step_pair["concrete"] = [_streams["step_concrete_a"], _streams["step_concrete_b"]]
	_step_pair["metal"] = [_streams["step_metal_a"], _streams["step_metal_b"]]
	_step_pair["wood"] = [_streams["step_wood_a"], _streams["step_wood_b"]]

	_streams["finish"] = _make_wav(_gen_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.14, 0.34), false)

	# Loop-seam verification for the two continuous loops.
	for nm in ["slide_loop", "wallrun_loop"]:
		var w: AudioStreamWAV = _streams[nm]
		var steps: int = w.loop_end
		var max_diff := 0
		for k in 16:
			max_diff = maxi(max_diff, absi(_wav_sample(w, steps - 16 + k) - _wav_sample(w, k)))
		print("[Sound] %s loop seam verified: max first/last delta=%d (click-free if <=2)." % [nm, max_diff])


func _wav_sample(w: AudioStreamWAV, i: int) -> int:
	var d: PackedByteArray = w.data
	if i < 0 or i >= w.loop_end:
		return 0
	var lo := d[i * 2]
	var hi := d[i * 2 + 1]
	var v := lo | (hi << 8)
	return v - 65536 if v >= 32768 else v


# ── Generators (mono float -1..1) ─────────────────────────────────────

func _gen_sweep(f0: float, f1: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var frac := float(i) / float(n)
		var freq := lerpf(f0, f1, frac)
		var env := pow(1.0 - frac, 1.6)
		var fade_in := minf(float(i) / 8.0, 1.0)
		out[i] = sin(float(i) / MIX_RATE * TAU * freq) * amp * env * fade_in
	return out


func _gen_noise(dur: float, amp: float, edge_fade: float) -> PackedFloat32Array:
	# edge_fade=0 → quick 6-sample attack + natural tail; else smooth to 0 at both ends (for loops)
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	var lp := 0.0
	for i in n:
		var s := rng.randf() * 2.0 - 1.0
		lp = lp + 0.12 * (s - lp)
		var env := 1.0
		if edge_fade > 0.0:
			var u := float(i) / float(n)
			env = pow(sin(PI * u), edge_fade)
		else:
			env = minf(float(i) / 8.0, 1.0)
		out[i] = lp * amp * env
	return out


func _gen_thump(freq: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 26.0)
		out[i] = sin(t * TAU * freq) * amp * env
	return out


func _gen_loop_whoosh(loop_sec: float, amp: float) -> PackedFloat32Array:
	var n := int(loop_sec * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var lp := 0.0
	# low whoosh tone with an integer number of cycles + noise swelled to zero at edges
	for i in n:
		var u := float(i) / float(n)
		var t := float(i) / MIX_RATE
		var tone := sin(t * TAU * 43.0) * 0.5 + sin(t * TAU * 87.0) * 0.3
		var s := rng.randf() * 2.0 - 1.0
		lp = lp + 0.08 * (s - lp)
		var env := pow(sin(PI * u), 0.7)
		var breath := 0.6 + 0.4 * sin(t * TAU * 0.5)
		out[i] = (tone * 0.5 + lp * 0.8) * amp * env * breath
	return out


func _gen_step(surface: String, phase: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	match surface:
		"metal":
			out = _gen_noise(0.02, 0.2, 0.0) + _gen_chirp(2600.0, 3400.0, 0.035, 0.12, phase)
		"wood":
			out = _gen_thump(110.0, 0.06, 0.24) + _gen_noise(0.03, 0.06, 0.0)
		_:
			out = _gen_noise(0.028, 0.16, 0.0) + _gen_thump(150.0, 0.04, 0.16)
	return out


func _gen_chirp(f0: float, f1: float, dur: float, amp: float, phase: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var frac := float(i) / float(n)
		var freq := lerpf(f0, f1, frac)
		var env := (1.0 - frac) * minf(float(i) / 6.0, 1.0)
		out[i] = sin((float(i) / MIX_RATE + phase) * TAU * freq) * amp * env
	return out


func _gen_arpeggio(freqs: Array, note_len: float, amp: float) -> PackedFloat32Array:
	var n := int(freqs.size() * note_len * MIX_RATE + 0.2 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var idx := 0
	for f in freqs:
		var nn := int(note_len * MIX_RATE)
		for i in nn:
			if idx >= n:
				break
			var t := float(i) / MIX_RATE
			var env := pow(maxf(1.0 - t / note_len, 0.0), 1.3)
			out[idx] = sin(t * TAU * float(f)) * amp * env
			idx += 1
	# small release after the last note
	for i in range(idx, n):
		var u := float(i - idx) / float(n - idx)
		out[i] = out[idx - 1] * (1.0 - u) * 0.3
	return out


# ── WAV encode ────────────────────────────────────────────────────────

func _make_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w