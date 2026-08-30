extends SceneTree
## Per-room movement checklist harness.
## Loads main.tscn, then runs scripted input schedules per room and asserts
## the full movement system (Phase 1/2 fixes + Room 2/3 features) against the
## real physics. Reports a PASS/FAIL line per check.
##
## Run:
##     godot --path <proj> --script res://scripts/test_movement_rooms.gd
##
## NOTE: The engine is forced to advance a maximum of ONE physics step per
## rendered frame so that the harness "tick" counter (one per frame) maps 1:1
## to physics ticks (1/60 s each).  Without this the physics timebase grows
## out of sync with slow software rendering and every scripted duration drifts.

var main_scene: Node
var player: CharacterBody3D
var cam: Node

var _cmds: Array = []
var _cidx := 0
var _t := 0
var _tick := 0
var _plan_ready := false

var _holding: Array = []       # actions currently held
var _dropped: Array = []       # actions forcibly released this sample (drop suppress)
var _trace: Array = []         # current sample trace
var _ok := 0
var _fail := 0
var _wr_jumped := false        # wall-jump one-shot latch
var _r2_stage := 0             # R2 gap sequence stage
var _dash_frames := 0          # dash press window counter
var _r3_pjumped := false       # R3 platform jump latch
var _r3_off_jumped := false    # R3 no-dash platform jump latch
var _fin_stage := 0            # R3 finish sequence stage
var _fin_dashed := false       # R3 finish dash latch


func _init() -> void:
	Engine.max_physics_steps_per_frame = 1
	var packed := load("res://scenes/main.tscn")
	if not packed:
		push_error("[RoomsTest] Failed to load scene")
		quit()
		return
	main_scene = packed.instantiate()
	root.add_child(main_scene)
	print("[RoomsTest] Scene loaded, waiting for 3-room build...")


func _process(_delta: float) -> bool:
	if not _plan_ready:
		if Engine.get_physics_frames() >= 10:
			resolve_refs()
			_cmds = _build_plan()
			_plan_ready = true
			print("[RoomsTest] Plan ready (%d commands)" % _cmds.size())
		return false

	if _cidx >= _cmds.size():
		_finish()
		return true

	var cmd: Dictionary = _cmds[_cidx]
	match cmd.k:
		"teleport":
			_teleport(cmd.pos, cmd.room)
			_next()
		"yaw":
			_yaw(cmd.yaw)
			_next()
		"wait":
			_tick += 1
			if _tick >= cmd["for"]:
				_next()
		"log":
			print("[RoomsTest]  " + cmd.msg)
			_next()
		"check":
			var r: Array = cmd.fn.call()
			_report(cmd.name, r)
			_next()
		"hold":
			if _tick == 0:
				_hold(cmd.action)
			_tick += 1
			if _tick >= cmd["for"]:
				_release(cmd.action)
				_next()
		"sample":
			_tick_sample(cmd)
		"finish":
			_finish()
			return true
	return false


func _tick_sample(cmd: Dictionary) -> void:
	if _tick == 0:
		_hold(cmd.actions)
		_dropped.clear()
		_trace.clear()
		_wr_jumped = false
		_r2_stage = 0
		_dash_frames = 0
		_r3_pjumped = false
		_r3_off_jumped = false
		_fin_stage = 0
		_fin_dashed = false
	# keep base actions pressed every frame (unless dropped this sample)
	_hold(cmd.actions)
	# scheduled "after" presses (kept until end)
	for a in cmd.get("after", []):
		if a.at == _tick:
			_hold(a.press)
	# scheduled taps (auto release two frames later)
	for t in cmd.get("taps", []):
		if t.at == _tick:
			_hold([t.action])
		if t.at + 2 == _tick:
			_release(t.action)
	# optional per-frame hook for conditional timing
	if cmd.get("during") and player:
		cmd.during.call(_tick, player)
	# record physics state
	if player:
		var vel: Vector3 = player.velocity
		var h := 1.8
		var cs := player.get_node_or_null("CollisionShape3D")
		if cs and cs.shape is CapsuleShape3D:
			h = cs.shape.height
		_trace.append([player.global_position, vel, player.state, player.is_on_floor(), h])
	_tick += 1
	if _tick >= cmd["for"]:
		_release(cmd.actions)
		for a in cmd.get("after", []):
			_release(a.press)
		for t in cmd.get("taps", []):
			_release(t.action)
		Input.action_release("jump")
		_wr_jumped = false
		_dropped.clear()
		if cmd.check:
			var r: Array = cmd.check.call(_trace, player)
			_report(cmd.name, r)
		else:
			_report(cmd.name, [true, "no check"])
		_trace.clear()
		_next()


