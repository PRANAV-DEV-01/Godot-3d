extends Node
## Lightweight multiplayer manager — ENet peer setup, peer spawn/despawn.
## Phase 5 foundation: 2-player, local-authority, no anti-cheat.

const PORT := 7777

var _is_host := false
var _peer: ENetMultiplayerPeer


func is_host() -> bool:
	return _is_host


func is_online() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host_game() -> void:
	_peer = ENetMultiplayerPeer.new()
	_peer.create_server(PORT, 1)
	multiplayer.multiplayer_peer = _peer
	_is_host = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Net] Hosting on port %d" % PORT)


func join_game(address: String = "127.0.0.1") -> void:
	_peer = ENetMultiplayerPeer.new()
	_peer.create_client(address, PORT)
	multiplayer.multiplayer_peer = _peer
	_is_host = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[Net] Joining %s:%d" % [address, PORT])


func disconnect_game() -> void:
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_is_host = false
	print("[Net] Disconnected")


func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)
	if _is_host:
		_spawn_on_main(id)
		for other_id in multiplayer.get_peers():
			if other_id != id:
				rpc("_rpc_spawn", other_id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	_despawn_on_main(id)
	for other_id in multiplayer.get_peers():
		rpc("_rpc_despawn", id)


# ── Scene-local helpers (called from Main.gd _ready) ───────────────

func spawn_myself_on_main() -> void:
	var my_id := multiplayer.get_unique_id()
	_spawn_on_main(my_id)
	for other_id in multiplayer.get_peers():
		_spawn_on_main(other_id)


# ── Private ─────────────────────────────────────────────────────────

func _spawn_on_main(peer_id: int) -> void:
	var players := _get_players()
	if not players:
		return
	var name_ := "Player_%d" % peer_id
	if players.has_node(name_):
		return
	var scene := preload("res://scenes/player.tscn")
	var inst := scene.instantiate()
	inst.name = name_
	inst.set_multiplayer_authority(peer_id)
	players.add_child(inst)


func _despawn_on_main(peer_id: int) -> void:
	var players := _get_players()
	if not players:
		return
	var node := players.get_node_or_null("Player_%d" % peer_id)
	if node:
		node.queue_free()


func _get_players() -> Node:
	var main := get_tree().current_scene
	if main and main.name == "Main":
		return main.get_node_or_null("Players")
	return null


# ── RPCs (called by remote peers) ──────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_spawn(peer_id: int) -> void:
	_spawn_on_main(peer_id)


@rpc("any_peer", "reliable")
func _rpc_despawn(peer_id: int) -> void:
	_despawn_on_main(peer_id)


## Called by the peer whose local player crossed the finish beacon, so the
## remote racer sees "Player X finished!" (Phase 5 race awareness).
@rpc("any_peer", "reliable", "call_remote")
func announce_finish(finisher_id: int) -> void:
	var who := "Host(1)" if finisher_id == 1 else "Client(%d)" % finisher_id
	print("[Net] Player %s finished!" % who)
	finish_reported.emit(finisher_id)


## Emitted on receiving peers when the remote racer crosses the finish.
signal finish_reported(finisher_id: int)
