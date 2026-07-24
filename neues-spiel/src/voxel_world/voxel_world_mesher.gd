## Voxel World's chunked, face-culled [ArrayMesh] mesher (Story vox-007,
## ADR-0014 Decision Section 2; TR-voxel-world-025/052) -- the production
## redemption of the vertical slice's "missing faces" winding saga.
##
## Consumes [VoxelWorldGrid]'s read API only ([method VoxelWorldGrid.get_cell])
## -- never mutates the grid, and issues zero physics API calls of any kind
## (ADR-0014 Decision Section 4 / ADR-0004 carryover).
##
## THE ONE mesher construction site in this codebase (sprint QA requirement,
## Control Manifest "never a second mesher code path"): every [ArrayMesh.new]
## + [method ArrayMesh.add_surface_from_arrays] call for committed-block
## chunk terrain lives in [method _build_chunk_arrays] and nowhere else --
## grep-verified by `tests/unit/voxel_world/mesher_material_contract_test.gd`.
##
## Winding (TR-voxel-world-052, HARD QA requirement): every emitted quad's
## two triangles are wound to match Godot 4.7's ACTUAL front-face convention,
## established from first principles by inspecting a native [BoxMesh]'s own
## index/normal data -- never a self-stored assumption. See [constant
## FACE_CORNERS]'s doc comment for the derived rule and
## `tests/unit/voxel_world/mesher_winding_derivation_test.gd` for the pinned,
## automated regression proof (reproduces the same BoxMesh check every test
## run, so a future engine change to this convention is caught immediately).
## The shared material ships with backface culling ENABLED (`cull_back`,
## Godot's default -- set EXPLICITLY per the sprint QA smoke item, never left
## implicit). `CULL_DISABLED` never appears anywhere in this system --
## grep-guarded by the same material-contract test file.
##
## Scope (vox-007 -- explicitly excludes Story 015's view-window streaming):
## this class does NOT decide WHICH chunks are meshed as the camera moves --
## it only (a) builds/rebuilds one chunk's [ArrayMesh] on demand via [method
## build_chunk], and (b) automatically rebuilds an ALREADY-tracked chunk when
## [signal VoxelWorldGrid.cell_changed] / [signal
## VoxelWorldGrid.cells_changed_batch] reports a change inside it -- or across
## its border into a tracked neighbor, since a solid/air change at a chunk's
## edge changes the NEIGHBORING chunk's own border-face culling too. A cell
## change in a chunk this class was never asked to [method build_chunk] is
## left alone; Story 015 owns chunk-membership decisions, this class only
## reacts within whatever membership already exists.
##
## Texturing (deliberately deferred, not this story's scope): no atlas story
## exists yet anywhere in `production/epics/voxel-world/` as of this story --
## [constant DEBUG_BLOCK_COLORS] stubs a flat per-block-type placeholder
## color (art-bible SS4.3's height-band hex values) as the mesh's per-vertex
## COLOR, sampled by the shared shader as plain unlit-texture ALBEDO.
## Vertex-AO and the vertical slice's `y_cut` slice-view uniform are ALSO
## deferred -- neither is required by this story's acceptance criteria. ONE
## shared [ShaderMaterial] ([member _material],
## `res://assets/shaders/terrain_chunk.gdshader`) is still the canonical
## single-material contract (art-bible SS8.9.1) specifically so later
## atlas/AO/y_cut stories extend this SAME material/shader file in place,
## never introduce a second one (art-bible SS8.9.11 Reject-If gate #1).
class_name VoxelWorldMesher
extends Node3D

