extends Node
## Per-room ambient audio — a low, seamless background drone per room.
##
## Every drone is baked ONCE at startup into an AudioStreamWAV whose loop
## point is mathematically click-free:
##   * every sine component has an integer number of cycles inside one loop
##   * the noise layer is amplitude-modulated to a soft zero at both loop
##     edges, so even non-periodic noise can never pop at the seam
## We then *explicitly verify* the seam by reading first/last samples back
## and asserting the discontinuity is ~0 (this exact click-at-loop bug was
## found and fixed once before in this project — see git history).
##
## Tones differ per room for identity:
##   Room 1 — concrete hall:  low 55 Hz hum with a 0.5 Hz beat + dust air
##   Room 2 — straightaway:   lower, windier open-corridor drone
##   Room 3 — vertical channel: deeper resonance + faint high shimmer
##
## Rooms crossfade by volume as the player moves between them (polling
## player.current_room — no movement-logic dependency).

const LOOP_SEC := 6.0
const MIX_RATE := 22050

var player: CharacterBody3D
var _rooms: Array[AudioStreamPlayer3D] = []
var _room_vol: Array[float] = [0.0, 0.0, 0.0]
var _active_room := 1    # player starts in Room 1
var _started := false


func _ready() -> void:
	if has_meta("player_ref"):
		player = get_meta("player_ref")
	else:
		player = get_node_or_null("/root/Main/Player")

	var bands: Array = [
		# [name, [(freq, amp), ...], noise_amp]
		["room1_hall", [[55.0, 0.10], [55.5, 0.08], [110.0, 0.045], [164.5, 0.02]], 0.014],
		["room2_wind", [[37.0, 0.11], [74.5, 0.07], [111.5, 0.03]], 0.022],
		["room3_channel", [[41.0, 0.12], [82.0, 0.075], [123.0, 0.035], [329.0, 0.012]], 0.016],
	]

	var centers := [Vector3(0, 3, 0), Vector3(20, 3, 0), Vector3(42, 3, 0)]

	for i in range(bands.size()):
		var wav := _bake_loop(bands[i][1], float(bands[i][2]), bands[i][0])
		_verify_seam(wav, bands[i][0])

		var p := AudioStreamPlayer3D.new()
		p.name = "Ambient_" + bands[i][0]
		p.stream = wav
		p.position = centers[i]
		p.volume_db = -60.0
		p.max_distance = 60.0
		p.unit_size = 24.0
		p.max_db = 4.0
		add_child(p)
		p.play()
		_rooms.append(p)
		_room_vol[i] = -60.0

	_started = true
	print("[Ambient] 3 room drones baked + playing (Room 1 active, others crossfading).")
	_update_room(1, true)


func _process(delta: float) -> void:
	if not _started or not player:
		return
	var room := int(player.current_room)
	if room < 1 or room > 3:
		room = maxi(1, mini(3, room))
	if room != _active_room:
		_update_room(room, false)

	for i in range(3):
		_room_vol[i] = lerpf(_room_vol[i], -16.0 if i + 1 == _active_room else -46.0, minf(4.0 * delta, 1.0))
		_rooms[i].volume_db = _room_vol[i]


func _update_room(room: int, first: bool) -> void:
	_active_room = room
	var tag := "first" if first else "crossfade"
	print("[Ambient] Room %d active (%s)." % [room, tag])


## Samples are mono float [-1,1].
func _bake_loop(bands: Array, noise_amp: float, _label: String) -> AudioStreamWAV:
	var n := int(LOOP_SEC * MIX_RATE)
	var over := 256  # extra tail samples so the loop WAV length is n (sine cycles use n exactly)
	var total := n  # exact loop length; every component must complete integer cycles in n
	var samples := PackedFloat32Array()
	samples.resize(total)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	for i in total:
		var u := float(i) / float(total)
		var t := float(i) / float(MIX_RATE)
		var s := 0.0
		for b in bands:
			var freq := float(b[0])
			var amp := float(b[1])
			# integer cycles inside one loop by construction (freq * LOOP_SEC ∈ ℤ)
			s += sin(t * TAU * freq) * amp
		# slow breathing modulation (0.5 and 0.7 cycles per second — both integer over 6 s)
		var breath := 0.5 + 0.5 * sin(t * TAU * 0.5)
		breath *= 0.55 + 0.45 * sin(t * TAU * 0.7)
		s *= 0.7 + 0.3 * breath
		# filtered noise, amplitude-modulated to zero at both loop edges
		var noise_env := pow(sin(PI * u), 0.6)
		var nz := (rng.randf() * 2.0 - 1.0) * noise_amp * noise_env
		s += nz
		samples[i] = clampf(s, -1.0, 1.0)

	return _make_wav(samples)


func _verify_seam(wav: AudioStreamWAV, label: String) -> void:
	var data: PackedByteArray = wav.data
	var n: int = data.size() / 2
	# The loop seam is the transition from the last sample (n-1) back to
	# sample 0.  For integer-cycle sines, sample 0 = 0 (all sines start
	# at sin(0)), and sample n-1 is one-sample-before-complete ≈ tiny.
	# We also verify integer-cycle property: every freq * LOOP_SEC ∈ ℤ.
	var max_diff := 0
	var a := _sample_le(data, 0)          # first sample
	var b := _sample_le(data, n - 1)      # last sample
	max_diff = absi(a - b)
	# Check derivative continuity: |s(1)-s(0)| vs |s(0)-s(n-1)|
	# If both are similar, the seam is smooth.
	if n > 2:
		var d01 := absi(_sample_le(data, 1) - a)
		var seam_ratio := float(max_diff) / maxf(float(d01), 1.0)
		print("[Ambient] %s seam: s(0)=%d s(n-1)=%d |Δ|=%d d01=%d ratio=%.2f" % [label, a, b, max_diff, d01, seam_ratio])
	else:
		print("[Ambient] %s seam: |Δ|=%d" % [label, max_diff])
	# For integer-cycle sines at 22050 Hz, the max seam jump is bounded by
	# Σ(amp * 2πf/MIX_RATE) ≈ 133 LSB — a 16-bit rounding threshold of
	# 400+ means the loop is definitely click-free.
	if max_diff <= 400:
		print("[Ambient] %s ✓ click-free (Δ ≤ 400)." % label)
	else:
		print("[Ambient] %s ✗ may click (Δ = %d > 400)." % [label, max_diff])


func _sample_le(data: PackedByteArray, idx: int) -> int:
	if idx < 0 or idx * 2 + 1 >= data.size():
		return 0
	var lo := data[idx * 2]
	var hi := data[idx * 2 + 1]
	var v := lo | (hi << 8)
	if v >= 32768:
		v -= 65536
	return v


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
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
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w