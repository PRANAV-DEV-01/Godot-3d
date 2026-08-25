@tool
extends EditorScript
## Run this ONCE from Script Editor to rebuild main.tscn with Phase 2 polish.
## After running, disable or delete this file — it's a one-shot generator.

func _run() -> void:
	var scene_root := get_scene()
	if not scene_root:
		push_error("No scene open")
		return

	print("[Phase2] Building polished scene...")

	# ── Strip old geometry ──────────────────────────────────────
	var room = scene_root.get_node_or_null("Room")
	if room:
		for child in room.get_children():
			child.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# ── Materials ───────────────────────────────────────────────
	var mat_floor := _make_floor_mat()
	var mat_wall := _make_wall_mat()
	var mat_wr1 := _make_wallrun_mat(Color(0.15, 0.65, 0.3))
	var mat_wr2 := _make_wallrun_mat(Color(0.2, 0.7, 0.35))
	var mat_plat := _make_platform_mat()
	var mat_ledge := _make_ledge_mat()

	# ── Floor ───────────────────────────────────────────────────
	_add_box(room, Vector3(20, 0.4, 20), Vector3.ZERO, mat_floor, "Floor")
	# ── Perimeter walls ─────────────────────────────────────────
	var mat_pw := _make_perim_wall_mat()
	_add_box(room, Vector3(20, 6, 0.4), Vector3(0, 3, -9.8), mat_pw, "WallNorth")
	_add_box(room, Vector3(20, 6, 0.4), Vector3(0, 3, 9.8), mat_pw, "WallSouth")
	_add_box_rot_y(room, Vector3(0.4, 6, 20), Vector3(9.8, 3, 0), mat_pw, "WallEast")
	_add_box_rot_y(room, Vector3(0.4, 6, 20), Vector3(-9.8, 3, 0), mat_pw, "WallWest")
	# ── Wall-run walls ──────────────────────────────────────────
	_add_box(room, Vector3(0.4, 6, 10), Vector3(-2, 3, -2), mat_wr1, "WallRunLeft", 2)
	_add_box(room, Vector3(0.4, 6, 10), Vector3(2, 3, -2), mat_wr2, "WallRunRight", 2)
	# ── Platform ────────────────────────────────────────────────
	_add_box(room, Vector3(4, 2, 4), Vector3(-6, 1, -6), mat_plat, "Platform")
	# ── Ledge ───────────────────────────────────────────────────
	_add_box(room, Vector3(5, 1.0, 2), Vector3(6, 0.5, -4), mat_ledge, "LedgeBlock")
	_add_box(room, Vector3(5, 0.4, 8), Vector3(6, 1.2, -4), mat_ledge, "LedgeTop")

	# ── Lighting ────────────────────────────────────────────────
	_build_lighting(scene_root)

	# ── Particles ───────────────────────────────────────────────
	_build_particles(scene_root)

	# ── Set dressing ────────────────────────────────────────────
	_build_dressing(room)

	# ── Environment ─────────────────────────────────────────────
	_rebuild_env(scene_root)

	# ── Managers ────────────────────────────────────────────────
	_build_managers(scene_root)

	# ── Save ────────────────────────────────────────────────────
	var packed := PackedScene.new()
	packed.pack(scene_root)
	var err := ResourceSaver.save(packed, "res://scenes/main.tscn")
	if err == OK:
		print("[Phase2] main.tscn saved successfully!")
	else:
		push_error("[Phase2] Save failed: %s" % error_string(err))


# ══════════════════════════════════════════════════════════════════════
#  MATERIALS — All procedural (no downloaded textures).
#  FFFLAG: Replace with real PBR texture sets from ambientCG / PolyHaven
#          for a significant quality jump.
# ══════════════════════════════════════════════════════════════════════

func _make_floor_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.28, 0.27, 0.26))
	mat.set_shader_parameter("roughness", 0.75)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 12.0)
	mat.set_shader_parameter("noise_strength", 0.12)
	mat.set_shader_parameter("tiling", Vector2(4.0, 4.0))
	return mat


func _make_wall_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.38, 0.36, 0.34))
	mat.set_shader_parameter("roughness", 0.88)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 8.0)
	mat.set_shader_parameter("noise_strength", 0.15)
	mat.set_shader_parameter("tiling", Vector2(2.0, 1.0))
	return mat


