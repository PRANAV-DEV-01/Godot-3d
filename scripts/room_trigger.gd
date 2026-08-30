extends Area3D
## Room transition trigger.
## Configure `destination`, `target_room`, `is_finish` and `label` after
## instantiation (the runtime builder does this) before adding to the tree.

var destination := Vector3.ZERO
var target_room := 1
var is_finish := false
var label := "trigger"

signal room_entered(player: CharacterBody3D)


func _init() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	room_entered.emit(body)
	if is_finish:
		print("[RoomTrigger] %s: FINISH — run complete, resetting player to Room %d start." % [label, target_room])
	else:
		print("[RoomTrigger] %s: advancing to Room %d." % [label, target_room])
	body.call("teleport_to", destination, target_room)