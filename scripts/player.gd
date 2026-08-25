extends CharacterBody3D

## ── State Machine ──────────────────────────────────────────────────
enum State { GROUND, AIR, WALL_RUN, SLIDE, DASH }

var state: State = State.AIR

## ── Movement Tuning ────────────────────────────────────────────────
@export var move_speed   := 7.0
@export var sprint_speed := 11.0
@export var acceleration := 10.0
@export var friction     := 12.0
@export var gravity      := 22.0
@export var jump_velocity := 8.5

## ── Coyote & Buffer ────────────────────────────────────────────────
var coyote_timer  := 0.0
var jump_buffer   := 0.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12

## ── Wall Run ───────────────────────────────────────────────────────
var wall_run_timer := 0.0
var wall_run_normal := Vector3.ZERO
var wall_run_direction := Vector3.FORWARD
const WALL_RUN_MAX := 1.5
const WALL_GRAVITY_MULT := 0.15
const WALL_SPEED_MULT   := 1.15

## ── Slide ──────────────────────────────────────────────────────────
var slide_timer := 0.0
const SLIDE_DURATION := 0.8
const SLIDE_BURST_MULT := 1.3
var is_sliding := false

## ── Dash ───────────────────────────────────────────────────────────
var dash_timer := 0.0
var dash_cooldown := 0.0
const DASH_DISTANCE  := 6.0
const DASH_DURATION  := 0.15
const DASH_COOLDOWN  := 1.5
var dash_velocity := Vector3.ZERO
var is_dashing := false

## ── References ─────────────────────────────────────────────────────
@onready var camera_pivot: Node3D   = $CameraPivot
@onready var camera: Camera3D       = $CameraPivot/Camera3D
@onready var wall_left: RayCast3D   = $WallLeft
@onready var wall_right: RayCast3D  = $WallRight
@onready var ceiling_check: RayCast3D = $CeilingCheck

## ── Internal ───────────────────────────────────────────────────────
var camera_node: Node = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_node = camera


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_update_cooldowns(delta)

	match state:
		State.GROUND:  _state_ground(delta)
		State.AIR:     _state_air(delta)
		State.WALL_RUN: _state_wall_run(delta)
		State.SLIDE:   _state_slide(delta)
		State.DASH:    _state_dash(delta)

	move_and_slide()

## ── Cooldowns ──────────────────────────────────────────────────────
func _update_cooldowns(delta: float) -> void:
	if dash_cooldown > 0.0:
		dash_cooldown = maxf(dash_cooldown - delta, 0.0)


## ══════════════════════════════════════════════════════════════════════
##  STATE: GROUND
## ══════════════════════════════════════════════════════════════════════
func _state_ground(delta: float) -> void:
	coyote_timer = COYOTE_TIME

	var input_dir := _get_input_direction()
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else move_speed
	var desired := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)) * target_speed

	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	velocity.y = -0.1

	_apply_friction(delta, input_dir)

	if Input.is_action_just_pressed("jump") or jump_buffer > 0.0:
		_do_jump()
		return

	if Input.is_action_just_pressed("slide") and Input.is_action_pressed("sprint") \
		and input_dir.length() > 0.1:
		_enter_slide()
		return

	if _try_dash():
		return

	if not is_on_floor():
		state = State.AIR


## ══════════════════════════════════════════════════════════════════════
##  STATE: AIR
## ══════════════════════════════════════════════════════════════════════
func _state_air(delta: float) -> void:
	velocity.y -= gravity * delta

	var input_dir := _get_input_direction()
	var desired := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)) * move_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)

	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= 0.5

	if coyote_timer > 0.0:
		coyote_timer -= delta

	if jump_buffer > 0.0:
		jump_buffer -= delta

	if (Input.is_action_just_pressed("jump") or jump_buffer > 0.0) and coyote_timer > 0.0:
		_do_jump()
		return

	if Input.is_action_just_pressed("jump"):
		jump_buffer = JUMP_BUFFER

	var wall_info := _check_wall_run()
	if wall_info.hit:
		_enter_wall_run(wall_info.normal, wall_info.speed)
		return

	if _try_dash():
		return

	if is_on_floor():
		_land()


