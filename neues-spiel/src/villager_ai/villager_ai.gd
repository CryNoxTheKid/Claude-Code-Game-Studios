## Villager AI injected-tier module scaffold (Story villager-ai-001, ADR-0001
## primary, ADR-0008 secondary for the FSM state set).
##
## Owns exactly two things at this story's scope: the [enum State] six-state
## agent machine (Deciding/Traveling/Working/Sleeping/Breather/Wandering,
## ADR-0008 Decision §1) and the tick-driven `match` dispatch skeleton that
## will carry each state's real behaviour in later stories -- every branch
## body is an empty stub here (`_tick_deciding`/`_tick_traveling`/
## `_tick_working`/`_tick_sleeping`/`_tick_breather`/`_tick_wandering`), per
## this story's explicit Out of Scope: walkability (story 002), the Deciding
## scheduler queue/budget (story 005), and the priority decision logic
## (story 006) are NOT implemented here.
##
## Injected-tier module (ADR-0001): [member config] and [member voxel_world]
## are wired via a scene file's Inspector in production, or assigned
## directly in a headless test; all wiring/validation lives in [method setup],
## never `_ready()`. [member time_tick_system] is the one deliberate
## exception to "typed `@export`" -- see that field's own doc comment for why
## it mirrors [GameWorld]'s existing `resource_item_database` duck-typed
## pattern instead.
##
## Dispatch is driven EXCLUSIVELY by [member time_tick_system]'s `tick`
## signal (ADR-0008 Decision §2, Control Manifest Feature Layer: "tick-driven
## via Time & Tick's signal, never raw delta") -- this class defines no
## `_process`/`_physics_process` override anywhere, so the "never raw delta"
## guarantee holds structurally rather than by a conditional bypass (the same
## structural-guarantee style `CameraInput`'s raw-delta contract already
## established for this codebase).
##
## Story villager-ai-002 (previous revision) adds the two shared walkability
## predicates ADR-0007 Decision §1 assigns to Villager AI as its public API:
## [method is_standable] and [method is_step_legal]. Both are pure queries
## against [member voxel_world]'s cell data plus two registered design
## constants ([constant VILLAGER_CLEARANCE], [constant MAX_STEP_HEIGHT]) --
## no mutation, no cached state, no duplicated copy anywhere else (Control
## Manifest Feature Layer Forbidden: "never duplicate walkability rules or
## constants"). Every future consumer -- this class's own AStar3D pathfinder
## (story 007), Build Validation's independent BFS, and the Unstuck
## Watchdog's rescue-target search (story 014) -- calls these same two
## functions; none of them may re-derive an equivalent rule locally.
##
## Story villager-ai-003 (this revision) names the **body-column** concept
## explicitly (GDD Rule 8a/[TR-villager-ai-behavior-098], ADR-0009 slice
## propagation, Control Manifest Core Layer: "Occupancy is a body-column, not
## a single cell") and adds it as a second pure-function public API:
## [method body_column] derives the villager's own 3-cell vertical space
## (2-cell body + 1 buffer headroom cell) from a single discrete
## `current_cell`, and [method is_cell_in_body_column] is the occupancy
## predicate against it. Both reuse [constant VILLAGER_CLEARANCE] unchanged
## -- no second constant, per this story's explicit scope -- and are
## interpolation-free by construction (they take a `Vector3i`, never a
## villager instance or its `_visual_position`). Future consumers -- the
## Unstuck Watchdog's rescue/trigger checks (stories 014/015) and
## seal-prevention/walled-in detection (story 016) -- derive/query the
## column through these two functions rather than re-deriving an equivalent
## span locally.
class_name VillagerAi
extends Node

## The six-state agent machine (GDD "States and Transitions" table; ADR-0008
## Decision §1 Architecture Diagram). Exactly these six and no others
## [TR-villager-ai-behavior-... state table]. Per-villager state is driven by
## `match` on [method _tick_state], never a behavior tree or utility-scored
## alternative (ADR-0008 Alternatives B/C, rejected).
enum State {
	DECIDING,
	TRAVELING,
	WORKING,
	SLEEPING,
	BREATHER,
	WANDERING,
}

