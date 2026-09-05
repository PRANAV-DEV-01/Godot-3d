extends SceneTree
## Phase 5 network sync harness.
## Run two instances (host & client) and compare logged positions.
##
##   Host:   godot --path <proj> --script res://scripts/test_network.gd -- --role host
##   Client: godot --path <proj> --script res://scripts/test_network.gd -- --role client --ip 127.0.0.1 --host 127.0.0.1
##
## Each prints the local player's own position AND the replicated view of the
## remote peer, sampled every 0.5 s, to stdout (captured per-role by a runner).

const SAMPLE_HZ := 4.0
const DURATION := 10.0

var _role := "host"
var _host_addr := "127.0.0.1"
var _drive := "host"
var _t := 0.0
var _next_sample := 0.0
var _started := false
var _connect_req := false
var _setup_done := false
var _driven := false


func _init() -> void:
	Engine.max_physics_steps_per_frame = 8
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--role":
				if i + 1 < args.size():
					_role = args[i + 1]; i += 1
			"--host":
				if i + 1 < args.size():
					_host_addr = args[i + 1]; i += 1
			"--drive":
				if i + 1 < args.size():
					_drive = args[i + 1]; i += 1
		i += 1
	print("[NetTest] role=%s host=%s drive=%s" % [_role, _host_addr, _drive])


func _nm() -> Node:
	return root.get_node_or_null("NetworkManager")


func _nm_mp() -> MultiplayerAPI:
	var nm := _nm()
	if nm:
		return nm.multiplayer
	return null


func _process(delta: float) -> bool:
	_t += delta
	if not _started:
		if get_root().get_child_count() == 0:
			return false
		_started = true
		_connect()
		return false

	# Load the world scene once the network is actually connected.
	var main := root.get_node_or_null("Main")
	if main == null and _nm() and _nm().is_online():
		if change_scene_to_file("res://scenes/main.tscn") == OK:
			print("[NetTest] %s: world loaded at t=%.2f" % [_role, _t])

	if not _setup_done:
		_try_setup()
		return false

	if _t >= _next_sample:
		_next_sample = _t + (1.0 / SAMPLE_HZ)
		_log_sample()

	_drive_input()

	if _t >= DURATION:
		print("[NetTest] %s: DONE_%s" % [_role.to_upper(), "HOST" if _role == "host" else "CLIENT"])
		quit()
		return true
	return false


func _connect() -> void:
	var nm := _nm()
	if not nm:
		push_error("[NetTest] No NetworkManager autoload")
		quit()
		return
	if _role == "host":
		nm.host_game()
	else:
		nm.join_game(_host_addr)
	_connect_req = true
	print("[NetTest] %s: connect requested" % _role)


func _drive_input() -> void:
	if not _setup_done or _driven:
		return
	_driven = true
	match _drive:
		"both":
			pass
		"host":
			if _role != "host":
				return
		"client":
			if _role != "client":
				return
		"none":
			return
	Input.action_press("move_forward")
	Input.action_press("sprint")


func _try_setup() -> void:
	var main := root.get_node_or_null("Main")
	var players: Node = main.get_node_or_null("Players") if main else null
	if not players or players.get_child_count() == 0:
		return
	var mp := _nm_mp()
	if _role == "host":
		var remote := _find_peer(players, true, mp)
		if remote == null:
			return
	elif _role == "client":
		var local := _find_peer(players, false, mp)
		if local == null:
			return
	_setup_done = true
	_next_sample = _t + 1.0
	print("[NetTest] %s: setup ready (%d players)" % [_role, players.get_child_count()])
	# Phase 5: exercise the finish broadcast once from the host right after setup.
	if _role == "host":
		var nm := _nm()
		nm.rpc("announce_finish", nm.multiplayer.get_unique_id())
		print("[NetTest] host: announce_finish sent")
	_next_sample = _t


func _find_peer(players: Node, want_remote: bool, mp: MultiplayerAPI) -> CharacterBody3D:
	var my: int = mp.get_unique_id()
	for c in players.get_children():
		var pl := c as CharacterBody3D
		if pl:
			if (pl.get_multiplayer_authority() != my) == want_remote:
				return pl
	return null


func _my_player(players: Node, mp: MultiplayerAPI) -> CharacterBody3D:
	return _find_peer(players, false, mp)


func _log_sample() -> void:
	var nm := _nm()
	if not nm or not nm.is_online():
		return
	var main := root.get_node_or_null("Main")
	var players: Node = main.get_node_or_null("Players") if main else null
	if not players:
		return
	var mp := _nm_mp()
	var local := _my_player(players, mp)
	var remote := _find_peer(players, true, mp)
	var st := "%.2f" % _t
	if local:
		print("[NetTest][%s] local  t=%s pos=(%.2f, %.2f, %.2f) room=%d state=%d" % [
			_role, st,
			local.global_position.x, local.global_position.y, local.global_position.z,
			(int(local.current_room) if "current_room" in local else -1),
			(int(local.state) if "state" in local else -1)])
	if remote:
		print("[NetTest][%s] remote t=%s pos=(%.2f, %.2f, %.2f) room=%d state=%d" % [
			_role, st,
			remote.global_position.x, remote.global_position.y, remote.global_position.z,
			(int(remote.current_room) if "current_room" in remote else -1),
			(int(remote.state) if "state" in remote else -1)])