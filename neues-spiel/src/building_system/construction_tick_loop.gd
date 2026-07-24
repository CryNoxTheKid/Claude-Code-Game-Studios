## Building System's construction tick loop (Story building-029, ADR-0016
## primary -- "when a cell's build time elapses, this system issues the
## Voxel World write and retires the blueprint cell" [TR-building-system-057];
## Time & Tick System secondary -- construction advances on game ticks only,
## never raw delta, GDD Formula F3 [TR-building-system-079]/
## [TR-building-system-080]).
##
## Owns exactly the "Planned -> UnderConstruction -> Built" per-cell
## progression [TR-building-system-068]/[TR-building-system-069] this
## story's own Control Manifest excerpt names, and nothing else:
##
## 1. **Job-claim seam** (AC43, [TR-building-system-068]): [method claim_job]
##    is the MOCKED on-site-job boundary this story's own Implementation
##    Notes name ("Test with a mocked on-site job... the villager claim/
##    path/arrival mechanic is Story 030"). A real caller (Story 030's
##    claim/report/on-site queue pipeline, [ConstructionJobQueue]) calls this
##    SAME method with a real claiming villager -- this class still treats
##    "claimed" and "on site" as the same fact for its OWN crediting loop
##    ([method _on_tick] has no villager-position concept and never will;
##    the real on-site/off-site distinction, [ConstructionJobQueue.is_on_site],
##    is wired by a future Villager AI story, not here). Story 030 (this
##    revision) DOES layer one refinement directly onto this seam without
##    changing [method claim_job]'s own shape: [method set_occupancy_predicate]
##    (see point 2b below) and [method release_job] (the symmetric un-claim
##    [method claim_job] never had a counterpart for).
## 2. **Tick-driven progress** (GDD Formula F3, [TR-building-system-079]):
##    [method _on_tick] -- this module's SOLE entry point that ever advances
##    any job -- credits every ACTIVE job exactly one tick per [signal
##    TimeTickSystem.tick] delivery. Warp-invariance and the burst rule (F3)
##    both fall out of [TimeTickSystem]'s OWN existing contract for free:
##    that Autoload's `_advance_ticks` already fires [signal
##    TimeTickSystem.tick] once per discrete drift-free tick boundary,
##    capped at `max_ticks_per_frame` (its own burst cap) and NEVER while
##    paused -- this class adds no second burst loop, no delta parameter,
##    and no warp read of any kind, so "tick count to complete is unchanged
##    by warp" and "at most `max_ticks_per_frame` ticks fire in one frame"
##    hold structurally, not via a second implementation of either rule.
## 2b. **Occupied-cell defer** (Story building-030, GDD Edge Case 6,
##    [TR-building-system-037]): [method set_occupancy_predicate] wires an
##    OPTIONAL `Callable(cell: Vector3i) -> bool` seam -- mirrors
##    [CommitPipeline]'s own established `set_furniture_support_predicate`
##    pattern exactly (an optional, default-invalid `Callable`, a future real
##    caller overrides it). Default `Callable()` (invalid) means "never
##    occupied" -- every pre-030 test/consumer's behavior is completely
##    unaffected. When wired, [method _on_tick] skips crediting any job whose
##    cell currently reads occupied THIS tick -- no `progress_ticks`
##    increment, the job stays exactly as UnderConstruction as it was, and
##    every OTHER active job in the SAME `_on_tick` dispatch still credits
##    normally (Edge Case 6: "that cell's progress is skipped... while all
##    other queued cells process normally" -- deferral is per-cell, never
##    per-command or global). The actual occupancy READ (a real character
##    standing on the target cell) is [ConstructionJobQueue]'s/Villager AI's
##    concern entirely -- this class only consults whatever boolean the
##    predicate returns, exactly as [CommitPipeline]'s furniture-support seam
##    never reasons about footprint geometry itself.
## 3. **Per-job independence, no rollover** (F3 burst rule, AC25/AC45,
##    [TR-building-system-080]): active jobs are tracked one per CELL, keyed
##    by that cell's address -- "N villagers complete at most N cells per
##    frame" and "excess ticks do NOT roll over to that villager's next
##    cell" both hold by construction: a completed job is removed from
##    [member _active_jobs] the instant it finishes, so any further tick
##    events in the SAME burst simply find nothing left to advance for that
##    cell, and a villager is never automatically re-assigned a new cell
##    within this class (claiming a new cell is Story 030's separate act).
## 4. **The Voxel World write + retirement** ([TR-building-system-057]):
##    completing a job means the cell's contents ([member
##    BlueprintCell.contents], a PLACEHOLDER pending Story 022's real
##    material-selection wiring -- see [BlueprintCell]'s own doc comment) get
##    written to Voxel World and [member BlueprintCell.state] transitions to
##    [constant BlueprintCell.MicroState.BUILT]. Story building-033 (point 5
##    below) changed HOW that write is issued -- see that paragraph for the
##    batched-write mechanics this point used to own entirely on its own.
## 5. **Batched completion write + self-write tag + Build Validation seam**
##    (Story building-033, [TR-building-system-072]/[TR-building-system-024]/
##    [TR-building-system-075]): [method _on_tick] no longer calls [method
##    VoxelWorldGrid.set_cell] once per completing job -- it collects EVERY
##    job that reaches its completion threshold in THIS SAME dispatch into
##    one `Dictionary[Vector3i, CellContents]` and issues exactly ONE
##    [method VoxelWorldGrid.bulk_write] call at the end via [method
##    _complete_jobs] (even for a single completion -- there is no "a batch
##    of one is still single-cell" special case; every completion, always,
##    goes through the SAME batched path), so [signal
##    VoxelWorldGrid.cells_changed_batch] fires AT MOST ONCE per tick
##    regardless of how many jobs completed, and [signal
##    VoxelWorldGrid.cell_changed] never fires for a completion anymore
##    (Villager AI's nav-graph patching, story villager-ai-008, already
##    subscribes to BOTH signals, so this is transparent to it). [member
##    write_tag] ([BuildingSystemWriteTag]) brackets that single [method
##    VoxelWorldGrid.bulk_write] call with `begin()`/`end()` -- Godot's
##    default synchronous signal delivery means [UndoRedoStack]'s own
##    undo-invalidation listener (a caller sharing the SAME
##    [BuildingSystemWriteTag] instance) observes `is_active() == true` for
##    the FULL duration of that call, recognizing every cell this dispatch
##    just wrote as self-originated and never invalidating an undo entry
##    over it (AC46). Every cell actually completed this dispatch (the SAME
##    set the batched write covers) is also collected into [signal
##    construction_completed] -- fired exactly once, AFTER the write, only
##    when at least one job completed (never a zero-cell emission) -- the
##    seam Build Validation (M02, not yet implemented) will consume to avoid
##    N region re-analyses for N parallel completions in one frame
##    ([TR-building-system-075]). Per-job state transition (to
##    [constant BlueprintCell.MicroState.BUILT]) and [member _active_jobs]
##    retirement still happen AFTER the batched write returns (mirroring the
##    exact ordering the single-cell path had before this story: the write's
##    own signal observes every completing cell still
##    [constant BlueprintCell.MicroState.UNDER_CONSTRUCTION], the state flips
##    only once the write has landed) -- no consumer of either signal has
##    ever been able to observe a completing cell's [BlueprintCell] already
##    flipped to BUILT mid-signal, before or after this story.
##
## **Explicitly out of scope** (this story's own Out of Scope section, and
## the neighbouring stories that own it):
## - Story 030 (this revision landed the two seams above -- point 2b's
##   occupancy predicate, [method release_job] -- but NOT the rest): the REAL
##   claim/report/on-site QUEUE itself (job aggregation across projects, the
##   Villager AI-facing `has_available_job()`/`release_claim()` contract,
##   one-job-per-villager bookkeeping, the on-site predicate definition, and
##   the unreachable-ghost signal/flag) lives in the separate
##   [ConstructionJobQueue] collaborator, not here. This class still does not
##   itself decide WHICH villager should claim WHICH cell, does not path
##   anyone anywhere, and still has no "on site" concept distinct from
##   "claimed" for its OWN crediting loop -- [ConstructionJobQueue] is the
##   seam that layers those concerns on top, calling [method claim_job]/
##   [method release_job]/[method set_occupancy_predicate] exactly as any
##   other caller would.
## - Story 009 (demolition / removal writes): this story's batching +
##   self-write-tag mechanics (Story building-033, point 5 above) are
##   generic to ANY completion this class issues -- a future demolition-job
##   completion path is expected to reuse the SAME [BuildingSystemWriteTag]
##   instance and the SAME batched-write discipline, not invent a second
##   one. No removal/demolition write path exists in this class yet.
## - Story 002/003: the persistent Build Project entity and its cell
##   registry/grouping -- this class has no concept of a project; it is
##   handed bare [BlueprintCell] references directly (mirrors
##   [CommitPipeline]'s own "Story 003 assigns project membership, not
##   here" precedent). Mutating [member BlueprintCell.state] here is
##   visible through any other holder of the SAME [RefCounted] reference
##   (e.g. [CommitPipeline]'s own tracking dictionary) by construction --
##   no second registry to keep in sync.
##
## Injected-tier module (ADR-0001): [member voxel_world]/[member config] are
## wired via a scene file's Inspector in production (once a future
## scene-assembly story attaches this node), or assigned directly in a
## headless test. [member time_tick_system] is a plain, non-`@export`
## `Object` -- mirrors [VillagerAi]'s own established duck-typed
## `time_tick_system` precedent exactly (`@export`ing an Autoload is
## Forbidden, ADR-0001): production resolves it lazily against
## `/root/TimeTickSystem`; a headless test assigns a `tick`-signal-shaped
## test double directly before calling [method setup]. All
## wiring/validation lives in [method setup], never `_ready()`.
class_name ConstructionTickLoop
extends Node

