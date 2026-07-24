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
## via Time & Tick's signal, never raw delta") -- FSM state mutation itself
## never happens from any raw-delta engine callback (the same
## structural-guarantee style `CameraInput`'s raw-delta contract already
## established for this codebase). **Amended by story villager-ai-004**: this
## class now defines exactly ONE narrow, deliberate exception -- [method
## _process] -- added for ADR-0009's cosmetic-only visual-position recompute;
## it never reads its own raw `_delta` parameter (named with the conventional
## unused-parameter underscore prefix) and never touches [member current_cell]
## or any FSM state, so the tick-signal-only dispatch guarantee above is
## completely unaffected. This class still defines no `_physics_process`
## override anywhere.
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
##
## Story villager-ai-004 (this revision) implements ADR-0009's two-layer
## deterministic position model: the discrete, tick-boundary-quantized
## [member current_cell] -- the sole authoritative occupancy value, exposed
## via [method get_current_cell] -- versus the continuous, cosmetic-only
## [member _visual_position] (recomputed every [method _process] frame,
## never read by any logic query anywhere). [method advance_travel_progress]
## is the pure, directly-testable movement-update function (this story's
## AC20/[TR-villager-ai-behavior-093]) that advances
## [member _intra_tick_progress]; [method _on_tick] performs the ONE
## sanctioned tick-boundary mutation of [member current_cell] this story
## owns (the OTHER sanctioned mutation -- a watchdog rescue -- is story
## 015's, out of scope here). Driving [member _from_cell]/[member _to_cell]
## to new values as a villager actually paths somewhere -- path selection,
## re-pathing, and calling [method advance_travel_progress] every frame with
## a live `game_delta` -- is story 009's Traveling-state-machine scope,
## explicitly NOT implemented here.
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

## DISCRETE, tick-boundary-quantized occupancy value -- the SOLE
## authoritative value for every logic/occupancy query (ADR-0009 Decision
## §1, Control Manifest Core Layer: "Occupancy authoritative value = discrete
## `current_cell`"). Mutated at EXACTLY two sanctioned points, both
## tick-boundary discrete: (a) [method _on_tick]'s arrival crediting below
## (this story), and (b) a future watchdog rescue (story 015) -- never
## anywhere else, never derived from [member _visual_position] or
## [member _intra_tick_progress]. While Traveling, this stays equal to
## [member _from_cell] for the step's ENTIRE duration (ADR-0009 Decision
## §1). Read via [method get_current_cell] -- never read directly by an
## outside consumer.
var current_cell: Vector3i = Vector3i.ZERO

## The current travel step's origin cell (Story villager-ai-004, ADR-0009
## Decision §1 Key Interfaces). [member current_cell] equals this for the
## step's entire duration -- driving it to a NEW value for the next step
## (path selection, re-pathing) is story 009's Traveling-state-machine
## concern, out of this story's scope.
var _from_cell: Vector3i = Vector3i.ZERO

## The current travel step's destination cell (Story villager-ai-004).
## [member current_cell] becomes this value ONLY via [method _on_tick]'s
## atomic arrival-crediting assignment, at the tick boundary where
## [member _intra_tick_progress] has reached `1.0`.
var _to_cell: Vector3i = Vector3i.ZERO

## CONTINUOUS, cosmetic-ONLY interpolated world position (ADR-0009 Decision
## §1) -- a rendering input, NEVER read by any occupancy/logic query
## anywhere (Control Manifest Core/Feature Layer Forbidden: "`_visual_
## position` is never read outside the movement/rendering path").
## Recomputed every [method _process] frame from [member _from_cell]/
## [member _to_cell]/[member _intra_tick_progress] ONLY -- [method _process]
## never touches [member current_cell] and never integrates the engine's
## own raw per-frame delta.
var _visual_position: Vector3 = Vector3.ZERO