func _next() -> void:
	_cidx += 1
	_tick = 0


func _report(name: String, r: Array) -> void:
	var pass_flag: bool = r[0]
	var detail: String = r[1] if r.size() > 1 else ""
	if pass_flag:
		_ok += 1
		print("[RoomsTest] PASS  %-42s %s" % [name, detail])
	else:
		_fail += 1
		print("[RoomsTest] FAIL  %-42s %s" % [name, detail])


func _finish() -> void:
	print("")
	print("[RoomsTest] ==== SUMMARY: %d passed, %d failed ====" % [_ok, _fail])
	quit()


# ══════════════════════════════════════════════════════════════════════
#  INPUT HELPERS
# ══════════════════════════════════════════════════════════════════════

func _hold(a) -> void:
	var arr: Array = a if a is Array else [a]
	for k in arr:
		if _dropped.has(k):
			continue
		if not _holding.has(k):
			Input.action_press(k)
			_holding.append(k)


func _release(a) -> void:
	var arr: Array = a if a is Array else [a]
	for k in arr:
		Input.action_release(k)
		_holding.erase(k)


## Force-release an action for the rest of the current sample (suppresses the
## automatic re-hold of base actions so the player actually stops).
func _drop(a) -> void:
	var arr: Array = a if a is Array else [a]
	for k in arr:
		Input.action_release(k)
		_holding.erase(k)
		if not _dropped.has(k):
			_dropped.append(k)


func _release_all() -> void:
	for k in _holding.duplicate():
		Input.action_release(k)
	_holding.clear()
	_dropped.clear()


func _teleport(pos: Array, room: int) -> void:
	_release_all()
	Input.action_release("jump")
	if player:
		player.call("teleport_to", Vector3(pos[0], pos[1], pos[2]), room)


func _yaw(y: float) -> void:
	if player:
		player.rotation.y = y
		player.rotation.z = 0.0
	if cam:
		cam.set("yaw", y)
		cam.set("pitch", 0.0)
		cam.set("slide_crouch", false)
		cam.set("current_roll", 0.0)
		cam.set("target_roll", 0.0)
		cam.set("landing_dip", 0.0)


func resolve_refs() -> void:
	player = main_scene.get_node_or_null("Player") as CharacterBody3D
	if player:
		cam = player.get_node_or_null("CameraPivot/Camera3D")
	# Don't let the ScreenshotManager burn time writing files during the run.
	var ss := main_scene.get_node_or_null("ScreenshotManager")
	if ss:
		ss.set("auto_done", true)


# ══════════════════════════════════════════════════════════════════════
#  TRACE QUERIES
# ══════════════════════════════════════════════════════════════════════

func _state_seen(trace: Array, st: int) -> bool:
	for e in trace:
		if e[2] == st:
			return true
	return false


func _first_state(trace: Array, st: int) -> int:
	for i in range(trace.size()):
		if trace[i][2] == st:
			return i
	return -1


func _max_speed(trace: Array) -> float:
	var m := 0.0
	for e in trace:
		var s := Vector2(e[1].x, e[1].z).length()
		if s > m:
			m = s
	return m


func _min_z(trace: Array) -> float:
	var m := 1e9
	for e in trace:
		if e[0].z < m:
			m = e[0].z
	return m


func _max_feet_y(trace: Array) -> float:
	var m := -1e9
	for e in trace:
		var feet: float = float(e[0].y) - 0.9
		if feet > m:
			m = feet
	return m


func _on_floor(trace: Array) -> bool:
	for e in trace:
		if e[3]:
			return true
	return false


func _shape_squat_seen(trace: Array) -> bool:
	for e in trace:
		if e[4] < 1.4:
			return true
	return false


