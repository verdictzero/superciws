class_name TerrainMesher
extends RefCounted
## Turns one square chunk of a DesertField into an ArrayMesh.
##
## Ported from mewd-engine's IslandChunkMesher with the island parts (land-mask
## contouring, coast pinning, cliff rim and wall bands, zones, splat-in-vertex-colour)
## taken out, because the desert has no coastline and its ground colours come from
## baked textures. What stays is the part that matters:
##   - a regular grid at `cells` per side, vertices relative to the chunk origin,
##   - analytic normals by central differences over a FIXED world distance, so the
##     shading of a coarse distant chunk matches a fine near one,
##   - vertical skirts on all four borders, so chunks at different resolutions never
##     open a crack where they meet.

static func build(field: DesertField, x0: float, z0: float, size: float, cells: int,
		skirt_depth: float, normal_radius: float) -> ArrayMesh:
	var n := maxi(cells, 1)
	var step := size / float(n)
	var g := n + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(g * g)
	norms.resize(g * g)
	var d := maxf(normal_radius, step * 0.5)
	for j in g:
		var wz := z0 + float(j) * step
		for i in g:
			var wx := x0 + float(i) * step
			var h := field.height(wx, wz)
			var hx0 := field.height(wx - d, wz)
			var hx1 := field.height(wx + d, wz)
			var hz0 := field.height(wx, wz - d)
			var hz1 := field.height(wx, wz + d)
			var k := j * g + i
			verts[k] = Vector3(wx - x0, h, wz - z0)
			norms[k] = Vector3((hx0 - hx1) / (2.0 * d), 1.0, (hz0 - hz1) / (2.0 * d)).normalized()
	for j in n:
		for i in n:
			var a := j * g + i
			var b := a + 1
			var c := a + g
			var e := c + 1
			# alternate the split so long slopes don't all crease the same way
			if (i + j) % 2 == 0:
				idx.append_array([a, b, e, a, e, c])
			else:
				idx.append_array([a, b, c, b, e, c])
	if skirt_depth > 0.0:
		_skirts(verts, norms, idx, g, skirt_depth)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Hang a strip straight down from each border edge. It takes the normals of the
## ground it hangs from, so where one does peek through it reads as more ground.
static func _skirts(verts: PackedVector3Array, norms: PackedVector3Array,
		idx: PackedInt32Array, g: int, depth: float) -> void:
	var n := g - 1
	var borders := [[0, 1], [n * g, 1], [0, g], [n, g]]   # start, stride
	for bd in borders:
		var start: int = bd[0]
		var stride: int = bd[1]
		for s in n:
			var ka: int = start + s * stride
			var kb: int = ka + stride
			var base := verts.size()
			verts.append(verts[ka])
			verts.append(verts[kb])
			verts.append(verts[kb] - Vector3(0, depth, 0))
			verts.append(verts[ka] - Vector3(0, depth, 0))
			norms.append(norms[ka])
			norms.append(norms[kb])
			norms.append(norms[kb])
			norms.append(norms[ka])
			# both windings: the materials draw double sided anyway, and this keeps
			# the skirt independent of which border it is on
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
