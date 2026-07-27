## The Valley scene (Scene/World Management Story 001, ADR-0001 + ADR-0013).
##
## A thin, self-contained hosting container -- NOT an injected-tier DI module
## in its own right (it owns no [method setup] and takes no part in the boot
## gate, ADR-0005). Its sole responsibility is scene TOPOLOGY: it is the
## child the World Root ([GameWorld]) attaches at boot
## [TR-scene-world-management-034], and it is the structural PARENT every
## Foundation/Core system that needs a stable session-lifetime root attaches
## under [TR-scene-world-management-035] [TR-scene-world-management-036] --
## a hosting relationship, not a data dependency: this class never calls any
## hosted child's [code]setup()[/code]. [GameWorld]'s
## [code]_setup_injected_tier()[/code] remains the ONLY sanctioned call site
## for that (ADR-0005) -- wiring a hosted child into that array, if/when its
## own epic's boot-integration story needs it, is out of this story's scope.
##
## Hosted children landed by this story -- both already exist as
## injected-tier modules per their own epics, and are wired here purely
## structurally (config assigned so the node is inspector-sane; `setup()`
## is deliberately never called from here): [VoxelWorldGrid], [CameraInput].
##
## Time & Tick System is Autoload-tier (ADR-0001; `neues-spiel/CONTRACTS.md`
## §1) -- it is never a scene child of anything, including Valley. This is a
## standing architectural fact predating this story, not a gap it introduces.
##
## Story scene-004 (THE INTEGRATION CROWN, ADR-0001 primary, ADR-0005/0013
## secondary) adds the remaining Foundation/Core tier modules the GDD names
## as hosted systems, now that their own epics have landed real code:
## [VoxelWorldMesher] (`voxel-world` epic, vox-007), the four Building System
## modules [ToolStateMachine]/[PlacementPick]/[CommitPipeline]/
## [ConstructionTickLoop] (`building-system` epic, stories 019-021/029), and
## one [VillagerAi] instance (`villager-ai-behavior` epic, stories 001-009;
## `starting_villager_count` GDD default is 1 at MVP scope -- multi-villager
## spawning is a future world-generation story's job, out of this story's
## scope). Each module's own config Resource IS wired via `Valley.tscn`'s
## Inspector (mirroring the existing [VoxelWorldGrid]/[CameraInput]
## precedent exactly) -- but the Node-typed CROSS-REFERENCES between hosted
## siblings (e.g. [member PlacementPick.camera_input]) are assigned in code,
## by [method _wire_hosted_modules] below, NOT via a `NodePath(...)` value
## authored directly in the scene file: verified against the running engine
## that a hand-authored text `.tscn` assigning a `NodePath` literal to a
## Node-typed `@export` property does NOT auto-resolve to the referenced
## Node at scene instantiation (the property is left `null`) -- only the
## editor's own node-picker workflow produces a resolvable reference this
## way. [method _wire_hosted_modules] runs in [method _ready], mirroring
## [method _wire_villager_population]'s own already-established
## code-wiring precedent, so this remains code-assigned, not Inspector-wired,
## DI -- `setup()` is still never called from here (ADR-0005: the SOLE
## `setup()` call site remains [method GameWorld._setup_injected_tier],
## reached via [method get_injected_tier_modules] below, not a second one on
## this class).
##
## M01 Go/No-Go condition C4 (`production/milestones/milestone-01-review-
## 2026-07-26.md`, criterion #9's "visible in the build" gap) additionally
## hosts [TorchFlicker] (`presentation-experience` epic, story presentation-001
## Sub-scope A) driving a real [OmniLight3D] ("AmbientTorchLight", a structural
## child of this class, not itself an injected-tier module -- a plain light
## has no `setup()`) -- wired exactly like every other hosted sibling above:
## [member TorchFlicker.config] is Resource-typed and Inspector-assigned
## directly on `Valley.tscn` (Story scene-004's own established "a Resource
## export resolves fine from a hand-authored `.tscn`, only Node-typed
## cross-references need code assignment" distinction), while
## [member TorchFlicker.light] (Node-typed) is code-assigned in [method
## _wire_hosted_modules] below, mirroring [member
## VoxelWorldMeshStreamer.grid]/[member VoxelWorldMeshStreamer.mesher]'s own
## precedent exactly. [TorchFlicker] IS appended to [method
## get_injected_tier_modules] (it has a real `setup()`/`is_set_up()` contract,
## [GameWorld] calls it same as every other hosted module) -- this is a
## genuine wiring of already-landed presentation code into the real Valley,
## not a rebuild of it.
##
## **Honest scope note, not silently narrowed**: presentation-001 Sub-scope A
## shipped FOUR ambient elements ([ChimneySmokeEmitter], [TorchFlicker],
## [InteriorClutterPlacer], `foliage_sway.gdshader`) -- only [TorchFlicker] is
## wired here. The other three each require a REAL host system this codebase
## does not yet have in the boot chain: [ChimneySmokeEmitter]'s one gating
## input, [method ChimneySmokeEmitter.set_occupied_lit], has no real
## occupied/lit data source anywhere yet (that class's own doc comment --
## "does not exist yet anywhere in this codebase"), so wiring it here would
## mean driving it from an invented/fake signal, which this story explicitly
## does not do; [InteriorClutterPlacer] needs a real room/building fixture to
## place its scene-authored `clutter_transforms` inside, and no fixture/
## building-interior entity exists yet (Valley boots with an EMPTY
## [VoxelWorldGrid] -- no `generate_terrain()` call anywhere in the boot chain,
## by this class's own long-standing design, a future world-generation
## story's job per this class's already-existing doc comment above); the
## foliage shader needs a real vegetation-placement host over real terrain,
## which the same empty-world fact rules out today. [TorchFlicker] alone needs
## neither a fixture, a room, nor terrain -- only a positioned [Light3D] --
## which is exactly why it is the one component this condition can honestly
## close today; the other three remain the CD's own already-tracked Sub-B/
## wave-2 backlog (`ambient-life-wave-1-evidence.md`), not silently dropped.
##
## Story vox-018 (ADR-0014 primary -- the deferred live-wiring integration
## `VoxelWorldMeshStreamer`'s own class doc comment explicitly named as a
## LATER story's job; ADR-0015 secondary) additionally hosts
## [VoxelWorldMeshStreamer], structurally, exactly like every other hosted
## sibling above -- [method _wire_hosted_modules] code-assigns its
## [member VoxelWorldMeshStreamer.grid]/[member VoxelWorldMeshStreamer.mesher]
## cross-references; `setup()` is still ONLY ever reached via
## [method GameWorld._setup_injected_tier] (this class calls it nowhere).
## [method _process] is this story's ONE new per-frame hook on this class:
## every engine frame it reads the hosted [CameraInput]'s current orbit
## target ([method CameraInput.get_target] -- the SAME ground-plane point
## `tools/camera_sandbox.gd` already mirrors onto its own driven [Camera3D]
## every frame, not the mouse-dependent world-ray/ground-pick, which would
## tie the mesh STREAMING window to wherever the cursor happens to point
## rather than to where the camera itself actually is), converts it to a
## cell via [method VoxelWorldGrid.world_to_cell] (the same conversion
## [PlacementPick] already uses for its own screen-ray pick), and forwards it
## to [method VoxelWorldMeshStreamer.update_view_window] -- the budgeted,
## per-frame streaming step vox-015 built and proved correct in isolation,
## now finally driven by a live, continuously-moving focus point in
## production. The UNBOUNDED initial window build
## ([method VoxelWorldMeshStreamer.build_initial_window], vox-015 AC-3) is
## deliberately NOT called from here -- it must run exactly once, during
## [GameWorld]'s own boot/WIRING sequence, strictly before this class's first
## `_process` call ever lands (so the ~2.6s unbounded build is never
## interleaved with the budgeted per-frame path) -- see
## [method GameWorld._build_initial_voxel_mesh_window] for that call site and
## its own doc comment for the honest note on today's boot-overlay gap.
##
## **The villager population's non-`@export` shared collaborators**
## ([VillagerDecidingScheduler], [VillagerNavGraph]) cannot be Inspector-wired
## -- both are plain `RefCounted`, not `Node`/`Resource` (see each class's own
## doc comment for why). [method _wire_villager_population] performs that DI
## assignment structurally, in [method _ready] -- which fires for this
## instance (and every child already Inspector-wired beneath it, per Godot's
## bottom-up `_ready()` ordering) strictly BEFORE [GameWorld] can ever reach
## [method get_injected_tier_modules]/[method GameWorld._setup_injected_tier]
## for this SAME instance (that call chain only runs from [method
## GameWorld._on_database_settled], itself only reached AFTER [method
## GameWorld._attach_valley] has already returned). This is what satisfies
## [VillagerAi]'s own documented "wiring-order requirement" doc comment:
## [method VillagerNavGraph.subscribe_to_voxel_world] runs here, before any
## [VillagerAi]'s own `setup()` is ever called. Deliberately does NOT call
## [method VillagerNavGraph.build] -- this story adds no world-generation
## step to [GameWorld]'s boot sequence (a fresh grid has no terrain yet, so a
## graph built now would hold zero points; a future world-generation story
## re-derives/patches it once real terrain exists, per that class's own
## documented "idempotent/re-buildable" contract) -- out of this story's
## explicit "no new gameplay features" scope.
##
## Story villager-ai-021 (this revision, GDD Rule 14b /
## [TR-villager-ai-behavior-065]) adds the config-driven STARTING ROSTER
## capability -- [method spawn_starting_roster] -- built on the new
## [VillagerRosterSpawner] library (placement + assembly, see that class's
## own doc comment). [member _villager_ai] (villager_id 0, the pre-existing
## single hosted instance) is completely UNCHANGED by this story -- still
## wired unconditionally by [method _wire_villager_population], still the
## sole hosted villager any pre-existing test/boot path observes. [method
## spawn_starting_roster] is ADDITIVE and deliberately NEVER called from
## [method _ready] -- it mirrors this class's own doc comment paragraph
## above verbatim: exactly the same "a fresh grid has no terrain yet" reason
## [method VillagerNavGraph.build] is deferred to a future world-generation
## story applies here too, and more sharply -- [VoxelWorldGrid]'s own
## chunk residency (ADR-0015) regenerates terrain ASYNCHRONOUSLY, off the
## main thread, over several POST-boot frames, so calling this synchronously
## during [method _ready] would deterministically find zero standable cells
## on every single boot, for a search cost that scales with the bound
## instead of buying a meaningful placement. [method spawn_starting_roster]
## is the ready-to-call, fully-tested surface a future world-generation story
## wires in once real terrain is confirmed resident near the chosen center --
## this story's own explicit scope boundary ("Population growth / arrivals /
## recruitment is Township Progression's job") does not cover WHEN world
## generation itself first runs, only that growth BEYOND the starting roster
## is out of scope.
## Story scene-005 (World genesis in the boot sequence, ADR-0005 primary /
## ADR-0015 primary / ADR-0014 secondary) closes every deferral the paragraphs
## above name. [method GameWorld._run_world_genesis] -- a NEW orchestration
## method on [GameWorld], not this class (this class still owns no `setup()`
## and calls no hosted child's `setup()` itself, per the class doc comment's
## opening hosting-vs-DI distinction) -- now drives, in this load-bearing
## order, during WIRING, strictly before [constant
## GameWorld.BootState.ACTIVE]: the camera's start-focus target ([method
## CameraInput.set_target], the SAME cell everything else below anchors on),
## the boot-window residency drive ([method VoxelWorldGrid.update_residency]
## alternated with [method VoxelWorldGrid.drain_pending_async_reads], bounded
## by a config-driven wall-clock ceiling -- never [method
## VoxelWorldGrid.generate_terrain], the full-extent call this class's own
## class doc comment used to name as never-called and still is), [method
## VoxelWorldGrid.mark_generated], [method build_villager_nav_graph] (closing
## [method VillagerNavGraph.build]'s "a fresh grid has no terrain yet"
## deferral), and finally [method spawn_starting_roster] itself -- which is
## THEREFORE no longer dead code: it is called exactly once per boot, from
## [GameWorld], after real terrain is confirmed resident. [method _process]
## additionally gains the per-frame residency-drive line documented on that
## method itself -- vox-018's own named seam, now cashed.
##
## Story presentation-003 (Villager body view, hit proxy & slice hook; VB-1)
## additionally hosts [VillagerBodyPresenter] -- structural child, exactly
## like every other hosted module above -- wired via [method
## _wire_hosted_modules] with a small anonymous roster-provider [RefCounted]
## ([member _villager_roster_provider]) whose sole member,
## `get_villagers() -> Array[VillagerAi]`, delegates to [method get_villagers]
## (the SAME "one hard-wired villager + spawned roster" list every other
## consumer already reads). [method spawn_starting_roster] additionally
## calls [method VillagerBodyPresenter.refresh] immediately after adding each
## newly-spawned villager, so a real boot (which calls
## [method spawn_starting_roster] exactly once from [method
## GameWorld._run_world_genesis]) produces exactly one [VillagerBodyView] per
## hosted villager, INCLUDING [member _villager_ai] itself (villager_id 0,
## always present, view created by [method VillagerBodyPresenter.setup]'s own
## boot-gated initial pass -- see [GameWorld]'s own `setup()` sweep, appended
## via [method get_injected_tier_modules] below; this class never calls a
## hosted child's `setup()` itself, per the class doc comment's opening
## hosting-vs-DI distinction).
##
## Story scene-006 (Villager need seeding in the boot sequence, ADR-0005
## primary) closes `needs-mood-006`'s own "uncalled in `src/`" gap: [method
## NeedsMood.initialize_villager] is now driven from exactly two call sites,
## both on this class. [method spawn_starting_roster] seeds each villager it
## creates, inline, right where it already assigns `needs_provider`
## (already legal under ADR-0005 -- that method is only ever reached from
## [method GameWorld._run_world_genesis], strictly after every hosted
## module's `setup()` has run). [member _villager_ai] (villager_id 0) needed
## a NEW home: its provider ASSIGNMENT stays in [method
## _wire_villager_population], which [method _ready] calls -- seeding there
## would violate `needs-mood-006`'s own Control Manifest rule ("never in
## `_ready()`"). [method seed_default_villager_needs] is that new home: an
## explicitly-callable method reached ONLY from [method
## GameWorld._run_world_genesis] (duck-typed, mirroring [method
## build_villager_nav_graph]/[method spawn_starting_roster]'s own call-site
## shape) -- [method _ready]/[method _wire_villager_population] remain
## completely UNCHANGED by this story. Both call sites assert [method
## NeedsMood.is_set_up] first (AC-SEED-AFTER-SETUP: seeding must read
## POST-validate/clamp config, never pre-`setup()` state) -- a
## code-enforced ordering guarantee, not merely a documented one.
class_name Valley
extends Node3D

