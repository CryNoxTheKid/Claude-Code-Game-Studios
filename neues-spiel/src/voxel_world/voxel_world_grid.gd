## Voxel World / Grid Data's coordinate math + bounds (Story vox-001,
## ADR-0002 + ADR-0001). Owns Cell<->World conversion (GDD Formulas) and the
## in-bounds predicate (Core Rule 1) that together satisfy
## TR-voxel-world-035/036/037.
##
## Injected-tier module (ADR-0001): [member config] is wired via a scene
## file's Inspector in production, or assigned directly in a headless test;
## all wiring/validation lives in [method setup], never `_ready()`.
##
## Story 002 (this revision) adds the chunked packed-array cell storage and
## its O(1) [method get_cell]/[method set_cell]/[method clear_cell] accessors
## per ADR-0014 Decision §1/Implementation Notes -- storage/streaming
## RESIDENCY (paging chunks to on-disk region files, ADR-0015) remains Story
## 010's concern; every chunk this class ever touches stays resident for the
## session's lifetime.
##
## Story 003 (this revision) adds [method bulk_write] and [signal
## cells_changed_batch] (ADR-0014 Implementation Notes; TR-voxel-world-042/
## 043) -- a bulk write reuses the same core mutation [method set_cell] uses
## ([method _apply_write]) but suppresses the per-cell [signal cell_changed]
## for the duration of the call, emitting exactly ONE batched signal instead.
##
## Story 004 (this revision) adds [method get_neighbors] and [method
## raycast_cells] -- completing Core Rule 5's read API (TR-voxel-world-031).
## [method raycast_cells] is a manual Amanatides-Woo DDA grid walk against
## [method get_cell] (ADR-0004 Decision, ADR-0014 Decision Section 4;
## TR-voxel-world-017/049/018) -- no physics API of any kind is used for
## picking anywhere in this file (grep-verified by
## `tests/integration/voxel_world/dda_raycast_test.gd`). Procedural terrain
## generation using [member VoxelWorldConfig.base_height]/`amplitude`/
## `frequency` remains Story 006's scope.
class_name VoxelWorldGrid
extends Node

## Chunk width/depth in cells (ADR-0014 Decision §1: "16×16-column chunks")
## -- a locked engine/storage-shape constant, not a designer tuning knob
## (same rationale as [VoxelWorldConfig.CELL_SIZE]). Chunks span the FULL
## configured vertical extent (no vertical chunking), matching the reference
## `prototypes/last-seal-vertical-slice/voxel_world.gd`'s `CHUNK`.
const CHUNK_SIZE: int = 16

## Private per-chunk storage (ADR-0014 Decision §1: "each chunk holds a flat
## `PackedByteArray`-class buffer indexed by local offset"). Two parallel
## same-length buffers, one per [CellContents] field -- keeps every cell's
## record at a fixed 2 bytes (within the ADR's ~1-4 B/cell budget,
## TR-voxel-world-041) while keeping block-type and material lookups both
## O(1) array-index reads with no bit-packing. Never exposed outside this
## file -- every caller only ever sees [CellContents].
class _ChunkBuffer:
	var block_type_ids: PackedByteArray
	var material_ids: PackedByteArray

	func _init(cell_count: int) -> void:
		block_type_ids.resize(cell_count)
		material_ids.resize(cell_count)
		# PackedByteArray.resize() zero-fills every new element -- this IS
		# the lazy-allocation contract (CellContents.EMPTY_BLOCK_TYPE_ID ==
		# 0), no explicit fill pass needed (matches the reference's own
		# "zero-filled = air" comment).


## Fires exactly once per single [method set_cell]/[method clear_cell] call
## that targets an in-bounds cell (Core Rule 6, TR-voxel-world-032) --
## identifies the changed cell and its full before/after [CellContents].
## Never fires for an out-of-bounds write (nothing changed) and is never
## batched here -- Story 003 owns the separate bulk/batched write path and
## its own single-batched-signal contract.
signal cell_changed(cell: Vector3i, before: CellContents, after: CellContents)

