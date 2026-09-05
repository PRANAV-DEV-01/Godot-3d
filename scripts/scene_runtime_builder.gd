extends Node
## Runtime scene builder — executes the Phase 2 visual pass that
## scene_builder.gd (an @tool EditorScript) was supposed to run once
## in the editor but never did.  Runs once on _ready, then removes
## itself from the tree.


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _build()
	queue_free()


func _build() -> void:
	var root := get_parent()
	if not root:
		return

	print("[Phase2-Runtime] Rebuilding room visuals (3-room course)...")

	# ── Strip old geometry ──────────────────────────────────────
	var room := root.get_node_or_null("Room")
	if room:
		for child in room.get_children():
			child.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# ── Room 1 — unchanged Phase 1/2 vertical dash + wall-run test floor ──
	_build_room_one(room)

	# ── Room 2 — slide + dash-required gap, offset +20 x ─────────
	var room2 := Node3D.new()
	room2.name = "Room2"
	room2.position = Vector3(20, 0, 0)
	root.add_child(room2)
	room2.owner = root.owner
	_build_room_two(room2)

	# ── Room 3 — vertical wall-run / climb / dash combo + finish, offset +42 x ──
	var room3 := Node3D.new()
	room3.name = "Room3"
	room3.position = Vector3(42, 0, 0)
	root.add_child(room3)
	room3.owner = root.owner
	_build_room_three(room3)

	# ── Shared systems ──────────────────────────────────────────
	_build_lighting(root)
	_build_particles(root)
	_build_dressing(room)
	_rebuild_env(root)
	_build_tramers(root)
	_build_managers(root)

	print("[Phase2-Runtime] Done! (3 rooms, 4 triggers)")


# ══════════════════════════════════════════════════════════════════════
#  ROOM BUILDERS
# ══════════════════════════════════════════════════════════════════════

func _build_room_one(room: Node3D) -> void:
	var mat_floor := _make_floor_mat()
	var mat_pw := _make_perim_wall_mat()
	var mat_wr1 := _make_wallrun_mat()
	var mat_wr2 := _make_wallrun_mat()
	var mat_plat := _make_platform_mat()
	var mat_ledge := _make_ledge_mat()

	_add_box(room, Vector3(20, 0.4, 20), Vector3.ZERO, mat_floor, "Floor", 1, "concrete")
	_add_box(room, Vector3(20, 6, 0.4), Vector3(0, 3, -9.8), mat_pw, "WallNorth", 1, "concrete")
	_add_box(room, Vector3(20, 6, 0.4), Vector3(0, 3, 9.8), mat_pw, "WallSouth", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 20), Vector3(9.8, 3, 0), mat_pw, "WallEast", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 20), Vector3(-9.8, 3, 0), mat_pw, "WallWest", 1, "concrete")
	_add_box(room, Vector3(0.4, 6, 10), Vector3(-2, 3, -2), mat_wr1, "WallRunLeft", 2, "metal")
	_add_box(room, Vector3(0.4, 6, 10), Vector3(2, 3, -2), mat_wr2, "WallRunRight", 2, "metal")
	_add_box(room, Vector3(4, 2, 4), Vector3(-6, 1, -6), mat_plat, "Platform", 1, "metal")
	_add_box(room, Vector3(5, 1.0, 2), Vector3(6, 0.5, -4), mat_ledge, "LedgeBlock", 1, "concrete")
	_add_box(room, Vector3(5, 0.4, 8), Vector3(6, 1.2, -4), mat_ledge, "LedgeTop", 1, "concrete")