## Hosted Voxel World / Grid Data instance (ADR-0001 injected-tier module;
## `voxel-world` epic, already-landed story vox-001). Structural child only
## -- see the class doc comment's hosting-vs-DI distinction.
@onready var _voxel_world: VoxelWorldGrid = $VoxelWorldGrid

## Hosted Voxel World mesher instance (ADR-0001 injected-tier module;
## `voxel-world` epic, story vox-007). Structural child only -- Story
## scene-004 addition.
@onready var _voxel_world_mesher: VoxelWorldMesher = $VoxelWorldMesher

## Hosted Camera & Input instance (ADR-0001 injected-tier module;
## `camera-input` epic, already-landed story cam-001/002). Structural child
## only -- see [member _voxel_world]'s doc comment.
@onready var _camera_input: CameraInput = $CameraInput

## Hosted Voxel World mesh view-window streamer instance (ADR-0001
## injected-tier module; `voxel-world` epic, story vox-015 landed the
## machinery, story vox-018 wires it live). Structural child only -- see
## [member _voxel_world]'s doc comment; cross-wired to [member _voxel_world]/
## [member _voxel_world_mesher] in [method _wire_hosted_modules], driven every
## frame by [method _process] -- see class doc comment's vox-018 scope note.
@onready var _voxel_world_mesh_streamer: VoxelWorldMeshStreamer = $VoxelWorldMeshStreamer

