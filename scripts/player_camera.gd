extends Camera3D

## ── Look ───────────────────────────────────────────────────────────
@export var sensitivity := 0.0025
@export var min_pitch   := -89.0
@export var max_pitch   :=  89.0

var yaw   := 0.0
var pitch := 0.0

## ── FOV Kick ───────────────────────────────────────────────────────
@onready var cam: Camera3D = self
const BASE_FOV    := 75.0
const KICK_FOV    := 8.0
const FOV_SPEED   := 6.0

## ── Head Bob ───────────────────────────────────────────────────────
var bob_timer   := 0.0
const BOB_H_FREQ := 9.0
const BOB_V_FREQ := 11.0
const BOB_H_AMP  := 0.025
const BOB_V_AMP  := 0.04
const BOB_SPEED_SCALE := 0.14

## ── Wall-Run Roll ──────────────────────────────────────────────────
var target_roll  := 0.0
var current_roll := 0.0
const WALL_ROLL_DEG := 14.0
const ROLL_SPEED    := 6.0

## ── Slide / Crouch ─────────────────────────────────────────────────
var slide_crouch := false
var crouch_t     := 0.0
const CROUCH_SPEED    := 8.0
const CROUCH_Y_OFFSET := -0.55

## ── Landing Dip ────────────────────────────────────────────────────
var landing_dip   := 0.0
var landing_timer := 0.0
const LANDING_DIP_AMT := -0.12
const LANDING_DIP_DUR := 0.12

## ── Player ref ─────────────────────────────────────────────────────
@onready var player: CharacterBody3D = get_parent().get_parent() as CharacterBody3D


func _ready() -> void:
	cam = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw   -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		pitch  = clampf(pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func _process(delta: float) -> void:
	_apply_look()
	_apply_fov(delta)
	_apply_roll(delta)
	_apply_crouch(delta)
	_apply_landing_dip(delta)

	# Compose camera local offset: head bob + landing dip
	var h_bob := 0.0
	var v_bob := 0.0
	if player.state == player.State.GROUND \
		and Vector2(player.velocity.x, player.velocity.z).length() > 1.5:
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		bob_timer += delta * spd * BOB_SPEED_SCALE
		var intensity := minf(spd / 8.0, 1.0)
		h_bob = sin(bob_timer * BOB_H_FREQ) * BOB_H_AMP * intensity
		v_bob = sin(bob_timer * BOB_V_FREQ) * BOB_V_AMP * intensity
	else:
		bob_timer = 0.0

	cam.position.x = lerpf(cam.position.x, h_bob, 8.0 * delta)
	cam.position.y = lerpf(cam.position.y, v_bob + landing_dip, 8.0 * delta)


## ── Look ───────────────────────────────────────────────────────────

func _apply_look() -> void:
	player.rotation.y = yaw
	rotation.x = pitch


## ── FOV ────────────────────────────────────────────────────────────

func _apply_fov(delta: float) -> void:
	var target_fov := BASE_FOV
	if player.is_dashing:
		target_fov = BASE_FOV + KICK_FOV
	elif player.state == player.State.GROUND and Input.is_action_pressed("sprint"):
		target_fov = BASE_FOV + KICK_FOV * 0.6

	cam.fov = lerpf(cam.fov, target_fov, FOV_SPEED * delta)


## ── Wall-Run Roll ──────────────────────────────────────────────────

func start_wall_run(side: int) -> void:
	target_roll = deg_to_rad(WALL_ROLL_DEG * side)


func end_wall_run() -> void:
	target_roll = 0.0


func _apply_roll(delta: float) -> void:
	current_roll = lerpf(current_roll, target_roll, ROLL_SPEED * delta)
	rotation.z = current_roll


## ── Slide / Crouch ─────────────────────────────────────────────────

func start_slide() -> void:
	slide_crouch = true


func end_slide() -> void:
	slide_crouch = false


func _apply_crouch(delta: float) -> void:
	var target := CROUCH_Y_OFFSET if slide_crouch else 0.0
	crouch_t = lerpf(crouch_t, target, CROUCH_SPEED * delta)
	position.y = crouch_t


## ── Landing Impact ─────────────────────────────────────────────────

func on_land(impact_velocity: float) -> void:
	if impact_velocity < -8.0:
		landing_dip = LANDING_DIP_AMT
		landing_timer = LANDING_DIP_DUR


func _apply_landing_dip(delta: float) -> void:
	if landing_timer > 0.0:
		landing_timer -= delta
		var t := 1.0 - (landing_timer / LANDING_DIP_DUR)
		landing_dip = LANDING_DIP_AMT * (1.0 - t * t)
	else:
		landing_dip = 0.0