## ══════════════════════════════════════════════════════════════════════
##  STATE: WALL RUN
## ══════════════════════════════════════════════════════════════════════
func _state_wall_run(delta: float) -> void:
	wall_run_timer -= delta

	velocity.y = maxf(velocity.y, -(gravity * WALL_GRAVITY_MULT))

	var cur_speed := minf(Vector2(velocity.x, velocity.z).length(), sprint_speed)
	velocity.x = wall_run_direction.x * cur_speed * WALL_SPEED_MULT
	velocity.z = wall_run_direction.z * cur_speed * WALL_SPEED_MULT

	if Input.is_action_just_pressed("jump"):
		_exit_wall_run()
		velocity = wall_run_normal * sprint_speed + Vector3.UP * jump_velocity
		coyote_timer = 0.0
		state = State.AIR
		return

	if wall_run_timer <= 0.0:
		_exit_wall_run()
		state = State.AIR
		return

	# re-check wall contact each frame
	if wall_right.is_colliding():
		wall_run_normal = wall_right.get_collision_normal()
	elif wall_left.is_colliding():
		wall_run_normal = wall_left.get_collision_normal()
	else:
		_exit_wall_run()
		state = State.AIR
		return

	# keep direction alive
	wall_run_direction = _tangent_along_wall(wall_run_normal)

	if is_on_floor():
		_exit_wall_run()
		_land()

	if _try_dash():
		_exit_wall_run()
		return


## ══════════════════════════════════════════════════════════════════════
##  STATE: SLIDE
## ══════════════════════════════════════════════════════════════════════
func _state_slide(delta: float) -> void:
	slide_timer -= delta

	velocity.y -= gravity * delta

	velocity.x = move_toward(velocity.x, 0.0, (friction * 0.5) * delta)
	velocity.z = move_toward(velocity.z, 0.0, (friction * 0.5) * delta)

	if not is_on_floor():
		_exit_slide()
		state = State.AIR
		return

	if Input.is_action_just_pressed("jump"):
		_exit_slide()
		_do_jump()
		return

	var spd := Vector2(velocity.x, velocity.z).length()
	if slide_timer <= 0.0 or spd < 2.0:
		_exit_slide()
		return

	if _try_dash():
		_exit_slide()
		return


## ══════════════════════════════════════════════════════════════════════
##  STATE: DASH
## ══════════════════════════════════════════════════════════════════════
func _state_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = dash_velocity

	if dash_timer <= 0.0:
		is_dashing = false
		if is_on_floor():
			state = State.GROUND
		else:
			state = State.AIR


## ══════════════════════════════════════════════════════════════════════
##  HELPERS
## ══════════════════════════════════════════════════════════════════════

func _get_input_direction() -> Vector2:
	return Vector2(
		Input.get_axis("move_backward", "move_forward"),
		Input.get_axis("move_left", "move_right")
	).normalized()


func _apply_friction(delta: float, input_dir: Vector2) -> void:
	if input_dir.length() < 0.1:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)


func _do_jump() -> void:
	velocity.y = jump_velocity
	state = State.AIR
	coyote_timer = 0.0
	jump_buffer = 0.0


func _land() -> void:
	if camera_node and camera_node.has_method("on_land"):
		camera_node.on_land(velocity.y)
	coyote_timer = COYOTE_TIME
	state = State.GROUND


func _try_dash() -> bool:
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0 and not is_dashing:
		_apply_dash()
		return true
	return false


func _apply_dash() -> void:
	var input_dir := _get_input_direction()
	var dash_dir: Vector3
	if input_dir.length() > 0.1:
		dash_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	elif state == State.WALL_RUN:
		dash_dir = wall_run_normal.normalized()  # push away from wall
	else:
		dash_dir = -transform.basis.z

	dash_velocity = dash_dir * (DASH_DISTANCE / DASH_DURATION)
	dash_timer = DASH_DURATION
	dash_cooldown = DASH_COOLDOWN
	is_dashing = true
	state = State.DASH