## Hosted Building System tool state machine instance (ADR-0001 injected-tier
## module; `building-system` epic, story building-019). Structural child
## only -- Story scene-004 addition.
@onready var _tool_state_machine: ToolStateMachine = $ToolStateMachine

## Hosted Building System placement-pick instance (ADR-0001 injected-tier
## module; `building-system` epic, story building-020/021). Structural child
## only -- Story scene-004 addition.
@onready var _placement_pick: PlacementPick = $PlacementPick

## Hosted Building System commit-pipeline instance (ADR-0001 injected-tier
## module; `building-system` epic, story building-021). Structural child
## only -- Story scene-004 addition.
@onready var _commit_pipeline: CommitPipeline = $CommitPipeline

## Hosted Building System construction-tick-loop instance (ADR-0001
## injected-tier module; `building-system` epic, story building-029).
## Structural child only -- Story scene-004 addition.
@onready var _construction_tick_loop: ConstructionTickLoop = $ConstructionTickLoop

## Hosted Villager AI instance -- ONE villager at MVP scope (GDD
## `starting_villager_count` default 1; `villager-ai-behavior` epic, stories
## 001-009). Structural child only -- Story scene-004 addition. See class
## doc comment for the non-`@export` scheduler/nav_graph wiring this class
## performs on top of the plain structural hosting every other child gets.
## Story villager-ai-021: completely UNCHANGED by the new starting-roster
## capability -- still the always-present, unconditionally-wired default
## (villager_id 0); [method get_villagers] reports it first.
@onready var _villager_ai: VillagerAi = $VillagerAi