## The 6 face directions this mesher tests for exposure, in a fixed
## deterministic order matching [VoxelWorldGrid.NEIGHBOR_OFFSETS] (+X, -X,
## +Y, -Y, +Z, -Z).
const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Per-face-direction quad corners, as integer offsets from a solid cell's
## MINIMUM corner (matching [method VoxelWorldGrid.cell_to_world]'s
## convention that cell `(x,y,z)` occupies the unit box
## `[x,x+1] x [y,y+1] x [z,z+1]`). Each entry is exactly 4 corners in a fixed
## rotational order; [method _append_face] fan-triangulates them as
## `(0,1,2)` + `(0,2,3)`.
##
## Winding derivation (TR-voxel-world-052, HARD QA requirement -- established
## empirically against THIS engine install, never from memory, the ADR's
## prose, or a self-stored assumption): a native [BoxMesh]'s own stored index
## order, taken in order `(v0,v1,v2)` per triangle, produces
## `(v1-v0).cross(v2-v0)` that points OPPOSITE that triangle's own stored
## vertex normal, for all 12 of its triangles (reproduced live by
## `tests/unit/voxel_world/mesher_winding_derivation_test.gd`, Part 1). Since
## [BoxMesh] is a native Godot primitive that renders correctly -- solid, no
## holes -- under Godot's default backface-culling material settings, this
## proves Godot's FRONT-FACING winding (the winding that SURVIVES backface
## culling) is the one where `(corner1-corner0).cross(corner2-corner0)`
## points OPPOSITE a face's true outward normal -- NOT the OpenGL/CCW-front
## convention the vertical slice wrongly assumed (`prototypes/last-seal-vertical-slice/voxel_world.gd`'s
## documented TR-voxel-world-052 "missing faces" root cause, which shipped
## `CULL_DISABLED` to compensate instead of fixing the winding). Every entry
## below was constructed fresh against that derived rule -- never copied from
## the slice's face tables -- and the same conformance check
## (`(corner1-corner0).cross(corner2-corner0)` opposite the face normal, for
## BOTH triangles of every face) is pinned as Part 2 of the same test file.
const FACE_CORNERS: Array[Array] = [
	# +X (RIGHT)
	[Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0)],
	# -X (LEFT)
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 0, 1)],
	# +Y (TOP)
	[Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(0, 1, 1)],
	# -Y (BOTTOM)
	[Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, 0)],
	# +Z (BACK)
	[Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	# -Z (FORWARD)
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0)],
]

## Placeholder flat per-block-type color (art-bible SS4.3 height-band hex
## values -- the design-authoritative source, not the reference slice) -- see
## class doc comment's Texturing note. Keyed by [CellContents.block_type_id];
## [constant DEBUG_UNKNOWN_COLOR] is a visibly-wrong magenta for any id this
## table doesn't recognize yet (this project's established "visible fail,
## never silent" precedent) -- a placeholder, not a real atlas lookup.
const DEBUG_BLOCK_COLORS: Dictionary[int, Color] = {
	1: Color("9CAD6E"),  # art-bible SS4.3 Lowland band -- Story 006's only terrain block-type id today
}
const DEBUG_UNKNOWN_COLOR: Color = Color(1.0, 0.0, 1.0)

## Voxel World / Grid Data dependency (ADR-0001 injected-tier). Wired via a
## scene file's Inspector in production, or assigned directly in a headless
## test/tool -- never read inside `_ready()` (see [method setup]).
@export var grid: VoxelWorldGrid

## True once [method setup] has completed.
var _is_set_up: bool = false

## ONE shared [ShaderMaterial] instance for every chunk this mesher ever
## builds (art-bible SS8.9.1 canonical contract, ADR-0014 Decision Section
## 2) -- constructed exactly once, at this node's own construction (field
## initializer), never per-chunk.
var _material: ShaderMaterial = _build_shared_material()

## Tracked chunk -> [MeshInstance3D] child, keyed identically to
## [VoxelWorldGrid]'s internal chunk storage
## (`Vector2i(cell.x / CHUNK_SIZE, cell.z / CHUNK_SIZE)`). Only chunks this
## mesher was explicitly asked to [method build_chunk] appear here -- see the
## class doc comment's Scope note.
var _chunk_nodes: Dictionary[Vector2i, MeshInstance3D] = {}


## Explicitly callable wiring entry point (ADR-0001). Asserts [member grid]
## (and its wired [VoxelWorldConfig]) are present, then subscribes to both of
## [VoxelWorldGrid]'s change signals so an already-[method build_chunk]'d
## chunk rebuilds automatically on any write inside (or bordering) it
## (TR-voxel-world-025) -- a chunk never asked for is left alone (Scope
## note).
func setup() -> void:
	assert(grid != null, "VoxelWorldMesher.grid not wired")
	assert(grid.config != null, "VoxelWorldMesher.grid.config not wired")
	grid.cell_changed.connect(_on_cell_changed)
	grid.cells_changed_batch.connect(_on_cells_changed_batch)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Builds (or rebuilds) the whole-chunk [ArrayMesh] for [param chunk_coord]
