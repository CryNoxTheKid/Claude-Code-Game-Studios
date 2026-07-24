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
## Story vox-010 (ADR-0015) added paged region-file residency -- [method
## update_residency] computes the resident working set (camera-near [member
## VoxelWorldConfig.view_radius_chunks] union active-settlement [member
## VoxelWorldConfig.settlement_radius_chunks], around two injected focus
## cells) and pages chunks in/out of [member _chunks] against on-disk
## [VoxelWorldRegionFile]s (TR-voxel-world-053). This is OPT-IN: a grid that
## never calls [method update_residency] behaves byte-for-byte as before that
## story (every touched chunk stays resident for the session, zero
## filesystem touches) -- [member _residency_active] gates the only
## behavioral change to an existing method ([method get_cell]'s page-in
## check). Story vox-010 also left a known, deliberately deferred gap: if a
## WRITE ([method _apply_write]) targets an already-evicted chunk, it still
## lazily allocates a fresh (empty) chunk rather than paging in the persisted
## data first -- that page-in-before-write correctness rule is Story 014's
## explicit scope.
##
## Story vox-011 (ADR-0015 Decision §6) makes EVERY region read, region-flush
## write, and terrain regeneration run on a capped `WorkerThreadPool` ([member
## VoxelWorldConfig.max_concurrent_async_tasks]) instead of synchronously on
## the calling thread -- "a synchronous fallback IS the failure mode" the
## spike measured (a ~55 ms worst-case tail from one unusually expensive item
## landing on the main thread). [method update_residency] and [method
## get_cell]'s page-in check are now purely non-blocking: a chunk whose
## background task has not finished, or could not even be DISPATCHED because
## the pool is already at capacity, simply STAYS QUEUED and is retried on the
## next call -- never read/regenerated/flushed synchronously as a fallback.
## Every background task writes its result into a mutex-guarded structure
## ([member _read_results]/[member _write_results]) that the calling thread
## later drains non-blockingly; [method
## WorkerThreadPool.wait_for_task_completion]'s return value (an [Error]
## code, not the task's data -- an engine fact the spike's own bug surfaced)
## is never used as data anywhere in this file. The read-through in-flight-
## write cache that lets a re-needed evicting chunk skip a racy region-file
## re-read was Story vox-013's scope (a corresponding known gap was documented
## at [method _request_resident] -- since resolved, see that story's own
## paragraph below); the completion-DRIVEN (vs. poll-based) drain is Story
## 017's scope. [method wait_for_async_residency_idle] is a bounded, blocking
## helper for tests and other explicit non-per-frame sync points ONLY --
## never call it from a per-frame path.
##
## Story vox-012 (this revision, ADR-0015 Decision §1) adds the per-frame TIME
## BUDGET Story vox-011 explicitly left as future scope: [method
## update_residency] no longer drains/dispatches its full page-in and
## eviction workload unconditionally -- each of the three call sites
## ([method _reap_finished_async_writes] reaping finished flush results,
## [method _request_resident]-per-desired-chunk page-in, [method
## _request_evict]-per-stale-chunk eviction) now runs through [method
## _drain_budgeted], which re-checks elapsed time against a configured budget
## ([member VoxelWorldConfig.page_budget_ms] / [member
## VoxelWorldConfig.evict_budget_ms]) AFTER EVERY SINGLE processed item --
## never a fixed items-per-frame count. The FIRST item in any batch is always
## processed unconditionally (progress guarantee: a single item that alone
## exceeds the budget still gets integrated/dispatched before the loop
## stops); every item after that is gated on the running elapsed time, so a
## burst of ready items in one call can never collectively exceed the
## budget -- the excess is simply left unprocessed and picked up again the
## NEXT call (Story vox-011's existing "stays queued, retried later" contract,
## now time- rather than concurrency-cap-bounded). The three phases each get
## their OWN fresh timer window (never a cumulative one) so that one phase's
## duration can never eat into another's budget -- [member
## VoxelWorldConfig.page_budget_ms] and [member
## VoxelWorldConfig.evict_budget_ms] are each independently spike-validated at
## 4.0 ms. The elapsed-time reading itself is injectable ([method
## set_time_source_for_test]) so tests can assert budget-driven cutoff
## behavior deterministically, without any real sleep or wall-clock-dependent
## assertion (QA determinism rule) -- production leaves it at the default
## [Time.get_ticks_usec] wall clock. [method wait_for_async_residency_idle]/
## [method drain_pending_async_reads] remain deliberately UNBOUNDED (pass no
## budget) -- they are explicit test/non-per-frame sync points that must fully
## settle, never partially drain.
##
## Story vox-013 (this revision, ADR-0015 Decision §3) closes the read-
## through-in-flight-write gap Story vox-011 documented at [method
## _request_resident]: [method _request_resident] now checks [member
## _write_in_flight_data] ([method _try_serve_from_in_flight_write]) BEFORE
## either integrating an already-finished background read or dispatching a
## fresh one -- a chunk whose eviction flush is currently in flight is
## re-hydrated directly from its own not-yet-durable bytes, with NO
## region-file read of any kind while that flush is outstanding. The
## background flush itself is entirely unaffected by this -- it keeps
## running to completion and [method _reap_finished_async_writes] still
## clears [member _write_in_flight_data] only once (and exactly once) that
## flush is confirmed durable via the mutex-guarded [member _write_results];
## reads resume from the region file transparently afterward, exactly as
## before this story. This is a READ-side-only fix: a WRITE arriving at an
## already-evicting chunk while its flush is still in flight remains Story
## 014's explicit scope (that story's own load-before-write rule, which this
## in-flight cache composes with rather than duplicates).
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
## [method set_cell]/[method bulk_write] -- a page-in that resulted from a
## fresh terrain regeneration is deliberately NOT marked dirty here -- see
## [method _bg_regenerate_from_seed]'s doc comment). ONLY a dirty chunk is
## ever flushed to a region file on eviction (ADR-0015 Decision §2/§5: "a
## region that never has a dirty chunk never gets a file on disk at all").
## Set by [method _apply_write]; cleared by [method _request_evict] once its
## background flush has been successfully DISPATCHED (Story vox-011 -- the
## bytes then live on in [member _write_in_flight_data] until that flush is
## actually durable).
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