## Injected-tier dependency (ADR-0001) -- the sole mutation path this class
## ever calls: [method VoxelWorldGrid.bulk_write], on job completion only
## (Story building-033 -- see class doc comment point 5).
@export var voxel_world: VoxelWorldGrid

## Tuning config dependency (ADR-0002) -- GDD Formula F3's
## `base_build_ticks[category]` knobs. Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: ConstructionTickLoopConfig

## Story building-033 addition (TR-building-system-024) -- the shared
## self-write exemption tag [method _complete_jobs]'s own batched completion
## write brackets with `begin()`/`end()`. Optional; default-constructed in
## [method setup] if left unwired (see [BuildingSystemWriteTag]'s own class
## doc comment for why a caller that wants [UndoRedoStack]'s
## undo-invalidation listener to recognize this class's writes as
## self-originated MUST wire the identical instance into both). Plain `var`,
## never `@export` -- `RefCounted` is not an exportable Inspector type
## (mirrors [member time_tick_system]/[VillagerAi]'s own `job_queue: Object`
## precedent: a code-assigned collaborator, not an Inspector-wired one).
var write_tag: BuildingSystemWriteTag = null

## Story building-033 addition ([TR-building-system-075]) -- fires exactly
## once per [method _on_tick] dispatch that completes at least one job,
## carrying every cell completed in THIS SAME dispatch (never a zero-cell
## emission) -- the seam Build Validation (M02) will consume to avoid one
## region re-analysis per completing cell.
signal construction_completed(cells: Array[Vector3i])