## Hosted Needs & Mood System instance (ADR-0001 injected-tier module;
## `needs-mood-system` epic, stories 001-008; Story needs-mood-010 -- THE
## CROWN's own production-wiring AC). Structural child only -- see [member
## _voxel_world]'s own hosting-vs-DI distinction. [method
## _wire_villager_population] assigns this SAME instance to every hosted
## [VillagerAi]'s `needs_provider` seam (both [member _villager_ai] and every
## member [method spawn_starting_roster] creates) -- the moment the landed
## nil-safe seam becomes live in the shipped game. This is the ONLY call site
## in `src/` that ever assigns [member VillagerAi.needs_provider].
@onready var _needs_mood: NeedsMood = $NeedsMood

## Tuning config for the whole starting roster (Story villager-ai-021,
## ADR-0002) -- Resource-typed, Inspector-assigned directly on `Valley.tscn`
## (Story scene-004's own established "a Resource export resolves fine from
## a hand-authored `.tscn`" distinction). Deliberately the SAME underlying
## `.tres` instance [member _villager_ai]'s own `config` field already
## points at (both wired from the identical ext_resource in `Valley.tscn`) --
## one shared Resource, read (never per-instance mutated) by every roster
## member [method spawn_starting_roster] creates.
@export var villager_ai_config: VillagerAIConfig

## Every [VillagerAi] instance [method spawn_starting_roster] has created so
## far (Story villager-ai-021) -- additional to, and villager_id-numbered
## starting after, [member _villager_ai]'s own `0`. Empty until that method
## is first called (deliberately NOT from [method _ready] -- see that
## method's own doc comment).
var _spawned_villagers: Array[VillagerAi] = []

