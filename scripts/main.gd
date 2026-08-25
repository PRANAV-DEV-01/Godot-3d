extends Node3D


func _ready() -> void:
	# Inject the runtime scene builder to apply Phase 2 visuals.
	# scene_builder.gd is an @tool EditorScript that was never run
	# in the editor, so the .tscn still has flat default materials.
	# This script rebuilds the room at runtime with shaders, lights,
	# particles, set dressing, and enhanced environment.
	var builder := Node.new()
	builder.name = "RuntimeBuilder"
	builder.set_script(load("res://scripts/scene_runtime_builder.gd"))
	add_child(builder)
