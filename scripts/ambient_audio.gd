extends Node
## Ambient audio drone — plays a low hum + wind via AudioStreamGenerator.
## Procedural fallback: real audio files would sound better.

var gen: AudioStreamGenerator
var ambient_player: AudioStreamPlayer
var time := 0.0


func _ready() -> void:
	gen = AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.5

	ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = gen
	ambient_player.volume_db = -18.0
	add_child(ambient_player)
	ambient_player.play()


func _process(delta: float) -> void:
	if not ambient_player.playing:
		ambient_player.play()

	var playback = ambient_player.get_stream_playback()
	if not playback:
		return

	time += delta
	var frames_available = playback.get_frames_available()
	for i in range(frames_available):
		var t := time + float(i) / gen.mix_rate
		# low 55 Hz hum + filtered wind noise
		var hum := sin(t * TAU * 55.0) * 0.08
		hum += sin(t * TAU * 82.5) * 0.04
		var wind := (randf() * 2.0 - 1.0) * 0.02 * (0.5 + 0.5 * sin(t * 0.3))
		var sample := hum + wind
		playback.push_frame(Vector2(sample, sample))
