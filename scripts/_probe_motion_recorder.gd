extends Node
## Records synthesized InputEventMouseMotion relative deltas for the
## TouchUI harness (proof that touch-drags emit the exact mouse-motion
## events desktop look consumes). Sink is a Callable set by the harness.
var sink: Callable

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if sink.is_valid():
			sink.call(e.relative)