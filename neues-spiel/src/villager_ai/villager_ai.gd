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
##
## Story villager-ai-005 (this revision) lands ADR-0008's Deciding-pass
## staggering: a per-tick budget (`max_deciding_per_tick`) plus a
## stable-order FIFO queue, so a mass-Deciding event cannot let every
## eligible villager run an expensive F2 selection pass in the same tick.
## Because stories 001-004 already fixed this codebase's shape as ONE
## [VillagerAi] instance PER villager (no manager coordinating them --
## [method get_current_cell]'s own doc comment), the cross-villager
## queue+budget bookkeeping ADR-0008 describes is factored into a separate,
## dependency-free collaborator, [VillagerDecidingScheduler] (see its own
## class doc comment for the full architecture rationale), rather than being
## duplicated onto every instance's own tick handler -- which would have let
## an N-villager population drain up to N queue entries per GLOBAL tick
## instead of `max_deciding_per_tick`. [member scheduler] is an
## explicitly-injected shared dependency (like [member voxel_world]/
## [member time_tick_system], NOT a static/class-level singleton -- that
## would be hidden shared state surviving across independent test runs).
## [method request_deciding_pass] is the ONE generic eligibility-enqueue
## entry point every trigger source calls (this story wires the initial
## Deciding-eligible-at-boot case and the periodic `decision_interval`
## re-check via [method _check_decision_interval_trigger]; future stories --
## need-urgent, job-complete -- call the SAME method from their own trigger
## points, no second enqueue path is ever introduced). [method _tick_state]'s
## `State.DECIDING` branch now gates the (still-stub) [method _tick_deciding]
## call behind [method VillagerDecidingScheduler.is_runnable_this_tick] --
## the actual priority-list logic inside a Deciding pass remains story 006's
## scope, untouched here.
##
## Story villager-ai-006 (this revision) implements that priority-list logic
## (GDD Rule 2, ADR-0008 Decision §1's "strict, discrete priority order
## (Urgent need > Work > Idle/Wander)"): [method _tick_deciding] is no longer
## a stub. Two duck-typed, nil-safe, mocked-boundary dependencies --
## [member needs_provider] (tier 1) and [member job_queue] (tier 2) -- mirror
## [member time_tick_system]'s pattern exactly, since neither the Needs &
## Mood System nor the Building System's real job queue exist anywhere in
## this codebase yet (both are named MOCKED boundaries in this story's own
## Engine Notes/Implementation Notes). [enum PursuedActivity] and
## [member _pursued_activity] track WHICH tier a villager is currently
## committed to, independent of [member _state] -- the thing claim-stickiness
## (AC41/[TR-villager-ai-behavior-052]) and Edge Case 3b's same-need no-op
## actually key off, since [member _state] alone changes again once Stories
## 009/012/018 add real Traveling->Working/Sleeping sub-transitions while
## still pursuing the SAME committed tier. [method _on_tick]'s new
## `was_deciding` guard is what lets a villager already mid-activity
## (Working, Wandering, ...) get preempted by this same priority check on a
## periodic `decision_interval` re-check WITHOUT double-invoking
## [method _tick_deciding] for a villager that started the tick already in
## `State.DECIDING` ([method _tick_state]'s own pre-existing gate, story 005,
## already handles that case) -- see that method's own doc comment for the
## full ordering rationale (GDD Rule 3's graceful preemption: the CURRENT
## tick's activity body always runs first, only then does a runnable
## Deciding pass reassign [member _state]).
##
## Story villager-ai-007 (this revision) does NOT add an AStar3D member to
## this class, despite ADR-0007's Key Interfaces snippet showing an
## `_astar: AStar3D` field inline in its pseudocode. That ADR's own
## Performance Implications section is explicit that memory holds "ONE
## AStar3D instance" for the whole settlement-core region -- one per
## [VillagerAi] instance (this codebase's established one-instance-per-
## villager shape, see [method get_current_cell]'s own doc comment) would
## duplicate tens of thousands of points N times over, for a population of up
## to 30. This story instead adds [VillagerNavGraph] as a separate shared
## collaborator class -- the SAME "separate shared object, not a per-instance
## member" architecture [VillagerDecidingScheduler] already established for
## the identical reason (see that class's own doc comment). [VillagerNavGraph]
## reuses this class's own [method is_standable]/[method is_step_legal] as
## its predicate source (ADR-0007 Decision Section 1's "every consumer calls
## these same two functions"); this story's only other change here is
## extracting [method classify_step_length_cells] as a reusable static twin
## of [method _current_step_length_cells] (see that method's own doc
## comment). Wiring a shared [VillagerNavGraph] instance into this class's
## own Traveling state is story 009's scope, untouched here.
##
## Story villager-ai-008 (this revision) implements GDD Rule 10b's re-path
## FILTER ([TR-villager-ai-behavior-012]/036): [method setup] connects this
## villager directly to [member voxel_world]'s [signal
## VoxelWorldGrid.cell_changed]/[signal VoxelWorldGrid.cells_changed_batch]
## (Godot's default, synchronous, NEVER `CONNECT_DEFERRED` flags -- the same
## race-closure reliance [VillagerNavGraph]'s own story-008 subscription
## documents). [method evaluate_repath_trigger] is the filter itself,
## delegating the actual clearance-envelope-intersection decision to the
## stateless [VillagerRepathFilter] library; [method
## get_remaining_movement_cells] supplies "the remaining movement's cells"
## for THIS story's scope as exactly the current single travel step
## ([member _from_cell], [member _to_cell]) -- the only movement this class
## tracks today (a full multi-cell remaining-PATH is story 009's Traveling
## state-machine addition; this story's filter is written generically enough
## that a future richer path representation only needs to widen [method
## get_remaining_movement_cells]'s return, not [VillagerRepathFilter] itself
## or [method evaluate_repath_trigger]'s call site). [method is_moving]
## reports "moving" purely from the discrete `_from_cell != _to_cell`
## comparison -- deliberately NOT keyed to [member _state] naming Traveling/
## Wandering/Breather explicitly, so the SAME check already covers every one
## of the GDD's 4 named moving cases (Traveling, a Wandering step, a
## Breather step-away, or a future F4 vacate step) without this class ever
## needing to enumerate them. A stationary villager (Deciding/Working/
## Sleeping, or a Breather not yet stepping -- `_from_cell == _to_cell`,
## true from construction and after every arrival-crediting [method
## _on_tick] assignment) always reports not-moving, so [signal
## repath_evaluation_requested] can never fire for it -- matching the rule's
## own "for any MOVING villager" scope. This story implements the FILTER
## decision only -- the actual re-path/redirect story 009 wires to this
## signal is explicitly out of this story's scope.
##
## Story villager-ai-009 (this revision) implements the Traveling state
## machine itself (GDD "States and Transitions": "Follows the computed path
## cell-by-cell; re-paths if a Voxel World write blocks the path"). [method
## start_traveling] is the generic entry point a future story's own
## target-selection logic calls (Story 010's F2 job site, Story 018's bed
## cell) -- it acquires a path from [member nav_graph] (a new shared
## [VillagerNavGraph] dependency, mirroring [member scheduler]'s own
## "population-wide, non-`@export`, not setup()-asserted" precedent exactly
## -- earlier stories' tests never wire it and this story does not widen
## [method setup]'s boot-gate assertion retroactively) from
## [member current_cell] toward a caller-supplied `target_cell`, storing the
## FULL REMAINING path ([member _travel_remaining_path]), not merely the
## current single step -- exactly the widening this story's own predecessor
## doc comment (above) already reserved: [method get_remaining_movement_cells]
## now returns the whole upcoming route, so [VillagerRepathFilter]'s
## clearance envelope (unchanged, zero lines touched) now also covers writes
## further down the path, not only the in-flight step.
##
## [method _tick_traveling] performs the tick-boundary-only step advance
## ("request next step at tick boundaries") -- called from [method
## _tick_state] AFTER [method _on_tick]'s own arrival-crediting assignment
## already ran this tick, so [member current_cell] already reflects a
## just-completed step by the time it runs: it pops the just-arrived cell
## off [member _travel_remaining_path] and either begins the next step or
## completes arrival ([method _complete_travel_arrival], transitioning to
## the caller-supplied `arrival_state` -- Working/Sleeping/etc, real
## per-state behaviour still owned by stories 012/018).
##
## [signal repath_evaluation_requested] (story 008's own FILTER signal) is
## now consumed INTERNALLY, connected in [method setup] with default
## synchronous flags: [method _on_repath_evaluation_requested] recomputes a
## path from [member current_cell] toward the SAME [member
## _travel_target_cell] -- the actual REDIRECT this story's race-closure AC
## requires, landing in the SAME synchronous call stack as the write that
## triggered it, before the next [method _process] frame could ever advance
## [member _visual_position] further toward now-solid geometry. An empty
## recompute result (no viable detour) fires [method _abandon_travel] (this
## story's AC19 -- "exits to Deciding and re-selects... never keeps
## traveling toward a dead target"), dispatched by [member _pursued_activity]
## per GDD Edge Case 1's per-target fallback: `WORK` releases the held claim
## via the already-existing [method _release_job_claim]; `NEED`'s
## ground-sleep fallback and `NONE`'s wander-reselection are Story 018/019's
## own scope (neither system exists in this codebase yet) -- this story's
## safe default for both is simply "abandon and re-decide."
##
## **Wiring-order requirement** (load-bearing, not incidental): whoever
## assembles a population must call [method
## VillagerNavGraph.subscribe_to_voxel_world] BEFORE this villager's own
## [method setup] -- Godot fires synchronous signal connections in
## CONNECTION order (Control Manifest Global Rules), so the shared graph
## must patch a blocking write before this villager's own repath recompute
## reads it, or the recompute would run against a stale graph that still
## thinks the just-blocked cell is standable.
##
## [method _process] now ALSO drives [member _intra_tick_progress] forward
## every frame -- story villager-ai-004's own explicitly-deferred wiring
## ("calling advance_travel_progress every frame with a live game_delta is
## story 009's... responsibility") -- by querying [member time_tick_system]'s
## OWN `get_game_delta()` (a value that system already computed this frame;
## never this function's own raw `_delta` parameter, still unread) whenever
## [method is_moving] is true. Guarded by `time_tick_system != null` so
## every earlier story's own position-model unit tests (which call [method
## _process] directly without ever wiring [member time_tick_system]) keep
## passing unchanged.
##
## Story villager-ai-012 (this revision) implements [method _tick_working]
## itself -- the CLOSED job loop (GDD Rule 5/[TR-villager-ai-behavior-054],
## Edge Case 4/[TR-villager-ai-behavior-083]): "work progress accrues only
## while on site," and "a job revoked mid-work stops at the tick boundary,
## no failure reaction, re-enters Deciding." This class owns NO
## progress-crediting mechanism of its own -- that stays [ConstructionTickLoop]'s
## job, per its own doc comment -- the on-site GATE on that crediting is
## wired for real, against actual villager positions, by the new
## [VillagerOnSiteGate] collaborator (composing Rule 5's on-site predicate
## with Building System Edge Case 6/AC40b's occupied-cell defer behind the
## SAME `set_occupancy_predicate` seam both landed classes already reserved
## for this exact story). [method _tick_working] itself is purely
## OBSERVATIONAL: it reads [member _claimed_blueprint_cell]'s CURRENT
## [member BlueprintCell.state] -- the SAME shared reference
## [ConstructionTickLoop] mutates directly -- to detect completion (BUILT,
## AC40) or revocation (anything but UNDER_CONSTRUCTION/BUILT, AC33) without
## a second query back into [member job_queue]. [member
## _claimed_blueprint_cell] is set the moment a claim succeeds ([method
## _attempt_claim_and_travel_to_job], BEFORE travel even starts -- the
## on-site gate must already exist for the full travel period too, since
## [method ConstructionTickLoop.claim_job] flips a cell to
## UNDER_CONSTRUCTION immediately at claim time) and cleared by [method
## _release_job_claim] (the ONE existing helper every claim-relinquishing
## path -- need-preemption, pathing failure, and this story's own
## completion/revocation handling -- already funnels through, so it never
## goes stale).
##
## Story villager-ai-015 (this revision) implements the Unstuck Watchdog's
## TRIGGER, rescue teleport, and F3 telemetry (GDD Rule 15/15b/F5,
## [TR-villager-ai-behavior-099]/[TR-villager-ai-behavior-104]/
## [TR-villager-ai-behavior-080], ADR-0009 slice propagation's "second
## sanctioned discrete `current_cell` mutation"). [method
## _update_unstuck_watchdog] runs every tick (called from [method _on_tick]
## right after arrival-crediting, before [method _tick_state] dispatches) and
## implements GDD F5's `stuck_tick_count` formula via [method
## _is_stuck_at_current_cell] -- itself delegating to the ALREADY-shared
## [method is_standable]/[method is_step_legal] predicates plus
## [VillagerNavGraph]'s own established [constant
## VillagerNavGraph.HORIZONTAL_FULL_OFFSETS]/[constant
## VillagerNavGraph.VERTICAL_STEP_OFFSETS] neighbor-candidate constants
## (Story villager-ai-008's patch-pass reuses the identical pair -- this
## story does not invent a second, locally-derived neighbor set). Scoped
## STRICTLY to `State.TRAVELING`/`State.WORKING` -- every other state
## ([member _distressed] is still updated for observability, this story's
## AC32/Edge Case 2 complement) never accumulates [member stuck_tick_count]
## and is never rescued.
##
## On reaching [member VillagerAIConfig.unstuck_watchdog_threshold_ticks],
## [method _attempt_watchdog_rescue] calls the F5 BFS
## ([VillagerRescueTargetSearch.find_rescue_target], Story villager-ai-014) --
## a miss (search exhausted at `unstuck_rescue_max_radius`) reports through
## [member _search_failure_gate] (a per-villager [RescueSearchFailureGate]
## instance, Story villager-ai-014's own once-per-episode gate primitive;
## THIS story owns calling it and firing the actual [signal
## unstuck_search_failed]) and defers to the next tick, retrying every tick
## thereafter (GDD Edge Case 14) since [member stuck_tick_count] keeps
## incrementing past the threshold with nothing to reset it. A hit performs
## the rescue itself ([method _perform_watchdog_rescue]): releases any held
## job claim via the SAME [method _release_job_claim] helper every other
## claim-relinquishing path already funnels through (AC52 -- "no
## double-release, no orphaned claim"; a `NEED`-pursuing villager, e.g.
## traveling to a bed, holds no claim, so this is a no-op with zero bed-
## ownership side effect, exactly AC52's second half), sets [member
## current_cell] atomically AND snaps [member _visual_position] to match (NO
## lerp -- ADR-0009's "the watchdog is the one deliberate exception" to
## "never snap/teleport"), resets [member stuck_tick_count] to `0` and
## [member _search_failure_gate] for a fresh future episode, increments both
## [member _unstuck_count] (this villager's own F3 counter) and the shared
## [member unstuck_telemetry]'s world total (Story villager-ai-015's own new
## shared, population-wide, non-`@export`, nil-safe collaborator --
## [VillagerUnstuckTelemetry] -- mirrors [member scheduler]/[member
## nav_graph]'s own "one shared instance, not a duplicated-per-villager
## copy" precedent), emits [signal unstuck_rescued], transitions to
## `State.DECIDING`, and re-enters the Deciding queue via the SAME [method
## request_deciding_pass] -> [VillagerDecidingScheduler.enqueue] path every
## OTHER Deciding-eligibility trigger uses -- deliberately NOT a bonus
## immediate decide bypassing [member scheduler]'s budget (this story's own
## QA-defined "no double-decide" assertion): because [member scheduler]'s own
## per-tick budget drain ([method VillagerDecidingScheduler.advance_tick],
## wired via [method connect_to_tick_source] during [method setup]) always
## fires BEFORE any villager's own [signal TimeTickSystem.tick] handler in
## the SAME global tick (connection order, story villager-ai-005's own
## established ordering), a rescue's own [method request_deciding_pass] call
## can only ever land a villager in the FIFO queue for a tick whose budget
## was already computed -- it is never granted an extra, unbudgeted slot the
## same tick it fires, and [method VillagerDecidingScheduler.enqueue]'s own
## idempotency guard means a villager already queued at rescue time (e.g.
## from an earlier `decision_interval` trigger) is never double-enqueued.
##
## [member population] is a new duck-typed, nil-safe, mocked-boundary
## dependency (mirrors [member needs_provider]/[member job_queue]'s own
## established precedent exactly -- a real population registry is a future
## spawner story's job, same as those two systems) exposing exactly one
## member, `func get_other_villager_cells(villager_id: int) ->
## Array[Vector3i]`, supplying [VillagerRescueTargetSearch.find_rescue_target]'s
## own `other_villager_cells` parameter (that function's own doc comment:
## "the watchdog's responsibility to assemble... never queries a
## population/registry itself").
class_name VillagerAi
extends Node