## In-flight background PAGE-IN task ids (Story vox-011), keyed by chunk
## coordinate -- present while a region-file read or terrain-gen dispatched
## via [method _try_dispatch_read] has not yet been observed complete by
## [method _try_integrate_read].
var _read_tasks: Dictionary[Vector2i, int] = {}

## Completed page-in results, keyed by chunk coordinate -- the MUTEX-GUARDED
## structure [method _try_integrate_read] consumes ([member _task_mutex]),
## written by a background task ([method _bg_read_from_disk]/[method
## _bg_regenerate_from_seed]) exactly once each. [method
## WorkerThreadPool.wait_for_task_completion]'s return value is NEVER used as
## this data (ADR-0015 Decision §6 engine note, TR-voxel-world-053 QA AC-3).
var _read_results: Dictionary[Vector2i, Dictionary] = {}

## In-flight background EVICTION-FLUSH task ids (Story vox-011), keyed by
## chunk coordinate -- present while a flush dispatched via [method
## _try_dispatch_write] has not yet been reaped by [method
## _reap_finished_async_writes].
var _write_tasks: Dictionary[Vector2i, int] = {}

## Completed flush results (`true` == succeeded), keyed by chunk coordinate --
## the MUTEX-GUARDED structure [method _reap_finished_async_writes] consumes,
## written by [method _bg_flush_chunk] exactly once each. Same
## never-trust-`wait_for_task_completion`'s-return-value discipline as
## [member _read_results].
var _write_results: Dictionary[Vector2i, bool] = {}

## A dirty chunk's serialized bytes while its eviction flush is in flight,
## keyed by chunk coordinate -- populated by [method _try_dispatch_write] the
## instant the resident copy is dropped from [member _chunks] (the bytes must
## live SOMEWHERE while the background write runs), cleared by [method
## _reap_finished_async_writes] once that write is durable. Story vox-013
## (ADR-0015 Decision §3) wires the READ-THROUGH consumption of this -- see
## [method _request_resident]/[method _try_serve_from_in_flight_write]: a
## chunk re-needed before its own flush lands is served from here directly,
## never racing a region-file read against the still-in-flight write.
var _write_in_flight_data: Dictionary[Vector2i, PackedByteArray] = {}

## Guards every read/write of [member _read_results] and [member
## _write_results] from both the calling thread and every background
## [WorkerThreadPool] task this class dispatches (Story vox-011, ADR-0015
## Decision §6).
var _task_mutex := Mutex.new()

## The focus cells [method update_residency] was most recently called with --
## used ONLY by [method wait_for_async_residency_idle] to keep re-driving the
## same desired window while it waits for in-flight async work to settle
## (tests/explicit sync points only, never the per-frame path itself).
var _last_camera_focus_cell: Vector3i = Vector3i.ZERO
var _last_settlement_anchor_cell: Vector3i = Vector3i.ZERO

## Injectable elapsed-time source (Story vox-012, ADR-0015 Decision §1) for
## [method _drain_budgeted]'s per-item budget re-check -- a zero-arg
## `Callable` returning microseconds as an `int`, defaulting to the real
## engine wall clock ([Time.get_ticks_usec]). Tests override this via
## [method set_time_source_for_test] with a deterministic fake clock so
## budget-driven stop/defer behavior can be asserted precisely without any
## real sleep or wall-clock-dependent assertion (QA determinism rule) --
## production code never calls the setter, so production always measures
## real elapsed time.
var _time_source_usec: Callable = Callable(Time, "get_ticks_usec")

## Current [enum GridState] -- see [method get_state] and [method
## generate_terrain]. Starts UNINITIALIZED for every new instance
## (TR-voxel-world-029).
var _state: GridState = GridState.UNINITIALIZED


