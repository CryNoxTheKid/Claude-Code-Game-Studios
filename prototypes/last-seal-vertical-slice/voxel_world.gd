# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: full build->furnish->live loop, unguided <=5 min, cozy at scale
# Date: 2026-07-12
# Voxel World / Grid Data System per design/gdd/voxel-world.md + CONTRACTS.md,
# slice-reduced: packed per-chunk byte storage (ADR-0014 chunked approach),
# lazy chunk allocation, true per-cell face-culled mesher (walls/roofs are
# free-standing cells, unlike the heightfield mesher in
# prototypes/chunked-mesher/main.gd — that prototype validated STORAGE
# feasibility only; its mesher does not apply here). No physics — DDA picking.
extends Node3D

# --- Global constants (duplicated per file per CONTRACTS.md; keep values identical) ---
const CHUNK := 16
const MAX_Y := 32
const WORLD_SIZE := 2000              # cells per horizontal axis (full data world)
const REGION_RADIUS_CHUNKS := 12      # meshed/playable window radius around center
const SEED := 1337
# Cell ids (byte values in packed chunks)
const AIR := 0
const TERRAIN_BASE := 1               # 1..4 terrain height bands
const WOOD := 10
const STONE := 11
const THATCH := 12
const BED := 20

const BAND_COLORS: Array[Color] = [
	# Art bible §4.3 per-height-band mapping: warm-neutral low -> cool-pale high
	Color("9CAD6E"),  # Lowland  — grass/valley floor
	Color("A98F5E"),  # Midland  — earth/hills
	Color("7C818A"),  # Highland — stone
	Color("C9D3D8"),  # Peak     — snow, blends into fog
]

# --- Procedural texture atlas + classic voxel AO (readability pass 2026-07-12) ---
# Tiles laid out horizontally: [4 terrain bands][WOOD][STONE][THATCH][BED][unknown].
# Vertex color no longer carries block hue (the atlas does) — it's now a pure
# grayscale multiplier: per-face-direction shade * per-vertex AO brightness.
const ATLAS_TILE_PX := 16
const ATLAS_VALUES: Array[int] = [TERRAIN_BASE, TERRAIN_BASE + 1, TERRAIN_BASE + 2, TERRAIN_BASE + 3, WOOD, STONE, THATCH, BED]

enum FaceDir { TOP, BOTTOM, RIGHT, LEFT, BACK, FORWARD }

const FACE_NORMAL: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_SHADE: Array[float] = [1.0, 1.0, 0.88, 0.88, 0.8, 0.8]  # milder now that AO carries definition
# Per face, the 4 corners (a,b,c,d matching the mesher's vertex order) each need
# two tangent "ortho" offsets (the two face-adjacent side cells used for AO).
# Entry layout per face: [a_side1, a_side2, b_side1, b_side2, c_side1, c_side2, d_side1, d_side2]
const FACE_ORTHOS: Array[Array] = [
	# TOP
	[Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1)],
	# BOTTOM
	[Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, 1)],
	# RIGHT (+X)
	[Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, -1, 0), Vector3i(0, 0, 1)],
	# LEFT (-X)
	[Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, 0, -1)],
	# BACK (+Z)
	[Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0)],
	# FORWARD (-Z)
	[Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0)],
]
const AO_BRIGHTNESS: Array[float] = [1.0, 0.82, 0.68, 0.55]   # 0..3 occluders

signal cell_changed(changes: Array)    # Array of {cell: Vector3i, before: int, after: int} — ONE emission per write call (batched)

var _chunk_data: Dictionary[Vector2i, PackedByteArray] = {}    # lazily allocated — only touched chunks
var _chunk_nodes: Dictionary[Vector2i, MeshInstance3D] = {}    # only chunks with a built mesh
var _noise: FastNoiseLite = FastNoiseLite.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _center_chunk: Vector2i = Vector2i.ZERO
var _region_chunk_min: Vector2i = Vector2i.ZERO
var _region_chunk_max: Vector2i = Vector2i.ZERO   # exclusive
var _region_cell_min: Vector2i = Vector2i.ZERO
var _region_cell_max: Vector2i = Vector2i.ZERO    # exclusive
var _value_tile_index: Dictionary[int, int] = {}   # cell value -> atlas tile index
var _unknown_tile_index: int = 0
var _atlas_tile_count: int = 0


