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
## - Ghost preview RENDERING (Story 023) and project grouping/merge/reverse-
##   index (Story 003, ADR-0016 Decision §2) -- [signal blueprint_cells_created]
##   is exactly the seam Story 003 consumes; this class performs no grouping
##   of its own and holds no project concept.
##
## Story building-022 (this revision) adds the full placement-VALIDITY gate
## Core Rule 9 requires ([TR-building-system-049]/[TR-building-system-050]/
## [TR-building-system-060]/[TR-building-system-084]/[TR-building-system-085]),
## wired directly into [method commit] as four sequential ALL-OR-NOTHING
## checks run AFTER the existing bounds clamp (which stays a PARTIAL clamp,
## Edge Case 1, unchanged) and BEFORE any [BlueprintCell] is created:
## 1. **Material/furniture selected + available** (AC42, [TR-building-system-049]):
##    [method _is_selected_item_available] -- see [method set_selected_item].
## 2. **Cell count <= `max_cells_per_command`** (AC39, [TR-building-system-049]):
##    checked against the POST-CLAMP in-bounds count -- see [member config].
## 3. **Combined-view occupancy** (AC10/AC11/AC14, Edge Cases 2/3,
##    [TR-building-system-060]/[TR-building-system-084]/[TR-building-system-085]):
##    [method _all_cells_available] queries the COMBINED view (Voxel World's
##    raw grid data UNION this pipeline's own [member _blueprint_cells]
##    registry) never raw Voxel World state alone -- see [method
##    _is_cell_available]'s doc comment for exactly how a cell's occupant is
##    classified as terrain/blueprint/already-built without any new state
##    beyond what [CommitPipeline]/[ConstructionTickLoop] already track by
##    construction (the "how" ADR-0016/building-system.md Core Rule 15
##    deliberately left as an implementation choice).
## 4. **Furniture support** (Rule 8, [TR-building-system-050]): [method
##    _all_cells_supported] calls an OPTIONAL predicate seam ([method
##    set_furniture_support_predicate]) -- Story 028's real footprint/support
##    geometry is the future real caller; the default `Callable()` means "no
##    support requirement," matching every non-furniture tool (block/wall/
##    floor/roof placement have no support concept at all).
## Any failed check emits [signal commit_rejected] with the failing [enum
## RejectReason] and returns an empty array -- ZERO [BlueprintCell]s created,
## matching every one of AC10/AC11/AC14/AC39/AC42's "no blueprint is created"
## wording exactly (an all-or-nothing rejection, deliberately UNLIKE the
## bounds clamp's own partial-commit behavior, Edge Case 1). [signal
## commit_rejected] is the seam Story 023's ghost-preview feedback (Core Rule
## 9's "rejected with visible feedback... never silently") will consume; no
## UI/feedback rendering exists yet in this codebase to wire it to.
##
## Injected-tier module (ADR-0001): [member placement_pick]/[member
## voxel_world]/[member config] are wired via a scene file's Inspector in
## production (`Valley.tscn`), or assigned directly in a headless test; all
## wiring lives in [method setup], never `_ready()`. [member
## resource_item_database] is an OPTIONAL, duck-typed Autoload-tier
## dependency (ADR-0001) -- see that member's own doc comment for why it is
## resolved lazily rather than asserted, mirroring [ConstructionTickLoop]'s
## [member ConstructionTickLoop.time_tick_system] shape but relaxed to a
## graceful fallback instead of a hard assert (see [method
## _is_selected_item_available]).
class_name CommitPipeline
extends Node

## Fires whenever [method commit] creates at least one [BlueprintCell] --
## never for a commit that clamps to zero in-bounds cells, and never for the
## no-valid-pick no-op (AC38). Story building-003 (project grouping/merge) is
## this signal's real future consumer; no such class exists yet in this
## codebase.
signal blueprint_cells_created(cells: Array[BlueprintCell])