## Lifecycle safety net (Story vox-011): every background [WorkerThreadPool]
## task this class dispatches holds a `Callable(self, ...)` bound into THIS
## Node -- freeing the Node while such a task is still in flight (queued or
## executing) trips Godot's object-lock protection ("Attempted to free a
## locked object"), since the engine correctly refuses to deallocate an
## Object another thread might still be calling into. `NOTIFICATION_PREDELETE`
## is the last point before actual deallocation where calling a method on
## `self` is still valid, so draining every in-flight task here -- via the
## SAME bounded, non-per-frame [method wait_for_async_residency_idle] tests
## and other explicit sync points use -- is the correct, general fix (not a
## test-only patch): ANY caller that destroys a grid with in-flight residency
## work is protected, not just tests. A grid that never engaged residency
## ([member _residency_active] false) has nothing to drain and this returns
## immediately.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		wait_for_async_residency_idle()


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
	return VoxelWorldGrid._pure_terrain_height(
		x, z, noise, config.base_height, config.amplitude, config.frequency, config.min_y, config.max_y
	)


## Pure per-column height evaluation (Story vox-011 extraction -- the exact
## formula [method _terrain_height] always computed inline before this story;
## behavior-preserving refactor, not a semantic change), parameterized
## entirely by primitives rather than reading [member config] -- this is what
## lets [method _bg_regenerate_from_seed] compute IDENTICAL terrain from a
## background thread without touching this instance's [member config] Resource
## at all (every value it needs is captured on the MAIN thread and bound into
## the background task before dispatch, see [method _try_dispatch_read]).
static func _pure_terrain_height(
	x: int, z: int, noise: FastNoiseLite, base_height: int, amplitude: float, frequency: float, min_y: int, max_y: int
) -> int:
	var raw: float = float(base_height) + amplitude * noise.get_noise_2d(float(x) * frequency, float(z) * frequency)
	return clampi(roundi(raw), min_y, max_y)


## Shared, fully-parameterized [FastNoiseLite] constructor (Story vox-010
## extraction -- identical field values [method generate_terrain] always set
## inline before this story; behavior-preserving refactor, not a semantic
## change) -- used by [method generate_terrain]'s eager fill, so it derives
## terrain from the EXACT same deterministic seed setup as [method
## _pure_terrain_noise] (TR-voxel-world-039).
func _make_terrain_noise() -> FastNoiseLite:
	return VoxelWorldGrid._pure_terrain_noise(config.terrain_seed)