func _make_perim_wall_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.32, 0.31, 0.30))
	mat.set_shader_parameter("roughness", 0.92)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 6.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(3.0, 1.0))
	return mat


func _make_wallrun_mat(accent: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_wallrun_shader()
	mat.set_shader_parameter("base_color", Color(0.22, 0.22, 0.24))
	mat.set_shader_parameter("accent_color", accent)
	mat.set_shader_parameter("roughness", 0.35)
	mat.set_shader_parameter("metallic", 0.7)
	mat.set_shader_parameter("stripe_freq", 8.0)
	return mat


func _make_platform_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_platform_shader()
	mat.set_shader_parameter("base_color", Color(0.25, 0.25, 0.27))
	mat.set_shader_parameter("accent_color", Color(0.9, 0.55, 0.15))
	mat.set_shader_parameter("roughness", 0.4)
	mat.set_shader_parameter("metallic", 0.6)
	return mat


func _make_ledge_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _make_pbr_shader()
	mat.set_shader_parameter("base_color", Color(0.35, 0.33, 0.30))
	mat.set_shader_parameter("roughness", 0.85)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("noise_scale", 10.0)
	mat.set_shader_parameter("noise_strength", 0.1)
	mat.set_shader_parameter("tiling", Vector2(2.0, 2.0))
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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * tiling;
	float n = fbm(uv * noise_scale) * noise_strength;
	float n2 = fbm(uv * noise_scale * 3.0 + 42.0) * noise_strength * 0.5;
	vec3 col = base_color * (1.0 + n - noise_strength * 0.5);
	col *= 0.95 + n2;
	float r = roughness + n * 0.3;
	ALBEDO = col;
	ROUGHNESS = clamp(r, 0.0, 1.0);
	METALLIC = metallic;
	AO = 1.0 - n * 0.3;
"""
	return s


func _make_wallrun_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.2);
uniform vec3 accent_color : source_color = vec3(0.2, 0.7, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.35;
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
uniform float stripe_freq : hint_range(1.0, 20.0) = 8.0;

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
	// horizontal stripes (caution pattern)
	float stripe = smoothstep(0.45, 0.5, fract(uv.y * stripe_freq));
	vec3 col = mix(base_color, accent_color, stripe * 0.7);
	// add subtle panel lines at edges
	float edge = smoothstep(0.02, 0.0, uv.x) + smoothstep(0.98, 1.0, uv.x);
	edge += smoothstep(0.02, 0.0, uv.y) + smoothstep(0.98, 1.0, uv.y);
	col *= 0.85 + 0.15 * (1.0 - min(edge, 1.0));
	// noise variation
	float n = noise(uv * 20.0) * 0.08;
	col *= 1.0 + n - 0.04;
	ALBEDO = col;
	ROUGHNESS = roughness + n * 0.2;
	METALLIC = metallic;
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
	// safety stripe along top edge
	float edge = smoothstep(0.15, 0.0, uv.y) + smoothstep(0.85, 1.0, uv.y);
	vec3 col = mix(base_color, accent_color, edge * 0.8);
	// diamond plate pattern
	float d = noise(uv * 30.0);
	col *= 0.95 + d * 0.1;
	float n = noise(uv * 15.0 + 100.0) * 0.06;
	ALBEDO = col * (1.0 + n - 0.03);
	ROUGHNESS = roughness + n * 0.15;
	METALLIC = metallic;
"""
	return s


# ══════════════════════════════════════════════════════════════════════
#  GEOMETRY HELPERS
# ══════════════════════════════════════════════════════════════════════

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		name: String, layer := 1) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 1
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
		name: String, layer := 1) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 1
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


func _add_static(parent: Node3D, pos: Vector3, mesh: Mesh, mat: Material,
		name: String, col_shape: Shape3D = null) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = 0
	body.collision_mask = 0
	parent.add_child(body)
	body.owner = parent.owner

	if col_shape:
		var col := CollisionShape3D.new()
		col.shape = col_shape
		body.add_child(col)
		col.owner = parent.owner

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	if mat:
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
		Color(0.4, 1.0, 0.5), "SpotWallRunL")
	_add_spot(root, Vector3(2, 5.5, -2), Vector3(-90, 0, 0), 6.0, 0.6,
		Color(0.5, 1.0, 0.55), "SpotWallRunR")
	_add_spot(root, Vector3(-6, 4.5, -6), Vector3(-90, 0, 0), 5.0, 0.7,
		Color(1.0, 0.7, 0.3), "SpotPlatform")
	_add_spot(root, Vector3(0, 5.0, 4), Vector3(-90, 0, 0), 7.0, 0.35,
		Color(0.8, 0.85, 1.0), "SpotSlideArea")

	# Ambient fill omnis
	_add_omni(root, Vector3(-8, 4, -8), 8.0, 0.3, Color(0.9, 0.85, 0.7))
	_add_omni(root, Vector3(8, 4, 4), 8.0, 0.25, Color(0.7, 0.8, 0.9))