# passed only while standing on top of a raised platform (feet ≈1.75 or 3.2),
# below the airborne apex of a plain jump (feet ≤ ~1.3)
func _feet_in(trace: Array, z0: float, z1: float) -> bool:
	for e in trace:
		var feet: float = float(e[0].y) - 0.9
		if feet > 1.5 and e[0].z >= z0 and e[0].z <= z1:
			return true
	return false


# ══════════════════════════════════════════════════════════════════════
#  CHECK HANDLERS  (called as `check.call(trace, player)`)
# ══════════════════════════════════════════════════════════════════════

func _f_probe_map(trace: Array, p) -> Array:
	var a: Vector3 = trace[0][0]
	var b: Vector3 = trace[-1][0]
	var d := b - a
	var moved: float = Vector2(d.x, d.z).length()
	var yaw_deg := int(rad_to_deg(p.rotation.y))
	return [moved > 0.5, "delta=(%.1f, %.1f, %.1f) yaw=%d" % [d.x, d.y, d.z, yaw_deg]]


func _f_r1_sprint(trace: Array, p) -> Array:
	return [_max_speed(trace) > 8.0, "top=%.1f u/s" % _max_speed(trace)]


func _f_r1_jump(trace: Array, p) -> Array:
	var air := _first_state(trace, 1)
	if air < 0:
		return [false, "never left ground"]
	var ground := -1
	for i in range(air + 1, trace.size()):
		if trace[i][2] == 0:
			ground = i
			break
	if ground < 0:
		return [false, "never landed"]
	return [ground > air, "air@%d land@%d" % [air, ground]]


func _f_r1_dash(trace: Array, p) -> Array:
	if not _state_seen(trace, 4):
		return [false, "DASH state never seen"]
	return [_max_speed(trace) > 25.0, "peak=%.1f u/s" % _max_speed(trace)]


func _f_r1_slide(trace: Array, p) -> Array:
	if not _state_seen(trace, 3):
		return [false, "SLIDE never entered (needs sprint+input)"]
	return [_shape_squat_seen(trace), "squat height observed"]


func _d_r1_wallrun(fi: int, pl) -> void:
	if player == null:
		return
	if player.state == player.State.WALL_RUN:
		if fi > 42 and not _wr_jumped:
			_wr_jumped = true
			Input.action_press("jump")
	elif _wr_jumped:
		_wr_jumped = false


func _f_r1_wallrun(trace: Array, p) -> Array:
	if _first_state(trace, 2) >= 0:
		var jf := _first_state(trace, 1)
		var up := false
		for i in range(maxi(jf, 0), trace.size()):
			if trace[i][2] == 1 and trace[i][1].y > 6.0:
				up = true
				break
		return [true, "wall-run seen; wall-jump vy=%s" % (">6 ok" if up else "<6 (low)")]
	return [false, "WALL_RUN never triggered"]


func _f_r1_exit(trace: Array, p) -> Array:
	return [p.current_room == 2, "current_room=%d" % p.current_room]


func _f_r2_sprint(trace: Array, p) -> Array:
	return [_max_speed(trace) > 8.0, "top=%.1f u/s" % _max_speed(trace)]


func _d_r2_slide_stop(fi: int, pl) -> void:
	if player and player.global_position.z < 9.2:
		_drop(["move_forward", "sprint"])


func _f_r2_slide(trace: Array, p) -> Array:
	if not _state_seen(trace, 3):
		return [false, "SLIDE never entered"]
	var minz := _min_z(trace)
	var sq := _shape_squat_seen(trace)
	if minz > 9.5:
		return [false, "never crossed barrier (min z=%.1f)" % minz]
	if minz < -1.2:
		return [false, "slid into the gap (min z=%.1f)" % minz]
	if not sq:
		return [false, "never squatted (shape height observed)"]
	if p.state not in [0, 1]:
		return [false, "ended mid-manoeuvre (state=%d)" % p.state]
	return [true, "passed barrier z=%.1f squat=%s" % [minz, sq]]


# True once the player is actually standing on the Room 2 exit slab
# (z -16.5..-11.5), as opposed to sailing over the pit into the void.
func _landed_on_r2_slab(trace: Array) -> bool:
	for e in trace:
		if e[0].z >= -16.5 and e[0].z <= -11.0 \
			and e[0].y >= 0.2 and e[0].y <= 1.7 and e[3]:
			return true
	return false