## Shared, population-wide unstuck-rescue telemetry accumulator (Story
## villager-ai-021, [VillagerUnstuckTelemetry]'s own doc comment: "the
## roster is its natural owner") -- ONE instance for [member _villager_ai]
## and every member of [member _spawned_villagers] alike, mirrors [member
## _villager_nav_graph]/[member _villager_deciding_scheduler]'s own "one
## shared instance, not duplicated per villager" precedent.
var _villager_unstuck_telemetry: VillagerUnstuckTelemetry = null

## Hosted ambient torch/lantern light fixture (M01 condition C4, see class
## doc comment). Structural child only, mirrors [member _voxel_world]'s own
## hosting-vs-DI distinction -- a plain [OmniLight3D] has no `setup()` of its
## own; [member _torch_flicker] is the actual injected-tier module that
## drives its `light_energy`.
@onready var _ambient_torch_light: Light3D = $AmbientTorchLight

## Hosted [TorchFlicker] instance (M01 condition C4; `presentation-experience`
## epic, story presentation-001 Sub-scope A). Structural child only -- see
## class doc comment for the full wiring rationale and the honest scope note
## on why the other three Sub-scope A elements are NOT hosted here.
@onready var _torch_flicker: TorchFlicker = $TorchFlicker

## Hosted [VillagerBodyPresenter] instance (Presentation Experience story
## presentation-003). Structural child only -- mirrors [member
## _torch_flicker]'s own "a real injected-tier module, `setup()` reached
## only via [GameWorld]'s boot-gated sweep" precedent. [member
## VillagerBodyPresenter.roster_provider] is code-assigned in [method
## _wire_hosted_modules] to [member _villager_roster_provider] below.
@onready var _villager_body_presenter: VillagerBodyPresenter = $VillagerBodyPresenter

## Small anonymous roster-provider [RefCounted] (Story presentation-003) --
## its sole member, `get_villagers() -> Array[VillagerAi]`, delegates to
## [method get_villagers] (the SAME "one hard-wired villager + spawned
## roster" list every other consumer already reads). Exists purely so
## [VillagerBodyPresenter]'s duck-typed `roster_provider` seam has a live
## object to call without holding a direct `Valley` reference of its own
## (mirrors this codebase's established small-mock/small-adapter precedent).
class _ValleyRosterProvider:
	var _valley: Valley = null

	func _init(valley: Valley) -> void:
		_valley = valley

	func get_villagers() -> Array[VillagerAi]:
		return _valley.get_villagers()

var _villager_roster_provider: _ValleyRosterProvider = null

## The shared, population-wide [VillagerNavGraph] instance [method
## _wire_villager_population] constructs -- exposed read-only for tests/
## future world-generation stories that need to (re)build it once real
## terrain exists.
var _villager_nav_graph: VillagerNavGraph = null

## The shared, population-wide [VillagerDecidingScheduler] instance [method
## _wire_villager_population] constructs -- exposed read-only, mirrors
## [member _villager_nav_graph].
var _villager_deciding_scheduler: VillagerDecidingScheduler = null


func _ready() -> void:
	_wire_hosted_modules()
	_wire_villager_population()


## Code-assigned DI for the Node-typed cross-references between hosted
## Building System / Voxel World siblings -- see class doc comment for why
## this is code-wired rather than authored as a `NodePath(...)` value
## directly in `Valley.tscn`. Each target's OWN config Resource dependency
## (if any) is still wired via that scene file's Inspector; only the
## cross-sibling Node references are assigned here.
func _wire_hosted_modules() -> void:
	_voxel_world_mesher.grid = _voxel_world
	_voxel_world_mesh_streamer.grid = _voxel_world
	_voxel_world_mesh_streamer.mesher = _voxel_world_mesher
	_placement_pick.camera_input = _camera_input
	_placement_pick.voxel_world = _voxel_world
	_placement_pick.tool_state_machine = _tool_state_machine
	_commit_pipeline.placement_pick = _placement_pick
	_commit_pipeline.voxel_world = _voxel_world
	_construction_tick_loop.voxel_world = _voxel_world
	_villager_ai.voxel_world = _voxel_world
	_torch_flicker.light = _ambient_torch_light
	_villager_roster_provider = _ValleyRosterProvider.new(self)
	_villager_body_presenter.roster_provider = _villager_roster_provider