func _build_room_two(room: Node3D) -> void:
	# Identity tint — slate blue (distinct from Room 1 grey and Room 3 amber).
	var mat_floor := _make_tinted_pbr(Color(0.20, 0.27, 0.36))
	var mat_pw := _make_tinted_pbr(Color(0.24, 0.30, 0.39))
	var mat_pit := _make_tinted_pbr(Color(0.15, 0.19, 0.26))
	var mat_barrier := _make_tinted_pbr(Color(0.30, 0.30, 0.33))

	# Run direction: -z, entrance → exit.
	_add_box(room, Vector3(12, 0.4, 18), Vector3(0, 0.2, 8), mat_floor, "FloorEntrance", 1, "concrete")
	_add_box(room, Vector3(13, 0.4, 5), Vector3(0, 0.2, -14), mat_floor, "FloorExit", 1, "concrete")
	_add_box(room, Vector3(13, 0.4, 9), Vector3(0, -5.8, -6), mat_pit, "PitFloor", 1, "concrete")
	# Slide-under barrier — spans the corridor width (x), thin in the run direction.
	# Layer 3 so the body collides AND the ceiling ray sees it.
	_add_box(room, Vector3(11.6, 1.2, 0.4), Vector3(0, 2.0, 10), mat_barrier, "SlideBarrier", 3, "metal")
	_add_box(room, Vector3(12, 6, 0.4), Vector3(0, 3, -16.7), mat_pw, "WallNorth", 1, "concrete")
	_add_box(room, Vector3(12, 6, 0.4), Vector3(0, 3, 17.2), mat_pw, "WallSouth", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 34), Vector3(6, 3, 0.2), mat_pw, "WallEast", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 34), Vector3(-6, 3, 0.2), mat_pw, "WallWest", 1, "concrete")

	# Glowing clearance strip on the barrier underside (visual affordance).
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(11.6, 0.05, 0.05)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, 1.382, 10)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(1.0, 0.72, 0.2)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 0.6, 0.15)
	strip_mat.emission_energy_multiplier = 1.8
	strip.set_surface_override_material(0, strip_mat)
	room.add_child(strip)
	strip.owner = room.owner

	# Dash-required gap z -11.5..-1.5 (10 m) between the two floor slabs.


func _build_room_three(room: Node3D) -> void:
	# Identity tint — warm grey/brown; amber reused for wall-run surfaces.
	var mat_floor := _make_tinted_pbr(Color(0.30, 0.28, 0.24))
	var mat_pw := _make_tinted_pbr(Color(0.34, 0.32, 0.28))
	var mat_pit := _make_tinted_pbr(Color(0.16, 0.18, 0.22))
	var mat_wr1 := _make_wallrun_mat()
	var mat_wr2 := _make_wallrun_mat()
	var mat_pad := _make_tinted_pbr(Color(0.25, 0.25, 0.27))

	# Run direction: -z; spawn at z=2.
	_add_box(room, Vector3(8, 0.4, 26), Vector3(0, 0.2, -10), mat_floor, "Floor", 1, "concrete")
	_add_box(room, Vector3(8, 6, 0.4), Vector3(0, 3, 3.4), mat_pw, "WallSouth", 1, "concrete")
	_add_box(room, Vector3(8, 6, 0.4), Vector3(0, 3, -23.4), mat_pw, "WallNorth", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 26), Vector3(4, 3, -10), mat_pw, "WallEast", 1, "concrete")
	_add_box_rot_y(room, Vector3(0.4, 6, 26), Vector3(-4, 3, -10), mat_pw, "WallWest", 1, "concrete")

	# Wall-run channel walls (layer 2 — pass-through, raycast surfaced).
	_add_box(room, Vector3(0.4, 7, 10), Vector3(-2, 3.5, -2), mat_wr1, "WallRunLeft", 2, "metal")
	_add_box(room, Vector3(0.4, 7, 10), Vector3(2, 3.5, -2), mat_wr2, "WallRunRight", 2, "metal")

	# Jump-able mid platform (top = floor + 1.35, feet y 1.75) before the gap.
	_add_box(room, Vector3(4, 1.35, 3), Vector3(0, 1.075, -9.5), mat_pad, "MidPlatform", 1, "metal")

	# Dash-required gap from the mid platform lip (z -8) to the finish pad lip (z -16).
	_add_box(room, Vector3(4, 0.5, 4), Vector3(0, 2.95, -18), mat_pad, "FinishPad", 1, "metal")
	_add_box(room, Vector3(4, 0.4, 9), Vector3(0, -5.8, -12.5), mat_pit, "PitCatch", 1, "concrete")

	# Glowing finish marker on the pad (built-in emission, no custom shader).
	_add_finish_marker(room)