## Fires exactly ONCE per [method bulk_write] call that changes at least one
## cell (TR-voxel-world-042) -- carries the full per-cell [CellChangeRecord]
## array (cell, before, after) for every affected cell, the SAME array
## [method bulk_write] returns (TR-voxel-world-043). [signal cell_changed] is
## suppressed for the duration of a [method bulk_write] call -- Control
## Manifest Forbidden: "one signal per cell on a bulk operation." Never fires
## for a batch that changes zero cells (an empty [param changes], or one
## whose every cell is out of bounds) -- "nothing changed" emits nothing.
signal cells_changed_batch(changes: Array[CellChangeRecord])

## Tuning config dependency (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: VoxelWorldConfig

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## The BLOCKING-tagged subset of the most recent `config.validate()` result,
## if any -- mirrors `ReferenceConfigConsumer`'s boot-gate contract (ADR-0002
## Decision, ADR-0005 terminal-halt reuse).
var _boot_blocking_issues: Array[String] = []

## Lazily-allocated per-chunk storage, keyed by chunk coordinate
## (`Vector2i(cell.x / CHUNK_SIZE, cell.z / CHUNK_SIZE)`) -- only chunks
## touched by at least one [method set_cell]/[method clear_cell] call exist
## here; an absent key means "still all-empty," matching [method get_cell]'s
## empty-without-allocating fast path (TR-voxel-world-047 read purity). This
## story keeps every touched chunk resident for the session's lifetime --
## paging/eviction is Story 010 (ADR-0015), not this class's concern yet.
var _chunks: Dictionary[Vector2i, _ChunkBuffer] = {}


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config] was wired, then applies ADR-0002's two-tier policy: every
## non-BLOCKING issue is a clamp+warn (already applied by `validate()`
## itself) and is logged via `push_warning`; any BLOCKING issue (`min_y <=
## max_y`) is recorded for [method get_boot_blocking_issues] instead of being
## treated as fatal here -- the halt decision lives in [GameWorld]'s boot
## gate (ADR-0005), not in this module.
func setup() -> void:
	assert(config != null, "VoxelWorldGrid.config not wired")
	var issues: Array[String] = config.validate()
	_boot_blocking_issues = issues.filter(
		func(issue: String) -> bool: return issue.begins_with(ConfigResource.BLOCKING_PREFIX)
	)
	for issue: String in issues:
		if not issue.begins_with(ConfigResource.BLOCKING_PREFIX):
			push_warning(issue)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the BLOCKING-tagged issues (if any) found in the most recent
## `config.validate()` call -- see `ReferenceConfigConsumer` for the
## demonstrated [GameWorld] boot-gate wiring this mirrors.
func get_boot_blocking_issues() -> Array[String]:
	return _boot_blocking_issues


## Cell->World conversion (GDD Formulas, TR-voxel-world-035): returns the
## cell's **center** point, `Vector3(cell) * cell_size + Vector3(0.5,0.5,0.5)
## * cell_size`. Pure and stateless -- exercisable directly with any
## [Vector3i], without an instance or [method setup].
static func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell) * VoxelWorldConfig.CELL_SIZE + Vector3(0.5, 0.5, 0.5) * VoxelWorldConfig.CELL_SIZE


## World->Cell conversion (GDD Formulas, TR-voxel-world-036): `floor()` per
## axis, never truncation -- so a world position fractionally below 0.0
## (e.g. x = -0.001) floors to a negative cell instead of aliasing into cell
## 0 (Core Rule 1 already guarantees no negative cell legitimately exists;
## this is defensive hardening for near-zero positions). Pure and
## stateless; does NOT check bounds -- see [method is_in_bounds] and
## [method query_world_to_cell] for the bounds-aware API.
static func world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / VoxelWorldConfig.CELL_SIZE),
		floori(world_pos.y / VoxelWorldConfig.CELL_SIZE),
		floori(world_pos.z / VoxelWorldConfig.CELL_SIZE)
	)