## Story vox-018's ONE new per-frame hook (class doc comment) -- reads the
## hosted [CameraInput]'s CURRENT orbit target every engine frame, converts
## it to a cell, and drives the hosted [VoxelWorldMeshStreamer]'s budgeted
## per-frame streaming step. Safe to run from this class's very first
## processed frame onward: by the time any node's `_process` callback can
## fire, [GameWorld]'s entire boot sequence (`_attach_valley` ->
## `_gather_valley_tier_modules` -> `_setup_injected_tier` ->
## [method GameWorld._build_initial_voxel_mesh_window]) has already run
## synchronously to completion within the SAME call stack that attached this
## instance to the tree -- so [member _voxel_world_mesh_streamer]'s DI is
## wired, every hosted module's `setup()` has already run, and the UNBOUNDED
## initial window build has already happened exactly once, before this
## method is ever invoked for the first time.
## Story scene-005 (World genesis in the boot sequence, AC-NO-SYNC-IO-IN-
## FRAME-PATH): drives [member _voxel_world]'s BUDGETED residency window
## (never [method VoxelWorldGrid.drain_pending_async_reads]/[method
## VoxelWorldGrid.wait_for_async_residency_idle] -- both grep-guarded absent
## from any `_process`/`_physics_process` call graph, tests/boot-genesis-only
## synchronization points) every frame, BEFORE the pre-existing mesh
## view-window streaming call -- vox-018's own explicitly-named seam ("a
## shared per-frame focus-drive call site is the natural home for both").
## The settlement anchor is recomputed each frame from [method
## VillagerRosterSpawner.world_center_cell] -- a pure, cheap function of
## [member _voxel_world]'s own config, so this is always the SAME start-focus
## cell world genesis anchored on ([method GameWorld._run_world_genesis]),
## with no separate stored-anchor seam to keep in sync.
func _process(_delta: float) -> void:
	var focus_cell: Vector3i = VoxelWorldGrid.world_to_cell(_camera_input.get_target())
	var settlement_anchor_cell: Vector3i = VillagerRosterSpawner.world_center_cell(_voxel_world.config)
	_voxel_world.update_residency(focus_cell, settlement_anchor_cell)
	_voxel_world_mesh_streamer.update_view_window(focus_cell)


## Performs the villager population's non-`@export` DI assignment -- see
## class doc comment for the full rationale and the load-bearing ordering
## guarantee this relies on. Idempotent-safe to call more than once (a fresh
## [VillagerDecidingScheduler]/[VillagerNavGraph] pair is harmless to
## construct twice for this story's single-villager population -- a future
## multi-villager spawning story owns the "exactly one shared pair for the
## whole population" bookkeeping this method's own single-villager shape
## does not yet need to enforce).
func _wire_villager_population() -> void:
	_villager_deciding_scheduler = VillagerDecidingScheduler.new()
	_villager_nav_graph = VillagerNavGraph.new()
	_villager_unstuck_telemetry = VillagerUnstuckTelemetry.new()
	_villager_ai.scheduler = _villager_deciding_scheduler
	_villager_ai.nav_graph = _villager_nav_graph
	_villager_ai.unstuck_telemetry = _villager_unstuck_telemetry
	_villager_ai.needs_provider = _needs_mood
	_villager_nav_graph.subscribe_to_voxel_world(_voxel_world, _villager_ai)


## Returns the hosted Voxel World / Grid Data instance.
func get_voxel_world() -> VoxelWorldGrid:
	return _voxel_world


## Returns the hosted Voxel World mesher instance.
func get_voxel_world_mesher() -> VoxelWorldMesher:
	return _voxel_world_mesher


## Returns the hosted Camera & Input instance.
func get_camera_input() -> CameraInput:
	return _camera_input


## Returns the hosted Voxel World mesh view-window streamer instance
## (story vox-018).
func get_voxel_world_mesh_streamer() -> VoxelWorldMeshStreamer:
	return _voxel_world_mesh_streamer


## Returns the hosted Building System tool state machine instance.
func get_tool_state_machine() -> ToolStateMachine:
	return _tool_state_machine


## Returns the hosted Building System placement-pick instance.
func get_placement_pick() -> PlacementPick:
	return _placement_pick


## Returns the hosted Building System commit-pipeline instance.
func get_commit_pipeline() -> CommitPipeline:
	return _commit_pipeline


## Returns the hosted Building System construction-tick-loop instance.
func get_construction_tick_loop() -> ConstructionTickLoop:
	return _construction_tick_loop


## Returns the hosted Villager AI instance.
func get_villager_ai() -> VillagerAi:
	return _villager_ai


## Returns the hosted Needs & Mood System instance (Story needs-mood-010).
func get_needs_mood() -> NeedsMood:
	return _needs_mood


## Returns the shared, population-wide [VillagerNavGraph] instance [method
## _wire_villager_population] constructs (fulfilling the "exposed read-only
## for... a future world-generation story" promise [member
## _villager_nav_graph]'s own doc comment already made -- this IS that story).
func get_villager_nav_graph() -> VillagerNavGraph:
	return _villager_nav_graph


## Default region size used ONLY when [member villager_ai_config] is unwired
## (mirrors [method spawn_starting_roster]'s own established "`if config !=
## null` else a documented literal default" precedent for this exact optional
## dependency) -- [constant VillagerAIConfig.NAV_REGION_SIZE_MIN], the GDD's
## own conservative floor, never an invented literal.
const DEFAULT_NAV_REGION_SIZE: int = VillagerAIConfig.NAV_REGION_SIZE_MIN


