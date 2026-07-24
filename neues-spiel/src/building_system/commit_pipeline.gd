## Building System's commit pipeline (Story building-021, ADR-0016 primary --
## a valid commit creates blueprint (Draft) cells owned by this system,
## invisible to Voxel World's data layer, never a direct grid write; ADR-0010
## secondary -- consumes [PlacementPick]'s ADR-0010 §3 drag-ownership release
## as this class's own commit trigger).
##
## Owns exactly the three things this story's Control Manifest excerpt names
## -- "the discrimination + clamp + blueprint-creation trigger" -- and
## nothing else:
##
## 1. **Discrimination** (GDD Formula F4, [TR-building-system-081], AC6):
##    consumed ready-made from [signal PlacementPick.build_committed]'s
##    `is_drag` payload -- that class (this story's own extension to it) owns
##    the actual pixel-distance tracking + threshold comparison; this class
##    only branches on the already-decided boolean, never re-derives it.
## 2. **Bounds clamp** (Edge Case 1, [TR-building-system-083], AC9): [method
##    commit] filters its candidate cell set down to [method
##    VoxelWorldGrid.is_in_bounds] entries only; a candidate set that clamps
##    to empty commits nothing at all -- no cell, no signal, no partial state
##    of any kind (Edge Case 1's "a drag entirely out of bounds commits
##    nothing").
## 3. **Blueprint-creation trigger** ([TR-building-system-052], AC4): every
##    surviving in-bounds cell becomes a fresh [BlueprintCell] in
##    [constant BlueprintCell.MicroState.PLANNED]. This class NEVER calls
##    [method VoxelWorldGrid.set_cell]/[method VoxelWorldGrid.bulk_write]/
##    [method VoxelWorldGrid.clear_cell] -- grep-verified by this story's own
##    test, mirroring Story 020's established "the pick/commit stays
##    side-effect-free w.r.t. Voxel World writes" precedent. Blueprint cells
##    are tracked ENTIRELY inside this class ([member _blueprint_cells]),
##    exactly as Core Rule 11 requires.
##
## Also enforces AC38/Edge Case 4 ("no valid pick... is a no-op"): [method
## commit] gates on [member PlacementPick.get_current_pick]'s CURRENT hit
## flag before doing anything else.
##
## **Explicitly out of scope** (this story's own Out of Scope section, and
## the neighbouring stories that own it):
## - The per-tool cell-set FORMULA (which cells a wall/floor/roof/block/
##   furniture drag actually produces, GDD Formulas F1/F2/F5) is Stories
##   024-028's job. Since none of those tools exist in this codebase yet,
##   [method _resolve_cell_set]'s fallback ([method _default_cell_set]) is a
##   deliberately minimal, explicitly-labeled PLACEHOLDER -- NOT an
##   implementation of F1/F2/F5 -- that exercises this story's own
##   discrimination/clamp/trigger mechanism only: a click commits the single
##   press cell; a drag commits the press AND release cells (nothing
##   in-between). [method set_cell_set_resolver] lets a future tool story
##   override this entirely without touching this class.
## - The full placement-VALIDITY rejection rules (occupied-cell check,
##   terrain replace-in-place, material selection, the `max_cells_per_command`
##   cap) are Story 022's job -- this class does not reject an
##   already-drafted or already-built cell; it only clamps to world bounds.
## - Ghost preview RENDERING (Story 023) and project grouping/merge/reverse-
##   index (Story 003, ADR-0016 Decision §2) -- [signal blueprint_cells_created]
##   is exactly the seam Story 003 consumes; this class performs no grouping
##   of its own and holds no project concept.
##
## Injected-tier module (ADR-0001): [member placement_pick]/[member
## voxel_world] are wired via a scene file's Inspector in production (once a
## future scene-assembly story attaches this node -- no Build Mode gate,
## Story building-001, exists yet to arm a tool in production), or assigned
## directly in a headless test; all wiring lives in [method setup], never
## `_ready()`.
class_name CommitPipeline
extends Node

## Fires whenever [method commit] creates at least one [BlueprintCell] --
## never for a commit that clamps to zero in-bounds cells, and never for the
## no-valid-pick no-op (AC38). Story building-003 (project grouping/merge) is
## this signal's real future consumer; no such class exists yet in this
## codebase.
signal blueprint_cells_created(cells: Array[BlueprintCell])

## Injected-tier dependency (ADR-0001) -- the sole source of [signal
## PlacementPick.build_committed] this pipeline reacts to, and of the current
## pick's hit/miss state [method commit] gates on (AC38).
@export var placement_pick: PlacementPick

## Injected-tier dependency (ADR-0001) -- read-only bounds check ([method
## VoxelWorldGrid.is_in_bounds]) ONLY. This class never calls [method
## VoxelWorldGrid.set_cell]/[method VoxelWorldGrid.bulk_write]/[method
## VoxelWorldGrid.clear_cell] -- see class doc comment point 3.
@export var voxel_world: VoxelWorldGrid

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## Every currently-tracked blueprint cell, keyed by its [Vector3i] address --
## the sole source of truth this class owns (Core Rule 11: "owned by this
## system, invisible to Voxel World's data layer"). A caller targeting the
## SAME cell twice overwrites the earlier [BlueprintCell] record at that key
## (mirrors [method VoxelWorldGrid.bulk_write]'s own "last value for a
## duplicate key wins" precedent) -- this story does not reject that (Story
## 022's Edge Case 3 owns that rejection rule).
var _blueprint_cells: Dictionary[Vector3i, BlueprintCell] = {}