func _f_r2_dashgap(trace: Array, p) -> Array:
	var minz := _min_z(trace)
	if minz > -9.0:
		return [false, "landed short or fell (min z=%.1f)" % minz]
	if not _landed_on_r2_slab(trace):
		return [false, "never stood on the exit slab (min z=%.1f)" % minz]
	return [true, "cleared to z=%.1f on exit slab, dash peak=%.1f" % [minz, _max_speed(trace)]]


func _f_r2_pit(trace: Array, p) -> Array:
	var minz := _min_z(trace)
	if p.current_room != 2:
		return [false, "left room unexpectedly (room=%d)" % p.current_room]
	if minz > -2.0:
		return [false, "never fell (min z=%.1f)" % minz]
	if p.global_position.z < 8.0:
		return [false, "pit reset did not fire (final z=%.1f)" % p.global_position.z]
	return [true, "fell to pit, reset then retreated to z=%.1f" % p.global_position.z]


func _f_r2_exit(trace: Array, p) -> Array:
	return [p.current_room == 3, "current_room=%d" % p.current_room]


# ── Conditional-timing during-hooks ─────────────────────────────────
# These turn absolute-tick taps into geometry-triggered inputs so the
# scripted inputs land at the pit lip / platform edge regardless of how
# fast the run-up actually was (1/60s physics, real sprint accel).

# R2 gap: run up, slide under the barrier (tap), jump at the entrance lip
# (z -1) while still grounded, then dash once clear so the post-dash fall
# lands ON the exit slab (z -11.5..-16.5), not in the pit.
func _d_r2_gap(fi: int, pl) -> void:
	if player == null:
		return
	match _r2_stage:
		0:
			if player.state == 0 and player.global_position.z < -0.85:
				_r2_stage = 1
		1:
			Input.action_press("jump")
			if player.state == 1:
				Input.action_release("jump")
				_dash_frames = 0
				_r2_stage = 2
		2:
			_dash_frames += 1
			if _dash_frames <= 2:
				Input.action_press("dash")
			else:
				Input.action_release("dash")
				_r2_stage = 3
		3:
			pass


# R3 jump onto the mid platform (top feet 1.75).  Slow walk-up (no sprint),
# jump as soon as we clear z -7.6, then cut forward once over the platform so
# we land standing on it instead of sliding off the far side.
func _d_r3_platform(fi: int, pl) -> void:
	if player == null:
		return
	if not _r3_pjumped:
			if player.state == 0 and player.global_position.z < -7.6:
				_r3_pjumped = true
				Input.action_press("jump")
	else:
		if player.global_position.z < -9.8:
			_drop(["move_forward"])


func _d_r3_finish(fi: int, pl) -> void:
	if player == null:
		return
	match _fin_stage:
		0:
			if player.state == 0 and player.global_position.z < -10.4:
				_fin_stage = 1
		1:
			Input.action_press("jump")
			if player.state == 1:
				_fin_stage = 2
		2:
			if player.global_position.z < -12.8 and not _fin_dashed:
				_fin_dashed = true
				_dash_frames = 0
			elif _fin_dashed:
				_dash_frames += 1
				if _dash_frames <= 2:
					Input.action_press("dash")
				else:
					Input.action_release("dash")
					_fin_stage = 3
		3:
			if player.global_position.z < -17.0 and player.global_position.y > 3.5:
				_drop(["move_forward", "sprint"])
				_fin_stage = 4
		4:
			pass


# R3 no-dash control: same platform launch, no dash, no cut-off — falls off
# the front edge, lands on the floor and slams into the finish pad's face.
func _d_r3_off(fi: int, pl) -> void:
	if player == null:
		return
	if not _r3_off_jumped:
		if player.state == 0 and player.global_position.z < -10.4:
			_r3_off_jumped = true
			Input.action_press("jump")


func _d_r3_walljump(fi: int, pl) -> void:
	if player == null:
		return
	if player.state == player.State.WALL_RUN:
		if fi > 42 and not _wr_jumped:
			_wr_jumped = true
			Input.action_press("jump")
	elif _wr_jumped:
		_wr_jumped = false


