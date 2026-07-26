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
##
## Story building-028 (this revision, ADR-0016 BV-1 ruling
## `production/architecture-decisions-m02-preflight-2026-07-26.md`) adds
## furniture IDENTITY to [method commit]'s creation step: [method
## _selected_item_is_furniture] resolves whether the currently selected item
## is a `furniture_fixture` RID entry, and [method commit] passes the
## resulting [enum BlueprintCell.Category]/[member
## BlueprintCell.furniture_definition_id] into every [BlueprintCell] it
## creates for that commit -- the "real material-selection wiring" this
## class's own doc comment (point 3) and [BlueprintCell]'s own doc comment
## already named as this story's future job. [method get_available_palette]
## is this story's other addition (TR-074/AC18) -- a pure read-only query
## over [member resource_item_database], no new state. [FurnitureTool] (this
## story) is the real caller that wires [method set_furniture_support_predicate]
## with the actual support-geometry check; this class still has no support
## concept of its own beyond the seam.
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
##
## The Autoload lookup is additionally guarded by [method is_inside_tree]
## (ADR-0001): [method get_node_or_null] with an ABSOLUTE path hard-errors
## ("Can't use get_node() with absolute paths from outside the active scene
## tree") when called on a freestanding, not-yet-parented node -- exactly
## the shape every headless test constructs via `auto_free(CommitPipeline.new())`
## (this codebase's own `reference_injected_module_test.gd`/
## `loop_payoff_surface_test.gd` precedent asserts `is_inside_tree() == false`
## for that exact construction). A test that wants RID behavior assigns a
## test double directly BEFORE calling [method setup] (see
## `placement_validity_test.gd`'s `_MockItemDatabase`); production always
## calls this from inside a live, parented scene tree, where the lookup
## proceeds exactly as before.
func setup() -> void:
	assert(placement_pick != null, "CommitPipeline.placement_pick not wired")
	assert(voxel_world != null, "CommitPipeline.voxel_world not wired")
	assert(config != null, "CommitPipeline.config not wired")
	for issue: String in config.validate():
		push_warning(issue)
	if resource_item_database == null and is_inside_tree():
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


## The tracked [BlueprintCell] at [param cell], or `null` if none is tracked
## -- Story building-028 addition. [FurnitureTool]'s own furniture-support
## predicate reads this to recognize a Draft/UnderConstruction/Built FLOOR
## blueprint cell as valid support (Rule 8's "a blueprint floor cell counts
## as support for a furniture blueprint," [TR-building-system-050]/AC49) --
## the SAME combined-view registry [method _is_cell_available] already reads
## internally, exposed read-only rather than duplicated. A CANCELED entry IS
## still returned here (mirrors [member _blueprint_cells]' own raw-storage
## shape) -- the caller decides whether a canceled cell counts as support
## (it never does, per [method _is_cell_available]'s own "canceled cells
## free up their address" precedent).
func get_blueprint_cell_at(cell: Vector3i) -> BlueprintCell:
	return _blueprint_cells.get(cell)


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
	# Story building-028: resolve the whole commit's category/furniture id
	# ONCE (the same selected item applies to every cell of one commit) --
	# see [method _selected_item_is_furniture]'s own doc comment for why this
	# is independent of [method _is_selected_item_available]'s own resolution.
	var is_furniture: bool = _selected_item_is_furniture()
	var category: BlueprintCell.Category = (
		BlueprintCell.Category.FURNITURE if is_furniture else BlueprintCell.Category.BLOCK
	)
	var furniture_definition_id: StringName = _selected_item_id if is_furniture else &""
	var created: Array[BlueprintCell] = []
	for cell: Vector3i in in_bounds_cells:
		var blueprint := BlueprintCell.new(
			cell, BlueprintCell.MicroState.PLANNED, category, null, furniture_definition_id
		)
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


## Story building-028 addition (GDD Rule 8, [TR-building-system-048]) --
## whether the CURRENTLY selected item ([member _selected_item_id]) is a
## `furniture_fixture` entry, consulted independently of [method
## _is_selected_item_available]'s own availability contract. Deliberately
## NOT unified with that method: its "no [member resource_item_database]
## wired" fallback TRUSTS a bare selection at face value for AVAILABILITY --
## that trust does not extend to "is furniture," so an untethered test with
## no RID double wired always resolves to [constant BlueprintCell.Category.BLOCK]
## (every pre-028 test's existing, unchanged expectation). Returns `false`
## whenever [member resource_item_database] is `null`/not ready/reports no
## definition for the id, or the definition's [method
## ItemDefinition.get_category] is not `&"furniture_fixture"`. The `is
## ItemDefinition` guard (rather than a duck-typed `has_method` check) is
## deliberate: [_MockItemDatabase]-shaped doubles used by pre-028 tests
## return a bare `bool`/`null` from `get_by_id`, and `bool is ItemDefinition`
## resolves to `false` safely (no runtime error) -- exactly the "default to
## BLOCK" fallback this method's own doc comment promises.
func _selected_item_is_furniture() -> bool:
	if resource_item_database == null:
		return false
	if String(_selected_item_id) == "":
		return false
	@warning_ignore("unsafe_method_access")
	if not bool(resource_item_database.is_ready()):
		return false
	@warning_ignore("unsafe_method_access")
	var definition: Variant = resource_item_database.get_by_id(_selected_item_id)
	if not (definition is ItemDefinition):
		return false
	return (definition as ItemDefinition).get_category() == &"furniture_fixture"


