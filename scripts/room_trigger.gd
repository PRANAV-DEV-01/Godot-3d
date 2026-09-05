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
		# Let HUD + finish FX nodes know the run ended (before the teleport
		# resets the player state; they freeze their timers / play the pulse).
		for node in get_tree().get_nodes_in_group("finish_listeners"):
			if node.has_method("on_finish"):
				node.on_finish()
		# Phase 5: tell the remote racer this (local) player finished.
		# Remote replicas are frozen with collision disabled, so a finish here
		# can only come from this peer's own player.
		if get_tree().has_multiplayer_peer() and body.is_multiplayer_authority() \
				and body.get_multiplayer_authority() == multiplayer.get_unique_id():
			var nm := get_tree().root.get_node_or_null("NetworkManager") as Node
			if nm and nm.has_method("rpc"):
				nm.rpc("announce_finish", multiplayer.get_unique_id())
	else:
		print("[RoomTrigger] %s: advancing to Room %d." % [label, target_room])
	body.call("teleport_to", destination, target_room)