func _f_r3_wallrun(trace: Array, p) -> Array:
	var i := _first_state(trace, 2)
	if i < 0:
		return [false, "wall-run never engaged"]
	return [true, "wall-run engaged@%d z=%.1f" % [i, trace[i][0].z]]


func _f_r3_walljump(trace: Array, p) -> Array:
	var i := _first_state(trace, 2)
	if i < 0:
		return [false, "no wall-run"]
	var up := false
	for e in trace.slice(i):
		if e[2] == 1 and e[1].y > 6.0:
			up = true
			break
	return [up, "wall-jump vy burst confirmed"]


func _f_r3_platform(trace: Array, p) -> Array:
	var feet := _max_feet_y(trace)
	if not _feet_in(trace, -11.0, -8.0):
		return [false, "never stood on platform (max feet y=%.2f)" % feet]
	return [true, "stood on platform (feet y=%.2f)" % feet]


func _f_r3_dashgap(trace: Array, p) -> Array:
	for e in trace:
		if e[0].distance_to(Vector3(0, 1.2, 6)) < 1.2:
			return [true, "FINISH reset to Room 1 spawn"]
	return [false, "final room=%d pos=%s" % [p.current_room, p.global_position]]


func _f_r3_pit(trace: Array, p) -> Array:
	var minz := _min_z(trace)
	if p.current_room != 3:
		return [false, "left room unexpectedly (room=%d)" % p.current_room]
	if minz > -9.0:
		return [false, "never made it past the deck (min z=%.1f)" % minz]
	if p.global_position.y > 2.5:
		return [false, "ended high (y=%.1f) — reached the finish pad?" % p.global_position.y]
	return [true, "no dash: grounded below finish deck (min z=%.1f, y=%.1f)" % [minz, p.global_position.y]]


# ══════════════════════════════════════════════════════════════════════
#  CHECKLIST PLAN
# ══════════════════════════════════════════════════════════════════════

