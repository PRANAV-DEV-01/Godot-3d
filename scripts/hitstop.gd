extends Node
## Hit-stop — micro time-scale dip (1-3 rendered frames near zero) on hard
## landings and dash end/impact. Subtle by design: 2 frames at 0.05 scale is
## ~33 ms of "freeze" on a 60 Hz display, well below the disorienting range.

var _frames_left := 0
var _scale := 1.0
var _restore := 1.0


func _ready() -> void:
	_scale = Engine.time_scale


func hit(scale: float, frames: int) -> void:
	if frames <= 0:
		return
	_restore = Engine.time_scale
	_scale = scale
	_frames_left = frames
	Engine.time_scale = scale


func _process(_delta: float) -> void:
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left <= 0:
			Engine.time_scale = _restore
			_scale = _restore