## In-bounds predicate (Core Rule 1, TR-voxel-world-027): exact non-negative
## integer comparisons against the configured world extent -- `x` in
## `[0, world_width_cells)`, `y` in `[min_y, max_y]` (inclusive both ends,
## matching the terrain height formula's own inclusive clamp range), `z` in
## `[0, world_depth_cells)`. Never epsilon-tolerant (TR-voxel-world-040).
func is_in_bounds(cell: Vector3i) -> bool:
	assert(config != null, "VoxelWorldGrid.config not wired")
	return (
		cell.x >= 0 and cell.x < config.world_width_cells
		and cell.y >= config.min_y and cell.y <= config.max_y
		and cell.z >= 0 and cell.z < config.world_depth_cells
	)


## Bounds-aware World->Cell query (TR-voxel-world-037): composes [method
## world_to_cell] with [method is_in_bounds] and returns an explicit
## [CellQueryResult] -- never a silent clamp to the edge, never a crash.
## `result.cell` is always the exact (unclamped) floored cell; callers MUST
## check `result.in_bounds` before trusting it as a valid grid address.
func query_world_to_cell(world_pos: Vector3) -> CellQueryResult:
	var cell: Vector3i = VoxelWorldGrid.world_to_cell(world_pos)
	return CellQueryResult.new(is_in_bounds(cell), cell)


## The 6 face-adjacent neighbor offsets (Story vox-004, Core Rule 5 read API
## completion, TR-voxel-world-031) -- fixed +/-1 integer offsets along each
## axis, in a stable, deterministic order. Locked engine-shape data, not a
## designer tuning knob (same rationale as [constant CHUNK_SIZE]).
const NEIGHBOR_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Neighbor lookup (Story vox-004, Core Rule 5, TR-voxel-world-031): returns
## [param cell]'s 6 face-adjacent grid neighbors via [constant NEIGHBOR_OFFSETS]'s
## fixed integer offsets, bounds-checked via [method is_in_bounds] (Story 001's
## out-of-grid rule, TR-voxel-world-037) -- an offset that falls outside the
## configured world bounds is OMITTED from the result entirely, never included
## as an invalid/sentinel entry (there is no "partial" neighbor to represent;
## a cell simply has fewer neighbors at the world's edge). Pure and
## side-effect-free -- never touches [member _chunks], safe to call every
## frame (TR-voxel-world-047 read-purity guarantee).
func get_neighbors(cell: Vector3i) -> Array[Vector3i]:
	assert(config != null, "VoxelWorldGrid.config not wired")
	var neighbors: Array[Vector3i] = []
	for offset: Vector3i in NEIGHBOR_OFFSETS:
		var neighbor: Vector3i = cell + offset
		if is_in_bounds(neighbor):
			neighbors.append(neighbor)
	return neighbors