func _add_finish_marker(room: Node3D) -> void:
	# Beacon pole
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.09
	cyl.height = 2.0
	pole.mesh = cyl
	pole.position = Vector3(0, 4.2, -18)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.32, 0.35)
	pole_mat.metallic = 0.7
	pole_mat.roughness = 0.4
	pole.set_surface_override_material(0, pole_mat)
	room.add_child(pole)
	pole.owner = room.owner

	# Glowing beacon orb
	var orb := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.3
	sp.height = 0.6
	orb.mesh = sp
	orb.position = Vector3(0, 5.5, -18)
	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(1.0, 0.88, 0.4)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.72, 0.2)
	orb_mat.emission_energy_multiplier = 3.0
	orb.set_surface_override_material(0, orb_mat)
	room.add_child(orb)
	orb.owner = room.owner

	# Base ring on the pad surface
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.9
	ring_mesh.bottom_radius = 0.9
	ring_mesh.height = 0.02
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 3.21, -18)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.85, 0.3)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.7, 0.2)
	ring_mat.emission_energy_multiplier = 2.0
	ring.set_surface_override_material(0, ring_mat)
	room.add_child(ring)
	ring.owner = room.owner


# ══════════════════════════════════════════════════════════════════════
#  TRAMERS — room transition triggers (Area3D, global coordinates).
# ══════════════════════════════════════════════════════════════════════

func _build_tramers(root: Node3D) -> void:
	# Room 1 → Room 2 (north end of the corridor).
	_add_trigger(root, "TriggerRoom1Exit",
		Vector3(0, 1.5, -8.4), Vector3(4, 3, 1.6),
		Vector3(20, 1.2, 15), 2, false, "Room1 exit")
	# Room 2 → Room 3 (on the exit slab).
	_add_trigger(root, "TriggerRoom2Exit",
		Vector3(20, 1.5, -14), Vector3(6, 3, 1.4),
		Vector3(42, 1.2, 1), 3, false, "Room2 exit")
	# Room 2 pit fallback — reset to the Room 2 spawn.
	_add_trigger(root, "TriggerRoom2PitReset",
		Vector3(20, -5.3, -6), Vector3(13, 0.6, 9),
		Vector3(20, 1.2, 15), 2, false, "Room2 pit fall")
	# Room 3 pit fallback — reset to the Room 3 spawn.
	_add_trigger(root, "TriggerRoom3PitReset",
		Vector3(42, -5.3, -12.5), Vector3(4, 0.6, 9),
		Vector3(42, 1.2, 1), 3, false, "Room3 pit fall")
	# Room 3 finish beacon — end of run, reset to the Room 1 spawn.
	_add_trigger(root, "TriggerFinish",
		Vector3(42, 4.2, -18), Vector3(4, 2.4, 4),
		Vector3(0, 1.2, 6), 1, true, "Room3 finish")


func _add_trigger(root: Node3D, trigger_name: String, pos: Vector3, size: Vector3,
		dest: Vector3, target_room: int, finish: bool, label: String) -> void:
	var area := Area3D.new()
	area.name = trigger_name
	area.set_script(load("res://scripts/room_trigger.gd"))
	area.position = pos
	root.add_child(area)
	area.owner = root.owner

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	area.add_child(col)
	col.owner = root.owner

	area.destination = dest
	area.target_room = target_room
	area.is_finish = finish
	area.label = label


# ══════════════════════════════════════════════════════════════════════
#  MATERIALS — Shader-based procedural PBR with noise detail.
# ══════════════════════════════════════════════════════════════════════

func _make_floor_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.28, 0.27, 0.26))
	mat.set_shader_parameter("roughness", 0.75)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 8.0)
	mat.set_shader_parameter("noise_strength", 0.12)
	mat.set_shader_parameter("tiling", Vector2(10.0, 10.0))
	return mat


func _make_perim_wall_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.32, 0.31, 0.30))
	mat.set_shader_parameter("roughness", 0.92)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 10.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(8.0, 2.0))
	return mat


func _make_wallrun_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.95, 0.58, 0.15))
	mat.set_shader_parameter("roughness", 0.92)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 10.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(8.0, 2.0))
	return mat


func _make_platform_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_platform_shader()
	mat.set_shader_parameter("base_color", Color(0.25, 0.25, 0.27))
	mat.set_shader_parameter("accent_color", Color(0.9, 0.55, 0.15))
	mat.set_shader_parameter("roughness", 0.4)
	mat.set_shader_parameter("metallic", 0.6)
	mat.set_shader_parameter("noise_scale", 28.0)
	return mat


