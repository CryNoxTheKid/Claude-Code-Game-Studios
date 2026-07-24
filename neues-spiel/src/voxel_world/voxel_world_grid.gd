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
## `tests/integration/voxel_world/dda_raycast_test.gd`).
##
## Story 006 (this revision) adds [method generate_terrain] -- procedural
## terrain fill (GDD Formulas' `procedural_terrain_height`, TR-voxel-world-038/
## 039) writing through [method bulk_write] (ADR-0014 Implementation Notes: at
## most ONE batched signal, TR-voxel-world-044) and the [enum GridState]
## Uninitialized->Generated lifecycle transition (TR-voxel-world-029). Meshing
## the generated terrain (Story 007/015) and removing it via dig orders
## (Story 009) remain out of this class's scope.
##
## Story vox-005 (this revision) adds [method iterate_occupied] -- the
## occupied-cells iteration API (ADR-0014 primary / ADR-0012 secondary;
## TR-voxel-world-021/048/033) the future Save/Load orchestrator (VS-tier)
## will consume; torn-read-free by construction (a plain synchronous scan,
## no locks) rather than via any locking mechanism.
##
## Story vox-010 (this revision, ADR-0015) adds paged region-file residency
## -- [method update_residency] computes the resident working set (camera-
## near [member VoxelWorldConfig.view_radius_chunks] union active-settlement
## [member VoxelWorldConfig.settlement_radius_chunks], around two injected
## focus cells) and pages chunks in/out of [member _chunks] against on-disk
## [VoxelWorldRegionFile]s (TR-voxel-world-053). This is OPT-IN: a grid that
## never calls [method update_residency] behaves byte-for-byte as before this
## story (every touched chunk stays resident for the session, zero
## filesystem touches) -- [member _residency_active] gates the only
## behavioral change to an existing method ([method get_cell]'s page-in
## check). Page-in/eviction here are SYNCHRONOUS (this story's own scope);
## moving them onto a `WorkerThreadPool` is Story 011, the per-frame time
## budget is Story 012, the in-flight-write read-through cache is Story 013,
## and load-before-write for a WRITE that targets a non-resident chunk is
## Story 014 (today, [method _apply_write] still lazily allocates a fresh
## chunk for such a write, same as before this story -- a known, deliberately
## deferred gap, not a regression). A pristine chunk (never dirtied, absent
## from its region file) pages in via deterministic terrain regeneration from
## the seed ([method _regenerate_chunk_from_seed], ADR-0015 Decision §5),
## never persisted until an actual write dirties it.
class_name VoxelWorldGrid
extends Node

## Chunk width/depth in cells (ADR-0014 Decision §1: "16×16-column chunks")
## -- a locked engine/storage-shape constant, not a designer tuning knob
## (same rationale as [VoxelWorldConfig.CELL_SIZE]). Chunks span the FULL
## configured vertical extent (no vertical chunking), matching the reference
## `prototypes/last-seal-vertical-slice/voxel_world.gd`'s `CHUNK`.
const CHUNK_SIZE: int = 16

## System lifecycle state (GDD "System lifecycle, not per-cell state" table,
## TR-voxel-world-029) -- [constant UNINITIALIZED] is this grid's state at
## construction, before [method generate_terrain] has ever run;
## [constant GENERATED] is entered once [method generate_terrain] completes
## and persists for the session. Deliberately NOT an access guard on any
## other method (`get_cell`/`set_cell`/`bulk_write`/`raycast_cells` all
## predate this story and none of their contracts changed) -- this exists
## purely as the observable milestone AC1/AC-4 (QA plan) require.
enum GridState { UNINITIALIZED, GENERATED }

