extends CanvasLayer

@onready var label: Label = $Label
@onready var player: CharacterBody3D = get_node("/root/Main/Player")


func _process(_delta: float) -> void:
	if not player or not label:
		return

	var state_name: String = player.get_state_name()
	var spd: float = player.get_speed()

	var dash_cd: float = player.dash_cooldown
	var dash_str: String = "READY" if dash_cd <= 0.0 else "%.1fs" % dash_cd

	var coyote_str: String = "ACTIVE" if player.coyote_timer > 0.0 else "inactive"
	var buffer_str: String = "ACTIVE" if player.jump_buffer > 0.0 else "inactive"

	var wall_run_str: String = ""
	if player.state == player.State.WALL_RUN:
		wall_run_str = "\nWall-Run: %.1fs" % player.wall_run_timer

	label.text = (
		"Room: %d\n" % player.current_room
		+ "State: %s\n" % state_name
		+ "Speed: %.1f u/s\n" % spd
		+ "Dash CD: %s\n" % dash_str
		+ "Coyote: %s | Buffer: %s" % [coyote_str, buffer_str]
		+ wall_run_str
	)