## Fires whenever [method commit] rejects a commit outright for one of Story
## building-022's ALL-OR-NOTHING validity reasons (see class doc comment) --
## never for the pre-existing silent no-ops (no valid pick, AC38; a candidate
## set that bounds-clamps to entirely empty, Edge Case 1), which keep their
## own established "absence of a ghost IS the feedback" contract unchanged.
## [param cells] carries the full post-bounds-clamp candidate set that was
## rejected (never a partial subset) -- Story 023's future feedback-rendering
## consumer is this signal's real caller; no such UI exists yet in this
## codebase.
signal commit_rejected(reason: RejectReason, cells: Array[Vector3i])

## Every distinct ALL-OR-NOTHING rejection reason [method commit] can emit via
## [signal commit_rejected] (Story building-022) -- named after the GDD
## Core Rule 9 clause each one enforces.
enum RejectReason {
	NO_MATERIAL_SELECTED,     ## AC42 [TR-building-system-049]
	CELL_COUNT_EXCEEDS_CAP,   ## AC39 [TR-building-system-049]
	CELL_OCCUPIED,            ## AC10/AC11/AC14 [TR-building-system-084]/[TR-building-system-085]
	FURNITURE_UNSUPPORTED,    ## Rule 8 [TR-building-system-050]
}

## Injected-tier dependency (ADR-0001) -- the sole source of [signal
## PlacementPick.build_committed] this pipeline reacts to, and of the current
## pick's hit/miss state [method commit] gates on (AC38).
@export var placement_pick: PlacementPick

## Injected-tier dependency (ADR-0001) -- read-only bounds check ([method
## VoxelWorldGrid.is_in_bounds]) ONLY. This class never calls [method
## VoxelWorldGrid.set_cell]/[method VoxelWorldGrid.bulk_write]/[method
## VoxelWorldGrid.clear_cell] -- see class doc comment point 3.
@export var voxel_world: VoxelWorldGrid

## Tuning config dependency (ADR-0002, Story building-022) -- GDD Core Rule
## 9's `max_cells_per_command` cap ([TR-building-system-049]). Wired via a
## scene file's Inspector in production (`Valley.tscn`), or assigned directly
## in a headless test. Never read inside `_ready()` -- see [method setup].
@export var config: CommitPipelineConfig

## OPTIONAL Autoload-tier dependency (ADR-0001, Story building-022) -- the
## sole source [method _is_selected_item_available] queries for "is the
## selected material/furniture entry available" (Core Rule 9). A plain,
## duck-typed `Object` (never `@export`ed -- ADR-0001 forbids `@export`ing an
## Autoload into any module), mirroring [ConstructionTickLoop]'s [member
## ConstructionTickLoop.time_tick_system] shape: production resolves it
## lazily against `/root/ResourceItemDatabase` in [method setup]; a headless
## test assigns an RID-shaped test double directly before calling that
## method. UNLIKE [ConstructionTickLoop]'s dependency, this one is never
## asserted non-null -- no Building UI/palette exists yet in this codebase to
## guarantee every caller of this class wires a real RID reference, and
## Story building-022's own acceptance criteria (AC42) only require proving
## the "nothing selected" rejection, not full palette-availability plumbing
## through every existing test construction site. See [method
## _is_selected_item_available]'s doc comment for the documented fallback
## this relaxation implies.
var resource_item_database: Object = null

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## The currently selected material/furniture entry's opaque id (Core Rule 9,
## AC42) -- empty (`&""`) means "nothing selected," which always fails
## [method _is_selected_item_available] regardless of [member
## resource_item_database]. Set via [method set_selected_item] -- the future
## Building UI palette's real wiring point (no such UI exists yet in this
## codebase; mirrors [method set_cell_set_resolver]'s own "future story
## overrides this" seam pattern).
var _selected_item_id: StringName = &""

