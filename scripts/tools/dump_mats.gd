extends SceneTree

var frame := 0
var dumped := false


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn")
	if packed:
		root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		print("[Dump] _process alive, root named: ", root.name)
	var ss := root.get_node_or_null("Main/RuntimeBuilder/ScreenshotManager")
	if ss:
		ss.set("auto_done", true)
		ss.set("auto_timer", 999999.0)
	if frame < 60:
		return false
	if dumped:
		quit()
		return true
	dumped = true
	_dump(root)
	quit()
	return true


func _dump(node: Node, indent := 0) -> void:
	var pre := ""
	for i in indent:
		pre += "  "
	var mi := node as MeshInstance3D
	if mi:
		var mesh := mi.mesh
		var mesh_desc := "none"
		if mesh:
			mesh_desc = mesh.get_class()
			if mesh is BoxMesh:
				mesh_desc += " size=%s" % str((mesh as BoxMesh).size)
			elif mesh is CylinderMesh:
				var cm := mesh as CylinderMesh
				mesh_desc += " h=%.2f r=%.2f" % [cm.height, cm.radius]
			elif mesh is CapsuleMesh:
				var cpm := mesh as CapsuleMesh
				mesh_desc += " h=%.2f r=%.2f" % [cpm.height, cpm.radius]
			elif mesh is SphereMesh:
				mesh_desc += " r=%.2f" % (mesh as SphereMesh).radius
		var mats := mi.get_surface_override_material_count()
		print("%sMI %s  pos=%s mesh=[%s] overrides=%d" % [pre, node.name, str(mi.global_position).substr(0, 28), mesh_desc, mats])
		for s in mats:
			var m := mi.get_surface_override_material(s)
			_dump_mat(pre, "  override", m)
	if node is CharacterBody3D or node is StaticBody3D:
		print("%sBODY %s pos=%s" % [pre, node.name, str(node.global_position).substr(0, 28)])
	for c in node.get_children():
		_dump(c, indent + 1)


func _dump_mat(pre: String, tag: String, m: Material) -> void:
	if m == null:
		return
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var names := ["base_color", "accent_color", "roughness", "metallic", "noise_scale",
			"noise_strength", "tiling", "stripe_freq", "edge_color"]
		var pstr := ""
		for p in names:
			if sm.get_shader_parameter(p) != null:
				pstr += "%s=%s " % [p, str(sm.get_shader_parameter(p))]
		print("%s%s ShaderMaterial [%s] params: %s" % [pre, tag, m.resource_path if m.resource_path != "" else "(inline)", pstr.substr(0, 160)])
		var sh := sm.shader
		if sh:
			var code := sh.code
			var head := ""
			for i in code.split("\n"):
				if i.begins_with("uniform") or i.find("stripe") >= 0 or i.find("fract") >= 0 or i.find("uv") >= 0:
					head += "  | " + i.strip_edges() + "\n"
			if head != "":
				print("%s%s shader-snippets:\n%s" % [pre, tag, head])
	elif m is StandardMaterial3D:
		var sm3 := m as StandardMaterial3D
		print("%s%s StandardMaterial3D albedo=%s uv1_scale=%s uv1_offset=%s uv2_scale=%s" % [pre, tag,
			str(sm3.albedo_color), str(sm3.uv1_scale), str(sm3.uv1_offset), str(sm3.uv2_scale)])