## Fires when [method evaluate_repath_trigger] determines a Voxel World
## write's changed cell(s) intersect this (currently moving) villager's
## remaining-movement clearance envelope (GDD Rule 10b, this story's AC18).
## Carries no arguments -- WHICH write and WHAT to do about it are story
## 009's concern; this story's own contract is purely "did the filter fire,
## and exactly how many times" (AC18/AC49's call-count assertions).
signal repath_evaluation_requested()

## Fires when the Unstuck Watchdog rescues this villager (Story
## villager-ai-015, GDD Rule 15/F5, AC51) -- carries the chosen rescue cell
## for observability/telemetry consumers (e.g. a future F3 debug overlay).
## Fired AFTER every rescue side effect below has already been applied
## ([member current_cell]/[member _visual_position] snapped, claim released,
## [member _state] transitioned to `State.DECIDING`) -- a listener never
## observes a half-applied rescue.
signal unstuck_rescued(rescue_cell: Vector3i)

## Fires when the watchdog's rescue search is exhausted at
## `unstuck_rescue_max_radius` with no eligible cell found (GDD Edge Case 14,
## AC53) -- gated by [member _search_failure_gate] to fire exactly once per
## stuck episode, never once per tick (the search itself keeps retrying every
## tick, per that Edge Case's own wording).
signal unstuck_search_failed()

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