func _make_ledge_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.35, 0.33, 0.30))
	mat.set_shader_parameter("roughness", 0.85)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 8.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(3.0, 1.0))
	return mat


## Per-room identity tint via the same noise PBR shader (no new shader).
func _make_tinted_pbr(base_color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", base_color)
	mat.set_shader_parameter("roughness", 0.9)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 10.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(8.0, 2.0))
	return mat


# ══════════════════════════════════════════════════════════════════════
#  SHADERS — Procedural PBR with noise-based detail.
# ══════════════════════════════════════════════════════════════════════

func _make_pbr_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.5);
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale : hint_range(0.1, 50.0) = 10.0;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.1;
uniform vec2 tiling = vec2(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
	           mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * tiling;
	// Coarse tile variation + fine-grain detail so near and far both look sane.
	float n = fbm(uv) * noise_strength;
	float n2 = fbm(uv * 2.0 + 17.0) * noise_strength * 0.7;
	float grain = fbm(uv * 8.0 + 101.0) * noise_strength * 0.35;
	vec3 col = base_color * (1.0 + n - noise_strength * 0.5);
	col *= 0.95 + n2;
	col *= 0.98 + grain;
	float r = clamp(roughness + (n + n2) * 0.3, 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = r;
	METALLIC = metallic;
	AO = clamp(1.0 - (n + n2) * 0.3, 0.0, 1.0);
}
"""
	return s


func _make_platform_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.25);
uniform vec3 accent_color : source_color = vec3(0.9, 0.55, 0.15);
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.6;
uniform float noise_scale : hint_range(1.0, 60.0) = 24.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
	           mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.12, 0.0, uv.y) + smoothstep(0.88, 1.0, uv.y);
	vec3 col = mix(base_color, accent_color, edge * 0.8);
	float d = noise(uv * noise_scale);
	float n = noise(uv * noise_scale * 3.0 + 100.0) * 0.08;
	float g = noise(uv * noise_scale * 8.0 + 211.0) * 0.05;
	col *= 0.94 + d * 0.12;
	col *= 0.98 + g;
	ALBEDO = col * (1.0 + n - 0.04);
	ROUGHNESS = clamp(roughness + n * 0.15, 0.0, 1.0);
	METALLIC = metallic;
}
"""
	return s


# ══════════════════════════════════════════════════════════════════════
#  GEOMETRY HELPERS
# ══════════════════════════════════════════════════════════════════════

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		box_name: String, layer := 1, surface := "concrete") -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 1
	body.set_meta("surface_type", surface)
	parent.add_child(body)
	body.owner = parent.owner

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	col.owner = parent.owner

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.set_surface_override_material(0, mat)
	body.add_child(mesh_inst)
	mesh_inst.owner = parent.owner


func _add_box_rot_y(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		box_name: String, layer := 1, surface := "concrete") -> void:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 1
	body.set_meta("surface_type", surface)
	parent.add_child(body)
	body.owner = parent.owner

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	col.owner = parent.owner

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.set_surface_override_material(0, mat)
	body.add_child(mesh_inst)
	mesh_inst.owner = parent.owner


# ══════════════════════════════════════════════════════════════════════
#  LIGHTING
# ══════════════════════════════════════════════════════════════════════