## Pure counterpart of [method _make_terrain_noise] (Story vox-011
## extraction), parameterized only by [param terrain_seed] -- used by BOTH
## [method _make_terrain_noise] (main thread, reads [member config]) and
## [method _bg_regenerate_from_seed] (background thread, never touches
## [member config]), so two calls with the same seed produce byte-identical
## terrain regardless of which thread runs them (TR-voxel-world-039).
static func _pure_terrain_noise(terrain_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = terrain_seed
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
		# as before Story vox-010 (no allocation, no filesystem I/O at all,
		# no async dispatch either -- TR-voxel-world-047 read-purity: a bare
		# read over unexplored pristine terrain must never allocate or
		# schedule background work as a side effect). [member
		# _residency_active] additionally gates this so a caller that never
		# engages residency ([method update_residency]) sees zero behavior
		# change.
		#
		# Story vox-011 (ADR-0015 Decision §6): the page-in itself is now
		# NON-BLOCKING -- [method _request_resident] either integrates an
		# already-finished background result right now (no disk/regen touch
		# on THIS thread, just consuming a completed task), dispatches a
		# fresh background task (best-effort, cap-checked), or -- if the pool
		# is already at capacity -- leaves the chunk queued for a later call.
		# In every case this method returns WITHOUT blocking; if the chunk
		# still isn't resident afterward, this read serves a transparent
		# empty result for now (never a synchronous fallback) -- a later
		# get_cell/update_residency call resolves it once the background task
		# lands.
		if _residency_active and _region_has_chunk(key):
			_request_resident(key)
		if not _chunks.has(key):
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

## Test-only override for [member _time_source_usec] (Story vox-012) -- lets
## a test substitute a deterministic fake clock ([Callable] returning an
## `int` microsecond count) so [method _drain_budgeted]'s per-item budget
## re-check can be asserted precisely (e.g. "the Nth item's post-check trips
## the budget") without any real sleep or wall-clock read. Never called from
## production code -- production always measures real elapsed time via the
## default [Time.get_ticks_usec].
func set_time_source_for_test(source: Callable) -> void:
	_time_source_usec = source


## Current elapsed-time reading in microseconds, via [member _time_source_usec]
## (real wall clock in production, an injected fake clock in tests -- see
## [method set_time_source_for_test]).
func _now_usec() -> int:
	return _time_source_usec.call()


## Converts a [VoxelWorldConfig] millisecond budget knob ([member
## VoxelWorldConfig.page_budget_ms] / [member VoxelWorldConfig.evict_budget_ms])
## to the microsecond unit [method _drain_budgeted] compares against --
## keeping the config-facing knob in the GDD/ADR's own "ms" unit while the
## internal comparison uses the same unit [method _now_usec] returns.
func _budget_usec(budget_ms: float) -> int:
	return int(budget_ms * 1000.0)


## Generic per-item time-budget drain (Story vox-012, ADR-0015 Decision §1;
## TR-voxel-world-053): invokes [param action] once per entry of [param
## items], in order, re-checking elapsed time against [param budget_usec]
## (elapsed since [param start_usec]) AFTER every single invocation -- never
## BEFORE the first one, so the first item in any batch is always processed
## unconditionally (the "a single item that alone exceeds the budget is
## still integrated, then the loop stops" progress guarantee). The instant an
## item's post-check shows the budget exceeded, every remaining item in
## [param items] is left untouched for this call -- simply not visited at
## all, no partial/half-applied state of any kind, since [param action] is
## only ever called for items this method decided to fully process. The
## caller is responsible for retrying the untouched remainder on ITS next
## call (every call site rebuilds its own worklist fresh from current state,
## so nothing needs to be threaded through as an explicit carry-over queue).
##
## [param budget_usec] < 0 means UNBOUNDED -- every item in [param items] is
## processed regardless of elapsed time, and [method _now_usec] is never even
## called. This is the explicit escape hatch [method wait_for_async_residency_idle]
## and [method drain_pending_async_reads] use (test/non-per-frame sync points
## that must fully settle, never partially drain) -- the default parameter
## values on [method _reap_finished_async_writes] preserve this for every
## existing bare call site.
func _drain_budgeted(items: Array, start_usec: int, budget_usec: int, action: Callable) -> void:
	if budget_usec < 0:
		for item in items:
			action.call(item)
		return
	var exceeded: bool = false
	for item in items:
		if exceeded:
			break
		action.call(item)
		exceeded = (_now_usec() - start_usec) >= budget_usec


## Recomputes the resident working set as camera-near
## [member VoxelWorldConfig.view_radius_chunks] UNION active-settlement
## [member VoxelWorldConfig.settlement_radius_chunks], around [param
## camera_focus_cell] and [param settlement_anchor_cell] respectively (ADR-0015
## Decision §1, TR-voxel-world-053), then requests page-in for every
## newly-desired chunk ([method _request_resident]) and requests eviction for
## every currently-resident chunk that fell outside the new desired set
## ([method _request_evict]).
##
## Story vox-011 (ADR-0015 Decision §6): both requests are NON-BLOCKING and
## best-effort -- a chunk whose background task has not finished, or could
## not even be dispatched because [member VoxelWorldConfig.max_concurrent_async_tasks]
## is already saturated, simply STAYS in its current state (not yet resident,
## or not yet evicted) and is retried the NEXT time this method is called --
## never a synchronous read/regen/flush fallback. This method's own public
## contract (signature, desired-set computation) is unchanged from Story
## vox-010; only the page-in/eviction MECHANISM is now async.
##
## Story vox-012 (this revision, ADR-0015 Decision §1): each of the three
## phases below -- reaping finished eviction-flush results, requesting
## page-in for the desired set, requesting eviction for the stale set -- now
## runs through [method _drain_budgeted], bounded by [member
## VoxelWorldConfig.evict_budget_ms] (reap and evict-dispatch) / [member
## VoxelWorldConfig.page_budget_ms] (page-in), re-checked after every single
## item. Each phase reads its OWN fresh [method _now_usec] start immediately
## before its own loop -- never a start captured once at the top and shared
## across phases -- so one phase's duration can never silently eat into
## another's budget; each of the three call sites gets its full nominal
## budget independent of how long the others took. A chunk left unprocessed
## when a phase's budget is exceeded is simply retried the NEXT call, exactly
## like a concurrency-cap-miss already was (Story vox-011) -- time-based and
## cap-based deferral compose without special-casing either.
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
## doc comment for the opt-in behavior this gates on [method get_cell]. Also
## records [param camera_focus_cell]/[param settlement_anchor_cell] as [member
## _last_camera_focus_cell]/[member _last_settlement_anchor_cell] -- consumed
## ONLY by [method wait_for_async_residency_idle] (tests/explicit sync points,
## never the per-frame path).
func update_residency(camera_focus_cell: Vector3i, settlement_anchor_cell: Vector3i) -> void:
	assert(config != null, "VoxelWorldGrid.update_residency: config not wired")
	_residency_active = true
	_last_camera_focus_cell = camera_focus_cell
	_last_settlement_anchor_cell = settlement_anchor_cell

	var reap_start_usec: int = _now_usec()
	_reap_finished_async_writes(reap_start_usec, _budget_usec(config.evict_budget_ms))

	var desired: Dictionary[Vector2i, bool] = {}
	_collect_window(desired, _chunk_key(camera_focus_cell), config.view_radius_chunks)
	_collect_window(desired, _chunk_key(settlement_anchor_cell), config.settlement_radius_chunks)
	var page_in_start_usec: int = _now_usec()
	_drain_budgeted(desired.keys(), page_in_start_usec, _budget_usec(config.page_budget_ms), Callable(self, "_request_resident"))

	var to_evict: Array[Vector2i] = []
	for chunk_key: Vector2i in _chunks:
		if not desired.has(chunk_key):
			to_evict.append(chunk_key)
	var evict_dispatch_start_usec: int = _now_usec()
	_drain_budgeted(to_evict, evict_dispatch_start_usec, _budget_usec(config.evict_budget_ms), Callable(self, "_request_evict"))


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


## Total in-flight async task count (Story vox-011) -- reads AND writes
## SHARE one [member VoxelWorldConfig.max_concurrent_async_tasks] budget
## (ADR-0015 Decision §6), so both dispatch paths check this same total
## before adding a new task.
func _in_flight_async_task_count() -> int:
	return _read_tasks.size() + _write_tasks.size()


## Test/diagnostic introspection (story QA plan AC-2): the current shared
## in-flight task count. By construction ([method _try_dispatch_read]/[method
## _try_dispatch_write] each check this BEFORE adding a task) this NEVER
## exceeds [member VoxelWorldConfig.max_concurrent_async_tasks], regardless of
## how many chunks are simultaneously desired.
func get_in_flight_async_task_count() -> int:
	return _in_flight_async_task_count()


## Best-effort page-in request for [param chunk_key] (Story vox-011, ADR-0015
## Decision §6) -- returns TRUE the instant the chunk is already resident, is
## currently mid-eviction-flush and gets served straight from its own
## not-yet-durable bytes ([method _try_serve_from_in_flight_write], Story
## vox-013, ADR-0015 Decision §3 -- checked FIRST, before either read path, so
## an in-flight chunk NEVER races a genuine region-file read against its own
## still-in-flight write), has a just-finished background result integrated
## into [member _chunks] right now ([method _try_integrate_read],
## non-blocking), or was freshly dispatched onto the [WorkerThreadPool] this
## call ([method _try_dispatch_read]). Returns FALSE only when the chunk still
## has no finished result AND could not be dispatched because [member
## VoxelWorldConfig.max_concurrent_async_tasks] is already saturated -- the
## caller ([method update_residency]/[method get_cell]) simply leaves [param
## chunk_key] queued and retries on a later call (ADR-0015 Decision §6:
## cap-miss stays queued, never a synchronous read/regen fallback).
func _request_resident(chunk_key: Vector2i) -> bool:
	if _chunks.has(chunk_key):
		return true
	if _try_serve_from_in_flight_write(chunk_key):
		return true
	if _try_integrate_read(chunk_key):
		return true
	return _try_dispatch_read(chunk_key)


## Read-through in-flight-write cache (Story vox-013, ADR-0015 Decision §3):
## if [param chunk_key] is currently mid-eviction-flush -- its serialized
## bytes live in [member _write_in_flight_data] because [method
## _try_dispatch_write] dispatched the background flush but [method
## _reap_finished_async_writes] has not yet confirmed it durable -- this
## re-hydrates [member _chunks] directly from those in-memory bytes and
## returns TRUE, WITHOUT dispatching or consuming any region-file read at
## all. This is the correctness fix for the gap [method _request_resident]'s
## own (now-superseded) doc comment used to name: the region file may be
## mid-write and genuinely incomplete while a flush is in flight, so a
## re-needed chunk must NEVER be served via a race between "read the file"
## and "the file is still being written" -- the in-memory bytes are the sole
## authoritative source for the whole window the flush is in flight (ADR-0015
## Decision §3: "the authoritative bytes live in memory until the write is
## durable").
##
## The background flush itself is completely unaffected by this -- it keeps
## running to completion regardless of whether this method re-hydrates the
## chunk in the meantime, and [method _reap_finished_async_writes] still
## clears [member _write_in_flight_data] only once (and exactly once) that
## flush is confirmed durable via the mutex-guarded [member _write_results];
## reads resume from the region file transparently afterward (Story vox-013's
## AC-2), exactly as before this story. If [param chunk_key] is later evicted
## again before any new write touches it, [method _request_evict] finds it
## absent from [member _dirty_chunks] (already cleared by the FIRST eviction's
## dispatch) and simply drops it from [member _chunks] with no new flush
## dispatched -- correct, since the bytes already in flight are unchanged and
## the original flush task still carries them to disk.
func _try_serve_from_in_flight_write(chunk_key: Vector2i) -> bool:
	if not _write_in_flight_data.has(chunk_key):
		return false
	_chunks[chunk_key] = _deserialize_chunk_buffer(_write_in_flight_data[chunk_key])
	return true


## Non-blocking: TRUE and integrates [param chunk_key] into [member _chunks]
## if (and only if) its background read task has already finished --
## [method WorkerThreadPool.is_task_completed] is a pure poll, never a wait.
## The finished payload is consumed from [member _read_results] under
## [member _task_mutex] -- [method WorkerThreadPool.wait_for_task_completion]
## IS still called here, but only to join/free an ALREADY-complete task (it
## never blocks in that case), and its [Error]-code return is discarded,
## never treated as the chunk's data (ADR-0015 Decision §6 engine note;
## TR-voxel-world-053 QA AC-3).
func _try_integrate_read(chunk_key: Vector2i) -> bool:
	if not _read_tasks.has(chunk_key):
		return false
	var task_id: int = _read_tasks[chunk_key]
	if not WorkerThreadPool.is_task_completed(task_id):
		return false
	WorkerThreadPool.wait_for_task_completion(task_id)  # instant join/free of an already-finished task; Error return discarded
	_read_tasks.erase(chunk_key)
	_task_mutex.lock()
	var result: Dictionary = _read_results[chunk_key]
	_read_results.erase(chunk_key)
	_task_mutex.unlock()
	_chunks[chunk_key] = _deserialize_chunk_buffer(result["data"])
	return true


## Dispatches a background page-in task for [param chunk_key] if [member
## VoxelWorldConfig.max_concurrent_async_tasks] allows -- returns TRUE once
## dispatched (or if a task for this key is already in flight), FALSE if the
## shared cap is already saturated (cap-miss, caller leaves it queued). The
## ONE sanctioned synchronous touch here is region-header bookkeeping
## ([method VoxelWorldRegionFile.has_chunk]/[method VoxelWorldRegionFile.offset_of],
## ADR-0015 Decision §6's one-time-per-region exception) -- the actual
## payload read ([method _bg_read_from_disk]) or terrain regen ([method
## _bg_regenerate_from_seed]) runs entirely on the [WorkerThreadPool], never
## on this thread.
func _try_dispatch_read(chunk_key: Vector2i) -> bool:
	if _read_tasks.has(chunk_key):
		return true
	if _in_flight_async_task_count() >= config.max_concurrent_async_tasks:
		return false
	var region_key: Vector2i = _region_key_for_chunk(chunk_key)
	var region_file: VoxelWorldRegionFile = _get_or_create_region_file(region_key)
	var slot: int = _slot_in_region(chunk_key, region_key)
	var present: bool = region_file.has_chunk(slot)
	var task_id: int
	if present:
		var offset: int = region_file.offset_of(slot)
		task_id = WorkerThreadPool.add_task(
			Callable(self, "_bg_read_from_disk").bind(chunk_key, region_file.path, offset, _chunk_payload_bytes())
		)
	else:
		task_id = WorkerThreadPool.add_task(
			Callable(self, "_bg_regenerate_from_seed").bind(
				chunk_key, config.terrain_seed, config.base_height, config.amplitude, config.frequency,
				config.min_y, config.max_y, config.world_width_cells, config.world_depth_cells
			)
		)
	_read_tasks[chunk_key] = task_id
	return true


## Background [WorkerThreadPool] task body (Story vox-011) -- pure disk I/O
## via the `static` [method VoxelWorldRegionFile.read_payload_at] (touches no
## shared instance state), writing its result into the MUTEX-GUARDED [member
## _read_results] -- never returned via [method
## WorkerThreadPool.wait_for_task_completion] (ADR-0015 Decision §6 engine
## note, the spike's own bug (i)).
func _bg_read_from_disk(chunk_key: Vector2i, path: String, offset: int, payload_bytes: int) -> void:
	var data: PackedByteArray = VoxelWorldRegionFile.read_payload_at(path, offset, payload_bytes)
	_task_mutex.lock()
	_read_results[chunk_key] = {"data": data}
	_task_mutex.unlock()


## Background [WorkerThreadPool] task body (Story vox-011, ADR-0015 Decision
## §5) -- deterministic terrain regen for a pristine (never-persisted) chunk,
## computing exactly the same `procedural_terrain_height` formula [method
## generate_terrain]/[method _terrain_height] use ([method
## _pure_terrain_height], [method _pure_terrain_noise]), scoped to [param
## chunk_key]'s own [constant CHUNK_SIZE] x [constant CHUNK_SIZE] columns.
## Deliberately reads NOTHING from [member config] or any other shared
## instance state -- every value this needs is captured on the MAIN thread
## and bound in before dispatch (see [method _try_dispatch_read]), so two
## calls with the same [param terrain_seed] produce byte-identical terrain
## regardless of which thread runs them (TR-voxel-world-039). Writes its
## result -- serialized in the SAME flat layout [method
## _serialize_chunk_buffer] uses (block_type_ids then material_ids) -- into
## the mutex-guarded [member _read_results]; see [method _bg_read_from_disk]'s
## doc comment for why. A column outside the configured world extent
## (possible only if `world_width_cells`/`world_depth_cells` isn't an exact
## multiple of [constant CHUNK_SIZE]) is skipped, staying zero-filled/empty --
## the same never-write-out-of-bounds discipline [method iterate_occupied]'s
## doc comment already establishes. Never marks anything dirty and never
## emits any signal -- page-in must be silent/transparent to consumers
## (ADR-0015 Decision §1), and this runs off the main thread besides.
func _bg_regenerate_from_seed(
	chunk_key: Vector2i, terrain_seed: int, base_height: int, amplitude: float, frequency: float,
	min_y: int, max_y: int, world_width_cells: int, world_depth_cells: int
) -> void:
	var noise: FastNoiseLite = VoxelWorldGrid._pure_terrain_noise(terrain_seed)
	var chunk_height: int = max_y - min_y + 1
	var cell_count: int = CHUNK_SIZE * CHUNK_SIZE * chunk_height
	var block_type_ids := PackedByteArray()
	block_type_ids.resize(cell_count)
	var material_ids := PackedByteArray()
	material_ids.resize(cell_count)
	for local_z in CHUNK_SIZE:
		var global_z: int = chunk_key.y * CHUNK_SIZE + local_z
		if global_z < 0 or global_z >= world_depth_cells:
			continue
		for local_x in CHUNK_SIZE:
			var global_x: int = chunk_key.x * CHUNK_SIZE + local_x
			if global_x < 0 or global_x >= world_width_cells:
				continue
			var height: int = VoxelWorldGrid._pure_terrain_height(
				global_x, global_z, noise, base_height, amplitude, frequency, min_y, max_y
			)
			for y in range(min_y, height + 1):
				var offset: int = ((y - min_y) * CHUNK_SIZE + local_z) * CHUNK_SIZE + local_x
				block_type_ids[offset] = TERRAIN_BLOCK_TYPE_ID
				material_ids[offset] = TERRAIN_MATERIAL_ID
	var payload := PackedByteArray()
	payload.append_array(block_type_ids)
	payload.append_array(material_ids)
	_task_mutex.lock()
	_read_results[chunk_key] = {"data": payload}
	_task_mutex.unlock()


## Best-effort eviction request for [param chunk_key] (Story vox-011, ADR-0015
## Decision §6 lever 2) -- returns TRUE the instant [param chunk_key] is
## already non-resident, was evicted immediately (clean -- no I/O needed at
## all, the exact same zero-I/O contract Story vox-010 already had for a
## never-dirtied chunk), or had its flush freshly dispatched onto the
## [WorkerThreadPool] this call (the resident copy is dropped immediately --
## its bytes live on in [member _write_in_flight_data] until the background
## write lands, ADR-0015 Decision §3's read-through mechanism, wired by Story
## 013). Returns FALSE (chunk stays resident, caller retries on a later call)
## ONLY when dirty AND the shared cap is already saturated -- never a
## synchronous flush fallback.
func _request_evict(chunk_key: Vector2i) -> bool:
	if not _chunks.has(chunk_key):
		return true
	if not _dirty_chunks.has(chunk_key):
		_chunks.erase(chunk_key)
		return true
	if not _try_dispatch_write(chunk_key, _serialize_chunk_buffer(_chunks[chunk_key])):
		return false
	_dirty_chunks.erase(chunk_key)
	_chunks.erase(chunk_key)
	return true


## Dispatches a background eviction-flush task for [param chunk_key] carrying
## the already-serialized [param data] if [member
## VoxelWorldConfig.max_concurrent_async_tasks] allows -- returns TRUE once
## dispatched (or if a flush for this key is already in flight), FALSE if the
## shared cap is already saturated. [VoxelWorldRegionFile.reserve_offset_for_write]
## is the ONE sanctioned synchronous touch (main-thread bookkeeping + a
## one-time-per-region file/header creation, ADR-0015 Decision §6) -- the
## actual payload write ([method _bg_flush_chunk]) runs entirely on the
## [WorkerThreadPool].
func _try_dispatch_write(chunk_key: Vector2i, data: PackedByteArray) -> bool:
	if _write_tasks.has(chunk_key):
		return true
	if _in_flight_async_task_count() >= config.max_concurrent_async_tasks:
		return false
	var region_key: Vector2i = _region_key_for_chunk(chunk_key)
	var region_file: VoxelWorldRegionFile = _get_or_create_region_file(region_key)
	var slot: int = _slot_in_region(chunk_key, region_key)
	var offset: int = region_file.reserve_offset_for_write(slot)
	_write_in_flight_data[chunk_key] = data
	var task_id: int = WorkerThreadPool.add_task(
		Callable(self, "_bg_flush_chunk").bind(chunk_key, region_file.path, slot, offset, data)
	)
	_write_tasks[chunk_key] = task_id
	return true


## Background [WorkerThreadPool] task body (Story vox-011) -- pure disk I/O
## via the `static` [method VoxelWorldRegionFile.write_payload_at] (touches
## no shared instance state), writing its `bool` success result into the
## MUTEX-GUARDED [member _write_results] -- never returned via [method
## WorkerThreadPool.wait_for_task_completion] (same discipline as [method
## _bg_read_from_disk]).
func _bg_flush_chunk(chunk_key: Vector2i, path: String, slot: int, offset: int, data: PackedByteArray) -> void:
	var ok: bool = VoxelWorldRegionFile.write_payload_at(path, slot, offset, data)
	_task_mutex.lock()
	_write_results[chunk_key] = ok
	_task_mutex.unlock()


## Non-blocking bookkeeping (Story vox-011): joins any FINISHED flush tasks --
## consumed from the MUTEX-GUARDED [member _write_results], never from
## [method WorkerThreadPool.wait_for_task_completion]'s return value
## (TR-voxel-world-053 QA AC-3). A failed flush `push_error`s (ADR-0015
## Decision §3's "never applied to disk blind, and never dropped" principle
## still applies off-thread) -- this story does not yet re-queue a failed
## flush for retry, a real, deliberately deferred gap in the same spirit as
## Story vox-010's documented load-before-write gap. Called at the top of
## every [method update_residency] call, and by [method
## wait_for_async_residency_idle].
##
## Story vox-012 (this revision) adds [param start_usec]/[param budget_usec] --
## the SAME per-item time-budget drain [method update_residency]'s page-in/
## eviction-dispatch phases use ([method _drain_budgeted]), so a burst of
## MANY finished flushes settling in the same call cannot collectively exceed
## [member VoxelWorldConfig.evict_budget_ms] either; any not-yet-reaped
## finished task simply stays in [member _write_tasks] and is reaped on a
## later call (harmless -- it is already durable on disk, just not yet
## bookkept as such). Defaults ([param start_usec] = -1, [param budget_usec] =
## -1) mean UNBOUNDED, preserving every existing bare `_reap_finished_async_writes()`
## call site's "drain everything currently finished" behavior verbatim (Story
## vox-011's [method wait_for_async_residency_idle], a test/non-per-frame
## sync point that must fully settle).
func _reap_finished_async_writes(start_usec: int = -1, budget_usec: int = -1) -> void:
	if _write_tasks.is_empty():
		return
	var done: Array[Vector2i] = []
	for chunk_key: Vector2i in _write_tasks:
		if WorkerThreadPool.is_task_completed(_write_tasks[chunk_key]):
			done.append(chunk_key)
	_drain_budgeted(done, start_usec, budget_usec, Callable(self, "_reap_one_finished_write"))


## Per-item body of [method _reap_finished_async_writes] (Story vox-012
## extraction -- behavior-preserving refactor, not a semantic change; the
## exact statements [method _reap_finished_async_writes]'s own loop body
## always ran inline before this story). Joins/frees [param chunk_key]'s
## already-complete flush task, consumes its success result from the
## MUTEX-GUARDED [member _write_results], and clears its in-flight-write
## bookkeeping.
func _reap_one_finished_write(chunk_key: Vector2i) -> void:
	WorkerThreadPool.wait_for_task_completion(_write_tasks[chunk_key])  # instant join/free; Error return discarded
	_write_tasks.erase(chunk_key)
	_task_mutex.lock()
	var ok: bool = _write_results.get(chunk_key, false)
	_write_results.erase(chunk_key)
	_task_mutex.unlock()
	if not ok:
		push_error("VoxelWorldGrid._reap_one_finished_write: background flush failed for chunk %s" % chunk_key)
	_write_in_flight_data.erase(chunk_key)


## Blocks (BOUNDED) until every currently in-flight async page-in/eviction
## task has settled, or [param max_wait_msec] elapses -- NEVER called from the
## per-frame residency path (that would reintroduce exactly the synchronous-
## fallback failure mode ADR-0015 Decision §6 forbids). This exists for tests
## and other explicit, infrequent synchronization points (mirroring the same
## "explicit action, not a per-frame path" exception ADR-0015 grants a
## save-triggered flush) -- each iteration drains whatever has already
## finished via the SAME non-blocking paths [method update_residency] itself
## uses ([method _reap_finished_async_writes], [method _try_integrate_read]
## for every currently in-flight read regardless of whether it is still in
## the last-requested desired window, plus a re-drive of [method
## update_residency] with the SAME focus cells to retry any chunk that was
## cap-missed and never got dispatched at all), with a BOUNDED [method
## OS.delay_msec] between polls -- never an unbounded spin. Returns as soon as
## nothing is left in flight.
##
## KNOWN LIMITATION (found while implementing this story's own tests): a
## chunk made resident ONLY via a side-channel dispatch OUTSIDE the currently
## active desired window (e.g. a bare [method get_cell] call on a chunk
## [method update_residency] was never asked to keep resident) can get
## evicted again by this method's OWN re-drive of [method update_residency]
## before the caller observes it -- this is in fact CORRECT production
## behavior (a transient page-in that nothing continues to want is not
## artificially pinned resident forever), but it means this method is the
## WRONG tool for "wait for a bare get_cell's own dispatch to land." Use
## [method drain_pending_async_reads] for that narrower case instead -- it
## never touches [method update_residency] or eviction at all.
func wait_for_async_residency_idle(max_wait_msec: int = 2000) -> void:
	var elapsed_msec: int = 0
	while true:
		_reap_finished_async_writes()
		var pending_reads: Array[Vector2i] = _read_tasks.keys()
		for chunk_key: Vector2i in pending_reads:
			_try_integrate_read(chunk_key)
		if _residency_active:
			update_residency(_last_camera_focus_cell, _last_settlement_anchor_cell)
		if _in_flight_async_task_count() == 0:
			return
		if elapsed_msec >= max_wait_msec:
			return
		OS.delay_msec(1)
		elapsed_msec += 1


## Blocks (BOUNDED) until every currently in-flight PAGE-IN (read) task has
## settled, or [param max_wait_msec] elapses -- narrower than [method
## wait_for_async_residency_idle]: this NEVER calls [method update_residency]
## and NEVER evicts anything, so it is the correct settle primitive for a
## chunk dispatched via a side channel (e.g. a bare [method get_cell] call)
## OUTSIDE the currently active desired window, which [method
## wait_for_async_residency_idle]'s own re-drive of [method update_residency]
## would otherwise evict again before the caller observes it. NEVER called
## from the per-frame residency path -- tests and other explicit,
## infrequent synchronization points ONLY, same as [method
## wait_for_async_residency_idle].
func drain_pending_async_reads(max_wait_msec: int = 2000) -> void:
	var elapsed_msec: int = 0
	while not _read_tasks.is_empty():
		var pending_reads: Array[Vector2i] = _read_tasks.keys()
		for chunk_key: Vector2i in pending_reads:
			_try_integrate_read(chunk_key)
		if _read_tasks.is_empty():
			return
		if elapsed_msec >= max_wait_msec:
			return
		OS.delay_msec(1)
		elapsed_msec += 1


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
## VoxelWorldRegionFile.has_chunk]/[method VoxelWorldRegionFile.offset_of]/
## [method VoxelWorldRegionFile.reserve_offset_for_write] calls (Story
## vox-011: the actual chunk-payload bytes are read/written off the main
## thread via that class's `static` [method VoxelWorldRegionFile.read_payload_at]/
## [method VoxelWorldRegionFile.write_payload_at]).
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