## Story building-028 addition (TR-building-system-074, AC18) -- the palette
## this MVP data set offers: every tier-0 `building_material` entry UNION
## every `furniture_fixture` entry (MVP list: `bed` only, Core Rule 8) --
## furniture is never tier-gated the way materials are (Core Rule 9: "the
## tier-0 set plus bed," not "the tier-0 set of materials and furniture").
## Returns an empty array whenever [member resource_item_database] is
## `null`/not ready -- mirrors every other RID-consuming query in this
## codebase (never a crash, never a partial read). No Building UI palette
## exists yet in this codebase to consume this; a future palette story is
## this method's real caller.
func get_available_palette() -> Array[StringName]:
	var ids: Array[StringName] = []
	if resource_item_database == null:
		return ids
	@warning_ignore("unsafe_method_access")
	if not bool(resource_item_database.is_ready()):
		return ids
	@warning_ignore("unsafe_method_access")
	var tier0_ids: Array = resource_item_database.list_ids_by_tier(0)
	@warning_ignore("unsafe_method_access")
	var material_ids: Array = resource_item_database.list_ids_by_category(&"building_material")
	for id: Variant in tier0_ids:
		if material_ids.has(id):
			ids.append(id as StringName)
	@warning_ignore("unsafe_method_access")
	var furniture_ids: Array = resource_item_database.list_ids_by_category(&"furniture_fixture")
	for id: Variant in furniture_ids:
		ids.append(id as StringName)
	return ids


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


## Preview-only cell-set resolution (Story building-023) -- the EXACT SAME
## per-tool resolver dispatch [method _on_build_committed] uses for a genuine
## commit ([method _resolve_cell_set], registered via [method
## set_cell_set_resolver] by whichever tool is currently wired -- wall/floor/
## roof/block, Stories 024-027), exposed publicly so a live ghost preview can
## call it every frame BEFORE any release ever happens. Never creates a
## [BlueprintCell] and never touches [VoxelWorldGrid] -- [method
## _resolve_cell_set] itself only ever calls a registered tool's pure static
## formula function (or [method _default_cell_set]'s placeholder). This is
## the "preview/commit parity by construction" every tool's own doc comment
## already promises this future call site ("reusable as-is by a future
## ghost-preview call site, Story 023").
func preview_cell_set(is_drag: bool, press_cell: Vector3i, release_cell: Vector3i) -> Array[Vector3i]:
	assert(is_set_up(), "CommitPipeline.preview_cell_set called before setup()")
	return _resolve_cell_set(is_drag, press_cell, release_cell)


## Bounds-clamp only (Story building-023) -- the EXACT SAME filter [method
## commit] applies before running its validity gate (Edge Case 1), exposed so
## a live ghost preview clamps identically without duplicating the filter
## predicate. Pure w.r.t. this instance's own state -- reads only [member
## voxel_world].
func clamp_to_bounds(candidate_cells: Array[Vector3i]) -> Array[Vector3i]:
	return candidate_cells.filter(
		func(cell: Vector3i) -> bool: return voxel_world.is_in_bounds(cell)
	)


## Preview-only validity probe (Story building-023) -- reuses the EXACT SAME
## four checks [method commit] itself runs, in the SAME order, entirely
## side-effect-free: no [BlueprintCell] is ever created and [signal
## commit_rejected] is never emitted (that signal is reserved for a genuine
## commit ATTEMPT -- a live per-frame preview probe asking "would this be
## valid right now" is not a rejection event, it would spam the signal every
## frame of a hover). Returns the first failing [enum RejectReason] as its
## plain [int] ordinal, or `-1` if every check passes (there is no "valid"
## [enum RejectReason] value to return instead -- mirrors this class's own
## sentinel conventions elsewhere, e.g. [ADR-0016]'s `-1 = none` for
## `project_at_cell`). [GhostPreview] (this story) is this method's real
## caller, on [param in_bounds_cells] (the output of [method clamp_to_bounds])
## -- calling this on a NOT-yet-clamped set would double-count an
## out-of-bounds cell against [member CommitPipelineConfig.max_cells_per_command]
## incorrectly, exactly as [method commit] itself avoids by always clamping
## first.
func first_rejection_reason(in_bounds_cells: Array[Vector3i]) -> int:
	assert(is_set_up(), "CommitPipeline.first_rejection_reason called before setup()")
	if not _is_selected_item_available():
		return RejectReason.NO_MATERIAL_SELECTED
	if in_bounds_cells.size() > config.max_cells_per_command:
		return RejectReason.CELL_COUNT_EXCEEDS_CAP
	if not _all_cells_available(in_bounds_cells):
		return RejectReason.CELL_OCCUPIED
	if not _all_cells_supported(in_bounds_cells):
		return RejectReason.FURNITURE_UNSUPPORTED
	return -1


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
