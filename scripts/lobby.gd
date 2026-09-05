extends Control
## Minimal multiplayer lobby — Host / Join / Solo Practice entry point.

@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var solo_btn: Button = %SoloBtn
@onready var ip_field: LineEdit = %IPField
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	solo_btn.pressed.connect(_on_solo)
	status_label.text = ""


func _on_host() -> void:
	NetworkManager.host_game()
	status_label.text = "Hosting — waiting for player..."
	_join_when_peer()


func _on_join() -> void:
	var addr := ip_field.text.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	NetworkManager.join_game(addr)
	status_label.text = "Connecting to %s..." % addr
	_join_when_peer()


func _on_solo() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _join_when_peer() -> void:
	# If already connected (host with instant local peer, or very fast LAN),
	# go immediately; otherwise wait for the first peer_connected signal.
	if multiplayer.get_peers().size() > 0 or NetworkManager.is_host():
		_to_game()
		return
	multiplayer.peer_connected.connect(func(_id): _to_game(), CONNECT_ONE_SHOT)


func _to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