func _ready() -> void:
	_noise.seed = SEED
	_noise.frequency = 0.012  # slice tuning: rolling hills, not per-cell speckle (was 0.05)
	_material.vertex_color_use_as_albedo = true
	# cull_mode left at default CULL_BACK — winding is authored for correct backface culling


func setup() -> void:
	_build_atlas()
	_center_chunk = Vector2i((WORLD_SIZE / 2) / CHUNK, (WORLD_SIZE / 2) / CHUNK)
	_region_chunk_min = _center_chunk - Vector2i(REGION_RADIUS_CHUNKS, REGION_RADIUS_CHUNKS)
	_region_chunk_max = _center_chunk + Vector2i(REGION_RADIUS_CHUNKS, REGION_RADIUS_CHUNKS)
	_region_cell_min = _region_chunk_min * CHUNK
	_region_cell_max = _region_chunk_max * CHUNK
	# Pass 1: fill terrain data for every chunk in the playable window.
	for cz in range(_region_chunk_min.y, _region_chunk_max.y):
		for cx in range(_region_chunk_min.x, _region_chunk_max.x):
			_fill_chunk_terrain(Vector2i(cx, cz))
	# Pass 2: mesh every chunk (data pass must finish first so cross-chunk
	# neighbor lookups at the mesher's border faces see committed terrain).
	for cz in range(_region_chunk_min.y, _region_chunk_max.y):
		for cx in range(_region_chunk_min.x, _region_chunk_max.x):
			_rebuild_chunk_mesh(Vector2i(cx, cz))
	# Deliberately no cell_changed emission here: per voxel-world.md Edge
	# Cases, terrain generation may emit "at most one batched signal... or
	# none, if listeners attach only after the Generated state" — true here,
	# since GameWorld calls this before any other system's setup().


func get_cell(cell: Vector3i) -> int:
	if cell.x < 0 or cell.z < 0 or cell.x >= WORLD_SIZE or cell.z >= WORLD_SIZE or cell.y < 0 or cell.y >= MAX_Y:
		return -1
	var cc := Vector2i(cell.x / CHUNK, cell.z / CHUNK)
	if not _chunk_data.has(cc):
		return AIR
	var arr: PackedByteArray = _chunk_data[cc]
	var lx := cell.x % CHUNK
	var lz := cell.z % CHUNK
	return arr[(cell.y * CHUNK + lz) * CHUNK + lx]


func set_cells(changes: Array) -> Array:
	var results: Array = []
	var chunk_writes: Dictionary[Vector2i, PackedByteArray] = {}   # cc -> in-progress array for this batch
	var touched_chunks: Dictionary[Vector2i, bool] = {}            # cc -> needs remesh (dedup set)
	for change: Dictionary in changes:
		var cell: Vector3i = change["cell"]
		var value: int = change["value"]
		if cell.x < 0 or cell.z < 0 or cell.x >= WORLD_SIZE or cell.z >= WORLD_SIZE or cell.y < 0 or cell.y >= MAX_Y:
			results.append({"cell": cell, "before": -1, "after": -1})
			continue
		var cc := Vector2i(cell.x / CHUNK, cell.z / CHUNK)
		var lx := cell.x % CHUNK
		var lz := cell.z % CHUNK
		var arr: PackedByteArray
		if chunk_writes.has(cc):
			arr = chunk_writes[cc]
		elif _chunk_data.has(cc):
			arr = _chunk_data[cc]
		else:
			arr = PackedByteArray()
			arr.resize(CHUNK * CHUNK * MAX_Y)   # zero-filled = air; lazy alloc for a never-touched chunk
		var idx := (cell.y * CHUNK + lz) * CHUNK + lx
		var before: int = arr[idx]
		arr[idx] = value
		chunk_writes[cc] = arr
		touched_chunks[cc] = true
		if lx == 0:
			touched_chunks[Vector2i(cc.x - 1, cc.y)] = true
		elif lx == CHUNK - 1:
			touched_chunks[Vector2i(cc.x + 1, cc.y)] = true
		if lz == 0:
			touched_chunks[Vector2i(cc.x, cc.y - 1)] = true
		elif lz == CHUNK - 1:
			touched_chunks[Vector2i(cc.x, cc.y + 1)] = true
		results.append({"cell": cell, "before": before, "after": value})
	for cc: Vector2i in chunk_writes:
		_chunk_data[cc] = chunk_writes[cc]
	for cc: Vector2i in touched_chunks:
		if _chunk_data.has(cc):
			_rebuild_chunk_mesh(cc)
	if not results.is_empty():
		cell_changed.emit(results)
	return results