## DDA cell-picking raycast (Story vox-004, ADR-0004 Decision + ADR-0014
## Decision Section 4; TR-voxel-world-017/049/047/018): a manual
## Amanatides-Woo grid walk against [method get_cell] -- returns the first
## occupied cell along the ray (or an explicit miss, [RaycastHitResult]) in
## O(ray-length-in-cells) time, INDEPENDENT of grid size (TR-voxel-world-019)
## and completely independent of the eventual rendering mechanism
## (TR-voxel-world-049). Never mutates [member _chunks] or any cell contents
## -- safe to call every frame for hover picking (TR-voxel-world-047). ZERO
## `PhysicsServer3D`/`RayCast3D`/`intersect_ray` usage anywhere in this method
## (TR-voxel-world-018; grep-verified by
## `tests/integration/voxel_world/dda_raycast_test.gd`).
##
## "Solid" for picking purposes is simply "non-empty"
## ([method CellContents.is_empty] false) -- Voxel World never resolves
## opaque block-type ids to gameplay meaning (Core Rule 2, TR-voxel-world-028),
## so no per-block-type solidity special-casing (e.g. a "water doesn't pick"
## rule) belongs at this layer; that would require this class to know what a
## given id MEANS, which it deliberately never does. Any such rule is a
## caller-side concern layered on top via [param extra_solid], not this
## method's.
##
## [param extra_solid] is an optional `Callable(cell: Vector3i) -> bool`
## overlay evaluated at every stepped cell (via OR) alongside the real grid
## data -- the exact hook the ADR-0014 Section 4 ghost-anchoring predicate
## plugs into later (Building System slice). Constructing or populating that
## overlay is explicitly OUT OF SCOPE for this story: this method only
## accepts and evaluates a predicate IF a caller supplies one; the default
## `Callable()` is invalid and is simply skipped.
##
## Bounds handling: the ray's origin MAY lie outside the configured world
## bounds (e.g. a camera positioned just outside the world's edge looking
## in) -- an out-of-bounds cell is never itself solid and stepping continues.
## Once the walk has entered the bounds at least once, the FIRST subsequent
## step back outside bounds terminates the walk as a miss immediately (the
## world is a convex axis-aligned box; a straight ray can enter it at most
## once and exit at most once, so re-entry after leaving is impossible) --
## this is the "ray exiting world bounds returns none" contract. A ray whose
## origin is outside bounds and which never enters them within `max_distance`
## also returns a miss, naturally, once the loop exhausts `max_distance`.
func raycast_cells(origin: Vector3, direction: Vector3, max_distance: float, extra_solid: Callable = Callable()) -> RaycastHitResult:
	assert(config != null, "VoxelWorldGrid.config not wired")
	var dir: Vector3 = direction.normalized()
	if dir.length_squared() == 0.0:
		return RaycastHitResult.new(false)

	var cell: Vector3i = VoxelWorldGrid.world_to_cell(origin)
	var entered_bounds: bool = false
	if is_in_bounds(cell):
		entered_bounds = true
		if _is_pick_solid(cell, extra_solid):
			return RaycastHitResult.new(true, cell, Vector3i.ZERO)

	var step: Vector3i = Vector3i(
		1 if dir.x > 0.0 else (-1 if dir.x < 0.0 else 0),
		1 if dir.y > 0.0 else (-1 if dir.y < 0.0 else 0),
		1 if dir.z > 0.0 else (-1 if dir.z < 0.0 else 0)
	)
	var t_max: Vector3 = Vector3(INF, INF, INF)
	var t_delta: Vector3 = Vector3(INF, INF, INF)
	if dir.x != 0.0:
		t_delta.x = 1.0 / absf(dir.x)
		var boundary_x: float = float(cell.x + (1 if step.x > 0 else 0))
		t_max.x = (boundary_x - origin.x) / dir.x
	if dir.y != 0.0:
		t_delta.y = 1.0 / absf(dir.y)
		var boundary_y: float = float(cell.y + (1 if step.y > 0 else 0))
		t_max.y = (boundary_y - origin.y) / dir.y
	if dir.z != 0.0:
		t_delta.z = 1.0 / absf(dir.z)
		var boundary_z: float = float(cell.z + (1 if step.z > 0 else 0))
		t_max.z = (boundary_z - origin.z) / dir.z

	var t: float = 0.0
	while t <= max_distance:
		var normal: Vector3i
		if t_max.x < t_max.y and t_max.x < t_max.z:
			t = t_max.x
			t_max.x += t_delta.x
			cell.x += step.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			t = t_max.y
			t_max.y += t_delta.y
			cell.y += step.y
			normal = Vector3i(0, -step.y, 0)
		else:
			t = t_max.z
			t_max.z += t_delta.z
			cell.z += step.z
			normal = Vector3i(0, 0, -step.z)
		if t > max_distance:
			break
		if is_in_bounds(cell):
			entered_bounds = true
			if _is_pick_solid(cell, extra_solid):
				return RaycastHitResult.new(true, cell, normal)
		elif entered_bounds:
			return RaycastHitResult.new(false)
		# else: not yet entered bounds -- keep stepping, may enter later.
	return RaycastHitResult.new(false)


## Solidity predicate for [method raycast_cells] -- see that method's doc
## comment for why "solid" is simply "non-empty" at this layer, and why
## [param extra_solid] exists but is never populated by this story. [param cell]
## is assumed already bounds-checked by the caller (both [method raycast_cells]
## call sites check [method is_in_bounds] first) -- [method get_cell] would
## otherwise return `null` here and crash on [method CellContents.is_empty].
func _is_pick_solid(cell: Vector3i, extra_solid: Callable) -> bool:
	if not get_cell(cell).is_empty():
		return true
	return extra_solid.is_valid() and bool(extra_solid.call(cell))