## Which GDD Rule 2 priority-list tier this villager is currently COMMITTED
## to pursuing (Story villager-ai-006) -- independent of [member _state],
## and the value [method _tick_deciding]'s claim-stickiness (AC41) and Edge
## Case 3b's same-need no-op actually key off of. [member _state] alone
## moves TRAVELING -> WORKING (Story 012) or TRAVELING -> SLEEPING (Story
## 018) while still pursuing the SAME tier the whole time, so this value is
## what stays constant across that sub-transition.
enum PursuedActivity {
	NONE,  ## Pursuing neither a need nor a job (Wandering/idle, Rule 2 tier 3).
	NEED,  ## Committed to satisfying the current urgent need (tier 1).
	WORK,  ## Committed to (holding a claim on) a construction job (tier 2).
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
## registration of its own. Duck-typed against two members this class
## depends on: `signal tick()` and, since story villager-ai-009,
## `func get_game_delta() -> float` ([method _process]'s live
## travel-progress wiring).
var time_tick_system: Object = null

## Deciding-pass scheduler dependency (Story villager-ai-005, ADR-0008
## Decision §2) -- the ONE shared, cross-villager FIFO-queue-and-budget
## collaborator every [VillagerAi] instance in the same population must
## point at the SAME object. Unlike [member config]/[member voxel_world]
## (typed `@export` Resource/Node references), [VillagerDecidingScheduler] is
## a plain [RefCounted] with no Inspector-editable representation --
## deliberately NOT `@export`ed, mirroring [member time_tick_system]'s own
## duck-typed, code-assigned precedent. Assigned directly by whichever code
## assembles the villager population (a headless test, or a future spawner
## story) BEFORE calling [method setup] -- asserted non-null there, exactly
## like [member config]/[member voxel_world]. This is NOT a manager: see
## [VillagerDecidingScheduler]'s own class doc comment for why sharing this
## one object across instances does not reintroduce a manager architecture.
var scheduler: VillagerDecidingScheduler = null

## Needs & Mood dependency (Story villager-ai-006, mocked boundary -- this
## story's own Engine Notes: "Needs & Mood values are mocked at the
## need-is-urgent boundary"). The Needs & Mood System is an MVP-sibling GDD
## not yet implemented anywhere in this codebase; its own future epic owns
## real production wiring. Duck-typed like [member time_tick_system] --
## exposes exactly one member this class depends on:
## `func has_urgent_need(villager_id: int) -> bool`. Deliberately nil-safe
## (see [method _has_urgent_need]) rather than asserted in [method setup]:
## a not-yet-wired villager always reads "no urgent need," never crashes --
## unlike [member time_tick_system], this dependency has no boot-gate this
## story enforces.
var needs_provider: Object = null

## Building System construction-job-queue dependency (Story villager-ai-006,
## mocked boundary -- Story 010 owns real F2 nearest-reachable selection,
## Story 011 owns real atomic claim/attribution; this story needs only the
## "available construction job" boolean gate the GDD Implementation Notes
## assign priority-list tier 2: "available construction job (queue
## non-empty)"). Duck-typed, nil-safe default (see [method
## _has_available_job]/[method _release_job_claim]) -- exposes exactly two
## members: `func has_available_job() -> bool` and
## `func release_claim(villager_id: int) -> void` (called only on graceful
## preemption, GDD Rule 3/[TR-villager-ai-behavior-050] -- never when
## nothing was actually claimed). This story models "holds a claim" purely
## as [member _pursued_activity] == `PursuedActivity.WORK`; Story 011
## introduces the real claim record this stands in for.
var job_queue: Object = null

## Story villager-ai-016 (this revision) adds the Seal Prevention trap
## predicate (GDD Rule 16/F6, ADR-0009 slice propagation Sec.2b): [method
## would_trap_builder] answers "would completing a write at this cell leave
## THIS villager with zero legal steps," evaluated as if the write had
## already committed, WITHOUT ever mutating [member voxel_world] (a real
## trial write would fire real signals for a change that might never
## commit). This class has no awareness of the Building System's write
## path, abandon-count bookkeeping, or the dig/demolition exemption at all --
## those live entirely in the new [VillagerSealPreventionGate] collaborator
## (mirrors [VillagerOnSiteGate]'s own "separate shared collaborator wired
## behind [ConstructionTickLoop]'s own predicate seam" architecture exactly),
## which calls this method once per registered villager per completing cell.

## Population dependency (Story villager-ai-015, mocked boundary -- see this
## class's own doc comment's villager-ai-015 paragraph). Duck-typed, nil-safe
## default (see [method _get_other_villager_cells]) -- exposes exactly one
## member: `func get_other_villager_cells(villager_id: int) ->
## Array[Vector3i]`, the caller-supplied occupancy snapshot
## [VillagerRescueTargetSearch.find_rescue_target] needs to reject an
## already-occupied rescue candidate. A villager with this left `null` (no
## population registry wired) simply searches as though no other villager
## exists -- a safe, conservative default, never a crash.
var population: Object = null

## Shared unstuck-rescue telemetry dependency (Story villager-ai-015, GDD
## Rule 15/F5's "a per-villager counter and a world total counter"). Unlike
## [member needs_provider]/[member job_queue] (mocked boundaries standing in
## for a NOT-YET-BUILT external system), [VillagerUnstuckTelemetry] is a
## small, fully-owned-by-this-story concrete class (see its own doc comment)
## -- a REAL shared, population-wide, non-`@export` [RefCounted] collaborator,
## mirroring [member scheduler]/[member nav_graph]'s own "one instance shared
## across the whole population" precedent (never one telemetry object per
## villager -- the world-total half of its job requires a single shared
## accumulator). Deliberately nil-safe rather than [method setup]-asserted
## (mirrors [member nav_graph]'s own "not every earlier story's test wires
## this" precedent): a villager with this left `null` still rescues/resets/
## re-decides correctly, it simply records no telemetry anywhere -- see
## [method _perform_watchdog_rescue].
var unstuck_telemetry: VillagerUnstuckTelemetry = null

## Shared travel-pathfinding graph dependency (Story villager-ai-009,
## ADR-0007 Decision Section 2) -- the SAME single, population-wide
## [VillagerNavGraph] instance that class's own doc comment establishes (one
## instance for the whole population, never one per villager). Deliberately
## a plain, non-`@export`ed [RefCounted] reference -- mirrors [member
## scheduler]'s own precedent exactly (no Inspector-authoring need, a
## shared-not-duplicated architecture). Assigned by whichever code
## assembles the villager population BEFORE [method start_traveling] is
## ever called -- asserted THERE (and in [method
## _recompute_path_from_current_cell]), deliberately NOT inside [method
## setup] (unlike [member config]/[member voxel_world]/[member scheduler]):
## every earlier story's own test already calls [method setup] without ever
## wiring this new dependency, and this story does not widen that boot-gate
## assertion retroactively -- mirrors [member needs_provider]/
## [member job_queue]'s own "nil-safe, not setup()-asserted" precedent
## (Story villager-ai-006's doc comment) exactly.
##
## **Wiring-order requirement** (load-bearing, not incidental): see this
## class's own doc comment's "Wiring-order requirement" paragraph -- the
## population assembler must call [method
## VillagerNavGraph.subscribe_to_voxel_world] on this SAME instance BEFORE
## this villager's own [method setup] runs.
var nav_graph: VillagerNavGraph = null

## This villager's stable identity/processing-order index (GDD Edge Case 3 /
## F2 tie-break convention: "stable villager processing order (villager
## index)"). Explicitly assigned by whichever code assembles the population
## (0, 1, 2... in creation order) -- deliberately NOT a static
## auto-incrementing counter on this class (hidden shared state would
## survive across independent GdUnit4 test runs in the same process,
## violating this codebase's test-isolation discipline); the wirer already
## controls creation order and is in the best position to assign this
## explicitly and deterministically. Used as the FIFO key [member scheduler]
## orders its queue by (this story's stable-order AC) and, in a future
## story, the value a job claim's worker-attribution record carries
## (Story 011, [TR-villager-ai-behavior-097]).
@export var villager_id: int = 0

## Current agent state (GDD "States and Transitions": Deciding is every
## agent's loop-start entry). Read-only from outside this class -- see
## [method get_state].
var _state: State = State.DECIDING

## See [enum PursuedActivity] (Story villager-ai-006). Starts at `NONE` -- a
## fresh villager pursues nothing until its first Deciding pass runs.
var _pursued_activity: PursuedActivity = PursuedActivity.NONE

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## Ticks elapsed since this villager's last Deciding-pass ELIGIBILITY
## trigger fired (not since a pass actually RAN -- those can differ once
## [member scheduler]'s budget queues a villager for a later tick). Drives
## the GDD Rule 2 periodic re-check ("`decision_interval` ticks so an urgent
## need can preempt long work"): this story implements the trigger itself
## ([method _check_decision_interval_trigger] calling [method
## request_deciding_pass] on cadence) -- the actual preemption/priority-list
## BEHAVIOUR once a pass runs is story 006's scope, untouched here.
var _ticks_since_last_decision: int = 0

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

## The villager's ultimate Traveling destination (Story villager-ai-009) --
## distinct from [member _to_cell] (the CURRENT single step's destination
## only). A mid-travel recompute ([method _recompute_path_from_current_cell])
## always paths TOWARD this same value; it never changes mid-travel itself
## (a target change mid-travel would be a preemption/abandon, not a
## redirect -- out of this story's scope). Meaningless while not actually
## traveling -- no sentinel is defined for "no target," since [member
## _travel_remaining_path] being empty is the authoritative "not traveling"
## signal this class already checks everywhere.
var _travel_target_cell: Vector3i = Vector3i.ZERO

## Which [enum State] this villager transitions into on arrival at
## [member _travel_target_cell] (Story villager-ai-009's AC: "arrival on
## site transitions to the next state (Working/Sleeping/etc.)") -- supplied
## by [method start_traveling]'s caller (future stories 010's job-site
## target / 018's bed target), never decided by this class itself.
var _travel_arrival_state: State = State.DECIDING

## The full remaining AStar3D path (Story villager-ai-009), EXCLUDING the
## cell the villager currently occupies -- `_travel_remaining_path[0]` is
## always kept equal to [member _to_cell] (the in-flight step's
## destination); later entries are cells not yet stepped onto. Empty
## whenever not traveling (mirrors [member _from_cell] == [member _to_cell]
## as the "stationary" signal). Widens [method get_remaining_movement_cells]
## per story villager-ai-008's own doc comment reservation -- neither
## [VillagerRepathFilter] nor [method evaluate_repath_trigger]'s call site
## needed a single line changed by this story.
var _travel_remaining_path: Array[Vector3i] = []

## Monotonic per-villager tick counter (Story villager-ai-011) -- incremented
## once per [method _on_tick] call, never reset (unlike [member
## _ticks_since_last_decision]). The sole clock [member
## _unreachable_retry_after_tick]'s cooldown windows are measured against --
## this villager's own local notion of "how many ticks have I processed,"
## independent of [TimeTickSystem]'s own global tick count (this class only
## ever observes that indirectly, via the `tick` signal itself).
var _tick_count: int = 0

## This villager's OWN per-cell retry-cooldown memory (Story villager-ai-011,
## GDD Rule 6/AC10, [TR-villager-ai-behavior-055]): cell -> the
## [member _tick_count] value at or after which this villager may
## true-path-check that cell again via F2 selection. Populated by [method
## _abandon_travel]'s WORK branch whenever [method start_traveling] (or a
## mid-travel redirect) fails to find a path to a job this villager had just
## claimed (Rule 6's "pathing to a job fails" case) -- NOT populated by F2's
## own internal pre-claim reachability filter ([VillagerJobSelector.
## select_job] already silently skips an unreachable candidate without ever
## claiming or reporting it, so there is nothing to throttle there). A
## per-villager Dictionary, deliberately NOT shared/global -- Rule 6's
## "reports... to the Building System" already shares the ghost-tint fact
## globally via [signal ConstructionJobQueue.job_reported_unreachable]; this
## Dictionary is purely this villager's own retry-pacing memory, distinct
## from that shared visual state. [method _attempt_claim_and_travel_to_job]
## consults it via [method _is_job_cooling_down] to exclude a still-cooling
## cell from this pass's candidate set (AC10's suppress-before-the-window
## guarantee); once [member _tick_count] reaches the stored value, the SAME
## cell is eligible again on the very next Deciding pass (AC10's "a retry
## attempt occurs").
var _unreachable_retry_after_tick: Dictionary[Vector3i, int] = {}

## The [BlueprintCell] this villager currently holds a claim on while
## [member _pursued_activity] == [constant PursuedActivity.WORK] (Story
## villager-ai-012) -- the SAME shared reference [ConstructionTickLoop]
## itself mutates directly (that class's own doc comment: "visible through
## any other holder of the SAME RefCounted reference"), so [method
## _tick_working] can read the REAL, live construction-progress state
## without a second query back into [member job_queue]. `null` whenever no
## claim is held (every state but Working, and Working itself immediately
## after completion/abandonment clears it back to `null`). See this class's
## own doc comment's villager-ai-012 paragraph for the full set/clear
## lifecycle.
var _claimed_blueprint_cell: BlueprintCell = null

## GDD F5's own named variable (Story villager-ai-015) -- consecutive ticks
## [member _state] has been `TRAVELING`/`WORKING` with [method
## _is_stuck_at_current_cell] true. Public (not `_`-prefixed), matching
## [member current_cell]'s own "field named exactly like the GDD variable,
## still read via a getter by outside consumers" precedent -- see [method
## get_stuck_tick_count]. Reset to `0` the instant relief is available (a
## legal step or standable [member current_cell] becomes available again),
## on leaving `TRAVELING`/`WORKING` entirely, AND after a successful rescue
## (this story's own interpretation of "the instant relief is available":
## exiting the two rescuable states is itself relief, since the counter is
## meaningless outside them) -- see [method _update_unstuck_watchdog].
var stuck_tick_count: int = 0

## Edge Case 2's distress cue flag (Story villager-ai-015, AC32 -- the scope
## boundary complement this story also implements): `true` whenever [method
## _is_stuck_at_current_cell] is true, for EVERY state, not only
## `TRAVELING`/`WORKING` -- an Idle/Wandering/Sleeping/Breather villager with
## no legal step sets this and stays put, never rescued (only
## `TRAVELING`/`WORKING` ever drive [member stuck_tick_count] toward a
## rescue). The exact visual treatment is explicitly deferred to the art
## bible (GDD Open Question 6) -- this field is the data seam a future
## presentation-layer story reads, not a rendering call of its own.
var _distressed: bool = false

## This villager's own F5 rescue counter (Story villager-ai-015, GDD Rule 15:
## "incrementing a per-villager counter"). Read via [method
## get_unstuck_count] -- see [member unstuck_telemetry] for the companion
## world-total counter this class does not itself hold (a single villager
## has no way to sum every OTHER villager's own rescue count).
var _unstuck_count: int = 0

## This villager's own per-stuck-episode instance of Story villager-ai-014's
## [RescueSearchFailureGate] (that class's own doc comment: "one instance per
## villager... each villager's stuck episode is its own independent
## history" -- deliberately NOT shared population-wide, unlike [member
## scheduler]/[member nav_graph]/[member unstuck_telemetry]). Constructed
## once, up front, exactly like [member _travel_remaining_path]'s own
## literal-default precedent -- no injection, no [method setup] wiring, since
## it depends on nothing but itself.
var _search_failure_gate: RescueSearchFailureGate = RescueSearchFailureGate.new()


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
## must carry this forward too. Story villager-ai-005 additionally asserts
## [member scheduler] is wired, connects it to [member time_tick_system]'s
## own tick broadcast via [method VillagerDecidingScheduler.
## connect_to_tick_source] (idempotent -- safe even if every villager in a
## shared population calls this during their own `setup()`), and marks this
## villager Deciding-eligible for its very first pass via [method
## request_deciding_pass] (the default [member _state] is `DECIDING` from
## construction -- without this call a freshly-created villager would never
## enter [member scheduler]'s queue at all).
func setup() -> void:
	assert(config != null, "VillagerAi.config not wired")
	assert(voxel_world != null, "VillagerAi.voxel_world not wired")
	assert(scheduler != null, "VillagerAi.scheduler not wired")
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
	scheduler.connect_to_tick_source(time_tick_system, config)
	@warning_ignore("unsafe_property_access")
	time_tick_system.tick.connect(_on_tick)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Story villager-ai-008 (GDD Rule 10b, re-path filter): default,
	# synchronous connection flags -- NEVER CONNECT_DEFERRED. The whole
	# race-closure argument (ADR-0009) depends on this filter evaluation
	# landing in the SAME call stack as the write.
	voxel_world.cell_changed.connect(_on_voxel_world_cell_changed)
	voxel_world.cells_changed_batch.connect(_on_voxel_world_cells_changed_batch)
	# Story villager-ai-009: consumes story 008's own FILTER signal
	# internally -- default, synchronous connection flags (never
	# CONNECT_DEFERRED), same race-closure reliance as the two connections
	# directly above.
	repath_evaluation_requested.connect(_on_repath_evaluation_requested)
	request_deciding_pass()
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the current agent state (read-only observability/test seam).
func get_state() -> State:
	return _state


## Returns which GDD Rule 2 priority-list tier this villager is currently
## committed to (read-only observability/test seam, mirrors [method
## get_state]; Story villager-ai-006) -- Story villager-ai-009's Traveling
## state needs this to know WHY it is traveling (bed vs. job site) once it
## lands.
func get_pursued_activity() -> PursuedActivity:
	return _pursued_activity


## Read-only observability seam (Story villager-ai-012) -- the cell address
## of [member _claimed_blueprint_cell], or `null` if this villager holds no
## claim right now. [VillagerOnSiteGate] is the real consumer: it has no
## other way to learn WHICH registered villager is the assigned worker for
## an arbitrary cell it is asked to gate.
func get_claimed_job_cell() -> Variant:
	return null if _claimed_blueprint_cell == null else _claimed_blueprint_cell.cell


## Returns this villager's stable identity/processing-order index (see
## [member villager_id]'s own doc comment).
func get_villager_id() -> int:
	return villager_id


## Read-only observability seam (Story villager-ai-015) -- see [member
## stuck_tick_count]'s own doc comment.
func get_stuck_tick_count() -> int:
	return stuck_tick_count


## Read-only observability seam (Story villager-ai-015, AC32) -- see [member
## _distressed]'s own doc comment.
func is_distressed() -> bool:
	return _distressed


## Read-only observability seam (Story villager-ai-015) -- this villager's
## own F5 rescue count, see [member _unstuck_count]'s own doc comment.
func get_unstuck_count() -> int:
	return _unstuck_count


## Marks this villager Deciding-eligible (ADR-0008 Decision §2 -- "a villager
## becomes eligible for a Deciding pass... enters a pending queue"). This is
## the generic entry point every eligibility trigger calls: this story wires
## it to [method setup]'s initial-eligible-at-boot call and [method
## _check_decision_interval_trigger]'s periodic re-check; future stories
## (006's state-transition-into-Deciding, 011/018's job-complete, Needs &
## Mood's need-urgent) call this SAME method from their own trigger points --
## no second enqueue path is ever introduced. Delegates entirely to [method
## VillagerDecidingScheduler.enqueue], which is itself idempotent -- calling
## this repeatedly while already queued never bumps this villager to the
## back of the stable FIFO order.
func request_deciding_pass() -> void:
	assert(scheduler != null, "VillagerAi.scheduler not wired")
	scheduler.enqueue(villager_id)


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
##
## Story villager-ai-009 (this revision) additionally drives
## [member _intra_tick_progress] forward every frame -- the "wire live
## game_delta into travel" wiring story villager-ai-004 explicitly deferred
## to this story (that story's own doc comment above: "calling
## advance_travel_progress every frame with a live game_delta is story 009's
## Traveling state-machine wiring responsibility"), matching GDD Core Rule
## 1's "visible movement interpolates continuously using game delta".
## Queries [member time_tick_system]'s OWN `get_game_delta()` -- a value
## that system already computed this frame from ITS OWN raw-delta clamp/
## warp/pause formula -- never this function's own [param _delta] parameter
## (still unread, still named with its conventional unused-parameter
## underscore prefix). Guarded by `time_tick_system != null` AND
## [method is_moving] so this call is a harmless no-op whenever either is
## false -- every earlier story's own position-model unit tests call
## [method _process] directly without ever wiring [member time_tick_system],
## and this guard keeps every one of them passing unchanged.
func _process(_delta: float) -> void:
	if is_moving() and time_tick_system != null:
		@warning_ignore("unsafe_method_access")
		advance_travel_progress(time_tick_system.get_game_delta())
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
## ([member _from_cell] -> [member _to_cell]) -- delegates entirely to
## [method classify_step_length_cells] (Story villager-ai-007 extraction: the
## exact math this method always computed inline before that story;
## behavior-preserving refactor, not a semantic change -- the same
## "extract a pure static twin" pattern [VoxelWorldGrid._pure_terrain_height]
## already established in this codebase).
func _current_step_length_cells() -> float:
	return VillagerAi.classify_step_length_cells(_from_cell, _to_cell)


## Pure, static GDD F1 step-length classifier (Story villager-ai-007
## extraction, [TR-villager-ai-behavior-072]): orthogonal steps (differing on
## at most one horizontal axis) are `1.0`; a true diagonal (differing on BOTH
## the X and Z axes -- the same diagonal test [method is_step_legal] already
## uses) is `1.4`. Height difference (Y) never affects step length, per F1.
## Returns `0.0` when [param from_cell] equals [param to_cell] -- F1's
## documented zero-length/immediate-arrival case. Reused by [method
## _current_step_length_cells] (this class's own Traveling-step math,
## story 004) AND by [VillagerNavGraph.path_length_cells] (story 007's
## AStar3D path-length summation) -- ONE classification, never two
## independently-written copies of the same F1 formula.
static func classify_step_length_cells(from_cell: Vector3i, to_cell: Vector3i) -> float:
	if from_cell == to_cell:
		return 0.0
	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.z - from_cell.z
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
## Story villager-ai-005 uses that seam: [method
## _check_decision_interval_trigger] runs before dispatch, marking this
## villager Deciding-eligible on the GDD Rule 2 periodic cadence regardless
## of its current state (so an urgent need can later preempt long work, per
## that rule) -- [method _tick_state]'s own `State.DECIDING` branch is what
## actually gates the (still-stub) Deciding pass body behind [member
## scheduler]'s budget.
##
## Story villager-ai-006 completes this seam. [method _tick_state]'s own
## `State.DECIDING` branch (unchanged since story 005) already re-evaluates
## the priority list for a villager that STARTS this tick already Deciding.
## For every OTHER state (Traveling/Working/Sleeping/Breather/Wandering),
## THIS method checks [member scheduler]'s budget itself, AFTER [method
## _tick_state] has already run that state's own body -- so the CURRENT
## tick's in-progress activity (e.g. a claimed job's work-progress credit,
## Story 012) always completes first, and only THEN, if runnable, does
## [method _tick_deciding] run and possibly reassign [member _state] --
## exactly GDD Rule 3's graceful-preemption ordering
## ([TR-villager-ai-behavior-050]: "finishes the current cell's in-progress
## tick, then releases its job claim... and pursues the need"). The
## `was_deciding` guard captures [member _state] BEFORE [method _tick_state]
## runs so a villager that started the tick already `DECIDING` -- whose
## Deciding pass [method _tick_state]'s own branch already ran -- is never
## double-invoked here; each villager's Deciding pass still runs at most
## once per tick (AC5).
func _on_tick() -> void:
	_tick_count += 1
	if _travel_complete():
		current_cell = _to_cell
	# Story villager-ai-015: the Unstuck Watchdog's own per-tick check runs
	# HERE -- after arrival-crediting (so `current_cell` already reflects any
	# just-completed step) but BEFORE `was_deciding` is captured below, so a
	# rescue firing THIS tick (which transitions `_state` to `State.DECIDING`)
	# is correctly seen by that capture -- see this method's own class-doc
	# "no double-decide" paragraph for the full ordering rationale.
	_update_unstuck_watchdog()
	_check_decision_interval_trigger()
	var was_deciding: bool = _state == State.DECIDING
	_tick_state()
	if not was_deciding and scheduler.is_runnable_this_tick(villager_id):
		_tick_deciding()


## GDD Rule 2's periodic re-check trigger ("re-evaluated... periodically
## every `decision_interval` ticks so an urgent need can preempt long
## work") -- this story's own concrete, independently-testable eligibility
## enqueue trigger (its Implementation Notes explicitly name
## `decision_interval` elapsed as one of the triggers this story owns,
## alongside need-urgent/job-complete, which remain future stories' scope
## since neither Needs & Mood nor the Building System's job queue exist in
## this codebase yet). Runs every tick regardless of [member _state] -- the
## cadence itself is what lets a Working villager's need be periodically
## reconsidered; deciding what to actually DO once reconsidered is story
## 006's priority-list logic.
func _check_decision_interval_trigger() -> void:
	_ticks_since_last_decision += 1
	if _ticks_since_last_decision >= config.decision_interval:
		_ticks_since_last_decision = 0
		request_deciding_pass()


## FSM dispatch (ADR-0008 Key Interfaces): one `match` branch per
## [enum State], one function per state. Every branch below is an
## intentionally empty stub for this story -- real per-state behaviour
## (movement, work progress, sleep recovery, breather pacing, wander
## micro-behaviours, the Deciding priority list) lands in stories 002/004/
## 005/006/etc., never here. Story villager-ai-005's own contribution lives
## entirely in the `State.DECIDING` branch: it gates the (still-stub) [method
## _tick_deciding] call behind [method VillagerDecidingScheduler.
## is_runnable_this_tick] -- a villager sitting in `DECIDING` but not yet
## dequeued by [member scheduler]'s budget simply does nothing this tick,
## remaining queued for a later one (ADR-0008 Decision §2). No other branch
## is touched by this story.
func _tick_state() -> void:
	match _state:
		State.DECIDING:
			if scheduler.is_runnable_this_tick(villager_id):
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


## The Deciding-pass priority-list evaluation (Story villager-ai-006; GDD
## Rule 2, ADR-0008 Decision §1: "strict, discrete priority order (Urgent
## need > Work > Idle/Wander)" -- plain early-return `if` checks in exactly
## that order, never scored). Called only when [member scheduler] has
## already marked this villager runnable this tick -- either by [method
## _tick_state]'s own `State.DECIDING` branch (a villager that started this
## tick already Deciding, story 005) or by [method _on_tick]'s
## `was_deciding`-guarded post-check (a villager preempted mid-activity,
## this story) -- so this function itself never re-checks that gate.
##
## Tier 1 -- urgent need ([member needs_provider], mocked boundary). Edge
## Case 3b: already committed to pursuing a need
## ([member _pursued_activity] == `NEED`) is a documented no-op -- the
## villager continues, nothing reassigned, no claim ever released (there is
## none to release while already pursuing a need). Otherwise, a held job
## claim ([member _pursued_activity] == `WORK`) is released first ([method
## _release_job_claim], GDD Rule 3's graceful abandon) before committing to
## the need (target selection is Story 018's).
##
## Tier 2 -- an available construction job ([member job_queue], mocked
## boundary). Claim stickiness (AC41/[TR-villager-ai-behavior-052]):
## already committed to work ([member _pursued_activity] == `WORK`) is ALSO
## a no-op -- the periodic `decision_interval` re-check must never re-run
## job selection against a held claim, so [member job_queue] is not even
## consulted in this branch. Otherwise, an available job commits the
## villager to work (target selection is Story 010's F2).
##
## Tier 3 -- idle/wander, the floor (GDD Edge Case 12's MVP degenerate
## case): reached only when neither tier above committed -- no urgent need,
## and either no available job or already sticky-committed to one (handled
## by tier 2's own early return above, so this line only ever sees "no job"
## in this story's own scope).
func _tick_deciding() -> void:
	if _has_urgent_need():
		if _pursued_activity == PursuedActivity.NEED:
			return
		if _pursued_activity == PursuedActivity.WORK:
			_release_job_claim()
		_pursued_activity = PursuedActivity.NEED
		_state = State.TRAVELING
		return
	if _pursued_activity == PursuedActivity.WORK:
		return
	if _has_available_job() and _attempt_claim_and_travel_to_job():
		return
	_pursued_activity = PursuedActivity.NONE
	_state = State.WANDERING


## Tier-1 gate read ([member needs_provider], mocked boundary). Nil-safe: a
## not-yet-wired villager (or any test that never assigns this) always reads
## "no urgent need" -- never crashes, no hard [method setup] assertion, since
## Needs & Mood has no boot-gate dependency this story enforces.
func _has_urgent_need() -> bool:
	if needs_provider == null:
		return false
	@warning_ignore("unsafe_method_access")
	return needs_provider.has_urgent_need(villager_id)


## Tier-2 gate read ([member job_queue], mocked boundary). Nil-safe, same
## rationale as [method _has_urgent_need].
func _has_available_job() -> bool:
	if job_queue == null:
		return false
	@warning_ignore("unsafe_method_access")
	return job_queue.has_available_job()


## Graceful-preemption claim release (GDD Rule 3/[TR-villager-ai-behavior-050]
## "releases its job claim back to the queue"). Called from [method
## _tick_deciding]'s tier-1 branch when [member _pursued_activity] was
## `WORK`, from [method _abandon_travel]'s WORK branch (pathing failure to a
## claimed job), and from this story's own [method _complete_claimed_job]/
## [method _abandon_claimed_job] (job completion/revocation, story
## villager-ai-012) -- i.e. only when a claim could plausibly be held.
## Story villager-ai-012 (this revision): ALSO clears [member
## _claimed_blueprint_cell] back to `null` unconditionally, regardless of
## whether [member job_queue] is wired -- every one of this method's callers
## is relinquishing a claim, so this field must never outlive the claim it
## refers to. A no-op on the [member job_queue] side when it was never
## wired (mocked-boundary nil-safety, same as [method _has_urgent_need]/
## [method _has_available_job]).
func _release_job_claim() -> void:
	_claimed_blueprint_cell = null
	if job_queue == null:
		return
	@warning_ignore("unsafe_method_access")
	job_queue.release_claim(villager_id)


## Tier-2 candidate-list read ([member job_queue], mocked boundary; Story
## villager-ai-011). Nil-safe, same rationale as [method _has_available_job]
## -- though by construction this is only ever called from [method
## _attempt_claim_and_travel_to_job], itself only reached after [method
## _has_available_job] already confirmed [member job_queue] is wired.
## [member ConstructionJobQueue.get_available_jobs]'s exact duck-typed
## signature/contract: every currently BUILDING-eligible [BlueprintCell]
## across every tracked project, commit-time ordered.
func _get_available_jobs() -> Array[BlueprintCell]:
	if job_queue == null:
		return []
	@warning_ignore("unsafe_method_access")
	return job_queue.get_available_jobs()


## Tier-2 atomic-claim attempt ([member job_queue], mocked boundary; Story
## villager-ai-011, GDD Rule 4/AC8/Edge Case 3, [TR-villager-ai-behavior-051]/
## [TR-villager-ai-behavior-081]). Nil-safe, same rationale as [method
## _has_available_job]. Delegates entirely to [member
## ConstructionJobQueue.claim_job]'s exact duck-typed signature/contract --
## this class performs no claim bookkeeping of its own; a `true` return means
## [param cell] is now locked to this villager (one job per villager, no
## other villager may claim it until released), a `false` return means
## either this villager already holds a different claim, or [param cell] lost
## its claim race to another villager's same-pass call (or is no longer
## eligible for any other Building-System-owned reason) -- this method
## cannot distinguish those cases, by design; the caller ([method
## _attempt_claim_and_travel_to_job]) simply tries the next candidate either
## way.
func _claim_job(cell: Vector3i) -> bool:
	if job_queue == null:
		return false
	@warning_ignore("unsafe_method_access")
	return job_queue.claim_job(cell, villager_id)


## Unreachable-job report ([member job_queue], mocked boundary; Story
## villager-ai-011, GDD Rule 6/AC9, [TR-villager-ai-behavior-055]). Nil-safe,
## same rationale as [method _has_available_job]. Delegates entirely to
## [member ConstructionJobQueue.report_unreachable] -- this class owns no
## ghost-tint/visual state of its own; only [method _abandon_travel]'s WORK
## branch ever calls this, and only for a job THIS villager had just claimed
## and then failed to path to (never for F2's own silent pre-claim
## reachability skip, which never claims or reports anything).
func _report_job_unreachable(cell: Vector3i) -> void:
	if job_queue == null:
		return
	@warning_ignore("unsafe_method_access")
	job_queue.report_unreachable(cell)


## AC10's per-cell retry throttle read (see [member
## _unreachable_retry_after_tick]'s own doc comment for the full rationale) --
## `true` iff [param cell] was reported unreachable by THIS villager recently
## enough that [member config]'s `unreachable_retry_ticks` have not yet
## elapsed since. A cell never reported unreachable by this villager (absent
## from the map) is never cooling down.
func _is_job_cooling_down(cell: Vector3i) -> bool:
	return _unreachable_retry_after_tick.has(cell) and _tick_count < _unreachable_retry_after_tick[cell]


## Rule 4/F2 claim-and-travel commit loop (Story villager-ai-011; GDD Rule 4
## "claiming locks the job"; [VillagerJobSelector]'s own doc comment
## explicitly deferred "WHICH job ends up actually claimed/traveled-to" to
## this story). Called ONLY from [method _tick_deciding]'s tier-2 branch,
## after [method _has_available_job] has already confirmed [member job_queue]
## is non-null and the queue is non-empty (Rule 2's cheap existence gate) --
## this method performs the more expensive part: select a candidate (F2 via
## [VillagerJobSelector.select_job]), attempt to atomically claim it, and if
## the claim is LOST to another villager's same-pass claim (AC8/Edge Case 3),
## try the NEXT F2 candidate within this SAME Deciding pass -- "the loser
## selects its next candidate," never a second, deferred Deciding pass for a
## lost claim RACE specifically (unlike Rule 6's post-claim PATHING failure,
## which DOES defer to a future pass via [method _abandon_travel]'s existing
## [method request_deciding_pass] re-queue, unchanged by this story).
## [member nav_graph] absent (null) short-circuits to `false` immediately --
## mirrors [member needs_provider]/[member job_queue]'s own nil-safe
## precedent; a villager with no shared graph wired yet simply has no work
## available this pass, exactly as if the queue were empty.
##
## Each iteration re-reads [method _get_available_jobs] fresh (the queue is
## the sole source of truth on which cells are still claimable -- a real
## [ConstructionJobQueue] naturally excludes an already-claimed cell from its
## own next [method ConstructionJobQueue.get_available_jobs] call), filtered
## by two local exclusions: `attempted_cells` (cells THIS pass already tried
## and lost the claim race for -- guarantees loop termination even against a
## queue double that never shrinks its own list: `attempted_cells` strictly
## grows by exactly one distinct cell per failed-claim iteration, bounded by
## the pass's own original candidate count) and [method _is_job_cooling_down]
## (AC10's per-cell throttle).
##
## Returns `false` when no candidate could be claimed at all this pass --
## every remaining candidate was cooling down, F2's own true-path cap found
## nothing reachable ([JobSelectionResult.has_selection] `false`), or every
## reachable candidate lost its claim race -- [method _tick_deciding]'s own
## caller then falls through to its existing tier-3 Wandering floor (AC11:
## "never stuck in Deciding").
##
## Returns `true` once a claim succeeds and [method start_traveling] has been
## invoked -- regardless of whether that travel call itself immediately
## succeeds: an immediate pathing failure is Rule 6/AC9's own post-claim
## flow, handled entirely by [method start_traveling]'s existing call into
## [method _abandon_travel] (this story only adds the unreachable-report +
## retry-cooldown side effects there, see that method's own doc comment) --
## this loop itself never retries after a successful claim.
func _attempt_claim_and_travel_to_job() -> bool:
	if nav_graph == null:
		return false
	var attempted_cells: Array[Vector3i] = []
	while true:
		var candidates: Array[BlueprintCell] = []
		for candidate: BlueprintCell in _get_available_jobs():
			if attempted_cells.has(candidate.cell):
				continue
			if _is_job_cooling_down(candidate.cell):
				continue
			candidates.append(candidate)
		if candidates.is_empty():
			return false
		var result: JobSelectionResult = VillagerJobSelector.select_job(
			candidates, current_cell, nav_graph, config.job_candidate_count, config.max_selection_candidates
		)
		if not result.has_selection():
			return false
		if _claim_job(result.chosen.cell):
			# Story villager-ai-012: recorded BEFORE travel starts -- Rule 5's
			# on-site gate must already exist for the FULL travel period, not
			# only once Working begins, since ConstructionTickLoop.claim_job
			# already flipped this cell to UNDER_CONSTRUCTION.
			_claimed_blueprint_cell = result.chosen
			_pursued_activity = PursuedActivity.WORK
			start_traveling(result.chosen.cell, State.WORKING)
			return true
		attempted_cells.append(result.chosen.cell)
	# Unreachable -- `while true` only exits via an explicit `return` above;
	# this satisfies GDScript's static "not all code paths return a value"
	# analyzer, which does not treat an unconditional `while true:` as
	# provably infinite/always-returning on its own.
	return false


## Begins Traveling toward [param target_cell], entering `State.TRAVELING`
## and transitioning to [param arrival_state] once [param target_cell] is
## reached (Story villager-ai-009; GDD "Traveling" state-table entry:
## "Activity chosen with a distant target"). The caller -- a future story's
## own target-selection logic (010's F2 job site, 018's bed cell) -- decides
## BOTH the target and what state arrival transitions into; this method
## itself never reasons about job/bed/wander semantics -- only [member
## _pursued_activity] (already set by whichever Deciding-pass tier committed
## to this activity, story 006) does, later, if travel must abandon (see
## [method _abandon_travel]).
##
## Acquires the path via [member nav_graph]'s shared [method
## VillagerNavGraph.find_path] from [member current_cell] -- NEVER from
## [member _visual_position]/[member _intra_tick_progress] (Control
## Manifest: occupancy/logic queries always read the discrete cell). Three
## outcomes, per [method VillagerNavGraph.find_path]'s own documented return
## shape:
## - Empty path (unreachable, or [member current_cell] itself isn't
##   currently a graph point) -- [method _abandon_travel] fires immediately;
##   this villager never enters `State.TRAVELING` at all. Returns `false`.
## - A single-cell path ([param target_cell] == [member current_cell]
##   already, GDD F1's "0 is valid... immediate arrival") --
##   [method _complete_travel_arrival] fires immediately, same call, no tick
##   needed. Returns `true`.
## - A multi-cell path -- stores the path (minus the already-occupied first
##   cell) as [member _travel_remaining_path], begins the first step
##   ([member _from_cell]/[member _to_cell]), resets
##   [member _intra_tick_progress], and enters `State.TRAVELING`. Returns
##   `true`.
func start_traveling(target_cell: Vector3i, arrival_state: State) -> bool:
	assert(nav_graph != null, "VillagerAi.nav_graph not wired -- required before start_traveling()")
	var path: Array[Vector3i] = nav_graph.find_path(current_cell, target_cell)
	if path.is_empty():
		# Story villager-ai-011: [member _travel_target_cell] must be set
		# BEFORE [method _abandon_travel] fires here -- that method's WORK
		# branch reports/cooldowns against it (Rule 6/AC9/AC10), and this is
		# the one call site where it would otherwise still hold a stale
		# leftover value (the normal multi-cell assignment below never runs
		# on this early-return path).
		_travel_target_cell = target_cell
		_abandon_travel()
		return false
	if path.size() == 1:
		_complete_travel_arrival(arrival_state)
		return true
	_travel_target_cell = target_cell
	_travel_arrival_state = arrival_state
	var remaining: Array[Vector3i] = path.slice(1)
	_travel_remaining_path = remaining
	_from_cell = current_cell
	_to_cell = _travel_remaining_path[0]
	_intra_tick_progress = 0.0
	_state = State.TRAVELING
	return true


## Traveling-state tick body (Story villager-ai-009; GDD "request next step
## at tick boundaries"). Called from [method _tick_state], which itself
## runs AFTER [method _on_tick]'s own arrival-crediting assignment
## (`current_cell = _to_cell` when [method _travel_complete] was true) THIS
## SAME tick -- so by the time this runs, [member current_cell] already
## reflects a just-completed step, if one completed this tick.
##
## A no-op while still mid-step ([member current_cell] still equals
## [member _from_cell], not yet [member _to_cell]) -- nothing to advance
## yet; [method _process]/[method advance_travel_progress] handle continuous
## progress every frame, independently of this tick-boundary function.
##
## On arrival at the current step's destination: pops the just-arrived cell
## off [member _travel_remaining_path] (its front always equals
## [member _to_cell] by construction, see that field's own doc comment). An
## empty remainder means the FINAL destination was just reached -- [method
## _complete_travel_arrival] fires. Otherwise begins the next step from the
## newly-arrived [member current_cell] toward the new front of
## [member _travel_remaining_path], resetting [member _intra_tick_progress]
## to `0.0`.
##
## Defensive branch: reachable only if `State.TRAVELING` was entered without
## going through [method start_traveling] (e.g. a hand-constructed test
## fixture, or a freshly-constructed villager whose [member current_cell]/
## [member _to_cell] both default to `Vector3i.ZERO` and therefore compare
## equal trivially -- `config_and_scaffold_test.gd`'s own dispatch-structure
## test does exactly this) -- [member _travel_remaining_path] already empty
## at entry means there was never a real step to credit arrival for, so this
## is a harmless, state-PRESERVING no-op, never a `pop_front()` against an
## empty array and never a call into [method _complete_travel_arrival] (a
## genuine arrival is ONLY ever detected after popping the just-arrived cell
## below, never before).
func _tick_traveling() -> void:
	if current_cell != _to_cell:
		return
	if _travel_remaining_path.is_empty():
		return
	_travel_remaining_path.pop_front()
	if _travel_remaining_path.is_empty():
		_complete_travel_arrival(_travel_arrival_state)
		return
	_from_cell = current_cell
	_to_cell = _travel_remaining_path[0]
	_intra_tick_progress = 0.0


## Successful-arrival completion (Story villager-ai-009; GDD "arrival on
## site transitions to the next state (Working/Sleeping/etc.)"): clears all
## travel bookkeeping ([method _clear_travel_state]) and transitions
## [member _state] to [param arrival_state] -- the actual per-state
## behaviour (work-progress accrual, sleep recovery) remains stories
## 012/018's own stub bodies, untouched here.
func _complete_travel_arrival(arrival_state: State) -> void:
	_clear_travel_state()
	_state = arrival_state


## Graceful travel abandonment (Story villager-ai-009, this story's AC19 --
## "exits to Deciding and re-selects... never keeps traveling toward a dead
## target"). Dispatches GDD Edge Case 1's per-target fallback by [member
## _pursued_activity] -- the ONLY case this codebase can act on today is
## `WORK` (releases the held claim via the already-existing [method
## _release_job_claim], GDD Rule 6's "releases the claim, and tries the
## next-nearest job"); `NEED`'s ground-sleep fallback and `NONE`'s
## wander-reselection are Story 018/019's own scope (neither system exists
## in this codebase yet) -- this story's minimal, safe default for both is
## simply "abandon and re-decide," which this story's own test proves does
## NOT erroneously call [method _release_job_claim] for a non-WORK target.
## Always resets [member _pursued_activity] to `NONE` before re-entering
## Deciding -- otherwise WORK's own claim-stickiness check ([method
## _tick_deciding]'s tier 2) would wrongly treat the just-abandoned claim as
## still held and skip job re-selection entirely.
func _abandon_travel() -> void:
	if _pursued_activity == PursuedActivity.WORK:
		# Story villager-ai-011 (Rule 6/AC9): release BEFORE report -- a real
		# [ConstructionJobQueue.report_unreachable] only finds [param cell]
		# via its own eligibility scan, which requires PLANNED state;
		# releasing first (UNDER_CONSTRUCTION -> PLANNED) is what makes the
		# SAME cell eligible again for that scan to find and flag. Reversing
		# this order would make [method _report_job_unreachable] a silent
		# no-op against the real queue. AC10's per-cell retry cooldown is
		# recorded here too -- this is the ONE place a WORK-pursuing
		# villager's own pathing failure to a claimed job is detected.
		_release_job_claim()
		_report_job_unreachable(_travel_target_cell)
		_unreachable_retry_after_tick[_travel_target_cell] = _tick_count + config.unreachable_retry_ticks
	_pursued_activity = PursuedActivity.NONE
	_clear_travel_state()
	_state = State.DECIDING
	request_deciding_pass()


## Shared travel-bookkeeping reset (Story villager-ai-009) -- used by both
## [method _complete_travel_arrival] (successful arrival) and [method
## _abandon_travel] (graceful abandonment). Empties [member
## _travel_remaining_path] and collapses [member _from_cell]/
## [member _to_cell] back to [member current_cell] (so [method is_moving]
## reports `false`, matching every other stationary state's own invariant),
## resetting [member _intra_tick_progress] to `0.0`.
func _clear_travel_state() -> void:
	_travel_remaining_path = []
	_from_cell = current_cell
	_to_cell = current_cell
	_intra_tick_progress = 0.0


## Working-state tick body (Story villager-ai-012; GDD Rule 5/[TR-villager-
## ai-behavior-054], Edge Case 4/[TR-villager-ai-behavior-083]). This class
## owns NO progress-crediting logic of its own -- [ConstructionTickLoop]'s
## own [signal TimeTickSystem.tick] handler (gated on this villager's REAL
## on-site position via [VillagerOnSiteGate]'s composed occupancy predicate,
## see that class's own doc comment) is the SOLE place a tick actually gets
## credited (AC12/AC13). This method's own job is purely OBSERVATIONAL: read
## [member _claimed_blueprint_cell]'s CURRENT [member BlueprintCell.state] --
## the SAME shared reference [ConstructionTickLoop] mutates directly -- and
## react to whichever of the three outcomes it now holds:
## - [constant BlueprintCell.MicroState.BUILT]: the job completed -- [method
##   _complete_claimed_job] (AC40: "the job is removed from the real
##   queue... villager re-enters Deciding").
## - [constant BlueprintCell.MicroState.UNDER_CONSTRUCTION]: still in
##   progress -- a no-op; nothing for this method to do while
##   [ConstructionTickLoop] keeps crediting (or deferring, per Rule 5/
##   Building Edge Case 6/this story's AC40b) on its own schedule.
## - Anything else ([constant BlueprintCell.MicroState.PLANNED] -- released
##   back by an external revocation, or [constant
##   BlueprintCell.MicroState.CANCELED] -- a project-level cancel mid-work):
##   the job was revoked out from under this villager (AC33/Edge Case 4) --
##   [method _abandon_claimed_job] (no failure reaction, clean re-decide;
##   bookkeeping was already cleared by the revocation itself, per this
##   story's own Implementation Notes, so this branch never calls [method
##   _release_job_claim]/[method _report_job_unreachable] again).
## A `null` [member _claimed_blueprint_cell] (defensive -- should not occur
## by construction, since [member _state] only ever reaches `WORKING` via a
## successful claim that sets this field first) is treated identically to
## the revoked case -- never a crash.
func _tick_working() -> void:
	if _claimed_blueprint_cell == null:
		_abandon_claimed_job()
		return
	match _claimed_blueprint_cell.state:
		BlueprintCell.MicroState.BUILT:
			_complete_claimed_job()
		BlueprintCell.MicroState.UNDER_CONSTRUCTION:
			pass
		_:
			_abandon_claimed_job()


## Successful job completion (Story villager-ai-012, AC40's final stage):
## clears this villager's own claim bookkeeping via [method
## _release_job_claim] -- [ConstructionTickLoop]'s own completion write does
## NOT clean up [ConstructionJobQueue]'s `_claims_by_villager` entry (that
## class has no concept of [ConstructionJobQueue] at all, see its own doc
## comment), so this villager must release its OWN claim explicitly here, or
## a future claim attempt would wrongly find this villager still "holding a
## claim" -- before re-entering Deciding.
func _complete_claimed_job() -> void:
	_release_job_claim()
	_pursued_activity = PursuedActivity.NONE
	_state = State.DECIDING
	request_deciding_pass()


## Revoked-mid-work handling (Story villager-ai-012, AC33/Edge Case 4): no
## failure reaction, clean re-decide. Deliberately does NOT call [method
## _release_job_claim]/[method _report_job_unreachable] -- the revocation
## itself already cleared this villager's claim bookkeeping (this story's
## own Implementation Notes: "Job revocation clears claim bookkeeping via
## the revocation itself"); calling either again here would be, at best,
## redundant, and at worst would wrongly report a legitimate revocation as
## an unreachable-job PATHING failure (Rule 6), which it is not.
func _abandon_claimed_job() -> void:
	_claimed_blueprint_cell = null
	_pursued_activity = PursuedActivity.NONE
	_state = State.DECIDING
	request_deciding_pass()


## Sleeping-state tick body -- stub (later needs/sleep story).
func _tick_sleeping() -> void:
	pass


## Breather-state tick body -- stub (later life-texture story).
func _tick_breather() -> void:
	pass


## Wandering-state tick body -- stub (story 004 wander/idle micro-behaviours).
func _tick_wandering() -> void:
	pass


# =============================================================================
# Story villager-ai-015 -- Unstuck Watchdog (GDD Rule 15/15b/F5)
# =============================================================================

## Rule 15/F5's own "zero legal step from `current_cell`" predicate half.
## Reuses the SAME horizontal x vertical neighbor-candidate set
## [VillagerNavGraph.HORIZONTAL_FULL_OFFSETS]/[VillagerNavGraph.
## VERTICAL_STEP_OFFSETS] already establishes as this codebase's one
## neighbor-candidate convention (Story villager-ai-008's own patch-pass
## reuses the identical pair) -- never a second, locally re-derived neighbor
## set (Control Manifest: "never duplicate walkability rules or constants",
## extended here to the neighbor-candidate set every consumer of [method
## is_standable]/[method is_step_legal] walks). `true` iff ANY candidate
## neighbor is both standable and a legal step FROM [member current_cell] --
## population/occupancy is deliberately NOT considered here (GDD F5's own
## trigger formula names only standability/step-legality; occupancy against
## other villagers is exclusively [VillagerRescueTargetSearch]'s own
## RESCUE-TARGET eligibility filter, a distinct concern from "is this
## villager stuck").
func _has_any_legal_step_from_current_cell() -> bool:
	for offset: Vector2i in VillagerNavGraph.HORIZONTAL_FULL_OFFSETS:
		for dy: int in VillagerNavGraph.VERTICAL_STEP_OFFSETS:
			var neighbor: Vector3i = current_cell + Vector3i(offset.x, dy, offset.y)
			if is_standable(neighbor) and is_step_legal(current_cell, neighbor):
				return true
	return false


## Rule 15/F5's OWN cell-standability half of the "stuck" predicate, split
## out as its own named query (fix for the M01 closure observation run's
## Scenario 1 finding, `production/qa/evidence/m01-closure-evidence-
## 20260726.md`): `true` iff [member current_cell] itself has become
## non-standable -- the exact signature of a self-seal completion (Rule
## 16/F6, [VillagerSealPreventionGate]'s own class doc comment point 1:
## "the villager ending up standing inside now-solid content"). Distinct
## from "walled in but my own cell is fine" (the OTHER half of [method
## _is_stuck_at_current_cell], see below) -- [method
## _update_unstuck_watchdog] treats the two halves differently: this one is
## rescue-eligible in EVERY state (see that method's own doc comment for
## why); the other stays strictly `TRAVELING`/`WORKING`-scoped, unchanged,
## per Rule 15/Edge Case 2/AC32.
func _is_self_sealed_at_current_cell() -> bool:
	return not is_standable(current_cell)


## Rule 15/F5's full "stuck" predicate: [member current_cell] fails
## standability, OR has zero legal step to any neighbor (GDD F5 Formulas:
## "`stuck_tick_count` increments... a Traveling/Working villager has zero
## legal step from `current_cell` OR `current_cell` fails the standability
## check"). Used both by [method _update_unstuck_watchdog]'s
## `TRAVELING`/`WORKING` counter and by [member _distressed]'s own
## all-states read (AC32) -- ONE predicate, not two independently-maintained
## copies. Delegates its own-cell half to [method
## _is_self_sealed_at_current_cell] rather than re-checking [method
## is_standable] inline a second time (this is a pure refactor of this
## method's OWN body -- its return value is byte-for-byte unchanged from
## before the M01 closure fix).
func _is_stuck_at_current_cell() -> bool:
	if _is_self_sealed_at_current_cell():
		return true
	return not _has_any_legal_step_from_current_cell()


## The Unstuck Watchdog's own per-tick entry point (Story villager-ai-015;
## GDD Rule 15/F5; ADR-0008/Control Manifest Feature Layer's "cheap
## O(villagers) per-tick check"), called from [method _on_tick] every tick
## for every villager -- see that method's own doc comment for exactly WHERE
## in tick ordering this runs and why.
##
## Every state updates [member _distressed] (AC32, Edge Case 2's complement:
## an Idle/Wandering/Sleeping/Breather villager with no legal step shows the
## distress cue and stays put, never rescued) -- and, as before, only
## `State.TRAVELING`/`State.WORKING` ever count a "walled in but my own cell
## is still standable" episode toward [member stuck_tick_count] (Rule 15's
## own explicit scope boundary, Edge Case 2/AC32's negative test, both
## UNCHANGED by this fix).
##
## **M01 closure fix** (`production/qa/evidence/m01-closure-evidence-
## 20260726.md` Scenario 1): a villager whose OWN [member current_cell] has
## become non-standable -- [method _is_self_sealed_at_current_cell] --
## remains rescue-eligible REGARDLESS of [member _state]. This is a
## narrowly-scoped exception to "only `TRAVELING`/`WORKING` count", not a
## general widening of Rule 15's rescue scope to Idle/Wandering/Sleeping/
## Breather (Edge Case 2's own "never teleported, stays put" guarantee for
## a merely WALLED-IN-but-standable villager in those states is completely
## untouched -- see [method _is_self_sealed_at_current_cell]'s own doc
## comment for the exact line this fix draws). It exists because Rule
## 16b/[VillagerSealPreventionGate]'s own class doc comment ALREADY promises
## this exact outcome ("the builder becomes sealed in by its own completed
## work, and the Unstuck Watchdog... rescues it on its normal schedule") --
## but [method _tick_working]'s own completion handling
## ([method _complete_claimed_job]) transitions `WORKING -> DECIDING` the
## SAME tick the self-seal first becomes true (GDD's own state table: "Cell
## Built" is an unconditional Working-exit trigger), and Rule 2's periodic
## `decision_interval` re-check (unrelated to this fix) can carry the
## villager on into `WANDERING` shortly after when no other job is
## reachable -- so a strictly `TRAVELING`/`WORKING`-scoped counter, as
## written before this fix, could accumulate at most ONE stuck tick before
## the villager left the counted states for good, structurally short of
## `unstuck_watchdog_threshold_ticks` (12 at production defaults) forever.
## Scoping the exception to "self-sealed" specifically (not "any villager
## with zero legal steps") is deliberate: a self-sealed cell is a
## comparatively rare, severe physical condition (the villager's own body
## literally overlaps solid content) that ONLY Rule 16's self-seal write
## can produce against a previously-standable cell; it is a strict subset
## of "stuck", never triggered by the ordinary "walled into a room by
## someone else's write while idling" case Edge Case 2 is about (that case
## always leaves [member current_cell] itself standable -- only the
## LEGAL-STEP half of [method _is_stuck_at_current_cell] fails there).
func _update_unstuck_watchdog() -> void:
	# Nil-safe against a villager fixture that has no [member voxel_world]
	# wired at all, or one wired but not yet given its own
	# [member VoxelWorldGrid.config] (several earlier stories' own tests
	# drive [method _on_tick] directly without either, since walkability
	# queries were never on THEIR call path before this story) -- mirrors
	# [member nav_graph]'s own "not every earlier story's test wires this"
	# nil-safe precedent, extended here to "not yet fully wired for
	# walkability queries": nothing to check yet is a harmless no-op, never
	# a crash. Every REAL production villager has both wired via [method
	# setup]'s own assert + the boot sequence's config wiring, so this guard
	# never masks anything in production.
	if voxel_world == null or voxel_world.config == null:
		return
	var stuck: bool = _is_stuck_at_current_cell()
	_distressed = stuck
	var rescue_eligible_now: bool = (
		_state == State.TRAVELING
		or _state == State.WORKING
		or _is_self_sealed_at_current_cell()
	)
	if not rescue_eligible_now:
		_reset_stuck_episode()
		return
	if not stuck:
		_reset_stuck_episode()
		return
	stuck_tick_count += 1
	if stuck_tick_count >= config.unstuck_watchdog_threshold_ticks:
		_attempt_watchdog_rescue()


## Shared "relief" reset (Story villager-ai-015) -- used by [method
## _update_unstuck_watchdog]'s own two relief paths (no longer
## Traveling/Working; still Traveling/Working but no longer stuck) AND by
## [method _perform_watchdog_rescue] (a successful rescue is relief too). A
## harmless no-op when [member stuck_tick_count] is already `0` and [member
## _search_failure_gate] already fresh -- [method
## RescueSearchFailureGate.reset_episode]'s own doc comment: "idempotent".
func _reset_stuck_episode() -> void:
	stuck_tick_count = 0
	_search_failure_gate.reset_episode()


## Rule 15's rescue attempt (Story villager-ai-015, AC51) -- called once
## [member stuck_tick_count] has reached [member VillagerAIConfig.
## unstuck_watchdog_threshold_ticks]. Delegates target selection entirely to
## the F5 BFS ([VillagerRescueTargetSearch.find_rescue_target], Story
## villager-ai-014) -- this method never re-derives an equivalent search of
## its own. A miss (search exhausted at `unstuck_rescue_max_radius`, GDD Edge
## Case 14) reports through [member _search_failure_gate]'s own
## once-per-episode gate and defers -- [member stuck_tick_count] is
## deliberately NOT reset here, so [method _update_unstuck_watchdog] keeps
## incrementing it and re-attempts this SAME search on every subsequent tick
## (Edge Case 14: "the search retries every tick until a cell is found"),
## with [member _search_failure_gate] guaranteeing [signal
## unstuck_search_failed] still fires only once across that whole retry
## run. A hit performs the actual rescue via [method
## _perform_watchdog_rescue].
func _attempt_watchdog_rescue() -> void:
	var other_cells: Array[Vector3i] = _get_other_villager_cells()
	var result: RescueSearchResult = VillagerRescueTargetSearch.find_rescue_target(
		current_cell,
		self,
		other_cells,
		config.unstuck_rescue_search_radius,
		config.unstuck_rescue_max_radius,
	)
	if not result.has_target():
		if _search_failure_gate.should_report_failure():
			unstuck_search_failed.emit()
		return
	_perform_watchdog_rescue(result.cell)


## The rescue itself (Story villager-ai-015, AC51/AC52; ADR-0009 slice
## propagation's second sanctioned discrete `current_cell` mutation). Order
## of operations, all within this single synchronous call (no tick spans
## mid-rescue):
## 1. Release any held job claim via the SAME [method _release_job_claim]
##    helper every OTHER claim-relinquishing path already funnels through
##    (AC52: "releases back to the queue exactly as Rule 6's unreachable-job
##    flow -- no double-release, no orphaned claim") -- ONLY when [member
##    _pursued_activity] is `WORK`; a `NEED`-pursuing villager (e.g. mid-travel
##    to a bed) holds no claim, so this is skipped entirely, exactly AC52's
##    "no claim-release side effect... bed ownership unaffected" half.
##    Deliberately does NOT also call [method _report_job_unreachable]/record
##    an unreachable-retry cooldown -- unlike Rule 6's own pathing-failure
##    flow, the claimed CELL itself was never unreachable here; this
##    villager was stuck, a distinct fact Rule 6's job-unreachable reporting
##    would mislabel (this story's own interpretation of AC52's "exactly as
##    Rule 6's unreachable-job flow" -- read as "reuses the same release
##    HELPER/no-double-release guarantee", not "replays every one of Rule
##    6's side effects").
## 2. Clears travel bookkeeping and sets [member current_cell] atomically to
##    [param rescue_cell], snapping [member _visual_position] to match via
##    the SAME [method VoxelWorldGrid.cell_to_world] conversion [method
##    _process] already uses -- NO lerp (ADR-0009: "the watchdog is the one
##    deliberate exception" to "never snap/teleport").
## 3. Resets the stuck episode ([method _reset_stuck_episode]) and [member
##    _distressed] -- relief.
## 4. Records telemetry: this villager's own [member _unstuck_count], plus
##    [member unstuck_telemetry]'s shared world total when wired (nil-safe,
##    see that field's own doc comment).
## 5. Emits [signal unstuck_rescued], transitions to `State.DECIDING`, and
##    re-enters the Deciding queue via the SAME [method request_deciding_pass]
##    every OTHER eligibility trigger uses -- see this class's own
##    villager-ai-015 doc-comment paragraph for why this is never a bonus,
##    unbudgeted immediate decide.
func _perform_watchdog_rescue(rescue_cell: Vector3i) -> void:
	if _pursued_activity == PursuedActivity.WORK:
		_release_job_claim()
	_pursued_activity = PursuedActivity.NONE
	_travel_remaining_path = []
	current_cell = rescue_cell
	_from_cell = rescue_cell
	_to_cell = rescue_cell
	_intra_tick_progress = 0.0
	_visual_position = VoxelWorldGrid.cell_to_world(rescue_cell)
	_reset_stuck_episode()
	_distressed = false
	_unstuck_count += 1
	if unstuck_telemetry != null:
		unstuck_telemetry.record_rescue(villager_id)
	_state = State.DECIDING
	unstuck_rescued.emit(rescue_cell)
	request_deciding_pass()


## [member population]'s nil-safe read (Story villager-ai-015). Nil-safe,
## same rationale as [method _has_urgent_need]/[method _has_available_job] --
## a villager with no population registry wired searches as though no other
## villager exists.
func _get_other_villager_cells() -> Array[Vector3i]:
	if population == null:
		return []
	@warning_ignore("unsafe_method_access")
	return population.get_other_villager_cells(villager_id)


# =============================================================================
# Story villager-ai-016 -- Seal Prevention (GDD Rule 16/F6, ADR-0009 slice
# propagation Sec.2b, [TR-villager-ai-behavior-101]/102/106/107)
# =============================================================================

## Seal-prevention trap predicate (GDD F6: `would_trap_builder`) -- true iff
## a write that makes [param written_cell] solid would leave THIS villager
## (at its own [member current_cell]) with zero legal steps to any standable
## neighbor, evaluated AS IF the write had already committed
## (Implementation Notes) without ever mutating the real [member voxel_world]
## (a genuine trial write would fire real signals -- nav-graph patching,
## repath filters -- for a change that might never actually commit, exactly
## the side-effect risk this predicate is designed to avoid). Reuses the
## SAME neighbor-candidate set [method _has_any_legal_step_from_current_cell]
## already establishes ([VillagerNavGraph.HORIZONTAL_FULL_OFFSETS]/[VillagerNavGraph.
## VERTICAL_STEP_OFFSETS]) and the SAME Rule 8/9 arithmetic [method
## is_standable]/[method is_step_legal] already define -- never a second,
## locally-derived neighbor set or a duplicated walkability formula (Control
## Manifest Feature Layer Forbidden). The private `_after_write` twins below
## are the ONLY new arithmetic this story adds: each mirrors its non-`_after_
## write` counterpart line-for-line, substituting exactly one thing --
## treating [param written_cell] as solid/occupied regardless of what
## [member voxel_world] currently reports there -- mirroring this codebase's
## own established "extract a parameterized twin rather than duplicate"
## precedent ([method classify_step_length_cells]'s own extraction, story
## villager-ai-007).
##
## Checked against [member current_cell] itself first (mirrors [method
## _is_stuck_at_current_cell]'s own "not standable OR no legal step"
## structure exactly) -- a write that removes the builder's OWN standing
## clearance (e.g. directly overhead) counts as trapping just as surely as
## sealing every exit does.
##
## [VillagerSealPreventionGate] is this predicate's real caller (wired into
## [ConstructionTickLoop]'s completion write path via [ConstructionJobQueue]
## behind [method ConstructionTickLoop.set_seal_prevention_predicate]) --
## this method itself has no Building System awareness whatsoever, exactly
## like [method is_standable]/[method is_step_legal].
func would_trap_builder(written_cell: Vector3i) -> bool:
	if not _is_standable_after_write(current_cell, written_cell):
		return true
	for offset: Vector2i in VillagerNavGraph.HORIZONTAL_FULL_OFFSETS:
		for dy: int in VillagerNavGraph.VERTICAL_STEP_OFFSETS:
			var neighbor: Vector3i = current_cell + Vector3i(offset.x, dy, offset.y)
			if (
				_is_standable_after_write(neighbor, written_cell)
				and _is_step_legal_after_write(current_cell, neighbor, written_cell)
			):
				return false
	return true


## [method is_standable]'s "as if written" twin -- see [method
## would_trap_builder]'s own doc comment. Identical control flow to [method
## is_standable]; only the solid-below/clearance-column reads are routed
## through the override-aware [method _is_solid_after_write]/[method
## _is_passable_after_write] below instead of [method _is_solid]/[method
## _is_passable] directly.
func _is_standable_after_write(cell: Vector3i, written_cell: Vector3i) -> bool:
	if not _is_solid_after_write(cell + Vector3i(0, -1, 0), written_cell):
		return false
	for offset in range(VILLAGER_CLEARANCE):
		if not _is_passable_after_write(cell + Vector3i(0, offset, 0), written_cell):
			return false
	return true


## [method is_step_legal]'s "as if written" twin -- see [method
## would_trap_builder]'s own doc comment. Identical control flow to [method
## is_step_legal]; only the diagonal flanker standability reads are routed
## through [method _is_standable_after_write] instead of [method
## is_standable] directly.
func _is_step_legal_after_write(from_cell: Vector3i, to_cell: Vector3i, written_cell: Vector3i) -> bool:
	if absi(to_cell.y - from_cell.y) > MAX_STEP_HEIGHT:
		return false
	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.z - from_cell.z
	if dx != 0 and dz != 0:
		var flanker_a := Vector3i(to_cell.x, from_cell.y, from_cell.z)
		var flanker_b := Vector3i(from_cell.x, from_cell.y, to_cell.z)
		if (
			not _is_standable_after_write(flanker_a, written_cell)
			or not _is_standable_after_write(flanker_b, written_cell)
		):
			return false
	return true


## [method _is_solid]'s override-aware twin -- [param written_cell] always
## reads solid (the hypothetical write has committed), regardless of
## [member voxel_world]'s REAL current contents there.
func _is_solid_after_write(cell: Vector3i, written_cell: Vector3i) -> bool:
	if cell == written_cell:
		return true
	return _is_solid(cell)


## [method _is_passable]'s override-aware twin -- [param written_cell] never
## reads passable (the hypothetical write has committed), regardless of
## [member voxel_world]'s REAL current contents there.
func _is_passable_after_write(cell: Vector3i, written_cell: Vector3i) -> bool:
	if cell == written_cell:
		return false
	return _is_passable(cell)


# =============================================================================
# Story villager-ai-008 -- re-path FILTER (GDD Rule 10b, TR-012/036)
# =============================================================================

## Whether this villager is currently mid-step (GDD Rule 10b's "any moving
## villager" scope). A pure, discrete comparison -- `_from_cell != _to_cell`
## -- never a read of [member _visual_position]/[member _intra_tick_progress]
## (Control Manifest Core Layer: occupancy/movement queries never reason
## about interpolation progress). Deliberately NOT keyed to [member _state]
## naming TRAVELING/WANDERING/BREATHER explicitly: whichever state is
## driving a 1-cell step (Traveling, a Wandering step, a Breather
## step-away, or a future F4 vacate step), that step sets
## [member _from_cell]/[member _to_cell] to two DIFFERENT cells for its
## duration and back to equal at arrival ([method _on_tick]'s
## `current_cell = _to_cell` moment coincides with `_from_cell == _to_cell`
## already being true from the PRIOR step's completion, by this class's own
## existing invariant) -- so this single check already covers all 4 named
## cases without enumerating them, and naturally excludes every stationary
## state (Deciding/Working/Sleeping, and a Breather not yet stepping) since
## none of them ever drives `_from_cell`/`_to_cell` apart.
func is_moving() -> bool:
	return _from_cell != _to_cell


## "The remaining movement's cells" (GDD Rule 10b) -- widened by story
## villager-ai-009 (exactly the widening this method's own predecessor doc
## comment reserved) to cover the villager's ENTIRE remaining route once
## [method start_traveling] is driving travel, not merely its single
## in-flight step: [member _from_cell] (the current step's origin) plus
## every cell still in [member _travel_remaining_path] (which always begins
## with [member _to_cell], the in-flight step's own destination). Falls
## back to the ORIGINAL single-step pair, `[_from_cell, _to_cell]`, when
## [member _travel_remaining_path] is empty despite [method is_moving] being
## `true` -- the case a hand-constructed test fixture produces by setting
## [member _from_cell]/[member _to_cell] apart directly without ever calling
## [method start_traveling] (story 008's own `graph_patching_test.gd`
## fixtures do exactly this; this fallback keeps them passing unchanged). An
## empty array when stationary ([method is_moving] `false`), unchanged from
## story 008.
func get_remaining_movement_cells() -> Array[Vector3i]:
	if not is_moving():
		return []
	if _travel_remaining_path.is_empty():
		return [_from_cell, _to_cell]
	var cells: Array[Vector3i] = [_from_cell]
	cells.append_array(_travel_remaining_path)
	return cells


## Mid-travel re-path recompute (Story villager-ai-009, this story's AC18 --
## "the villager re-paths from its current cell"). Called ONLY from [method
## _on_repath_evaluation_requested]'s `State.TRAVELING` guard. Re-queries
## [member nav_graph] -- already patched against the SAME write, by
## construction, per [member nav_graph]'s own wiring-order doc comment --
## for a fresh path from [member current_cell] toward the SAME
## [member _travel_target_cell] (a redirect never changes the ultimate
## target itself, only the route). An empty result means no viable detour
## exists -- [method _abandon_travel] fires (this story's AC19, dispatched
## via the SAME per-target fallback [method start_traveling]'s own
## unreachable case uses). A single-cell result (rare: [member current_cell]
## itself is now the target) still completes arrival correctly via
## [method _complete_travel_arrival]. A genuine multi-cell detour replaces
## [member _travel_remaining_path] outright and resets
## [member _intra_tick_progress] -- the redirected step begins from `0.0`
## progress, never from wherever the abandoned step's progress happened to
## be (a fresh step, not a resumed one).
func _recompute_path_from_current_cell() -> void:
	assert(nav_graph != null, "VillagerAi.nav_graph not wired -- required once Traveling")
	var new_path: Array[Vector3i] = nav_graph.find_path(current_cell, _travel_target_cell)
	if new_path.is_empty():
		_abandon_travel()
		return
	if new_path.size() == 1:
		_complete_travel_arrival(_travel_arrival_state)
		return
	var remaining: Array[Vector3i] = new_path.slice(1)
	_travel_remaining_path = remaining
	_from_cell = current_cell
	_to_cell = _travel_remaining_path[0]
	_intra_tick_progress = 0.0


## [signal repath_evaluation_requested] handler (Story villager-ai-009),
## connected in [method setup] with Godot's DEFAULT synchronous flags
## (never `CONNECT_DEFERRED`) -- the actual REDIRECT this story's
## race-closure AC requires happens here, in the SAME synchronous call
## stack as the Voxel World write that triggered [signal
## repath_evaluation_requested] (story 008's own filter, unchanged), well
## before the next frame's [method _process] call could ever advance
## [member _visual_position] further toward now-solid geometry. Guarded to
## `State.TRAVELING` only: [method evaluate_repath_trigger] can fire for any
## moving villager regardless of [member _state] (nothing in that check
## depends on it, story 008), but a villager whose [member _from_cell]/
## [member _to_cell] were set apart by some OTHER means (e.g. a
## hand-constructed test fixture never touching [member _state]) has no
## [member _travel_target_cell]/[member nav_graph] to recompute against --
## a harmless no-op for every state but Traveling.
func _on_repath_evaluation_requested() -> void:
	if _state != State.TRAVELING:
		return
	_recompute_path_from_current_cell()


## The re-path FILTER itself (GDD Rule 10b, this story's AC18/AC49): given
## the cell(s) a Voxel World write just changed, fires [signal
## repath_evaluation_requested] exactly once if -- and only if -- this
## villager is currently moving ([method is_moving]) AND [param
## changed_cells] intersects [method get_remaining_movement_cells]'s own
## clearance envelope (delegated entirely to the stateless
## [VillagerRepathFilter] library, never a locally re-derived copy of the
## envelope rule). A write outside that envelope -- or any write while this
## villager is stationary -- fires nothing (AC49: "re-path evaluation
## call-count == 0").
func evaluate_repath_trigger(changed_cells: Array[Vector3i]) -> void:
	if not is_moving():
		return
	if VillagerRepathFilter.changed_cells_intersect_envelope(changed_cells, get_remaining_movement_cells()):
		repath_evaluation_requested.emit()


## [signal VoxelWorldGrid.cell_changed] handler (wired in [method setup] with
## Godot's DEFAULT, synchronous, NEVER `CONNECT_DEFERRED` connection flags --
## see this class's own doc comment for why that is load-bearing). Delegates
## to [method evaluate_repath_trigger] for the single changed cell; [param
## _before]/[param _after] are unused -- the filter only cares WHICH cell
## changed, never what it changed FROM/TO.
func _on_voxel_world_cell_changed(cell: Vector3i, _before: CellContents, _after: CellContents) -> void:
	evaluate_repath_trigger([cell])


## [signal VoxelWorldGrid.cells_changed_batch] handler -- same delegation as
## [method _on_voxel_world_cell_changed], batched: every changed cell across
## one bulk write is folded into ONE [method evaluate_repath_trigger] call
## (so at most one [signal repath_evaluation_requested] emission per batch,
## never one per record), consistent with [VillagerNavGraph]'s own
## story-008 batch handler.
func _on_voxel_world_cells_changed_batch(changes: Array[CellChangeRecord]) -> void:
	var cells: Array[Vector3i] = []
	for record: CellChangeRecord in changes:
		cells.append(record.cell)
	evaluate_repath_trigger(cells)