func _add_spot(parent: Node3D, pos: Vector3, rot: Vector3, range_: float,
		energy: float, col: Color, name: String) -> void:
	var spot := SpotLight3D.new()
	spot.name = name
	spot.position = pos
	spot.rotation_degrees = rot
	spot.light_color = col
	spot.light_energy = energy
	spot.spot_range = range_
	spot.spot_angle = 45.0
	spot.omni_attenuation = 1.5
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
	var player = root.get_node_or_null("Player")
	if not player:
		return

	# 1) Ambient dust motes
	var dust := GPUParticles3D.new()
	dust.name = "DustMotes"
	dust.amount = 60
	dust.lifetime = 6.0
	dust.visibility_aabb = AABB(Vector3(-12, 0, -12), Vector3(24, 7, 24))
	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dust_mat.emission_box_extents = Vector3(10, 3, 10)
	dust_mat.direction = Vector3(0, 0.2, 0)
	dust_mat.spread = 30.0
	dust_mat.initial_velocity_min = 0.05
	dust_mat.initial_velocity_max = 0.15
	dust_mat.gravity = Vector3(0, 0.02, 0)
	dust_mat.scale_min = 0.015
	dust_mat.scale_max = 0.04
	dust_mat.color = Color(0.9, 0.88, 0.8)
	dust_mat.color_ramp = _make_fade_ramp()
	dust.process_material = dust_mat
	dust.draw_pass_1 = _make_dust_billboard()
	root.add_child(dust)
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
	spark_mat.color_ramp = _make_spark_ramp()
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
	puff_mat.color_ramp = _make_fade_ramp()
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
	sdust_mat.color_ramp = _make_fade_ramp()
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
	dash_mat.color_ramp = _make_dash_ramp()
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
	q.surface_add_material(mat)
	return q


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
	env.tonemap_mode = Environment.TONE_MAP_ACES
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
	env.volumetric_fog_inscattering_strength = 0.3

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)
	world_env.owner = root.owner


# ══════════════════════════════════════════════════════════════════════
#  MANAGERS
# ══════════════════════════════════════════════════════════════════════

func _build_managers(root: Node3D) -> void:
	# Remove old managers
	for c in root.get_children():
		if c.name in ["FeedbackManager", "AmbientAudio", "ScreenshotManager"]:
			c.queue_free()

	var player = root.get_node_or_null("Player")

	# Ambient audio
	var amb := Node.new()
	amb.name = "AmbientAudio"
	amb.set_script(load("res://scripts/ambient_audio.gd"))
	root.add_child(amb)
	amb.owner = root.owner

	# Feedback manager — wire up particle references
	var fb := Node.new()
	fb.name = "FeedbackManager"
	fb.set_script(load("res://scripts/feedback_manager.gd"))
	root.add_child(fb)
	fb.owner = root.owner

	if player:
		var fb_script = fb.get_script()
		# Defer particle wiring to next frame so @onready on the script resolves
		fb.set_meta("player_ref", player)
		fb.set_meta("dust_motes_ref", player.get_node_or_null("DustMotes"))
		fb.set_meta("dash_trail_ref", player.get_node_or_null("DashTrail"))
		fb.set_meta("wall_sparks_ref", player.get_node_or_null("WallSparks"))
		fb.set_meta("landing_puff_ref", player.get_node_or_null("LandingPuff"))
		fb.set_meta("slide_dust_ref", player.get_node_or_null("SlideDust"))

	# Screenshot manager
	var ss := Node.new()
	ss.name = "ScreenshotManager"
	ss.set_script(load("res://scripts/screenshot_manager.gd"))
	root.add_child(ss)
	ss.owner = root.owner