func _build_lighting(root: Node3D) -> void:
	# Remove old DirectionalLight3D
	for c in root.get_children():
		if c is DirectionalLight3D:
			c.queue_free()

	# Key light — warm afternoon sun through a high window
	var sun := DirectionalLight3D.new()
	sun.name = "SunKey"
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.3
	sun.directional_shadow_blend_splits = true
	sun.rotation_degrees = Vector3(-55, 30, 0)
	root.add_child(sun)
	sun.owner = root.owner

	# Fill light — cool blue from opposite side
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.6, 0.7, 0.9)
	fill.light_energy = 0.25
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-30, -150, 0)
	root.add_child(fill)
	fill.owner = root.owner

	# Accent spotlights on gameplay features
	_add_spot(root, Vector3(-2, 5.5, -2), Vector3(-90, 0, 0), 6.0, 0.6,
		Color(1.0, 0.75, 0.3), "SpotWallRunL")
	_add_spot(root, Vector3(2, 5.5, -2), Vector3(-90, 0, 0), 6.0, 0.6,
		Color(1.0, 0.78, 0.33), "SpotWallRunR")
	_add_spot(root, Vector3(-6, 4.5, -6), Vector3(-90, 0, 0), 5.0, 0.7,
		Color(1.0, 0.7, 0.3), "SpotPlatform")
	_add_spot(root, Vector3(0, 5.0, 4), Vector3(-90, 0, 0), 7.0, 0.35,
		Color(0.8, 0.85, 1.0), "SpotSlideArea")

	# Ambient fill omnis
	_add_omni(root, Vector3(-8, 4, -8), 8.0, 0.3, Color(0.9, 0.85, 0.7))
	_add_omni(root, Vector3(8, 4, 4), 8.0, 0.25, Color(0.7, 0.8, 0.9))

	# ── Room 2 accents ───────────────────────────────────────────
	_add_spot(root, Vector3(20, 5.2, 10), Vector3(-90, 0, 0), 7.0, 0.55,
		Color(1.0, 0.75, 0.3), "SpotBarrier2")
	_add_spot(root, Vector3(20, 4.8, -6), Vector3(-90, 0, 0), 6.0, 0.5,
		Color(0.6, 0.7, 1.0), "SpotGap2")
	_add_spot(root, Vector3(20, 5.0, 16), Vector3(-90, 0, 0), 6.0, 0.4,
		Color(0.85, 0.8, 0.95), "SpotSpawn2")

	# ── Room 3 accents ───────────────────────────────────────────
	_add_spot(root, Vector3(40, 5.6, -2), Vector3(-90, 0, 0), 7.0, 0.6,
		Color(1.0, 0.75, 0.3), "SpotChannelL3")
	_add_spot(root, Vector3(44, 5.6, -2), Vector3(-90, 0, 0), 7.0, 0.6,
		Color(1.0, 0.78, 0.33), "SpotChannelR3")
	_add_spot(root, Vector3(42, 6.0, -18), Vector3(-90, 0, 0), 8.0, 0.9,
		Color(1.0, 0.85, 0.5), "SpotFinish3")
	_add_spot(root, Vector3(42, 4.0, -13), Vector3(-90, 0, 0), 6.0, 0.4,
		Color(0.7, 0.75, 0.95), "SpotGap3")

	_add_omni(root, Vector3(20, 3.5, 0), 9.0, 0.25, Color(0.9, 0.85, 0.7))
	_add_omni(root, Vector3(42, 3.5, -9), 9.0, 0.25, Color(0.9, 0.85, 0.7))
	_add_omni(root, Vector3(42, 5.0, -18), 6.0, 0.8, Color(1.0, 0.8, 0.4))


func _add_spot(parent: Node3D, pos: Vector3, rot: Vector3, range_: float,
		energy: float, col: Color, spot_name: String) -> void:
	var spot := SpotLight3D.new()
	spot.name = spot_name
	spot.position = pos
	spot.rotation_degrees = rot
	spot.light_color = col
	spot.light_energy = energy
	spot.spot_range = range_
	spot.spot_angle = 45.0
	spot.spot_attenuation = 1.5
	parent.add_child(spot)
	spot.owner = parent.owner


func _add_omni(parent: Node3D, pos: Vector3, range_: float,
		energy: float, col: Color) -> void:
	var omni := OmniLight3D.new()
	omni.position = pos
	omni.light_color = col
	omni.light_energy = energy
	omni.omni_range = range_
	omni.omni_attenuation = 1.2
	parent.add_child(omni)
	omni.owner = parent.owner


# ══════════════════════════════════════════════════════════════════════
#  PARTICLES
# ══════════════════════════════════════════════════════════════════════