## Vertical clearance a standable cell requires: the cell itself plus the
## two cells directly above it must all be empty (GDD Rule 8/8a,
## [TR-villager-ai-behavior-009]/[TR-villager-ai-behavior-098]'s body-column
## definition -- the 2-cell body plus one buffer cell of headroom). A
## registered design constant (`design/registry/entities.yaml`'s
## `villager_clearance` = 3), not a tunable knob -- same locked-constant
## rationale as [VoxelWorldGrid.CHUNK_SIZE]; deliberately absent from
## [VillagerAIConfig] (ADR-0007: "no duplicated constants, anywhere").
const VILLAGER_CLEARANCE: int = 3

## Maximum legal height difference between two adjacent standable cells
## (GDD Rule 9, [TR-villager-ai-behavior-010]). A registered design constant
## (`design/registry/entities.yaml`'s `max_step_height` = 1), not a tunable
## knob -- same locked-constant rationale as [constant VILLAGER_CLEARANCE].
const MAX_STEP_HEIGHT: int = 1

## Tuning config dependency (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup]. No gameplay value is ever hardcoded in
## this module -- every tunable is read from this config once later stories
## give the state bodies real behaviour [TR-villager-ai-behavior-090].
@export var config: VillagerAIConfig

## Voxel World dependency (ADR-0001), typed `@export` since [VoxelWorldGrid]
## is itself an injected-tier module (not an Autoload) -- wired via a scene
## file's Inspector in production, or assigned directly in a headless test.
## Unused by this story's stub state bodies (walkability reads are story
## 002's scope); asserted as wired in [method setup] regardless, since every
## later story's `_tick_traveling`/`_tick_working`/etc. body will need it and
## the DI wiring point belongs on this scaffold from day one, not
## re-threaded per story.
@export var voxel_world: VoxelWorldGrid

## Time & Tick System dependency (ADR-0001 Autoload tier). Deliberately a
## plain, non-`@export` `Object` -- `@export`ing an Autoload into any module
## is Forbidden (ADR-0001) -- mirroring [GameWorld]'s existing
## `resource_item_database` duck-typed field exactly: production leaves this
## `null` and [method setup] resolves it lazily against
## `/root/TimeTickSystem` (the real Autoload, registered project-wide); a
## headless test assigns a `tick`-signal-shaped test double directly before
## calling [method setup], with zero scene tree and zero manual Autoload
## registration of its own. Duck-typed against exactly one member this class
## depends on: `signal tick()`.
var time_tick_system: Object = null

## Current agent state (GDD "States and Transitions": Deciding is every
## agent's loop-start entry). Read-only from outside this class -- see
## [method get_state].
var _state: State = State.DECIDING

## True once [method setup] has completed at least once.
var _is_set_up: bool = false


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config], [member voxel_world], and a
## [member time_tick_system]-shaped dependency are all wired, applies
## ADR-0002's clamp+warn `validate()` policy, then connects this module's
## tick dispatch to the SOLE global tick broadcast (`TimeTickSystem.tick`,
## per that Autoload's own doc comment) -- never a per-villager `Timer` or
## raw-delta poll.
func setup() -> void:
	assert(config != null, "VillagerAi.config not wired")
	assert(voxel_world != null, "VillagerAi.voxel_world not wired")
	if time_tick_system == null:
		time_tick_system = get_node_or_null(^"/root/TimeTickSystem")
	assert(
		time_tick_system != null,
		"VillagerAi requires a TimeTickSystem-shaped dependency (assign a mock in"
		+ " tests; the real Autoload is registered project-wide) before setup() can"
		+ " connect tick dispatch"
	)
	for issue: String in config.validate():
		if not issue.begins_with(ConfigResource.BLOCKING_PREFIX):
			push_warning(issue)
	@warning_ignore("unsafe_property_access")
	time_tick_system.tick.connect(_on_tick)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the current agent state (read-only observability/test seam).
func get_state() -> State:
	return _state