## Config-driven nav-graph build (Story scene-005, AC-NAV-GRAPH-BUILT) --
## builds the shared [VillagerNavGraph] over a [param region_size] x
## [param region_size] window centered on [param region_center], reading
## [member villager_ai_config]'s `nav_region_size` (never a literal, ADR-0002)
## with the same optional-config fallback [method spawn_starting_roster]
## already establishes. [member _villager_ai] (villager_id 0, always present)
## is the `predicate_source` -- [VillagerNavGraph.build]'s own predicate reads
## are instance-independent (BV-4 ruling: every [VillagerAi] instance answers
## identically), so which hosted villager supplies them is immaterial; this is
## the SAME predicate_source shape [VillagerNavGraph.subscribe_to_voxel_world]
## already uses in [method _wire_villager_population]. Called from [method
## GameWorld._run_world_genesis], AFTER the boot-window residency drive has
## made real terrain resident (this class never calls this on its own --
## exactly [VillagerNavGraph.build]'s own pre-existing "a fresh grid has no
## terrain yet" deferral this story closes).
func build_villager_nav_graph(region_center: Vector3i) -> void:
	var region_size: int = DEFAULT_NAV_REGION_SIZE
	if villager_ai_config != null:
		region_size = villager_ai_config.nav_region_size
	_villager_nav_graph.build(_voxel_world, _villager_ai, region_center, region_size)


## Seeds [member _villager_ai] (villager_id 0, the always-present default)
## through [method NeedsMood.initialize_villager] -- Story scene-006's own
## new home for this call, since the provider ASSIGNMENT for this villager
## stays in [method _wire_villager_population] (unchanged, still [method
## _ready]'s own call graph) while the SEEDING moves here: an explicitly-
## callable method reached ONLY from [method GameWorld._run_world_genesis]
## (duck-typed, mirroring [method build_villager_nav_graph]/[method
## spawn_starting_roster]'s own call-site shape) -- never from [method
## _ready] (AC-SEED-NOT-FROM-READY, ADR-0005, `needs-mood-006`'s own Control
## Manifest "never in `_ready()`"). Asserts [method NeedsMood.is_set_up]
## first (AC-SEED-AFTER-SETUP) -- [method GameWorld._run_world_genesis] only
## ever runs after [method GameWorld._setup_injected_tier]'s own `setup()`
## sweep has already completed, so this assert should never trip in
## production; it exists to make the ordering constraint fail LOUDLY rather
## than silently seed from unvalidated config if a future call site ever
## violates it. Idempotent by [method NeedsMood.initialize_villager]'s own
## landed contract -- calling this twice never resets an already-decayed
## value.
func seed_default_villager_needs() -> void:
	assert(
		_needs_mood.is_set_up(),
		"Valley.seed_default_villager_needs called before NeedsMood.setup() has completed"
	)
	_needs_mood.initialize_villager(_villager_ai.villager_id)


## Returns every hosted [VillagerAi] instance (Story villager-ai-021) --
## [member _villager_ai] (the always-present default, villager_id 0) first,
## then any members [method spawn_starting_roster] has added so far, in the
## order they were spawned.
func get_villagers() -> Array[VillagerAi]:
	var all: Array[VillagerAi] = [_villager_ai]
	all.append_array(_spawned_villagers)
	return all