func raycast_cells(origin: Vector3, dir: Vector3, max_dist: float = 200.0) -> Dictionary:
	var d := dir.normalized()
	if d.length_squared() == 0.0:
		return {}
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	if get_cell(cell) > AIR:
		return {"cell": cell, "normal": Vector3i.ZERO}   # ray origin embedded in solid geometry
	var step := Vector3i(
		1 if d.x > 0.0 else (-1 if d.x < 0.0 else 0),
		1 if d.y > 0.0 else (-1 if d.y < 0.0 else 0),
		1 if d.z > 0.0 else (-1 if d.z < 0.0 else 0))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	if d.x != 0.0:
		t_delta.x = 1.0 / absf(d.x)
		var boundary_x: float = float(cell.x + (1 if step.x > 0 else 0))
		t_max.x = (boundary_x - origin.x) / d.x
	if d.y != 0.0:
		t_delta.y = 1.0 / absf(d.y)
		var boundary_y: float = float(cell.y + (1 if step.y > 0 else 0))
		t_max.y = (boundary_y - origin.y) / d.y
	if d.z != 0.0:
		t_delta.z = 1.0 / absf(d.z)
		var boundary_z: float = float(cell.z + (1 if step.z > 0 else 0))
		t_max.z = (boundary_z - origin.z) / d.z
	var t := 0.0
	var last_normal := Vector3i.ZERO
	while t <= max_dist:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			t = t_max.x
			t_max.x += t_delta.x
			cell.x += step.x
			last_normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			t = t_max.y
			t_max.y += t_delta.y
			cell.y += step.y
			last_normal = Vector3i(0, -step.y, 0)
		else:
			t = t_max.z
			t_max.z += t_delta.z
			cell.z += step.z
			last_normal = Vector3i(0, 0, -step.z)
		if t > max_dist:
			break
		var v := get_cell(cell)
		if v > AIR:
			return {"cell": cell, "normal": last_normal}
	return {}


func is_in_region(cell: Vector3i) -> bool:
	if cell.y < 0 or cell.y >= MAX_Y:
		return false
	return cell.x >= _region_cell_min.x and cell.x < _region_cell_max.x \
		and cell.z >= _region_cell_min.y and cell.z < _region_cell_max.y


func get_region_aabb() -> AABB:
	var pos := Vector3(float(_region_cell_min.x), 0.0, float(_region_cell_min.y))
	var size := Vector3(
		float(_region_cell_max.x - _region_cell_min.x),
		float(MAX_Y),
		float(_region_cell_max.y - _region_cell_min.y))
	return AABB(pos, size)


func terrain_height(x: int, z: int) -> int:
	# Gentle rolling hills (low frequency) with a flattened settlement core:
	# building on speckle-bumps is miserable, and the core is the play area
	# (slice tuning 2026-07-12; authored heightmaps are a production option).
	var n := _noise.get_noise_2d(float(x), float(z))
	var center := Vector2(float(WORLD_SIZE) / 2.0, float(WORLD_SIZE) / 2.0)
	var dist := Vector2(float(x), float(z)).distance_to(center)
	var core_blend := smoothstep(40.0, 110.0, dist)  # 0 at core -> 1 outside
	# Core keeps GENTLE undulation (+-1..2 cells); far terrain rolls fully.
	var amplitude := lerpf(1.8, 6.0, core_blend)
	var h := 8.0 + n * amplitude
	return clampi(int(roundf(h)), 2, MAX_Y - 6)


func _fill_chunk_terrain(cc: Vector2i) -> void:
	var arr := PackedByteArray()
	arr.resize(CHUNK * CHUNK * MAX_Y)   # zero-filled = air
	for lz in CHUNK:
		var gz := cc.y * CHUNK + lz
		for lx in CHUNK:
			var gx := cc.x * CHUNK + lx
			var h := terrain_height(gx, gz)
			for ly in h:
				arr[(ly * CHUNK + lz) * CHUNK + lx] = TERRAIN_BASE + (ly * 3) / MAX_Y
	_chunk_data[cc] = arr