## Standability predicate (ADR-0007 Decision §1, GDD Rule 8/[TR-villager-ai-
## behavior-009]): [param cell] is standable iff the cell directly below it
## is solid (occupied -- terrain or a Built block) AND [param cell] itself
## plus the [constant VILLAGER_CLEARANCE] - 1 cells directly above it are all
## empty (GDD Rule 8a's body-column: the 2-cell body plus one buffer cell of
## headroom).
##
## An unbuilt Planned blueprint cell is never written to [member voxel_world]
## (Control Manifest Core Layer: "Built cells mutate ONLY via worker-executed
## jobs") -- it reads back empty via [method VoxelWorldGrid.get_cell], so it
## is non-solid/passable here BY CONSTRUCTION, matching Building System Core
## Rule 14b / GDD AC17 with no special-case branch needed.
##
## Pure query: reads only [member voxel_world]'s cell data, never mutates
## anything, caches nothing of its own (Control Manifest Feature Layer
## Guardrail: "predicates are pure queries... no mutation, no caching state
## of their own"). A cell outside the configured world bounds reads back
## `null` from [method VoxelWorldGrid.get_cell] and is treated as blocking by
## both helpers below -- the world simply does not extend there, so it can
## neither support a foot (never solid-below) nor offer clearance (never
## passable).
func is_standable(cell: Vector3i) -> bool:
	assert(voxel_world != null, "VillagerAi.voxel_world not wired")
	if not _is_solid(cell + Vector3i(0, -1, 0)):
		return false
	for offset in range(VILLAGER_CLEARANCE):
		if not _is_passable(cell + Vector3i(0, offset, 0)):
			return false
	return true