## Opaque terrain block-type id (Story vox-006) [CellContents]'s "Resource &
## Item Database vocabulary" doc-comment applies -- this class never resolves
## what the id MEANS (Core Rule 2, TR-voxel-world-028); a single fixed id is
## a placeholder consistent with the GDD's "terrain-band/sand 1..5 value
## family" convention (TR-voxel-world-051, Story 009 dig-order eligibility),
## not itself a designer tuning knob (same "locked engine-shape data"
## rationale as [constant CHUNK_SIZE]/[constant NEIGHBOR_OFFSETS]).
const TERRAIN_BLOCK_TYPE_ID: int = 1

## Opaque terrain material id (Story vox-006) -- paired with [constant
## TERRAIN_BLOCK_TYPE_ID]; see that constant's doc comment. Texturing/material
## variety is a later (mesher/RID) concern, out of this story's scope.
const TERRAIN_MATERIAL_ID: int = 0

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

## RESIDENT per-chunk storage, keyed by chunk coordinate
## (`Vector2i(cell.x / CHUNK_SIZE, cell.z / CHUNK_SIZE)`) -- only chunks
## touched by at least one [method set_cell]/[method clear_cell] call, or
## paged in by [method update_residency], exist here; an absent key means
## "still all-empty (or not currently resident)," matching [method get_cell]'s
## empty/page-in fast path (TR-voxel-world-047 read purity, TR-voxel-world-053
## residency). A grid that never calls [method update_residency] keeps every
## touched chunk resident for the session's lifetime, exactly as before Story
## vox-010 -- this dictionary IS the resident set; [method
## get_resident_chunk_keys]/[method is_chunk_resident] report it directly.
var _chunks: Dictionary[Vector2i, _ChunkBuffer] = {}

## Chunks with at least one write since they last became resident (either via
## [method set_cell]/[method bulk_write], or a Story vox-010 page-in that
## resulted from a fresh terrain regeneration is deliberately NOT marked
## dirty here -- see [method _regenerate_chunk_from_seed]'s doc comment).
## ONLY a dirty chunk is ever flushed to a region file on eviction (ADR-0015
## Decision §2/§5: "a region that never has a dirty chunk never gets a file
## on disk at all"). Set by [method _apply_write]; cleared by [method
## _evict_chunk] on a successful flush.
var _dirty_chunks: Dictionary[Vector2i, bool] = {}

## Per-region on-disk file handles (Story vox-010, ADR-0015 Decision §2),
## keyed by region coordinate (`chunk_key / config.region_size_chunks`) --
## lazily created on first touch and cached for this grid instance's whole
## lifetime, so a region's header is read/created exactly ONCE (ADR-0015
## Decision §6's one sanctioned synchronous exception, TR-voxel-world-053).
var _region_files: Dictionary[Vector2i, VoxelWorldRegionFile] = {}

## True once [method update_residency] has been called at least once --
## gates [method get_cell]'s region-file page-in check so a grid that never
## engages residency behaves byte-for-byte as it did before Story vox-010
## (zero filesystem touches for a chunk that was never written).
var _residency_active: bool = false

## Current [enum GridState] -- see [method get_state] and [method
## generate_terrain]. Starts UNINITIALIZED for every new instance
## (TR-voxel-world-029).
var _state: GridState = GridState.UNINITIALIZED


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


## Current lifecycle [enum GridState] (GDD "System lifecycle" table,
## TR-voxel-world-029) -- UNINITIALIZED until [method generate_terrain] has
## completed at least once, GENERATED afterward (persists for the session).
func get_state() -> GridState:
	return _state