## Optional per-tool cell-set override (see class doc comment's "out of
## scope" note) -- `Callable(is_drag: bool, press_cell: Vector3i,
## release_cell: Vector3i) -> Array[Vector3i]`. Default `Callable()` (invalid)
## falls back to [method _default_cell_set].
var _cell_set_resolver: Callable = Callable()


## Explicitly callable wiring entry point (ADR-0001). Asserts both
## dependencies were wired and connects to [signal
## PlacementPick.build_committed] (idempotent via [method Signal.is_connected],
## mirroring [ToolStateMachine]'s own precedent).
func setup() -> void:
	assert(placement_pick != null, "CommitPipeline.placement_pick not wired")
	assert(voxel_world != null, "CommitPipeline.voxel_world not wired")
	if not placement_pick.build_committed.is_connected(_on_build_committed):
		placement_pick.build_committed.connect(_on_build_committed)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Overrides the per-tool cell-set resolver (see class doc comment) -- a
## future tool story (024-028) calls this with its own real formula instead
## of relying on [method _default_cell_set]'s placeholder.
func set_cell_set_resolver(resolver: Callable) -> void:
	_cell_set_resolver = resolver


## Every blueprint cell currently tracked by this pipeline -- Story
## building-003's future read surface (project grouping consumes exactly
## this).
func get_blueprint_cells() -> Array[BlueprintCell]:
	var result: Array[BlueprintCell] = []
	for cell: Vector3i in _blueprint_cells:
		result.append(_blueprint_cells[cell])
	return result


## Whether [param cell] is currently a tracked blueprint cell.
func has_blueprint_cell(cell: Vector3i) -> bool:
	return _blueprint_cells.has(cell)


## The commit pipeline's core entry point (AC4, [TR-building-system-002]/
## [TR-building-system-052]): gates on a currently-valid pick (AC38, Edge Case
## 4 -- "no valid pick... is a no-op"), clamps [param candidate_cells] to
## world bounds (Edge Case 1, AC9), and creates one fresh [BlueprintCell] per
## surviving cell -- exactly matching what survives the clamp, never more,
## never less. Returns the created cells (an empty array on any no-op path).
## Callable directly by a future tool story, or by [method
## _on_build_committed]'s own live wiring below -- and by tests, mirroring
## this project's established direct-method-call test convention.
func commit(candidate_cells: Array[Vector3i]) -> Array[BlueprintCell]:
	assert(is_set_up(), "CommitPipeline.commit called before setup()")
	if not placement_pick.get_current_pick().hit:
		return []
	var in_bounds_cells: Array[Vector3i] = candidate_cells.filter(
		func(cell: Vector3i) -> bool: return voxel_world.is_in_bounds(cell)
	)
	if in_bounds_cells.is_empty():
		return []
	var created: Array[BlueprintCell] = []
	for cell: Vector3i in in_bounds_cells:
		var blueprint := BlueprintCell.new(cell)
		_blueprint_cells[cell] = blueprint
		created.append(blueprint)
	blueprint_cells_created.emit(created)
	return created


## Live wiring: reacts to [signal PlacementPick.build_committed] (a genuine
## release, never an aborted drag -- see that signal's own doc comment) by
## resolving a candidate cell set via [method _resolve_cell_set] and calling
## [method commit] with it.
func _on_build_committed(is_drag: bool, press_cell: Vector3i, release_cell: Vector3i) -> void:
	commit(_resolve_cell_set(is_drag, press_cell, release_cell))


## Dispatches to [member _cell_set_resolver] if one was wired ([method
## set_cell_set_resolver]), else [method _default_cell_set]'s placeholder.
func _resolve_cell_set(is_drag: bool, press_cell: Vector3i, release_cell: Vector3i) -> Array[Vector3i]:
	if _cell_set_resolver.is_valid():
		var resolved: Array[Vector3i] = _cell_set_resolver.call(is_drag, press_cell, release_cell)
		return resolved
	return CommitPipeline._default_cell_set(is_drag, press_cell, release_cell)


## Deliberately minimal placeholder cell-set (see class doc comment's "out of
## scope" note) -- NOT GDD Formula F1/F2/F5. A click (AC6) commits exactly
## the single press cell ("single-column commit" collapses to one cell at
## this story's tool-agnostic layer, since the real column height is Story
## 024's Wall-tool-owned `wall_height` knob); a drag commits the press and
## release cells (a minimal two-point set, sufficient to exercise the
## bounds-clamp mechanism, AC9) with the degenerate zero-length-drag case
## collapsed to one cell. Pure and stateless.
static func _default_cell_set(is_drag: bool, press_cell: Vector3i, release_cell: Vector3i) -> Array[Vector3i]:
	if not is_drag or press_cell == release_cell:
		return [press_cell]
	return [press_cell, release_cell]
