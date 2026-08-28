extends SceneTree
## Dumps the UV layout of a BoxMesh(0.4, 6, 10) on its +x/-x faces so we can
## state which world axis the V texture coordinate runs along.

func _initialize() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 6.0, 10.0)
	var arr: Array = bm.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	for f in range(0, idx.size(), 3):
		var a := idx[f]
		var b := idx[f + 1]
		var c := idx[f + 2]
		var n := normals[a]
		if absf(n.x) > 0.99:
			print("face normal=%s" % n)
			for v in [a, b, c]:
				print("   vert pos=%s uv=%s" % [verts[v], uvs[v]])
	quit()