## Procedural terrain generation (Story vox-006, ADR-0002 config + ADR-0014
## chunked storage; TR-voxel-world-026/029/038/039/044/046). For every
## in-bounds column `(x, z)` across the configured world extent, computes
## `h(x, z)` via the GDD Formulas' `procedural_terrain_height` --
## `clamp(round(base_height + amplitude * noise2D(x*frequency, z*frequency)),
## min_y, max_y)` (TR-voxel-world-038) -- and fills every cell from [member
## VoxelWorldConfig.min_y] up to and including that column's height `h` with
## [constant TERRAIN_BLOCK_TYPE_ID]/[constant TERRAIN_MATERIAL_ID]; cells
## above `h` (up to `max_y`) are left empty. "Every in-bounds cell holds
## either a terrain block or empty" (AC1/AC-4, QA plan) follows directly from
## this fill rule.
##
## Writes through [method bulk_write] -- reusing the already-established
## single-write core ([method _apply_write]) -- so the entire fill emits AT
## MOST ONE [signal cells_changed_batch] and ZERO [signal cell_changed]
## (TR-voxel-world-044, Control Manifest Forbidden: "per-cell signals at
## boot"; QA plan AC-3). Transitions [member _state] from UNINITIALIZED to
## GENERATED (TR-voxel-world-029) unconditionally on completion, even for a
## degenerate zero-cell extent.
##
## Deterministic and seeded (TR-voxel-world-039): every [FastNoiseLite]
## property this method depends on ([member FastNoiseLite.seed], [member
## FastNoiseLite.noise_type], [member FastNoiseLite.frequency], [member
## FastNoiseLite.fractal_type]) is set explicitly rather than left at engine
## defaults, so behavior cannot silently drift across engine versions --
## two calls with the same [member VoxelWorldConfig.terrain_seed] (and
## otherwise-identical config) produce byte-identical terrain; two different
## seeds produce different terrain. This is the load-bearing
## deterministic-seeded-regen premise ADR-0015 §5 depends on for the later
## sparse far-terrain regeneration layer. [member FastNoiseLite.frequency] is
## deliberately pinned at `1.0` (neutral) -- the GDD's `frequency` tuning
## knob is applied manually to `x`/`z` below, matching
## `procedural_terrain_height`'s literal `noise2D(x*frequency, z*frequency)`
## form -- so there is exactly ONE frequency knob in effect, never two
## silently-stacked ones. [member FastNoiseLite.fractal_type] is pinned at
## `FRACTAL_NONE` so `noise2D` stays a single-octave call matching the GDD
## Formula's plain `noise2D` term, never a multi-octave fractal sum.
##
## Guardrail (Control Manifest, TR-voxel-world-046): a misconfigured
## `base_height > max_y` logs exactly one [method push_warning] up front and
## is otherwise left entirely to the height formula's own `clamp()` to
## flatten every column at `max_y` -- no second/special-cased clamp path, no
## crash. Never writes to [member config] (ADR-0002's read-only-config rule)
## -- the warning is diagnostic only, [method VoxelWorldConfig.validate]
## (run separately, at boot) owns the actual field clamp.
func generate_terrain() -> void:
	assert(config != null, "VoxelWorldGrid.config not wired")
	if config.base_height > config.max_y:
		push_warning(
			"VoxelWorldGrid.generate_terrain: base_height (%d) exceeds max_y (%d) -- terrain clamps flat at max_y" %
			[config.base_height, config.max_y]
		)

	var noise: FastNoiseLite = _make_terrain_noise()

	var changes: Dictionary[Vector3i, CellContents] = {}
	for x in config.world_width_cells:
		for z in config.world_depth_cells:
			var height: int = _terrain_height(x, z, noise)
			for y in range(config.min_y, height + 1):
				changes[Vector3i(x, y, z)] = CellContents.new(TERRAIN_BLOCK_TYPE_ID, TERRAIN_MATERIAL_ID)
	bulk_write(changes)
	_state = GridState.GENERATED


## Pure per-column height evaluation for [method generate_terrain] -- the
## GDD Formulas' `procedural_terrain_height` (TR-voxel-world-038), with
## [param noise] already fully parameterized by the caller (see [method
## generate_terrain]'s doc comment). Hard-clamped to `[min_y, max_y]`
## regardless of [param noise]'s returned value, so `noise2D` returning
## exactly `+-1` (QA plan AC-1 edge case) can never escape bounds.
func _terrain_height(x: int, z: int, noise: FastNoiseLite) -> int:
	var raw: float = float(config.base_height) + config.amplitude * noise.get_noise_2d(
		float(x) * config.frequency, float(z) * config.frequency
	)
	return clampi(roundi(raw), config.min_y, config.max_y)