## Optional furniture-support predicate (Rule 8, [TR-building-system-050],
## Story building-022) -- `Callable(cell: Vector3i) -> bool`. Default
## `Callable()` (invalid) means "no support requirement," matching every
## MVP tool except furniture (block/wall/floor/roof placement have no
## support concept at all). Story 028's real footprint/support-geometry
## check is this seam's future real caller -- set via [method
## set_furniture_support_predicate], mirroring [method set_cell_set_resolver]'s
## own "future story overrides this" seam pattern exactly.
var _furniture_support_predicate: Callable = Callable()

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


## Explicitly callable wiring entry point (ADR-0001). Asserts the required
## dependencies were wired, applies ADR-0002's clamp+warn `validate()` policy
## to [member config], lazily resolves [member resource_item_database]
## against the real Autoload when a caller has not already assigned a test
## double (mirrors [ConstructionTickLoop.setup]'s identical lazy-resolution
## shape, but never asserts non-null here -- see that member's own doc
## comment), and connects to [signal PlacementPick.build_committed]
## (idempotent via [method Signal.is_connected], mirroring
## [ToolStateMachine]'s own precedent).
func setup() -> void:
	assert(placement_pick != null, "CommitPipeline.placement_pick not wired")
	assert(voxel_world != null, "CommitPipeline.voxel_world not wired")
	assert(config != null, "CommitPipeline.config not wired")
	for issue: String in config.validate():
		push_warning(issue)
	if resource_item_database == null:
		resource_item_database = get_node_or_null(^"/root/ResourceItemDatabase")
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


## Sets the currently selected material/furniture entry's opaque id (Core
## Rule 9, AC42, Story building-022) -- the future Building UI palette's real
## wiring point (see [member _selected_item_id]'s doc comment). Passing `&""`
## clears the selection, which always fails [method
## _is_selected_item_available] regardless of [member resource_item_database].
func set_selected_item(id: StringName) -> void:
	_selected_item_id = id


## Returns the currently selected material/furniture entry's opaque id, or
## `&""` if none is selected.
func get_selected_item() -> StringName:
	return _selected_item_id


## Overrides the furniture-support predicate (Rule 8, [TR-building-system-050],
## Story building-022) -- Story 028's real footprint/support-geometry check
## calls this with its own real predicate instead of relying on the default
## "no support requirement" (see [member _furniture_support_predicate]'s doc
## comment).
func set_furniture_support_predicate(predicate: Callable) -> void:
	_furniture_support_predicate = predicate


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
## world bounds (Edge Case 1, AC9), runs Story building-022's full
## ALL-OR-NOTHING validity gate (see class doc comment for the four checks
## and their order), and creates one fresh [BlueprintCell] per surviving cell
## -- exactly matching what survives the clamp, never more, never less.
## Returns the created cells (an empty array on any no-op/rejection path).
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
	if not _is_selected_item_available():
		commit_rejected.emit(RejectReason.NO_MATERIAL_SELECTED, in_bounds_cells)
		return []
	if in_bounds_cells.size() > config.max_cells_per_command:
		commit_rejected.emit(RejectReason.CELL_COUNT_EXCEEDS_CAP, in_bounds_cells)
		return []
	if not _all_cells_available(in_bounds_cells):
		commit_rejected.emit(RejectReason.CELL_OCCUPIED, in_bounds_cells)
		return []
	if not _all_cells_supported(in_bounds_cells):
		commit_rejected.emit(RejectReason.FURNITURE_UNSUPPORTED, in_bounds_cells)
		return []
	var created: Array[BlueprintCell] = []
	for cell: Vector3i in in_bounds_cells:
		var blueprint := BlueprintCell.new(cell)
		_blueprint_cells[cell] = blueprint
		created.append(blueprint)
	blueprint_cells_created.emit(created)
	return created