## Time & Tick System dependency (ADR-0001 Autoload tier) -- see class doc
## comment. Duck-typed against the one member this class depends on:
## `signal tick()`.
var time_tick_system: Object = null

## One currently-active (claimed) job per cell -- see class doc comment
## point 3 for why per-cell keying alone gives AC25/AC45's independence and
## no-rollover guarantees for free. A cell absent from this dictionary is
## either not yet claimed (still [constant BlueprintCell.MicroState.PLANNED])
## or already retired ([constant BlueprintCell.MicroState.BUILT]) -- [method
## claim_job]/[method _complete_jobs] are the sole writer/eraser.
class _ActiveJob:
	## The claimed [BlueprintCell] itself -- this class mutates its [member
	## BlueprintCell.state] directly (a shared [RefCounted] reference, not a
	## copy) so the SAME object a caller still holds observes the
	## transition.
	var blueprint_cell: BlueprintCell

	## The claiming villager's id (Story building-005's future worker-
	## attribution rollup reads this indirectly once [method claim_job] is
	## wired to a real claim -- this story only stores it, never reports it
	## anywhere itself).
	var villager_id: int

	## Ticks credited toward [member blueprint_cell]'s
	## `required_ticks_for(...)` total so far.
	var progress_ticks: int = 0

	func _init(p_blueprint_cell: BlueprintCell, p_villager_id: int) -> void:
		blueprint_cell = p_blueprint_cell
		villager_id = p_villager_id

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## See [_ActiveJob] doc comment above.
var _active_jobs: Dictionary[Vector3i, _ActiveJob] = {}