## Shared, fully-parameterized [FastNoiseLite] constructor (Story vox-010
## extraction -- identical field values [method generate_terrain] always set
## inline before this story; behavior-preserving refactor, not a semantic
## change) -- used by both [method generate_terrain]'s eager fill and [method
## _regenerate_chunk_from_seed]'s lazy per-chunk page-in regen, so both paths
## derive terrain from the EXACT same deterministic seed setup
## (TR-voxel-world-039).
func _make_terrain_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = config.terrain_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return noise


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
		# Story vox-010 (TR-voxel-world-041/053): a chunk with real persisted
		# data (this grid's own past write, now evicted) must page in and
		# read correctly -- transparent residency. A chunk that was NEVER
		# touched and has no region-file entry stays untouched here, exactly
		# as before this story (no allocation, no filesystem I/O at all) --
		# [member _residency_active] additionally gates this so a caller that
		# never engages residency ([method update_residency]) sees zero
		# behavior change.
		if _residency_active and _region_has_chunk(key):
			_ensure_resident(key)
		else:
			return CellContents.empty()
	var buffer: _ChunkBuffer = _chunks[key]
	var offset: int = _local_offset(cell, key)
	return CellContents.new(buffer.block_type_ids[offset], buffer.material_ids[offset])


## Occupied-cell iteration API (Story vox-005, ADR-0014 primary / ADR-0012
## secondary; TR-voxel-world-021/048/033) -- the sole interface the future
## Save/Load orchestrator (VS-tier) needs to serialize this grid's cell data;
## it never needs to know this class stores cells as chunked packed-byte
## buffers ([_ChunkBuffer]) to use this method (GDD "Save/Load & World
## Persistence" Interactions row).
##
## Walks [member _chunks] chunk-by-chunk (only chunks touched by at least one
## write are ever visited -- an untouched chunk contributes nothing and is
## never allocated just to iterate it, the same read-purity discipline as
## [method get_cell]), and within each touched chunk walks every local cell in
## a fixed, deterministic `(y, z, x)` order matching [method _local_offset]'s
## own indexing scheme. Any cell whose [member CellContents.block_type_id]
## equals [constant CellContents.EMPTY_BLOCK_TYPE_ID] is skipped -- ONLY
## non-empty (occupied) cells are ever wrapped into a returned
## [CellOccupantRecord] (TR-voxel-world-021, AC15). A cell within a touched
## chunk whose column happens to fall outside the configured world bounds
## (possible only if `world_width_cells`/`world_depth_cells` isn't an exact
## multiple of [constant CHUNK_SIZE]) is never itself a false positive here --
## [method _apply_write] never writes an out-of-bounds offset in the first
## place, so it stays zero-filled ("empty") and is skipped by the same check.
##
## Torn-read-free by construction, not by any lock (Implementation Notes: "Do
## not add locks; assert the serialization invariant in a test"): this method
## is a single, plain synchronous loop with no `await` and no
## `Thread`/`WorkerThreadPool` call anywhere in its body -- nothing here ever
## yields control back to the caller mid-scan, so no write can interleave
## between two cells of the SAME call (there is no "iteration step" the
## engine could pause on). Every write this grid ever applies ([method
## _apply_write]) is itself a single uninterrupted synchronous call that
## updates BOTH packed-byte buffers before its change signal fires (Story
## 002/003's already-established contract) -- so even a write triggered
## reentrantly from within a signal handler that itself calls this method
## observes only a fully-committed record, never a partial one
## (TR-voxel-world-048, AC14; TR-voxel-world-033's "Mutating state is brief,
## no concurrent writes" is exactly why no lock is needed here). Never
## mutates [member _chunks] -- safe to call at any time, the same read-purity
## guarantee as [method get_cell]/[method raycast_cells].
##
## Returns an empty array for an all-empty grid (edge case, QA plan AC-2).
func iterate_occupied() -> Array[CellOccupantRecord]:
	assert(config != null, "VoxelWorldGrid.config not wired")
	var occupied: Array[CellOccupantRecord] = []
	var height: int = _chunk_height()
	for key: Vector2i in _chunks:
		var buffer: _ChunkBuffer = _chunks[key]
		for local_y in height:
			for local_z in CHUNK_SIZE:
				for local_x in CHUNK_SIZE:
					var offset: int = (local_y * CHUNK_SIZE + local_z) * CHUNK_SIZE + local_x
					var block_type_id: int = buffer.block_type_ids[offset]
					if block_type_id == CellContents.EMPTY_BLOCK_TYPE_ID:
						continue
					var cell := Vector3i(
						key.x * CHUNK_SIZE + local_x,
						config.min_y + local_y,
						key.y * CHUNK_SIZE + local_z
					)
					occupied.append(CellOccupantRecord.new(cell, CellContents.new(block_type_id, buffer.material_ids[offset])))
	return occupied


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
##
## KNOWN GAP, deliberately deferred to Story 014 (ADR-0015 Decision §3,
## "load-before-write"): if [param cell]'s chunk was previously resident,
## dirtied, evicted, and flushed to a region file, and is NOT currently
## resident, this method still lazily allocates a FRESH (empty) chunk here --
## exactly the same lazy-allocation this method has always done, unchanged by
## Story vox-010 -- rather than first paging in the persisted region data.
## That page-in-before-write correctness rule is Story 014's explicit scope
## (see that story's Dependencies: "Depends on: ... Story 010 (residency)").
## This is a real, intentional gap today, not a silent regression: it only
## exists once a caller BOTH engages residency (Story vox-010's [method
## update_residency] is opt-in) AND writes to an already-evicted chunk.
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
	_dirty_chunks[key] = true
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