func _enter_slide() -> void:
	state = State.SLIDE
	slide_timer = SLIDE_DURATION
	is_sliding = true

	var spd := Vector2(velocity.x, velocity.z).length()
	var burst_speed := maxf(spd, move_speed) * SLIDE_BURST_MULT
	var fwd := Vector3(velocity.x, 0, velocity.z).normalized()
	velocity.x = fwd.x * burst_speed
	velocity.z = fwd.z * burst_speed

	if camera_node and camera_node.has_method("start_slide"):
		camera_node.start_slide()


func _exit_slide() -> void:
	is_sliding = false
	state = State.GROUND
	if camera_node and camera_node.has_method("end_slide"):
		camera_node.end_slide()


## ── Wall Run Helpers ───────────────────────────────────────────────

class WallInfo:
	var hit := false
	var normal := Vector3.ZERO
	var speed := 0.0


## Compute the tangent direction along the wall surface that best
## aligns with the player's current horizontal velocity.
func _tangent_along_wall(wall_normal: Vector3) -> Vector3:
	var candidate_a := wall_normal.cross(Vector3.UP).normalized()
	var candidate_b := -candidate_a
	var vel_h := Vector3(velocity.x, 0, velocity.z)
	if vel_h.length_squared() < 0.01:
		# no horizontal velocity — default to player forward projected onto wall
		var fwd := -transform.basis.z
		return (fwd - wall_normal * fwd.dot(wall_normal)).normalized()
	if candidate_a.dot(vel_h) >= 0.0:
		return candidate_a
	return candidate_b


func _check_wall_run() -> WallInfo:
	var info := WallInfo.new()
	if state == State.WALL_RUN:
		return info

	var vel_h := Vector3(velocity.x, 0, velocity.z)
	var cur_speed := vel_h.length()

	# must be airborne, moving horizontally, not falling too fast
	if is_on_floor() or cur_speed < 1.0 or velocity.y < -12.0:
		return info

	if wall_right.is_colliding():
		info.hit = true
		info.normal = wall_right.get_collision_normal()
		info.speed = maxf(cur_speed, move_speed)
	elif wall_left.is_colliding():
		info.hit = true
		info.normal = wall_left.get_collision_normal()
		info.speed = maxf(cur_speed, move_speed)

	return info


func _enter_wall_run(wall_normal: Vector3, speed: float) -> void:
	state = State.WALL_RUN
	wall_run_timer = WALL_RUN_MAX
	wall_run_normal = wall_normal
	velocity.y = maxf(velocity.y, -2.0)

	wall_run_direction = _tangent_along_wall(wall_normal)
	velocity.x = wall_run_direction.x * speed
	velocity.z = wall_run_direction.z * speed

	if camera_node and camera_node.has_method("start_wall_run"):
		var side := 1 if wall_left.is_colliding() else -1
		camera_node.start_wall_run(side)


func _exit_wall_run() -> void:
	wall_run_timer = 0.0
	wall_run_normal = Vector3.ZERO
	wall_run_direction = Vector3.FORWARD
	if camera_node and camera_node.has_method("end_wall_run"):
		camera_node.end_wall_run()


func _get_wall_run_normal() -> Vector3:
	if wall_run_normal.length_squared() > 0.01:
		return wall_run_normal
	if wall_right.is_colliding():
		return wall_right.get_collision_normal()
	elif wall_left.is_colliding():
		return wall_left.get_collision_normal()
	return -transform.basis.z


## ── Debug Info ─────────────────────────────────────────────────────

func get_state_name() -> String:
	match state:
		State.GROUND:  return "GROUND"
		State.AIR:     return "AIR"
		State.WALL_RUN: return "WALL_RUN"
		State.SLIDE:   return "SLIDE"
		State.DASH:    return "DASH"
	return "?"


func get_speed() -> float:
	return Vector3(velocity.x, 0, velocity.z).length()