## Tick-owned progress through the CURRENT travel step, `[0.0, 1.0]`
## (ADR-0009 Decision §1 Key Interfaces naming -- despite the name, this is
## progress through the STEP, not a tick period; a step may take zero, one,
## or several ticks to complete, GDD F1). Advanced EXCLUSIVELY via
## [method advance_travel_progress], using [TimeTickSystem]'s `game_delta`
## -- never the engine's raw per-frame delta (Control Manifest Core Layer:
## "`_intra_tick_progress` advances via `game_delta` ticks only -- frozen
## during pause, no glide"). Calling [method advance_travel_progress] every
## frame with a live `game_delta` is story 009's Traveling-state-machine
## wiring responsibility (Out of Scope here) -- this story supplies only
## the pure, directly-testable advance function itself (this story's
## AC20/[TR-villager-ai-behavior-093]: "drivable directly with injected
## `game_delta` values, no real engine frames").
var _intra_tick_progress: float = 0.0


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config], [member voxel_world], and a
## [member time_tick_system]-shaped dependency are all wired, applies
## ADR-0002's clamp+warn `validate()` policy, then connects this module's
## tick dispatch to the SOLE global tick broadcast (`TimeTickSystem.tick`,
## per that Autoload's own doc comment) -- never a per-villager `Timer` or
## raw-delta poll. Also explicitly sets `physics_interpolation_mode = OFF`
## on this node (Story villager-ai-004, ADR-0009 Engine Notes/Risks:
## defends against a project-wide physics-interpolation setting ever being
## flipped elsewhere and stacking with this class's own hand-rolled
## [member _visual_position] lerp, double-interpolation jitter) -- applied
## here since this class IS the villager's own node; a later
## presentation-layer story's dedicated visual child, if one is ever added,
## must carry this forward too.
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
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the current agent state (read-only observability/test seam).
func get_state() -> State:
	return _state


## Public occupancy query (ADR-0009 Decision §1 Key Interfaces
## `get_current_cell(villager_id)` -- this codebase's actual architecture is
## one [VillagerAi] instance PER villager, established stories 001-003 and
## mirrored by [method get_state]'s own no-id signature, so no `villager_id`
## parameter exists here; a hypothetical multi-villager manager class is not
## this project's shape). ALWAYS returns the discrete [member current_cell]
## -- never [member _to_cell], never a value derived from
## [member _visual_position] or [member _intra_tick_progress] (this story's
## AC: "returns from_cell for a mid-transit villager... never an
## interpolation-derived value"). Because [member current_cell] only ever
## changes via [method _on_tick]'s atomic arrival-crediting assignment, a
## mid-transit call (any [member _intra_tick_progress] strictly between
## `0.0` and `1.0`, and even exactly `1.0` before the next tick boundary
## runs) always still returns [member _from_cell]'s value here, by
## construction -- no branching logic needed in this function itself.
func get_current_cell() -> Vector3i:
	return current_cell


## Cosmetic-only visual-position recompute (ADR-0009 Decision §1 Key
## Interfaces, Control Manifest Core Layer Required Pattern: "Visual lerp...
## each frame"). This is [VillagerAi]'s ONE deliberate, narrowly-scoped
## exception to story villager-ai-001's "no raw-delta hook" structural
## guarantee -- [param _delta] (the engine's own per-frame value) is named
## with its conventional unused-parameter underscore prefix and is NEVER
## read: this function recomputes [member _visual_position] from
## [member _from_cell]/[member _to_cell]/[member _intra_tick_progress] ONLY,
## using [method VoxelWorldGrid.cell_to_world] for the single source of
## truth on cell<->world conversion (never a second, locally-duplicated
## formula). It never touches [member current_cell], never advances
## [member _intra_tick_progress] itself (that is [method
## advance_travel_progress]'s job, called elsewhere with [TimeTickSystem]'s
## `game_delta` -- story 009's wiring), and never mutates FSM state --
## [method _tick_state]'s tick-signal-only dispatch is completely unaffected
## by this function's existence. When paused, [member _intra_tick_progress]
## simply never changes between calls (nothing advances it), so this
## recompute keeps yielding the identical [member _visual_position] every
## frame -- villagers do NOT glide while paused (this story's AC21), with no
## pause-aware branch needed here.
func _process(_delta: float) -> void:
	_visual_position = VoxelWorldGrid.cell_to_world(_from_cell).lerp(
		VoxelWorldGrid.cell_to_world(_to_cell), _intra_tick_progress
	)


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