# =============================================================================
# Story vox-010 -- paged region-file residency (ADR-0015)
# =============================================================================

## Recomputes the resident working set as camera-near
## [member VoxelWorldConfig.view_radius_chunks] UNION active-settlement
## [member VoxelWorldConfig.settlement_radius_chunks], around [param
## camera_focus_cell] and [param settlement_anchor_cell] respectively (ADR-0015
## Decision §1, TR-voxel-world-053), then pages in every newly-desired chunk
## ([method _ensure_resident]) and evicts every currently-resident chunk that
## fell outside the new desired set ([method _evict_chunk]). SYNCHRONOUS --
## this story's own scope; async dispatch (Story 011) and a per-frame time
## budget (Story 012) are later stories layered behind this same method's
## public contract, which does not change.
##
## Both focus cells may lie outside the configured world bounds (e.g. a
## camera just past the world's edge) -- each candidate window chunk is
## bounds-filtered individually ([method _is_chunk_in_world]) via the same
## floor-friendly division [method _chunk_key] already uses; an anchor whose
## OWN raw division is imprecise for a negative cell (integer division
## truncates toward zero, not floor) only shifts which specific chunks are
## candidates near that edge, never crashes or corrupts state.
##
## Sets [member _residency_active] true on first call -- see that member's
## doc comment for the opt-in behavior this gates on [method get_cell].
func update_residency(camera_focus_cell: Vector3i, settlement_anchor_cell: Vector3i) -> void:
	assert(config != null, "VoxelWorldGrid.update_residency: config not wired")
	_residency_active = true
	var desired: Dictionary[Vector2i, bool] = {}
	_collect_window(desired, _chunk_key(camera_focus_cell), config.view_radius_chunks)
	_collect_window(desired, _chunk_key(settlement_anchor_cell), config.settlement_radius_chunks)
	for chunk_key: Vector2i in desired:
		_ensure_resident(chunk_key)
	var to_evict: Array[Vector2i] = []
	for chunk_key: Vector2i in _chunks:
		if not desired.has(chunk_key):
			to_evict.append(chunk_key)
	for chunk_key: Vector2i in to_evict:
		_evict_chunk(chunk_key)


