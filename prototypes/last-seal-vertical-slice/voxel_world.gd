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
	Color(0.35, 0.55, 0.25), Color(0.45, 0.60, 0.30), Color(0.55, 0.55, 0.45), Color(0.60, 0.58, 0.55),
]

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


func _ready() -> void:
	_noise.seed = SEED
	_noise.frequency = 0.05
	_material.vertex_color_use_as_albedo = true
	# cull_mode left at default CULL_BACK — winding is authored for correct backface culling


func setup() -> void:
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
	var n := _noise.get_noise_2d(float(x), float(z))
	return clampi(8 + int(roundf(n * 6.0)), 2, MAX_Y - 6)


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
				var col := _color_for_value(v)
				if _neighbor_value(cc, arr, lx, ly + 1, lz) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx, fy1, fz), Vector3(fx, fy1, fz + 1), Vector3(fx + 1, fy1, fz + 1), Vector3(fx + 1, fy1, fz),
						Vector3.UP, col)
				if _neighbor_value(cc, arr, lx, ly - 1, lz) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx, fy, fz), Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy, fz + 1), Vector3(fx, fy, fz + 1),
						Vector3.DOWN, col)
				if _neighbor_value(cc, arr, lx + 1, ly, lz) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx + 1, fy, fz), Vector3(fx + 1, fy1, fz), Vector3(fx + 1, fy1, fz + 1), Vector3(fx + 1, fy, fz + 1),
						Vector3.RIGHT, col.darkened(0.2))
				if _neighbor_value(cc, arr, lx - 1, ly, lz) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx, fy, fz), Vector3(fx, fy, fz + 1), Vector3(fx, fy1, fz + 1), Vector3(fx, fy1, fz),
						Vector3.LEFT, col.darkened(0.2))
				if _neighbor_value(cc, arr, lx, ly, lz + 1) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx, fy, fz + 1), Vector3(fx + 1, fy, fz + 1), Vector3(fx + 1, fy1, fz + 1), Vector3(fx, fy1, fz + 1),
						Vector3.BACK, col.darkened(0.3))
				if _neighbor_value(cc, arr, lx, ly, lz - 1) <= AIR:
					_quad(verts, normals, colors, indices,
						Vector3(fx, fy, fz), Vector3(fx, fy1, fz), Vector3(fx + 1, fy1, fz), Vector3(fx + 1, fy, fz),
						Vector3.FORWARD, col.darkened(0.3))
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


func _color_for_value(v: int) -> Color:
	if v < WOOD:
		return BAND_COLORS[clampi(v - TERRAIN_BASE, 0, BAND_COLORS.size() - 1)]
	var def: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_cell_value(v)
	if def == null:
		return Color.MAGENTA   # visibly wrong instead of a silent crash — unknown built cell value
	return def.color


func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	var base := verts.size()
	verts.append_array([a, b, c, d])
	for i in 4:
		normals.append(n)
		colors.append(col)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