## Chunked read API (Core Rule 5, TR-voxel-world-031): returns the occupant
## matching the last write to [param cell] -- O(1) regardless of grid size
## (TR-voxel-world-019), a chunk-coordinate Dictionary lookup plus fixed
## local-offset arithmetic, never a full-grid scan. Never mutates
## [member _chunks] -- an untouched chunk returns [method CellContents.empty]
## without being allocated, and no chunk lookup ever writes
## (TR-voxel-world-047 read-purity guarantee, safe to call every frame for
## hover picking). Returns `null` for a cell outside the configured world
## bounds -- an explicit "outside grid" result, never a silent clamp
## (TR-voxel-world-037).
func get_cell(cell: Vector3i) -> CellContents:
	assert(config != null, "VoxelWorldGrid.config not wired")
	if not is_in_bounds(cell):
		return null
	var key: Vector2i = _chunk_key(cell)
	if not _chunks.has(key):
		return CellContents.empty()
	var buffer: _ChunkBuffer = _chunks[key]
	var offset: int = _local_offset(cell, key)
	return CellContents.new(buffer.block_type_ids[offset], buffer.material_ids[offset])


## Chunked low-level write API (Core Rule 5, TR-voxel-world-007): overwrites
## [param cell]'s contents unconditionally and returns the PREVIOUS contents
## (TR-voxel-world-045) -- whether overwriting SHOULD be allowed is the
## caller's (Building System's) decision, not this layer's. Lazily allocates
## the target chunk on first touch (this story's storage strategy; Story 010
## / ADR-0015 owns paging/eviction, not this class). Emits
## [signal cell_changed] exactly once identifying [param cell] and its
## before/after [CellContents] (TR-voxel-world-032). Returns `null` (no
## write, no signal -- nothing changed) for a cell outside the configured
## world bounds (TR-voxel-world-037).
func set_cell(cell: Vector3i, contents: CellContents) -> CellContents:
	assert(config != null, "VoxelWorldGrid.config not wired")
	assert(contents != null, "VoxelWorldGrid.set_cell contents must not be null")
	assert(
		contents.block_type_id >= 0 and contents.block_type_id <= 255,
		"VoxelWorldGrid.set_cell block_type_id out of packed-byte range 0-255: %s" % contents.block_type_id
	)
	assert(
		contents.material_id >= 0 and contents.material_id <= 255,
		"VoxelWorldGrid.set_cell material_id out of packed-byte range 0-255: %s" % contents.material_id
	)
	var record: CellChangeRecord = _apply_write(cell, contents)
	if record == null:
		return null
	cell_changed.emit(record.cell, record.before, record.after)
	return record.before


## Convenience wrapper for [method set_cell] with [method CellContents.empty]
## (Core Rule 5's "clear a cell") -- identical before/after-signal contract,
## including the `null`/no-op result for an out-of-bounds cell.
func clear_cell(cell: Vector3i) -> CellContents:
	return set_cell(cell, CellContents.empty())