## True if [param chunk_key] is CURRENTLY resident (has an entry in [member
## _chunks]) -- the ground truth for "is this chunk paged in right now,"
## independent of whether it's presently desired.
func is_chunk_resident(chunk_key: Vector2i) -> bool:
	return _chunks.has(chunk_key)


## Every currently-resident chunk coordinate (QA-plan/test introspection --
## [member _chunks]'s key set, snapshotted into a plain array).
func get_resident_chunk_keys() -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for key: Vector2i in _chunks:
		keys.append(key)
	return keys


## Public wrapper for [method _chunk_key] -- lets a caller (test, or a future
## Camera & Input integration) compute the exact same chunk coordinate this
## class uses internally from a cell position, without duplicating
## [constant CHUNK_SIZE] math.
func chunk_key_for_cell(cell: Vector3i) -> Vector2i:
	return _chunk_key(cell)


## Test-observable proof of ADR-0015 Decision §6's one sanctioned synchronous
## exception (TR-voxel-world-053, story QA plan AC-3): returns how many times
## [param chunk_key]'s region actually performed header I/O ([method
## VoxelWorldRegionFile._ensure_header] running past its cache guard) -- `0`
## if that region's file handle was never created at all.
func get_region_header_load_count(chunk_key: Vector2i) -> int:
	var region_key: Vector2i = _region_key_for_chunk(chunk_key)
	if not _region_files.has(region_key):
		return 0
	return _region_files[region_key].header_load_count


## Pages [param chunk_key] into [member _chunks] if it is not already
## resident -- reads its persisted region-file payload if one exists
## ([VoxelWorldRegionFile.has_chunk]), otherwise regenerates it deterministically
## from the seed ([method _regenerate_chunk_from_seed], ADR-0015 Decision §5,
## "pristine chunks regenerate from seed"). A no-op if already resident.
func _ensure_resident(chunk_key: Vector2i) -> void:
	if _chunks.has(chunk_key):
		return
	var region_key: Vector2i = _region_key_for_chunk(chunk_key)
	var region_file: VoxelWorldRegionFile = _get_or_create_region_file(region_key)
	var slot: int = _slot_in_region(chunk_key, region_key)
	if region_file.has_chunk(slot):
		_chunks[chunk_key] = _deserialize_chunk_buffer(region_file.read_chunk(slot))
	else:
		_chunks[chunk_key] = _regenerate_chunk_from_seed(chunk_key)


## Evicts [param chunk_key] from [member _chunks] -- if it is currently
## dirty ([member _dirty_chunks]), flushes its bytes to its region file
## FIRST ([VoxelWorldRegionFile.write_chunk], ADR-0015 Decision §2) and only
## then drops it from residency. A flush failure (surfaced via [method
## VoxelWorldRegionFile.write_chunk]'s `bool` return) `push_error`s and keeps
## the chunk resident rather than evicting it -- "never applied to disk
## blind, and never dropped" (ADR-0015 Decision §3's principle, applied here
## to the eviction-flush case too). A no-op if not currently resident.
func _evict_chunk(chunk_key: Vector2i) -> void:
	if not _chunks.has(chunk_key):
		return
	if _dirty_chunks.has(chunk_key):
		var region_key: Vector2i = _region_key_for_chunk(chunk_key)
		var region_file: VoxelWorldRegionFile = _get_or_create_region_file(region_key)
		var slot: int = _slot_in_region(chunk_key, region_key)
		var flushed: bool = region_file.write_chunk(slot, _serialize_chunk_buffer(_chunks[chunk_key]))
		if not flushed:
			push_error(
				"VoxelWorldGrid._evict_chunk: failed to flush dirty chunk %s -- keeping it resident (never drop a write)" % chunk_key
			)
			return
		_dirty_chunks.erase(chunk_key)
	_chunks.erase(chunk_key)