## Occupied-cell defer seam (Story building-030, class doc comment point 2b)
## -- `Callable(cell: Vector3i) -> bool`, `true` meaning "occupied this
## tick." Default `Callable()` (invalid) mirrors [CommitPipeline]'s own
## `_furniture_support_predicate` default exactly: "never occupied," a
## complete no-op for every pre-030 caller. Set via [method
## set_occupancy_predicate].
var _occupancy_predicate: Callable = Callable()


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member voxel_world] and a [member time_tick_system]-shaped dependency
## are wired, applies ADR-0002's clamp+warn `validate()` policy, then
## connects this module's tick dispatch to [signal TimeTickSystem.tick]
## (idempotent, mirroring [CommitPipeline]/[ToolStateMachine]'s own
## `is_connected` guard precedent).
func setup() -> void:
	assert(voxel_world != null, "ConstructionTickLoop.voxel_world not wired")
	assert(config != null, "ConstructionTickLoop.config not wired")
	for issue: String in config.validate():
		push_warning(issue)
	if time_tick_system == null:
		time_tick_system = get_node_or_null(^"/root/TimeTickSystem")
	assert(
		time_tick_system != null,
		"ConstructionTickLoop requires a TimeTickSystem-shaped dependency (assign a mock in"
		+ " tests; the real Autoload is registered project-wide) before setup() can"
		+ " connect tick dispatch"
	)
	@warning_ignore("unsafe_property_access")
	var tick_already_connected: bool = time_tick_system.tick.is_connected(_on_tick)
	if not tick_already_connected:
		@warning_ignore("unsafe_property_access")
		time_tick_system.tick.connect(_on_tick)
	if write_tag == null:
		write_tag = BuildingSystemWriteTag.new()
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## The job-claim seam (AC43, [TR-building-system-068]) -- see class doc
## comment point 1. Transitions [param blueprint_cell] from
## [constant BlueprintCell.MicroState.PLANNED] to
## [constant BlueprintCell.MicroState.UNDER_CONSTRUCTION] and begins
## crediting it ticks via [method _on_tick]. Returns `false` (no-op) if
## [param blueprint_cell] is not currently Planned, or if its cell address
## already has an active job (double-claim guard) -- either way nothing is
## mutated.
func claim_job(blueprint_cell: BlueprintCell, villager_id: int) -> bool:
	assert(is_set_up(), "ConstructionTickLoop.claim_job called before setup()")
	if blueprint_cell.state != BlueprintCell.MicroState.PLANNED:
		return false
	if _active_jobs.has(blueprint_cell.cell):
		return false
	blueprint_cell.state = BlueprintCell.MicroState.UNDER_CONSTRUCTION
	_active_jobs[blueprint_cell.cell] = _ActiveJob.new(blueprint_cell, villager_id)
	return true


## Symmetric un-claim to [method claim_job] (Story building-030, GDD Rule 3 /
## [TR-building-system-054]'s "a villager finishes or abandons its current
## job before claiming another" -- the release half of that contract, which
## [ConstructionTickLoop] never had a counterpart for before this story).
## Transitions [param cell]'s active job's [member BlueprintCell.state] back
## to [constant BlueprintCell.MicroState.PLANNED] and erases it from [member
## _active_jobs] -- any [member _ActiveJob.progress_ticks] already banked is
## discarded with it (this codebase carries no partial-progress-preservation
## concept anywhere; an abandoned-then-reclaimed job restarts from zero,
## mirroring [method claim_job]'s own fresh-[_ActiveJob] construction).
## Returns `false` (no-op, nothing mutated) if [param cell] has no active
## job. [ConstructionJobQueue] is this method's real caller (graceful
## abandon / claim-released-on-abandon, GDD Rule 3/Edge Case 4) -- this class
## itself never decides WHEN to release, only performs the mechanical
## un-claim once asked.
func release_job(cell: Vector3i) -> bool:
	if not _active_jobs.has(cell):
		return false
	var job: _ActiveJob = _active_jobs[cell]
	job.blueprint_cell.state = BlueprintCell.MicroState.PLANNED
	_active_jobs.erase(cell)
	return true


## Whether [param cell] currently has an active (claimed, not yet completed)
## construction job.
func is_job_active(cell: Vector3i) -> bool:
	return _active_jobs.has(cell)