## Material/furniture availability check (Core Rule 9, AC42,
## [TR-building-system-049]): `false` whenever [member _selected_item_id] is
## empty (`&""`) -- AC42's core case, reachable with zero RID wiring of any
## kind. When a selection IS present, delegates to [member
## resource_item_database] if one is reachable (`is_ready()` AND
## `get_by_id(id) != null` -- the exact palette-availability contract Core
## Rule 9 names). If [member resource_item_database] is `null` (no Autoload
## reachable and no test double assigned), a non-empty selection is trusted
## at face value -- a deliberate MVP simplification (see that member's own
## doc comment): production always resolves a real reference in [method
## setup] once inside the live scene tree, so this fallback only matters for
## a bare, untethered test construction that does not care about
## availability specifically. Tests proving the FULL availability contract
## assign an explicit RID-shaped double before calling [method setup] instead
## (see `placement_validity_test.gd`).
func _is_selected_item_available() -> bool:
	if String(_selected_item_id) == "":
		return false
	if resource_item_database == null:
		return true
	@warning_ignore("unsafe_method_access")
	if not bool(resource_item_database.is_ready()):
		return false
	@warning_ignore("unsafe_method_access")
	return resource_item_database.get_by_id(_selected_item_id) != null


## Combined-view per-cell availability check (Edge Cases 2/3,
## [TR-building-system-060]/[TR-building-system-084]/[TR-building-system-085]):
## a cell is available for a NEW blueprint entry iff EITHER (a) it is
## untracked by this pipeline's own [member _blueprint_cells] registry (or
## tracked only by a [constant BlueprintCell.MicroState.CANCELED] entry --
## canceled cells free up their address) AND currently empty in raw Voxel
## World data (the ordinary "nothing here yet" case, including the attach-to-
## a-terrain-face case: the attach cell itself is always empty by
## construction), OR (b) it IS tracked with [constant
## BlueprintCell.MicroState.BUILT] -- a valid replace-in-place of a block THIS
## SYSTEM already built (the one narrow exception Core Rule 9 names).
##
## This is the COMBINED view TR-building-system-060 requires (Voxel World
## blocks UNION blueprint cells), never raw Voxel World state alone: a raw-
## grid-occupied cell this pipeline does NOT itself track as BUILT can only be
## terrain (this system is the sole writer of every cell it ever tracks, via
## [ConstructionTickLoop]'s completion write) -- correctly rejected regardless
## of whether the candidate is an "attach" or "replace-in-place" attempt, with
## no separate attach/replace-intent flag needed anywhere in this class (Edge
## Case 2's "replace-in-place targeting terrain is invalid, attaching to a
## terrain cell's face remains valid" falls out of this single rule: an
## attach cell is never the terrain cell itself, so it is always empty here).
## A Draft/UnderConstruction tracked entry is always unavailable (Edge
## Case 3) -- unconditional, no replace-in-place exception applies to an
## already-drafted cell.
func _is_cell_available(cell: Vector3i) -> bool:
	var existing: BlueprintCell = _blueprint_cells.get(cell)
	if existing != null and existing.state != BlueprintCell.MicroState.CANCELED:
		return existing.state == BlueprintCell.MicroState.BUILT
	return voxel_world.get_cell(cell).is_empty()


## `true` iff every cell in [param cells] passes [method _is_cell_available]
## -- the ALL-OR-NOTHING aggregate [method commit] gates on (AC10/AC11/AC14).
func _all_cells_available(cells: Array[Vector3i]) -> bool:
	for cell: Vector3i in cells:
		if not _is_cell_available(cell):
			return false
	return true


## Furniture-support aggregate (Rule 8, [TR-building-system-050]): `true`
## unconditionally when no predicate has been wired ([member
## _furniture_support_predicate] invalid) -- "no support requirement," the
## correct default for every MVP tool except furniture. When a predicate IS
## wired (Story 028's real check), every cell in [param cells] must pass it
## independently for the whole commit to be considered supported.
func _all_cells_supported(cells: Array[Vector3i]) -> bool:
	if not _furniture_support_predicate.is_valid():
		return true
	for cell: Vector3i in cells:
		if not bool(_furniture_support_predicate.call(cell)):
			return false
	return true


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
