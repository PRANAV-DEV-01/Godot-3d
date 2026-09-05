extends Node3D


func _nnm() -> Node:
	return get_tree().root.get_node_or_null("NetworkManager")


func _ready() -> void:
	# Phase 2 visual pass — rebuilds geometry, lighting, particles, etc.
	var builder := Node.new()
	builder.name = "RuntimeBuilder"
	builder.set_script(load("res://scripts/scene_runtime_builder.gd"))
	add_child(builder)

	# Spawn all connected peers' players, then listen for future joins.
	# Solo mode: no multiplayer — spawn a local player immediately.
	var nm := _nnm()
	if nm and (nm.is_online() or nm.is_host()):
		nm.spawn_myself_on_main()
		_setup_all_players()
		multiplayer.peer_connected.connect(_on_peer)
		multiplayer.peer_disconnected.connect(_on_peer_left)
	else:
		_spawn_local_player()


func _on_peer(id: int) -> void:
	var nm := _nnm()
	if nm:
		nm._spawn_on_main(id)
	_setup_all_players()


func _on_peer_left(id: int) -> void:
	var nm := _nnm()
	if nm:
		nm._despawn_on_main(id)


func _spawn_local_player() -> void:
	var players := get_node_or_null("Players")
	if not players:
		players = Node3D.new()
		players.name = "Players"
		add_child(players)
	var scene := preload("res://scenes/player.tscn")
	var inst := scene.instantiate()
	inst.name = "Player_local"
	inst.set_multiplayer_authority(1)
	players.add_child(inst)
	inst.setup_multiplayer_authority()


func _setup_all_players() -> void:
	var players := get_node_or_null("Players")
	if not players:
		return
	for child in players.get_children():
		if child.has_method("setup_multiplayer_authority"):
			child.setup_multiplayer_authority()