## Deterministic per-chunk terrain regeneration (ADR-0015 Decision §5,
## TR-voxel-world-039 seeded-regen premise) -- computes exactly the same
## `procedural_terrain_height` formula [method generate_terrain] uses (via
## the SAME [method _make_terrain_noise] seed setup), scoped to [param
## chunk_key]'s own [constant CHUNK_SIZE] x [constant CHUNK_SIZE] columns,
## and fills a fresh [_ChunkBuffer] DIRECTLY -- bypassing [method
## _apply_write] entirely, so this never marks the chunk dirty and never
## emits [signal cell_changed]/[signal cells_changed_batch] (page-in must be
## silent/transparent to consumers, ADR-0015 Decision §1). A column outside
## the configured world extent (possible only if `world_width_cells`/
## `world_depth_cells` isn't an exact multiple of [constant CHUNK_SIZE]) is
## skipped, staying zero-filled/empty -- the same never-write-out-of-bounds
## discipline [method iterate_occupied]'s doc comment already establishes.
func _regenerate_chunk_from_seed(chunk_key: Vector2i) -> _ChunkBuffer:
	var noise: FastNoiseLite = _make_terrain_noise()
	var buffer := _ChunkBuffer.new(CHUNK_SIZE * CHUNK_SIZE * _chunk_height())
	for local_z in CHUNK_SIZE:
		var global_z: int = chunk_key.y * CHUNK_SIZE + local_z
		if global_z < 0 or global_z >= config.world_depth_cells:
			continue
		for local_x in CHUNK_SIZE:
			var global_x: int = chunk_key.x * CHUNK_SIZE + local_x
			if global_x < 0 or global_x >= config.world_width_cells:
				continue
			var height: int = _terrain_height(global_x, global_z, noise)
			for y in range(config.min_y, height + 1):
				var offset: int = ((y - config.min_y) * CHUNK_SIZE + local_z) * CHUNK_SIZE + local_x
				buffer.block_type_ids[offset] = TERRAIN_BLOCK_TYPE_ID
				buffer.material_ids[offset] = TERRAIN_MATERIAL_ID
	return buffer


## True if [param chunk_key]'s region file has a persisted entry for it --
## used by [method get_cell]'s transparent page-in check so a read never
## allocates a chunk that has neither resident data nor a region-file entry
## (preserving the pre-Story-vox-010 "never allocate an untouched chunk on
## read" contract, TR-voxel-world-047).
func _region_has_chunk(chunk_key: Vector2i) -> bool:
	var region_key: Vector2i = _region_key_for_chunk(chunk_key)
	var region_file: VoxelWorldRegionFile = _get_or_create_region_file(region_key)
	return region_file.has_chunk(_slot_in_region(chunk_key, region_key))