func _rebuild_chunk_mesh(cc: Vector2i) -> void:
	if not _chunk_data.has(cc):
		return
	var arr: PackedByteArray = _chunk_data[cc]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ly in MAX_Y:
		var fy := float(ly)
		var fy1 := fy + 1.0
		for lz in CHUNK:
			var gz := cc.y * CHUNK + lz
			var fz := float(gz)
			for lx in CHUNK:
				var v: int = arr[(ly * CHUNK + lz) * CHUNK + lx]
				if v == AIR:
					continue
				var gx := cc.x * CHUNK + lx
				var fx := float(gx)
				var tile_index := _tile_index_for_value(v)
				if _neighbor_value(cc, arr, lx, ly + 1, lz) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx, fy1, fz), Vector3(fx, fy1, fz + 1), Vector3(fx + 1, fy1, fz + 1), Vector3(fx + 1, fy1, fz),
						FaceDir.TOP, tile_index, cc, arr, lx, ly, lz)
				if _neighbor_value(cc, arr, lx, ly - 1, lz) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + 1), Vector3(fx, fy, fz + 1),
						FaceDir.BOTTOM, tile_index, cc, arr, lx, ly, lz)
				if _neighbor_value(cc, arr, lx + 1, ly, lz) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy1, fz), Vector3(fx + 1, fy1, fz + 1), Vector3(fx + 1, fy, fz + 1),
						FaceDir.RIGHT, tile_index, cc, arr, lx, ly, lz)
				if _neighbor_value(cc, arr, lx - 1, ly, lz) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx, fy, fz), Vector3(fx, fy, fz + 1), Vector3(fx, fy1, fz + 1), Vector3(fx, fy1, fz),
						FaceDir.LEFT, tile_index, cc, arr, lx, ly, lz)
				if _neighbor_value(cc, arr, lx, ly, lz + 1) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1), Vector3(fx + 1, fy1, fz + 1), Vector3(fx, fy1, fz + 1),
						FaceDir.BACK, tile_index, cc, arr, lx, ly, lz)
				if _neighbor_value(cc, arr, lx, ly, lz - 1) <= AIR:
					_append_face(verts, normals, colors, uvs, indices,
						Vector3(fx, fy, fz), Vector3(fx, fy1, fz), Vector3(fx + 1, fy1, fz), Vector3(fx + 1, fy, fz),
						FaceDir.FORWARD, tile_index, cc, arr, lx, ly, lz)
	if verts.is_empty():
		if _chunk_nodes.has(cc):
			(_chunk_nodes[cc] as MeshInstance3D).mesh = null
		return
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	if _chunk_nodes.has(cc):
		(_chunk_nodes[cc] as MeshInstance3D).mesh = mesh
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_end = 600.0
		add_child(mi)
		_chunk_nodes[cc] = mi


func _neighbor_value(cc: Vector2i, arr: PackedByteArray, lx: int, ly: int, lz: int) -> int:
	if ly < 0 or ly >= MAX_Y:
		return -1   # world edge (no vertical chunking — MAX_Y is the full column height)
	if lx >= 0 and lx < CHUNK and lz >= 0 and lz < CHUNK:
		return arr[(ly * CHUNK + lz) * CHUNK + lx]
	var gx := cc.x * CHUNK + lx
	var gz := cc.y * CHUNK + lz
	return get_cell(Vector3i(gx, ly, gz))