func _build_particles(root: Node3D) -> void:
	var player := _find_player(root)
	if not player:
		return

	# 1) Ambient dust motes — parented to Player so feedback_manager + verify_structure
	# can find it under Player/DustMotes.  Position is local to the Player root.
	var dust := GPUParticles3D.new()
	dust.name = "DustMotes"
	dust.amount = 60
	dust.lifetime = 6.0
	dust.position = Vector3(0, 1.5, 0)
	dust.visibility_aabb = AABB(Vector3(-30, -4, -18), Vector3(66, 9, 34))
	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_mat.emission_box_extents = Vector3(32, 4, 16)
	dust_mat.direction = Vector3(0, 0.2, 0)
	dust_mat.spread = 30.0
	dust_mat.initial_velocity_min = 0.05
	dust_mat.initial_velocity_max = 0.15
	dust_mat.gravity = Vector3(0, 0.02, 0)
	dust_mat.scale_min = 0.015
	dust_mat.scale_max = 0.04
	dust_mat.color = Color(0.9, 0.88, 0.8)
	dust_mat.color_ramp = _make_gradient_tex(_make_fade_ramp())
	dust.process_material = dust_mat
	dust.draw_pass_1 = _make_dust_billboard()
	player.add_child(dust)
	dust.owner = root.owner

	# 2) Wall-run sparks
	var sparks := GPUParticles3D.new()
	sparks.name = "WallSparks"
	sparks.amount = 12
	sparks.lifetime = 0.3
	sparks.one_shot = true
	sparks.emitting = false
	var spark_mat := ParticleProcessMaterial.new()
	spark_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	spark_mat.direction = Vector3(0, 0.5, 0)
	spark_mat.spread = 60.0
	spark_mat.initial_velocity_min = 1.0
	spark_mat.initial_velocity_max = 3.0
	spark_mat.gravity = Vector3(0, -8, 0)
	spark_mat.scale_min = 0.02
	spark_mat.scale_max = 0.06
	spark_mat.color = Color(1.0, 0.8, 0.3)
	spark_mat.color_ramp = _make_gradient_tex(_make_spark_ramp())
	sparks.process_material = spark_mat
	sparks.draw_pass_1 = _make_dust_billboard()
	player.add_child(sparks)
	sparks.owner = root.owner

	# 3) Landing dust puff
	var puff := GPUParticles3D.new()
	puff.name = "LandingPuff"
	puff.amount = 15
	puff.lifetime = 0.5
	puff.one_shot = true
	puff.emitting = false
	var puff_mat := ParticleProcessMaterial.new()
	puff_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	puff_mat.emission_sphere_radius = 0.3
	puff_mat.direction = Vector3(0, 0.5, 0)
	puff_mat.spread = 80.0
	puff_mat.initial_velocity_min = 0.5
	puff_mat.initial_velocity_max = 2.0
	puff_mat.gravity = Vector3(0, -4, 0)
	puff_mat.scale_min = 0.08
	puff_mat.scale_max = 0.2
	puff_mat.damping_min = 3.0
	puff_mat.damping_max = 6.0
	puff_mat.color = Color(0.7, 0.68, 0.62)
	puff_mat.color_ramp = _make_gradient_tex(_make_fade_ramp())
	puff.process_material = puff_mat
	puff.draw_pass_1 = _make_dust_billboard()
	player.add_child(puff)
	puff.owner = root.owner

	# 4) Slide dust
	var sdust := GPUParticles3D.new()
	sdust.name = "SlideDust"
	sdust.amount = 8
	sdust.lifetime = 0.4
	sdust.one_shot = false
	sdust.emitting = false
	var sdust_mat := ParticleProcessMaterial.new()
	sdust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sdust_mat.emission_sphere_radius = 0.2
	sdust_mat.direction = Vector3(0, 0.3, 0)
	sdust_mat.spread = 40.0
	sdust_mat.initial_velocity_min = 0.3
	sdust_mat.initial_velocity_max = 1.0
	sdust_mat.gravity = Vector3(0, -3, 0)
	sdust_mat.scale_min = 0.05
	sdust_mat.scale_max = 0.12
	sdust_mat.color = Color(0.65, 0.63, 0.58)
	sdust_mat.color_ramp = _make_gradient_tex(_make_fade_ramp())
	sdust.process_material = sdust_mat
	sdust.draw_pass_1 = _make_dust_billboard()
	player.add_child(sdust)
	sdust.owner = root.owner

	# 5) Dash trail
	var dash := GPUParticles3D.new()
	dash.name = "DashTrail"
	dash.amount = 20
	dash.lifetime = 0.25
	dash.one_shot = true
	dash.emitting = false
	var dash_mat := ParticleProcessMaterial.new()
	dash_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dash_mat.emission_sphere_radius = 0.2
	dash_mat.direction = Vector3(0, 0, 1)
	dash_mat.spread = 15.0
	dash_mat.initial_velocity_min = 0.5
	dash_mat.initial_velocity_max = 1.5
	dash_mat.gravity = Vector3.ZERO
	dash_mat.scale_min = 0.04
	dash_mat.scale_max = 0.1
	dash_mat.color = Color(0.7, 0.8, 1.0)
	dash_mat.color_ramp = _make_gradient_tex(_make_dash_ramp())
	dash.process_material = dash_mat
	dash.draw_pass_1 = _make_dust_billboard()
	player.add_child(dash)
	dash.owner = root.owner