## Wires the occupied-cell defer seam (Story building-030, class doc comment
## point 2b) -- [ConstructionJobQueue]'s real caller, or a test's mocked
## occupied-state stand-in, supplies `Callable(cell: Vector3i) -> bool`.
## Passing an invalid [Callable] (the default, or an explicit `Callable()`)
## restores the pre-030 "never occupied" behavior.
func set_occupancy_predicate(predicate: Callable) -> void:
	_occupancy_predicate = predicate


## Ticks credited so far toward [param cell]'s active job, or `0` if it has
## none (never claimed, or already retired) -- read-only observability
## (e.g. a future UI progress-fill consumer, TR-building-system-069).
func get_progress_ticks(cell: Vector3i) -> int:
	if not _active_jobs.has(cell):
		return 0
	return _active_jobs[cell].progress_ticks


## GDD Formula F3's `cell_build_ticks = base_build_ticks[category]` -- pure
## and stateless, exercisable directly with an arbitrary [param
## ticks_config], mirroring this codebase's established testable-pure-
## function precedent ([method PlacementPick.is_drag], [method
## PlacementPick.derive_attach_cell]).
static func required_ticks_for(category: BlueprintCell.Category, ticks_config: ConstructionTickLoopConfig) -> int:
	match category:
		BlueprintCell.Category.FURNITURE:
			return ticks_config.base_build_ticks_furniture
		_:
			return ticks_config.base_build_ticks_block


## [signal TimeTickSystem.tick] handler -- see class doc comment point 2 for
## why no burst loop/delta/warp handling belongs here. Credits every
## currently-active job exactly one tick. Iterates a SNAPSHOT of [member
## _active_jobs]'s keys (never the live [Dictionary] itself) since a
## completing job is retired from it only AFTER [method _complete_jobs]'s own
## batched write below (Story building-033, class doc comment point 5).
## Story building-030 (class doc comment point 2b): a job whose cell is
## currently occupied per [member _occupancy_predicate] is skipped entirely
## THIS dispatch -- no progress increment, no completion check -- while every
## other active job in the SAME snapshot still credits normally. Every job
## that reaches its `required_ticks_for(...)` total THIS dispatch is
## collected (never written individually) and handed to [method
## _complete_jobs] once the credit pass is done.
func _on_tick() -> void:
	var changes: Dictionary[Vector3i, CellContents] = {}
	var completed_jobs: Array[_ActiveJob] = []
	for cell: Vector3i in _active_jobs.keys():
		if _occupancy_predicate.is_valid() and bool(_occupancy_predicate.call(cell)):
			continue
		var job: _ActiveJob = _active_jobs[cell]
		job.progress_ticks += 1
		if job.progress_ticks >= ConstructionTickLoop.required_ticks_for(job.blueprint_cell.category, config):
			changes[cell] = job.blueprint_cell.contents
			completed_jobs.append(job)
	_complete_jobs(changes, completed_jobs)


## Completes every job in [param completed_jobs] (Story building-033, class
## doc comment point 5) -- issues [param changes] as exactly ONE [method
## VoxelWorldGrid.bulk_write] call (never one [method VoxelWorldGrid.set_cell]
## per job, and never conditionally -- a single completion goes through this
## SAME path), bracketed by [member write_tag]'s self-write exemption tag,
## then transitions every completed [BlueprintCell] to [constant
## BlueprintCell.MicroState.BUILT] and retires it from [member _active_jobs]
## -- AFTER the write, matching this class's pre-033 ordering (the write's
## own signal always observed a completing cell still UnderConstruction).
## Fires [signal construction_completed] with every completed cell, but only
## when [param completed_jobs] is non-empty -- a dispatch with nothing to
## complete emits neither signal, matching [method VoxelWorldGrid.bulk_write]'s
## own "nothing changed, nothing emitted" contract.
func _complete_jobs(changes: Dictionary[Vector3i, CellContents], completed_jobs: Array[_ActiveJob]) -> void:
	if completed_jobs.is_empty():
		return
	write_tag.begin()
	voxel_world.bulk_write(changes)
	write_tag.end()
	var completed_cells: Array[Vector3i] = []
	for job: _ActiveJob in completed_jobs:
		job.blueprint_cell.state = BlueprintCell.MicroState.BUILT
		_active_jobs.erase(job.blueprint_cell.cell)
		completed_cells.append(job.blueprint_cell.cell)
	construction_completed.emit(completed_cells)