## from [member grid]'s CURRENT cell data -- the ONE mesher construction site
## (class doc comment). Creates the chunk's [MeshInstance3D] child on first
## call; subsequent calls reuse it and simply replace `.mesh` (ADR-0014
## Decision Section 2: "rebuilt whole on any cell change"). A chunk with zero
## exposed faces (fully empty, or fully buried with no border to air) gets
## `.mesh = null` -- the [MeshInstance3D] itself is kept (never freed), since
## chunk-instance lifecycle/unloading is Story 015's concern, not this
## method's.
func build_chunk(chunk_coord: Vector2i) -> void:
	assert(grid != null, "VoxelWorldMesher.grid not wired")
	assert(grid.config != null, "VoxelWorldMesher.grid.config not wired")
	var arrays: Array = _build_chunk_arrays(chunk_coord)
	var mesh_instance: MeshInstance3D = _get_or_create_chunk_node(chunk_coord)
	if arrays.is_empty():
		mesh_instance.mesh = null
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	mesh_instance.mesh = mesh


## Returns the tracked [MeshInstance3D] for [param chunk_coord], or `null` if
## [method build_chunk] was never called for it.
func get_chunk_mesh_instance(chunk_coord: Vector2i) -> MeshInstance3D:
	return _chunk_nodes.get(chunk_coord)


## Whether [param chunk_coord] has ever been passed to [method build_chunk]
## -- the "already tracked" gate the change-signal handlers check before
## auto-rebuilding (Scope note).
func is_chunk_tracked(chunk_coord: Vector2i) -> bool:
	return _chunk_nodes.has(chunk_coord)


## Returns the ONE shared [ShaderMaterial] instance (art-bible SS8.9.1) --
## exposed read-only for tests/tools that need to inspect it (e.g. confirming
## `cull_mode`), never for a caller to assign a second, per-chunk instance.
func get_shared_material() -> ShaderMaterial:
	return _material


## Single-cell change reaction (TR-voxel-world-025): rebuilds [param cell]'s
## own chunk if tracked, and its chunk-boundary neighbor(s) if [param cell]
## sits on a chunk edge and that neighboring chunk is ALSO tracked (a
## solid/air change at a chunk's border changes the adjacent chunk's own
## face-culling at that shared boundary -- class doc comment Scope note).
func _on_cell_changed(cell: Vector3i, _before: CellContents, _after: CellContents) -> void:
	_rebuild_tracked_chunks_touched_by(cell)


## Batched-write change reaction (TR-voxel-world-042/025): the same per-cell
## chunk-touching logic as [method _on_cell_changed], applied once per
## changed cell in [param changes], with each touched-and-tracked chunk
## rebuilt exactly once even if multiple changed cells map to it.
func _on_cells_changed_batch(changes: Array[CellChangeRecord]) -> void:
	var touched: Dictionary[Vector2i, bool] = {}
	for record: CellChangeRecord in changes:
		for key: Vector2i in _chunk_keys_touched_by(record.cell):
			touched[key] = true
	for key: Vector2i in touched:
		if _chunk_nodes.has(key):
			build_chunk(key)


## Rebuilds every tracked chunk [param cell] touches (its own chunk, plus a
## chunk-boundary neighbor if applicable) -- the single-cell path's version of
## [method _on_cells_changed_batch]'s dedup loop.
func _rebuild_tracked_chunks_touched_by(cell: Vector3i) -> void:
	for key: Vector2i in _chunk_keys_touched_by(cell):
		if _chunk_nodes.has(key):
			build_chunk(key)


## Returns every chunk coordinate [param cell] can affect the MESH of: its
## own chunk, always -- plus the chunk across a chunk boundary when [param
## cell] sits on that boundary's outermost local index (matching
## [VoxelWorldGrid.CHUNK_SIZE] / that class's own chunk-key formula).
func _chunk_keys_touched_by(cell: Vector3i) -> Array[Vector2i]:
	var chunk_size: int = VoxelWorldGrid.CHUNK_SIZE
	var own_key := Vector2i(cell.x / chunk_size, cell.z / chunk_size)
	var keys: Array[Vector2i] = [own_key]
	var local_x: int = cell.x - own_key.x * chunk_size
	var local_z: int = cell.z - own_key.y * chunk_size
	if local_x == 0:
		keys.append(Vector2i(own_key.x - 1, own_key.y))
	elif local_x == chunk_size - 1:
		keys.append(Vector2i(own_key.x + 1, own_key.y))
	if local_z == 0:
		keys.append(Vector2i(own_key.x, own_key.y - 1))
	elif local_z == chunk_size - 1:
		keys.append(Vector2i(own_key.x, own_key.y + 1))
	return keys