func _build_atlas() -> void:
	_value_tile_index.clear()
	for i in ATLAS_VALUES.size():
		_value_tile_index[ATLAS_VALUES[i]] = i
	_unknown_tile_index = ATLAS_VALUES.size()
	_atlas_tile_count = ATLAS_VALUES.size() + 1
	var atlas_w := _atlas_tile_count * ATLAS_TILE_PX
	var img := Image.create(atlas_w, ATLAS_TILE_PX, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for tile_i in _atlas_tile_count:
		var value := ATLAS_VALUES[tile_i] if tile_i < ATLAS_VALUES.size() else -1
		var base_color := _base_color_for_tile(value)
		var streaky := value == WOOD or value == THATCH
		for py in ATLAS_TILE_PX:
			var row_mult := 1.0
			if streaky:
				row_mult = 1.0 + (rng.randf() - 0.5) * 0.14   # horizontal plank/straw streaks
			for px in ATLAS_TILE_PX:
				var pixel_noise := 1.0 + (rng.randf() - 0.5) * 0.16   # ~0.92..1.08 per-pixel variation
				var mult := pixel_noise * row_mult
				if px == 0 or px == ATLAS_TILE_PX - 1 or py == 0 or py == ATLAS_TILE_PX - 1:
					mult *= 0.85   # 1px tile border so block boundaries read at a distance
				img.set_pixel(tile_i * ATLAS_TILE_PX + px, py, Color(
					clampf(base_color.r * mult, 0.0, 1.0),
					clampf(base_color.g * mult, 0.0, 1.0),
					clampf(base_color.b * mult, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_material.albedo_texture = tex
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


func _base_color_for_tile(value: int) -> Color:
	if value < 0:
		return Color.MAGENTA   # reserved "unknown value" tile
	if value < WOOD:
		return BAND_COLORS[clampi(value - TERRAIN_BASE, 0, BAND_COLORS.size() - 1)]
	var def: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_cell_value(value)
	if def == null:
		return Color.MAGENTA   # visibly wrong instead of a silent crash — unknown built cell value
	return def.color


func _tile_index_for_value(v: int) -> int:
	return _value_tile_index.get(v, _unknown_tile_index)


func _vertex_ao(cc: Vector2i, arr: PackedByteArray, lx: int, ly: int, lz: int, face_dir: Vector3i, o1: Vector3i, o2: Vector3i) -> int:
	# Classic voxel AO (0fps-style): both side-adjacent cells solid always
	# forces max occlusion regardless of the corner cell (avoids a bright
	# seam where the corner is empty but both sides already block light).
	var side1 := _neighbor_value(cc, arr, lx + face_dir.x + o1.x, ly + face_dir.y + o1.y, lz + face_dir.z + o1.z) > AIR
	var side2 := _neighbor_value(cc, arr, lx + face_dir.x + o2.x, ly + face_dir.y + o2.y, lz + face_dir.z + o2.z) > AIR
	if side1 and side2:
		return 3
	var corner := _neighbor_value(cc, arr,
		lx + face_dir.x + o1.x + o2.x, ly + face_dir.y + o1.y + o2.y, lz + face_dir.z + o1.z + o2.z) > AIR
	var count := 0
	if side1:
		count += 1
	if side2:
		count += 1
	if corner:
		count += 1
	return count


func _append_face(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, face: int, tile_index: int,
		cc: Vector2i, arr: PackedByteArray, lx: int, ly: int, lz: int) -> void:
	var face_dir: Vector3i = FACE_NORMAL[face]
	var shade: float = FACE_SHADE[face]
	var orthos: Array = FACE_ORTHOS[face]
	var ao_a := _vertex_ao(cc, arr, lx, ly, lz, face_dir, orthos[0], orthos[1])
	var ao_b := _vertex_ao(cc, arr, lx, ly, lz, face_dir, orthos[2], orthos[3])
	var ao_c := _vertex_ao(cc, arr, lx, ly, lz, face_dir, orthos[4], orthos[5])
	var ao_d := _vertex_ao(cc, arr, lx, ly, lz, face_dir, orthos[6], orthos[7])
	var m_a := shade * AO_BRIGHTNESS[ao_a]
	var m_b := shade * AO_BRIGHTNESS[ao_b]
	var m_c := shade * AO_BRIGHTNESS[ao_c]
	var m_d := shade * AO_BRIGHTNESS[ao_d]
	var base := verts.size()
	verts.append_array([a, b, c, d])
	var n := Vector3(face_dir)
	normals.append_array([n, n, n, n])
	colors.append_array([Color(m_a, m_a, m_a), Color(m_b, m_b, m_b), Color(m_c, m_c, m_c), Color(m_d, m_d, m_d)])
	var u0 := float(tile_index) / float(_atlas_tile_count)
	var u1 := float(tile_index + 1) / float(_atlas_tile_count)
	uvs.append_array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)])
	# Standard AO seam fix: flip the triangulation diagonal when the "a-c"
	# diagonal is more occluded than "b-d", to avoid the classic X-shaped
	# AO artifact on partially-occluded quads.
	if ao_a + ao_c > ao_b + ao_d:
		indices.append_array([base + 1, base + 2, base + 3, base + 1, base + 3, base + 0])
	else:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