## Bulk write API (Story vox-003, ADR-0014 Implementation Notes;
## TR-voxel-world-042/043): applies every (cell, contents) pair in [param
## changes] under this single call, reusing [method _apply_write] -- the same
## core mutation [method set_cell] uses -- for each cell, but suppressing
## [signal cell_changed] for every individual cell (Control Manifest
## Forbidden: "one signal per cell on a bulk operation"). Emits
## [signal cells_changed_batch] exactly ONCE at the end, carrying the full
## per-cell [CellChangeRecord] array (cell, before, after) for every affected
## cell -- the SAME array this method returns, so the Building System's undo
## stack can restore every cell individually from either the signal payload
## or the return value (TR-voxel-world-043).
##
## A cell outside the configured world bounds is skipped -- the same
## "nothing changed" contract as [method set_cell]'s `null` return for a
## single out-of-bounds write; it contributes no [CellChangeRecord] and is
## never counted toward the batch. An empty [param changes] (or one whose
## every cell is out of bounds) applies nothing and emits nothing -- there is
## no "batch of zero" signal.
##
## [param changes] is a typed `Dictionary[Vector3i, CellContents]` rather
## than an ordered array of pairs -- a caller targeting the same cell twice
## is naturally deduplicated (the last value for that key wins, matching a
## single [method set_cell] call's own overwrite semantics), and Godot's
## [Dictionary] preserves insertion order, so per-cell write order stays
## deterministic.
func bulk_write(changes: Dictionary[Vector3i, CellContents]) -> Array[CellChangeRecord]:
	assert(config != null, "VoxelWorldGrid.config not wired")
	var records: Array[CellChangeRecord] = []
	for cell: Vector3i in changes:
		var contents: CellContents = changes[cell]
		assert(contents != null, "VoxelWorldGrid.bulk_write contents must not be null")
		assert(
			contents.block_type_id >= 0 and contents.block_type_id <= 255,
			"VoxelWorldGrid.bulk_write block_type_id out of packed-byte range 0-255: %s" % contents.block_type_id
		)
		assert(
			contents.material_id >= 0 and contents.material_id <= 255,
			"VoxelWorldGrid.bulk_write material_id out of packed-byte range 0-255: %s" % contents.material_id
		)
		var record: CellChangeRecord = _apply_write(cell, contents)
		if record != null:
			records.append(record)
	if not records.is_empty():
		cells_changed_batch.emit(records)
	return records


## Shared write-application core (Story vox-003, ADR-0014 Implementation
## Notes: bulk_write "reuses the single-write mechanism internally") --
## performs the bounds check, lazy chunk allocation, and packed-buffer
## mutation common to both [method set_cell] and [method bulk_write],
## returning the resulting [CellChangeRecord] (or `null` for an
## out-of-bounds cell -- nothing changed, no record, and deliberately no
## signal of any kind here; emitting [signal cell_changed]/[signal
## cells_changed_batch] is each caller's own responsibility, not this
## helper's). Callers validate [param contents] (packed-byte range,
## non-null) BEFORE calling this -- this function assumes that check already
## passed.
func _apply_write(cell: Vector3i, contents: CellContents) -> CellChangeRecord:
	if not is_in_bounds(cell):
		return null
	var key: Vector2i = _chunk_key(cell)
	if not _chunks.has(key):
		_chunks[key] = _ChunkBuffer.new(CHUNK_SIZE * CHUNK_SIZE * _chunk_height())
	var buffer: _ChunkBuffer = _chunks[key]
	var offset: int = _local_offset(cell, key)
	var before := CellContents.new(buffer.block_type_ids[offset], buffer.material_ids[offset])
	buffer.block_type_ids[offset] = contents.block_type_id
	buffer.material_ids[offset] = contents.material_id
	var after := CellContents.new(contents.block_type_id, contents.material_id)
	return CellChangeRecord.new(cell, before, after)


## Chunk coordinate for [param cell]
## (`Vector2i(cell.x / CHUNK_SIZE, cell.z / CHUNK_SIZE)`). Integer division
## floors correctly here because [method is_in_bounds] already guarantees
## `cell.x`/`cell.z` are non-negative (Core Rule 1) before this is ever
## reached from [method get_cell]/[method set_cell].
func _chunk_key(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x / CHUNK_SIZE, cell.z / CHUNK_SIZE)


## Flat local index within a chunk's buffers, matching the
## `(local_y * CHUNK_SIZE + local_z) * CHUNK_SIZE + local_x` layout used by
## the reference `prototypes/last-seal-vertical-slice/voxel_world.gd`
## mesher -- keeping the same layout here means Story 007's production
## mesher can walk these buffers with the same indexing scheme.
func _local_offset(cell: Vector3i, key: Vector2i) -> int:
	var local_x: int = cell.x - key.x * CHUNK_SIZE
	var local_z: int = cell.z - key.y * CHUNK_SIZE
	var local_y: int = cell.y - config.min_y
	return (local_y * CHUNK_SIZE + local_z) * CHUNK_SIZE + local_x


## Full vertical extent of one chunk's buffers, in cells -- chunks are never
## split vertically (ADR-0014 Decision §1), so this is simply the whole
## configured Y range.
func _chunk_height() -> int:
	return config.max_y - config.min_y + 1