## Adds every chunk within [param radius] (inclusive, square window --
## matching the reference spike's own window shape) of [param center] to
## [param desired], skipping any candidate outside the configured world
## bounds ([method _is_chunk_in_world]).
func _collect_window(desired: Dictionary[Vector2i, bool], center: Vector2i, radius: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var candidate := center + Vector2i(dx, dz)
			if _is_chunk_in_world(candidate):
				desired[candidate] = true


## True if [param chunk_key] has at least one cell inside the configured
## world bounds -- the chunk-granularity counterpart to [method is_in_bounds]'s
## cell-granularity check, used by [method _collect_window] to filter
## residency-window candidates.
func _is_chunk_in_world(chunk_key: Vector2i) -> bool:
	return (
		chunk_key.x >= 0 and chunk_key.x * CHUNK_SIZE < config.world_width_cells
		and chunk_key.y >= 0 and chunk_key.y * CHUNK_SIZE < config.world_depth_cells
	)


## Region coordinate for [param chunk_key]
## (`Vector2i(chunk_key.x / config.region_size_chunks, chunk_key.y / config.region_size_chunks)`).
## Integer division floors correctly here because every caller reaches this
## only with a [param chunk_key] already known non-negative (Core Rule 1),
## the same invariant [method _chunk_key] itself documents.
func _region_key_for_chunk(chunk_key: Vector2i) -> Vector2i:
	return Vector2i(chunk_key.x / config.region_size_chunks, chunk_key.y / config.region_size_chunks)


## Flat local slot index within [param region_key]'s
## [constant VoxelWorldRegionFile]'s header/body layout.
func _slot_in_region(chunk_key: Vector2i, region_key: Vector2i) -> int:
	var local_x: int = chunk_key.x - region_key.x * config.region_size_chunks
	var local_z: int = chunk_key.y - region_key.y * config.region_size_chunks
	return local_z * config.region_size_chunks + local_x


## Returns [param region_key]'s cached [VoxelWorldRegionFile] handle, creating
## it (and caching it in [member _region_files] for this grid instance's
## whole lifetime -- the one-header-load-per-region guarantee, TR-voxel-world-053)
## on first touch. Constructing a [VoxelWorldRegionFile] does NOT itself
## touch the filesystem -- that happens lazily inside its own [method
## VoxelWorldRegionFile.has_chunk]/[method VoxelWorldRegionFile.read_chunk]/
## [method VoxelWorldRegionFile.write_chunk] calls.
func _get_or_create_region_file(region_key: Vector2i) -> VoxelWorldRegionFile:
	if _region_files.has(region_key):
		return _region_files[region_key]
	var path: String = config.region_directory.path_join("r_%d_%d.bin" % [region_key.x, region_key.y])
	var slots: int = config.region_size_chunks * config.region_size_chunks
	var region_file := VoxelWorldRegionFile.new(path, slots, _chunk_payload_bytes())
	_region_files[region_key] = region_file
	return region_file


## Fixed serialized byte length of one chunk's region-file payload --
## constant for this grid's [member config] (depends only on [constant
## CHUNK_SIZE] and [method _chunk_height], both fixed once [member config] is
## wired): the concatenation of a [_ChunkBuffer]'s two parallel packed-byte
## arrays (see [method _serialize_chunk_buffer]).
func _chunk_payload_bytes() -> int:
	return 2 * CHUNK_SIZE * CHUNK_SIZE * _chunk_height()


## Concatenates [param buffer]'s two parallel packed-byte arrays
## (`block_type_ids` then `material_ids`) into the single flat
## [PackedByteArray] a [VoxelWorldRegionFile] payload stores -- the inverse of
## [method _deserialize_chunk_buffer].
func _serialize_chunk_buffer(buffer: _ChunkBuffer) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.append_array(buffer.block_type_ids)
	payload.append_array(buffer.material_ids)
	return payload


## Splits a [VoxelWorldRegionFile] payload's flat [PackedByteArray] back into
## a fresh [_ChunkBuffer]'s two parallel arrays -- the inverse of [method
## _serialize_chunk_buffer]. [param data] MUST be exactly [method
## _chunk_payload_bytes] long (guaranteed by construction -- every payload
## this grid ever writes has that exact length).
func _deserialize_chunk_buffer(data: PackedByteArray) -> _ChunkBuffer:
	var cell_count: int = CHUNK_SIZE * CHUNK_SIZE * _chunk_height()
	var buffer := _ChunkBuffer.new(cell_count)
	buffer.block_type_ids = data.slice(0, cell_count)
	buffer.material_ids = data.slice(cell_count, cell_count * 2)
	return buffer