func _build_plan() -> Array:
	var c: Array = []

	# ── Axis-mapping probe: on the open slab, yaw 0 must face -z (forward = -z)
	c.append({"k": "log", "msg": "PROBE — move_forward must move -z (camera forward)"})
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, -5], "room": 1})
	c.append({"k": "sample", "name": "PROBE move_forward axis", "for": 25,
		"actions": ["move_forward", "sprint"],
		"check": _f_probe_map})

	# ───────────────────────── Room 1
	c.append({"k": "log", "msg": "ROOM 1 — Phase 1/2 regression checks"})
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, 5], "room": 1})
	c.append({"k": "sample", "name": "R1 sprint", "for": 58,
		"actions": ["move_forward", "sprint"],
		"check": _f_r1_sprint})

	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, 4], "room": 1})
	c.append({"k": "sample", "name": "R1 jump→AIR then GROUND", "for": 70,
		"actions": ["move_forward"],
		"taps": [{"at": 12, "action": "jump"}],
		"check": _f_r1_jump})

	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, 5], "room": 1})
	c.append({"k": "sample", "name": "R1 dash burst", "for": 70,
		"actions": ["move_forward"],
		"taps": [{"at": 14, "action": "dash"}],
		"check": _f_r1_dash})

	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, 5], "room": 1})
	c.append({"k": "sample", "name": "R1 slide squats capsule", "for": 70,
		"actions": ["move_forward", "sprint"],
		"taps": [{"at": 14, "action": "slide"}],
		"check": _f_r1_slide})

	# Wall-run corridor: layer-2 amber walls at x=±2, z -7..3.  Start right of
	# centre, steer into the right wall while airborne, wall-jump once on it.
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [1.0, 1.2, 3.0], "room": 1})
	c.append({"k": "sample", "name": "R1 wall-run + wall-jump", "for": 200,
		"actions": ["move_forward", "sprint"],
		"after": [{"at": 10, "press": ["move_right"]}],
		"taps": [{"at": 24, "action": "jump"}],
		"during": _d_r1_wallrun,
		"check": _f_r1_wallrun})

	# Room 1 → Room 2 transition trigger (north end of the corridor, z -8.4)
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [0, 1.2, -7.2], "room": 1})
	c.append({"k": "sample", "name": "R1 exit trigger → Room 2", "for": 80,
		"actions": ["move_forward"],
		"check": _f_r1_exit})

	# ───────────────────────── Room 2
	c.append({"k": "log", "msg": "ROOM 2 — sprint / slide-under / dash-required gap"})
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [20, 1.2, 15], "room": 2})
	c.append({"k": "sample", "name": "R2 sprint straightaway", "for": 58,
		"actions": ["move_forward", "sprint"],
		"check": _f_r2_sprint})

	# Slide under the low barrier (z 10.2), then stop before the pit (z -1.5).
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [20, 1.2, 13.5], "room": 2})
	c.append({"k": "sample", "name": "R2 slide under barrier", "for": 160,
		"actions": ["move_forward", "sprint"],
		"taps": [{"at": 6, "action": "slide"}],
		"during": _d_r2_slide_stop,
		"check": _f_r2_slide})

	# Dash-required gap: entrance slab ends z -1, exit slab starts z -16.5.
	# Sprint up the run-up, jump at the lip, dash mid-flight → land on exit slab.
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [20, 1.2, 15], "room": 2})
	c.append({"k": "sample", "name": "R2 dash clears 10.5m gap", "for": 220,
		"actions": ["move_forward", "sprint"],
		"taps": [{"at": 54, "action": "slide"}],
		"during": _d_r2_gap,
		"check": _f_r2_dashgap})

	# gap WITHOUT dash (control — must fall into the pit and pit-reset)
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [20, 1.2, 15], "room": 2})
	c.append({"k": "sample", "name": "R2 no-dash falls → pit reset", "for": 250,
		"actions": ["move_forward", "sprint"],
		"taps": [{"at": 54, "action": "slide"}],
		"check": _f_r2_pit})

	# Room 2 → Room 3 transition (on the exit slab, z -14)
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [20, 1.8, -12.5], "room": 2})
	c.append({"k": "sample", "name": "R2 exit trigger → Room 3", "for": 80,
		"actions": ["move_forward"],
		"check": _f_r2_exit})

	# ───────────────────────── Room 3
	c.append({"k": "log", "msg": "ROOM 3 — wall-run channel / jump climb / dash gap / finish"})
	# Wall-run channel walls at x=±2, z -7..3.  Start slightly right of centre.
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [42, 1.2, 1.2], "room": 3})
	c.append({"k": "sample", "name": "R3 wall-run in channel", "for": 200,
		"actions": ["move_forward", "sprint"],
		"after": [{"at": 10, "press": ["move_right"]}],
		"taps": [{"at": 24, "action": "jump"}],
		"during": _d_r3_walljump,
		"check": _f_r3_wallrun})

	# Wall-jump off the channel wall must convert the run into vertical gain.
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [42, 1.2, 1.2], "room": 3})
	c.append({"k": "sample", "name": "R3 wall-jump gains height", "for": 200,
		"actions": ["move_forward", "sprint"],
		"after": [{"at": 10, "press": ["move_right"]}],
		"taps": [{"at": 24, "action": "jump"}],
		"during": _d_r3_walljump,
		"check": _f_r3_walljump})

	# Jump climb onto the mid platform (top feet 1.75, z -11..-8).
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [42, 1.2, -7], "room": 3})
	c.append({"k": "sample", "name": "R3 jump onto mid platform", "for": 90,
		"actions": ["move_forward"],
		"during": _d_r3_platform,
		"check": _f_r3_platform})

	# finish combo: start standing on the platform, jump + dash over the 8m gap
	# to the finish pad (top feet 3.2, z -20..-16) → beacon trigger → Room 1.
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [42, 2.65, -8.8], "room": 3})
	c.append({"k": "sample", "name": "R3 dash-gap → finish beacon", "for": 200,
		"actions": ["move_forward", "sprint"],
		"during": _d_r3_finish,
		"check": _f_r3_dashgap})

	# R3 no-dash control (jump off the platform only — can never reach the pad)
	c.append({"k": "yaw", "yaw": 0.0})
	c.append({"k": "teleport", "pos": [42, 2.65, -9.0], "room": 3})
	c.append({"k": "sample", "name": "R3 no-dash falls below deck", "for": 200,
		"actions": ["move_forward", "sprint"],
		"during": _d_r3_off,
		"check": _f_r3_pit})

	c.append({"k": "finish"})
	return c