func _make_fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.set_offset(0, 0.0)
	g.set_offset(1, 1.0)
	return g


func _make_spark_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.4))
	g.set_color(1, Color(1.0, 0.3, 0.1))
	g.set_offset(0, 0.0)
	g.set_offset(1, 1.0)
	return g


func _make_dash_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.9, 1.0, 0.9))
	g.set_color(1, Color(0.5, 0.6, 1.0, 0.0))
	g.set_offset(0, 0.0)
	g.set_offset(1, 1.0)
	return g


func _make_dust_billboard() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.5)
	q.surface_set_material(0, mat)
	return q


func _make_gradient_tex(g: Gradient) -> GradientTexture1D:
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


# ══════════════════════════════════════════════════════════════════════
#  SET DRESSING — simple primitives, no collision, purely visual.
# ══════════════════════════════════════════════════════════════════════

func _build_dressing(room: Node3D) -> void:
	var mat_pipe := _make_pipe_mat()
	var mat_beam := _make_beam_mat()
	var mat_crate := _make_crate_mat()

	# Support beams along north wall
	for x in [-7.0, -3.0, 1.0, 5.0, 7.0]:
		var beam := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 6.0, 0.15)
		beam.mesh = box
		beam.position = Vector3(x, 3.0, -9.5)
		beam.set_surface_override_material(0, mat_beam)
		room.add_child(beam)
		beam.owner = room.owner

	# Pipes running along east wall near ceiling
	for z in [-7.0, -2.0, 3.0, 7.0]:
		var pipe := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = 2.5
		pipe.mesh = cyl
		pipe.position = Vector3(9.5, 5.2, z)
		pipe.rotation_degrees.z = 90.0
		pipe.set_surface_override_material(0, mat_pipe)
		room.add_child(pipe)
		pipe.owner = room.owner

	# Horizontal pipe runs along north wall ceiling
	for y_off in [0.0, 0.3]:
		var pipe := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 18.0
		pipe.mesh = cyl
		pipe.position = Vector3(0, 5.5 + y_off, -9.5)
		pipe.rotation_degrees.x = 90.0
		pipe.set_surface_override_material(0, mat_pipe)
		room.add_child(pipe)
		pipe.owner = room.owner

	# Crates in corners
	_add_crate(room, Vector3(-8.5, 0.3, -8.5), Vector3(0.6, 0.6, 0.6), mat_crate)
	_add_crate(room, Vector3(-8.2, 0.3, -8.8), Vector3(0.5, 0.6, 0.5), mat_crate)
	_add_crate(room, Vector3(8.5, 0.3, 8.0), Vector3(0.7, 0.6, 0.7), mat_crate)
	_add_crate(room, Vector3(8.8, 0.9, 8.0), Vector3(0.5, 0.6, 0.5), mat_crate)
	_add_crate(room, Vector3(-8.0, 0.3, 7.5), Vector3(0.8, 0.6, 0.6), mat_crate)

	# Caution tape strip on floor near wall-run approach (visual marker)
	var tape := MeshInstance3D.new()
	var tape_mesh := BoxMesh.new()
	tape_mesh.size = Vector3(3.5, 0.01, 0.3)
	tape.mesh = tape_mesh
	tape.position = Vector3(0, 0.21, 2.5)
	var tape_mat := StandardMaterial3D.new()
	tape_mat.albedo_color = Color(0.9, 0.8, 0.1)
	tape_mat.roughness = 0.6
	tape.set_surface_override_material(0, tape_mat)
	room.add_child(tape)
	tape.owner = room.owner


func _add_crate(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.set_surface_override_material(0, mat)
	parent.add_child(mesh)
	mesh.owner = parent.owner


func _make_pipe_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.38)
	mat.metallic = 0.8
	mat.roughness = 0.35
	return mat


func _make_beam_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.28, 0.30)
	mat.metallic = 0.5
	mat.roughness = 0.6
	return mat


