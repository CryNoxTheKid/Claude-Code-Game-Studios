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
@onready var _villager_ai: VillagerAi = $VillagerAi

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
func _process(_delta: float) -> void:
	var focus_cell: Vector3i = VoxelWorldGrid.world_to_cell(_camera_input.get_target())
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
	_villager_ai.scheduler = _villager_deciding_scheduler
	_villager_ai.nav_graph = _villager_nav_graph
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


## The GameWorld assembly seam (Story scene-004): every hosted tier module
## this Valley owns, in the load-bearing DI order [method
## GameWorld._setup_injected_tier] will call `setup()` in (Voxel World grid,
## then its mesher, then its mesh view-window streamer (story vox-018 --
## placed here so both its `grid`/`mesher` dependencies have already
## completed their own `setup()` by the time this streamer's runs), then
## Camera & Input, then the four Building System modules, then Villager AI).
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
		_villager_ai,
	]
