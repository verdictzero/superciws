extends SceneTree
## Offline terrain bake. Run from the project root:
##   godot --headless --script res://tools/bake_terrain.gd
##
## Writes
##   assets/terrain/bake/terrain.scn    the ground: 128 m chunks, each at a fixed resolution
##                                      chosen by its distance from the battery, merged in
##                                      blocks of merge_chunks^2 to keep draw calls down
##   assets/terrain/bake/height.bin     runtime height grid (gameplay ground queries)
##   assets/terrain/bake/meta.json      signature, grid layout, stats
##   build/terrain/height_bake.bin      fine height grid for tools/bake_ground.py (not shipped)
##
## The camera never leaves the battery, so unlike mewd-engine's streaming IslandWorld
## there is no LOD switching at all: each chunk is meshed once, at the resolution its
## distance calls for, and the result is committed so no device ever generates terrain.

const OUT_DIR := "res://assets/terrain/bake"
const SOURCES := ["res://scripts/terrain/desert_field.gd", "res://scripts/terrain/terrain_mesher.gd",
		"res://assets/terrain/desert.json"]

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var field := DesertField.new()
	var cfg := field.cfg
	var R: float = cfg["radius"]
	var cs: float = cfg["chunk_size"]
	var lods: Array = cfg["lod"]
	var skirt: float = cfg["skirt_depth"]
	var nr: float = cfg["curvature_radius"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var root := Node3D.new()
	root.name = "Terrain"
	var merge := int(cfg.get("merge_chunks", 1))
	var groups := {}   # Vector2i block -> Array of [mesh, offset]
	var half := int(ceil(R / cs))
	var tris := 0
	var chunks := 0
	var per_lod := {}
	for cj in range(-half, half):
		for ci in range(-half, half):
			var x0 := float(ci) * cs
			var z0 := float(cj) * cs
			# nearest point of the chunk to the battery decides inclusion and resolution
			var nx := clampf(0.0, x0, x0 + cs)
			var nz := clampf(0.0, z0, z0 + cs)
			var near := Vector2(nx, nz).length()
			if near > R:
				continue
			var cells := 8
			for l in lods:
				if near <= float(l[0]):
					cells = int(l[1])
					break
			var mesh := TerrainMesher.build(field, x0, z0, cs, cells, skirt, nr)
			var block := Vector2i(floori(float(ci) / merge), floori(float(cj) / merge))
			if not groups.has(block):
				groups[block] = []
			groups[block].append([mesh, Vector3(x0, 0, z0)])
			chunks += 1
			tris += cells * cells * 2
			per_lod[cells] = int(per_lod.get(cells, 0)) + 1
	for block in groups:
		var origin := Vector3(float(block.x * merge) * cs, 0, float(block.y * merge) * cs)
		var mi := MeshInstance3D.new()
		mi.name = "block_%d_%d" % [block.x, block.y]
		mi.mesh = _merge(groups[block], origin)
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT_DIR + "/terrain.scn", ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("saving terrain.scn failed: %d" % err)

	# height grids: a coarse one the game ships, a fine one for the ground texture bake
	var rt_step: float = cfg["runtime_grid_step"]
	var bk_step: float = cfg["height_grid_step"]
	_write_grid(field, R, rt_step, OUT_DIR + "/height.bin")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/terrain"))
	_write_grid(field, R, bk_step, "res://build/terrain/height_bake.bin")

	var meta := {
		"signature": _signature(),
		"radius": R, "chunk_size": cs, "chunks": chunks, "meshes": groups.size(), "triangles": tris,
		"chunks_per_resolution": per_lod,
		"height_grid": {"file": "height.bin", "step": rt_step, "origin": -R,
				"size": int(round(2.0 * R / rt_step)) + 1},
		"bake_ms": Time.get_ticks_msec() - t0,
	}
	var f := FileAccess.open(OUT_DIR + "/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  ", false))
	f.close()
	print("terrain: %d chunks in %d meshes, %d triangles, %s, %d ms" % [chunks, groups.size(), tris, per_lod, meta["bake_ms"]])
	root.free()
	quit()

## Concatenate chunk meshes (each built relative to its own corner) into one mesh
## relative to `origin`.
func _merge(parts: Array, origin: Vector3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for part in parts:
		var arr: Array = (part[0] as ArrayMesh).surface_get_arrays(0)
		var off: Vector3 = part[1] - origin
		var base := verts.size()
		for v in arr[Mesh.ARRAY_VERTEX]:
			verts.append(v + off)
		norms.append_array(arr[Mesh.ARRAY_NORMAL])
		for i in arr[Mesh.ARRAY_INDEX]:
			idx.append(i + base)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

## Square grid of heights over [-R, R]^2, row-major (z rows, x columns), float32 LE,
## preceded by a 16-byte header: "HGT1", size (u32), step (f32), origin (f32).
func _write_grid(field: DesertField, R: float, step: float, path: String) -> void:
	var size := int(round(2.0 * R / step)) + 1
	var data := PackedFloat32Array()
	data.resize(size * size)
	for j in size:
		var z := -R + float(j) * step
		for i in size:
			data[j * size + i] = field.height(-R + float(i) * step, z)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("HGT1".to_ascii_buffer())
	f.store_32(size)
	f.store_float(step)
	f.store_float(-R)
	f.store_buffer(data.to_byte_array())
	f.close()

func _signature() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for p in SOURCES:
		ctx.update(FileAccess.get_file_as_bytes(p))
	return ctx.finish().hex_encode().substr(0, 16)