## Config-driven starting-roster spawn (Story villager-ai-021, GDD Rule 14b /
## [TR-villager-ai-behavior-065]) -- reads [member villager_ai_config]'s
## `starting_villager_count`, selects that many valid standable cells near
## the world center via [method VillagerRosterSpawner.select_starting_cells],
## and assembles + hosts one new [VillagerAi] per selected cell via [method
## VillagerRosterSpawner.assemble_roster] (DI-wired: config/voxel_world/
## scheduler/nav_graph/unstuck_telemetry, `villager_id` continuing after
## every villager already hosted, `current_cell`/`_from_cell`/`_to_cell` on
## its assigned cell). Adds each as a REAL child of this Valley (so its own
## [method VillagerAi._process] visual-lerp runs every frame in production,
## mirroring every other hosted module) and calls its `setup()` directly --
## a sanctioned, on-demand call site distinct from [GameWorld]'s own
## boot-gate sweep (ADR-0005: that rule governs the ONE-TIME INITIAL sweep
## only; a villager assembled well after boot, once real terrain actually
## exists, has no other entry point to reach `setup()` from).
##
## Deliberately NEVER called from [method _ready] -- see class doc comment's
## Story villager-ai-021 paragraph for the full "terrain pages in
## asynchronously, post-boot" rationale this mirrors from [method
## VillagerNavGraph.build]'s own pre-existing deferral. Returns however many
## villagers were actually placed -- fewer than `starting_villager_count` (or
## even zero) is a valid, deterministic outcome when the world does not yet
## have enough standable cells near the center within [constant
## VillagerRosterSpawner.MAX_SEARCH_RADIUS] (never a crash, never a partial/
## inconsistent villager).
func spawn_starting_roster() -> Array[VillagerAi]:
	# Story scene-006 (AC-SEED-AFTER-SETUP): checked FIRST, before any
	# placement/assembly work runs -- a villager is never even constructed
	# (let alone left as an unhosted orphan node) if this guard trips. Makes
	# the ordering constraint fail loudly rather than silently seed from
	# unvalidated config if a future call site ever violates it.
	assert(
		_needs_mood.is_set_up(),
		"Valley.spawn_starting_roster seeding a villager before NeedsMood.setup() has completed"
	)
	var center_cell: Vector3i = VillagerRosterSpawner.world_center_cell(_voxel_world.config)
	var count: int = 1
	if villager_ai_config != null:
		count = villager_ai_config.starting_villager_count
	var cells: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(
		_voxel_world, center_cell, count
	)
	var next_id: int = 1 + _spawned_villagers.size()
	var new_villagers: Array[VillagerAi] = VillagerRosterSpawner.assemble_roster(
		_voxel_world,
		villager_ai_config,
		_villager_deciding_scheduler,
		_villager_nav_graph,
		_villager_unstuck_telemetry,
		cells,
		next_id,
	)
	for villager: VillagerAi in new_villagers:
		villager.needs_provider = _needs_mood
		# Story scene-006 (AC-SEED-EVERY-ROSTER-MEMBER): seed this villager's
		# needs through the landed [method NeedsMood.initialize_villager]
		# surface, right where its provider is assigned -- already legal here
		# (this method is only ever reached from [method
		# GameWorld._run_world_genesis], strictly after every hosted module's
		# `setup()` has run; see [method seed_default_villager_needs]'s own
		# doc comment for why villager_id 0 needed a DIFFERENT call site
		# instead of this one). The ordering guard already ran above, before
		# any villager in this loop was even assembled.
		_needs_mood.initialize_villager(villager.villager_id)
		add_child(villager)
		villager.setup()
		_spawned_villagers.append(villager)
	# Story presentation-003: re-sync the hosted body-view set so every newly
	# spawned villager gets a real VillagerBodyView -- [member
	# _villager_body_presenter]'s own `setup()` (boot-gated, [GameWorld]'s own
	# sweep) already created a view for [member _villager_ai] (villager_id 0)
	# before any roster spawn can run; this call only ADDS views for the
	# entries this method just created, never touching that one.
	_villager_body_presenter.refresh()
	return new_villagers


## Returns the hosted ambient torch/lantern light fixture (M01 condition C4).
func get_ambient_torch_light() -> Light3D:
	return _ambient_torch_light


## Returns the hosted [TorchFlicker] instance (M01 condition C4).
func get_torch_flicker() -> TorchFlicker:
	return _torch_flicker


## Returns the hosted [VillagerBodyPresenter] instance (Story
## presentation-003).
func get_villager_body_presenter() -> VillagerBodyPresenter:
	return _villager_body_presenter


## The GameWorld assembly seam (Story scene-004): every hosted tier module
## this Valley owns, in the load-bearing DI order [method
## GameWorld._setup_injected_tier] will call `setup()` in (Voxel World grid,
## then its mesher, then its mesh view-window streamer (story vox-018 --
## placed here so both its `grid`/`mesher` dependencies have already
## completed their own `setup()` by the time this streamer's runs), then
## Camera & Input, then the four Building System modules, then Villager AI).
## Story needs-mood-010 appends [NeedsMood]; story presentation-003 appends
## [VillagerBodyPresenter] LAST -- its own `setup()` reads [method
## get_villagers] (already valid: [member _villager_ai] exists from this
## same `_ready()` pass), creating that villager's initial
## [VillagerBodyView] before any roster spawn can ever run.
## [GameWorld] calls this exactly once, from
## [method GameWorld._on_database_settled], AFTER [method
## GameWorld._attach_valley] has already attached this instance -- appending
## the result to its own [member GameWorld.injected_tier_modules] array
## rather than requiring these dynamically-instantiated (`PackedScene`)
## nodes to somehow be Inspector-wired directly onto `GameWorld.tscn` itself
## (structurally impossible -- this Valley instance does not exist in that
## scene file's own saved node tree; it is instantiated at runtime). This
## class still never calls `setup()` on any of these itself (see class doc
## comment's hosting-vs-DI distinction) -- it only reports the list.
func get_injected_tier_modules() -> Array[Node]:
	return [
		_voxel_world,
		_voxel_world_mesher,
		_voxel_world_mesh_streamer,
		_camera_input,
		_tool_state_machine,
		_placement_pick,
		_commit_pipeline,
		_construction_tick_loop,
		_needs_mood,
		_villager_ai,
		_torch_flicker,
		_villager_body_presenter,
	]