func _make_crate_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.38, 0.30)
	mat.metallic = 0.0
	mat.roughness = 0.85
	return mat


# ══════════════════════════════════════════════════════════════════════
#  ENVIRONMENT
# ══════════════════════════════════════════════════════════════════════

func _rebuild_env(root: Node3D) -> void:
	# Remove old WorldEnvironment
	for c in root.get_children():
		if c is WorldEnvironment:
			c.queue_free()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.35, 0.55)
	sky_mat.sky_horizon_color = Color(0.55, 0.55, 0.6)
	sky_mat.ground_bottom_color = Color(0.12, 0.10, 0.08)
	sky_mat.ground_horizon_color = Color(0.4, 0.38, 0.35)
	sky_mat.sun_angle_max = 30.0

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4

	# Tonemap
	env.tonemap_mode = 3  # TONE_MAP_ACES
	env.tonemap_white = 6.0

	# Glow / bloom
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5

	# Fog
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.65, 0.72)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.3

	# Volumetric fog
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_length = 30.0
	env.volumetric_fog_gi_inject = 0.3

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)
	world_env.owner = root.owner


# ══════════════════════════════════════════════════════════════════════
#  MANAGERS
# ══════════════════════════════════════════════════════════════════════

func _build_managers(root: Node3D) -> void:
	# Find the local player — may not exist yet in multiplayer (spawned later).
	var player = _find_player(root)

	# Ambient audio
	var amb := Node.new()
	amb.name = "AmbientAudio"
	amb.set_script(load("res://scripts/ambient_audio.gd"))
	root.add_child(amb)
	amb.owner = root.owner

	# Hitstop — time-scale micro-freeze (Layer 15, same as DebugHUD overlay layer)
	var hit := Node.new()
	hit.name = "Hitstop"
	hit.set_script(load("res://scripts/hitstop.gd"))
	root.add_child(hit)
	hit.owner = root.owner

	# Sound manager — baked 3D SFX (player children via player.add_child)
	var snd := Node.new()
	snd.name = "SoundManager"
	snd.set_script(load("res://scripts/sound_manager.gd"))
	if player:
		snd.set_meta("player_ref", player)
	root.add_child(snd)
	snd.owner = root.owner

	# Run HUD — live timer + results panel
	var hud := CanvasLayer.new()
	hud.name = "RunHUD"
	hud.set_script(load("res://scripts/run_hud.gd"))
	root.add_child(hud)
	hud.owner = root.owner

	# Finish FX — vignette/chromatic pulse overlay
	var fx := CanvasLayer.new()
	fx.name = "FinishFX"
	fx.set_script(load("res://scripts/finish_fx.gd"))
	root.add_child(fx)
	fx.owner = root.owner

	# Feedback manager — wire up particle + system references
	var fb := Node.new()
	fb.name = "FeedbackManager"
	fb.set_script(load("res://scripts/feedback_manager.gd"))
	if player:
		fb.set_meta("player_ref", player)
		fb.set_meta("sound_ref", snd)
		fb.set_meta("hitstop_ref", hit)
		fb.set_meta("dust_motes_ref", player.get_node_or_null("DustMotes"))
		fb.set_meta("dash_trail_ref", player.get_node_or_null("DashTrail"))
		fb.set_meta("wall_sparks_ref", player.get_node_or_null("WallSparks"))
		fb.set_meta("landing_puff_ref", player.get_node_or_null("LandingPuff"))
		fb.set_meta("slide_dust_ref", player.get_node_or_null("SlideDust"))
	root.add_child(fb)
	fb.owner = root.owner

	# Screenshot manager
	var ss := Node.new()
	ss.name = "ScreenshotManager"
	ss.set_script(load("res://scripts/screenshot_manager.gd"))
	root.add_child(ss)
	ss.owner = root.owner


## Find a local, player-controlled instance anywhere under Players/ (or a lone
## solo player).  Returns null if none exists yet (multiplayer spawn is delayed).
func _find_player(root: Node3D) -> Node3D:
	var players := root.get_node_or_null("Players")
	if players:
		for c in players.get_children():
			if c is CharacterBody3D and c.is_multiplayer_authority():
				return c as Node3D
		# Fall back to the first player if authority is 0/unknown.
		if players.get_child_count() > 0:
			return players.get_child(0) as Node3D
	return null