## Step-legality predicate (ADR-0007 Decision §1, GDD Rule 9/[TR-villager-ai-
## behavior-010]): a step from [param from_cell] to [param to_cell] is legal
## iff the vertical height difference is at most [constant MAX_STEP_HEIGHT],
## AND -- only when the step is diagonal (both the X and Z coordinates
## differ; a purely orthogonal step never runs this second check at all) --
## both flanking orthogonal cells (the cell at `(to_cell.x, from_cell.y,
## from_cell.z)` and the cell at `(from_cell.x, from_cell.y, to_cell.z)`) are
## themselves standable ([method is_standable]) -- no corner-cutting through
## walls.
##
## Assumes [param from_cell] and [param to_cell] are themselves standable --
## the caller (the AStar3D graph builder, story 007) only ever connects
## standable-cell pairs via this predicate, so re-verifying that here would
## duplicate [method is_standable]'s own job. Pure query, no mutation, no
## cached state (same guardrail as [method is_standable]).
func is_step_legal(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if absi(to_cell.y - from_cell.y) > MAX_STEP_HEIGHT:
		return false
	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.z - from_cell.z
	if dx != 0 and dz != 0:
		var flanker_a := Vector3i(to_cell.x, from_cell.y, from_cell.z)
		var flanker_b := Vector3i(from_cell.x, from_cell.y, to_cell.z)
		if not is_standable(flanker_a) or not is_standable(flanker_b):
			return false
	return true


## Body-column derivation (Story villager-ai-003, ADR-0009 slice-propagation
## Decision §2/Key Interfaces, GDD Rule 8a/[TR-villager-ai-behavior-098],
## Control Manifest Core Layer: "Occupancy is a body-column, not a single
## cell"): the villager's own space is a 3-cell vertical span -- the 2-cell
## body (feet + head) plus one buffer headroom cell -- derived
## deterministically from a single discrete cell, exactly the same span
## [method is_standable] already checks for standability clearance
## ([constant VILLAGER_CLEARANCE] -- no second constant is introduced by
## this story, per its Implementation Notes). This function only names the
## concept as a reusable, callable definition so the Unstuck Watchdog
## (stories 014/015) and seal-prevention/walled-in queries (story 016) share
## ONE source of truth instead of each re-deriving an equivalent span
## locally.
##
## Interpolation-free by construction: [param cell] is a plain `Vector3i` --
## there is no villager instance, `current_cell`, or `_visual_position`
## anywhere in this function's signature or body, so it cannot accidentally
## read interpolation state. Callers are responsible for always passing the
## authoritative discrete `current_cell` (ADR-0009 Decision §1), never a
## visual/interpolated position.
##
## Pure query: no mutation, no cached state, identical inputs always yield
## an identical result (the same purity guarantee as [method is_standable] /
## [method is_step_legal]).
func body_column(cell: Vector3i) -> Array[Vector3i]:
	var column: Array[Vector3i] = []
	for offset in range(VILLAGER_CLEARANCE):
		column.append(cell + Vector3i(0, offset, 0))
	return column


## Occupancy predicate against a villager's body-column (ADR-0009
## slice-propagation Decision §2/§2b, Control Manifest Core Layer: "Seal
## prevention is a negative-write gate the Building System write path MUST
## accept" -- this is the shared predicate that gate, and the Watchdog's
## rescue/trigger checks, read). Returns whether [param query_cell] falls
## within the body-column occupying [param occupant_cell] -- i.e. whether a
## villager standing at [param occupant_cell] occupies [param query_cell].
##
## Deliberately NOT a feet-only comparison (`query_cell == occupant_cell`):
## this story's AC requires proving a feet-only check is insufficient -- the
## body cell directly above the feet, and the buffer headroom cell above
## that, are also occupied, and a write there must be caught by
## seal-prevention exactly as a write at the feet cell would be (a check
## that only ever compares against the feet cell would miss it -- the exact
## defect the column exists to prevent).
##
## Pure query: delegates entirely to [method body_column]; no mutation, no
## cached state.
func is_cell_in_body_column(occupant_cell: Vector3i, query_cell: Vector3i) -> bool:
	return body_column(occupant_cell).has(query_cell)


## Solidity read for [method is_standable]'s "solid below" check -- an
## out-of-bounds cell ([method VoxelWorldGrid.get_cell] returns `null`) is
## never solid (there is nothing to stand ON there).
func _is_solid(cell: Vector3i) -> bool:
	var contents: CellContents = voxel_world.get_cell(cell)
	return contents != null and not contents.is_empty()


## Passability read for [method is_standable]'s clearance-column check -- an
## out-of-bounds cell is never passable (the world doesn't extend there, so
## clearance can't be confirmed).
func _is_passable(cell: Vector3i) -> bool:
	var contents: CellContents = voxel_world.get_cell(cell)
	return contents != null and contents.is_empty()


## [signal TimeTickSystem.tick] handler -- the sole entry point that ever
## advances this agent's state machine (ADR-0008 Decision §2). Delegates
## immediately to [method _tick_state]; kept as a separate method (rather
## than connecting [method _tick_state] directly) so a later story's
## Deciding-pass staggering budget (ADR-0008's `max_deciding_per_tick` FIFO
## queue, story 005) has an obvious, single seam to insert into without
## touching the signal-wiring line in [method setup].
func _on_tick() -> void:
	_tick_state()


## FSM dispatch (ADR-0008 Key Interfaces): one `match` branch per
## [enum State], one function per state. Every branch below is an
## intentionally empty stub for this story -- real per-state behaviour
## (movement, work progress, sleep recovery, breather pacing, wander
## micro-behaviours, the Deciding priority list) lands in stories 002/004/
## 005/006/etc., never here.
func _tick_state() -> void:
	match _state:
		State.DECIDING:
			_tick_deciding()
		State.TRAVELING:
			_tick_traveling()
		State.WORKING:
			_tick_working()
		State.SLEEPING:
			_tick_sleeping()
		State.BREATHER:
			_tick_breather()
		State.WANDERING:
			_tick_wandering()


## Deciding-state tick body -- stub (story 005 scheduler queue/budget,
## story 006 priority decision logic).
func _tick_deciding() -> void:
	pass


## Traveling-state tick body -- stub (story 002 walkability, later movement
## stories).
func _tick_traveling() -> void:
	pass


## Working-state tick body -- stub (later work-progress story).
func _tick_working() -> void:
	pass


## Sleeping-state tick body -- stub (later needs/sleep story).
func _tick_sleeping() -> void:
	pass


## Breather-state tick body -- stub (later life-texture story).
func _tick_breather() -> void:
	pass


## Wandering-state tick body -- stub (story 004 wander/idle micro-behaviours).
func _tick_wandering() -> void:
	pass