## Returns the [MeshInstance3D] child tracked for [param chunk_coord],
## creating and adding it (and registering it in [member _chunk_nodes]) on
## first call.
func _get_or_create_chunk_node(chunk_coord: Vector2i) -> MeshInstance3D:
	if _chunk_nodes.has(chunk_coord):
		return _chunk_nodes[chunk_coord]
	var mesh_instance := MeshInstance3D.new()
	add_child(mesh_instance)
	_chunk_nodes[chunk_coord] = mesh_instance
	return mesh_instance


## Face-culled geometry pass for one chunk (ADR-0014 Decision Section 2:
## "faces emitted only where a cell borders air"). Walks every cell in
## [param chunk_coord]'s full configured vertical extent
## ([VoxelWorldConfig.min_y]..[VoxelWorldConfig.max_y], inclusive) via
## [method VoxelWorldGrid.get_cell] (the grid's O(1) read API -- never
## [VoxelWorldGrid]'s internal storage directly). For every non-empty cell,
## tests each of the 6 [constant FACE_NORMALS] directions via [method
## _is_air] -- solid cells touching an empty OR OUT-OF-BOUNDS neighbor (world
## edge; [method VoxelWorldGrid.get_cell] returns `null` there) emit that
## face, so the world's outer boundary renders its outward-facing surface
## exactly like any other air-adjacent face. Returns an empty [Array] (never
## a populated-but-zero-length arrays [Array]) when the chunk has zero
## exposed faces -- [method build_chunk]'s empty-mesh contract depends on
## this exact return shape.
##
## THE ONE mesher geometry-assembly site (class doc comment) -- no other
## method in this class or file builds triangle data.
func _build_chunk_arrays(chunk_coord: Vector2i) -> Array:
	var chunk_size: int = VoxelWorldGrid.CHUNK_SIZE
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for local_x in chunk_size:
		var global_x: int = chunk_coord.x * chunk_size + local_x
		for local_z in chunk_size:
			var global_z: int = chunk_coord.y * chunk_size + local_z
			for global_y in range(grid.config.min_y, grid.config.max_y + 1):
				var cell := Vector3i(global_x, global_y, global_z)
				var contents: CellContents = grid.get_cell(cell)
				if contents == null or contents.is_empty():
					continue
				var color: Color = DEBUG_BLOCK_COLORS.get(contents.block_type_id, DEBUG_UNKNOWN_COLOR)
				for face_index in FACE_NORMALS.size():
					if _is_air(cell + FACE_NORMALS[face_index]):
						_append_face(verts, normals, colors, indices, cell, face_index, color)
	if verts.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Air/solid predicate for face-culling (ADR-0014 Decision Section 2): a cell
## OUTSIDE the configured world bounds ([method VoxelWorldGrid.get_cell]
## returns `null`) counts as air.
func _is_air(cell: Vector3i) -> bool:
	var contents: CellContents = grid.get_cell(cell)
	return contents == null or contents.is_empty()


## Appends one face's two triangles (4 shared corner vertices, fan-
## triangulated) to the in-progress mesh arrays. [param face_index] indexes
## both [constant FACE_NORMALS] and [constant FACE_CORNERS] -- see that
## constant's doc comment for the winding derivation this method's fixed
## `(0,1,2)` + `(0,2,3)` triangulation relies on.
func _append_face(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		cell: Vector3i, face_index: int, color: Color) -> void:
	var base: int = verts.size()
	var normal := Vector3(FACE_NORMALS[face_index])
	var corners: Array = FACE_CORNERS[face_index]
	for corner: Vector3i in corners:
		verts.append((Vector3(cell) + Vector3(corner)) * VoxelWorldConfig.CELL_SIZE)
		normals.append(normal)
		colors.append(color)
	indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Constructs the ONE shared [ShaderMaterial] instance every chunk's surface
## uses (see [member _material]'s doc comment).
## `res://assets/shaders/terrain_chunk.gdshader` ships `cull_back` explicitly
## (never `cull_disabled`) -- see that shader file's own doc comment and
## `mesher_material_contract_test.gd`'s grep guard.
func _build_shared_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/terrain_chunk.gdshader")
	return material