## Pure movement-update function (Story villager-ai-004 AC20,
## [TR-villager-ai-behavior-093]): advances [member _intra_tick_progress] by
## `(config.move_speed * game_delta) / step_length_cells`, clamped to
## `[0.0, 1.0]` -- never overshoots past arrival even if [param game_delta]
## is unusually large (a stall, or several skipped frames). [param
## game_delta] is injected directly by the caller ([TimeTickSystem]'s own
## `get_game_delta()` in production, story 009's wiring) -- this function
## itself has ZERO dependency on [TimeTickSystem] or any engine callback,
## which is exactly what lets a test drive it with hand-picked
## [param game_delta] samples, "no real engine frames" (this story's AC20
## wording). Touches [member _intra_tick_progress] ONLY -- never
## [member current_cell] (the tick-boundary-only mutation discipline this
## story's AC13 depends on: reaching `1.0` progress here does NOT itself
## credit arrival; only [method _on_tick] does that, separately).
##
## Step length follows GDD F1's classification -- orthogonal = `1.0`,
## diagonal = `1.4` -- derived from [member _from_cell]/[member _to_cell]
## via [method _current_step_length_cells]; a zero-length step (the
## `from == to` case F1 documents as "target is the current/adjacent cell...
## immediate arrival") snaps progress straight to `1.0` with no division.
func advance_travel_progress(game_delta: float) -> void:
	assert(config != null, "VillagerAi.config not wired")
	var step_length: float = _current_step_length_cells()
	if step_length <= 0.0:
		_intra_tick_progress = 1.0
		return
	var progress_delta: float = (config.move_speed * game_delta) / step_length
	_intra_tick_progress = clampf(_intra_tick_progress + progress_delta, 0.0, 1.0)


## GDD F1's step-length classification for the CURRENT travel step
## ([member _from_cell] -> [member _to_cell]): orthogonal steps (differing
## on at most one horizontal axis) are `1.0`; a true diagonal (differing on
## BOTH the X and Z axes -- the same diagonal test [method is_step_legal]
## already uses, reused here rather than re-derived) is `1.4`. Height
## difference (Y) never affects step length, per F1. Returns `0.0` when
## [member _from_cell] equals [member _to_cell] -- F1's documented
## zero-length/immediate-arrival case.
func _current_step_length_cells() -> float:
	if _from_cell == _to_cell:
		return 0.0
	var dx: int = _to_cell.x - _from_cell.x
	var dz: int = _to_cell.z - _from_cell.z
	return 1.4 if (dx != 0 and dz != 0) else 1.0


## Tick-boundary arrival predicate (ADR-0009 Decision §1 Key Interfaces
## `_travel_complete()`): true once [member _intra_tick_progress] has
## reached `1.0` -- the CURRENT travel step's target has been reached.
## Reports only on the current step; it says nothing about whether the
## villager has reached its ultimate destination, should transition out of
## Traveling, or should release a job claim -- those remain story 009/other
## stories' concerns entirely.
func _travel_complete() -> bool:
	return _intra_tick_progress >= 1.0


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
## advances this agent's state machine (ADR-0008 Decision §2). Also performs
## tick-boundary travel-arrival crediting (ADR-0009 Decision §1 Key
## Interfaces `_on_tick()`; GDD F1 [TR-villager-ai-behavior-029]'s
## tick-boundary-only crediting, extended to occupancy by that ADR): the
## atomic `current_cell = _to_cell` assignment is one of the exactly two
## sanctioned points [member current_cell] is ever mutated (the other is a
## future watchdog rescue, story 015). Idempotent once credited --
## [member current_cell] already equals [member _to_cell], a harmless no-op
## -- until a NEW travel step's [member _from_cell]/[member _to_cell] begin
## (story 009). Delegates the FSM dispatch itself to [method _tick_state];
## kept as a separate method (rather than connecting [method _tick_state]
## directly) so a later story's Deciding-pass staggering budget (ADR-0008's
## `max_deciding_per_tick` FIFO queue, story 005) has an obvious, single seam
## to insert into without touching the signal-wiring line in [method setup].
func _on_tick() -> void:
	if _travel_complete():
		current_cell = _to_cell
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
