## Building System's DDA placement pick + surface-aware targeting + picked-
## block highlight (Story building-020, ADR-0004 primary: zero-physics manual
## DDA grid-walk; ADR-0014 §4 secondary: the `extra_solid` ghost-anchoring
## overlay hook; ADR-0010 secondary: the drag-ownership `_unhandled_input()`
## press -> `_input()` release switch).
##
## Owns the pipeline's PICK half only (GDD Core Rule 2/[TR-building-system-002]):
## the current mouse world-ray ([CameraInput.get_world_ray]) is forwarded to
## Voxel World's manual DDA raycast ([VoxelWorldGrid.raycast_cells]) -- no
## collider of any kind is ever involved, so this class is structurally
## incapable of hitting a villager (ADR-0004 Decision, "Building System's own
## placement pick calls only step 1"). Ghost preview RENDERING of the full
## pending shape (Story 023) and the commit pipeline's click-vs-drag
## discrimination + actual write (Story 021, F4, NOT committed this sprint per
## the Sprint 5 QA plan) are both explicitly out of scope here -- this class
## never calls [method VoxelWorldGrid.set_cell]/[method VoxelWorldGrid.bulk_write]
## anywhere; the pick stays side-effect-free by construction.
##
## Injected-tier module (ADR-0001): [member camera_input]/[member voxel_world]/
## [member tool_state_machine]/[member config] are wired via a scene file's
## Inspector in production (once a future scene-assembly story attaches this
## node, mirroring [ToolStateMachine]'s own "wired once Story 001 assembles
## Building System into `GameWorld.tscn`" precedent), or assigned directly in
## a headless test; all wiring/validation lives in [method setup], never
## `_ready()`.
##
## **Surface-aware targeting** (Core Rule 3, [TR-building-system-043]):
## [method resolve_pick]'s returned [RaycastHitResult] carries the raw hit
## cell + entry-face normal; [method get_attach_cell] derives the adjacent
## empty face cell (placement target) and [method get_replace_cell] returns
## the hit cell itself (removal target) -- both are pure one-line derivations
## ([method derive_attach_cell]) a future per-tool story (024-028) selects
## between per its own attach-vs-replace mode; this class does not know which
## of the two a given tool wants.
##
## **Working-plane lock** (Core Rule 3, AC8, [TR-building-system-043]): a
## press ([method _unhandled_input]) resolves the initial pick and locks
## [member _locked_plane_cell_y] to the ATTACH cell's height (the surface the
## drag will build ON, not the picked block's own height) for the drag's
## entire duration -- every subsequent pick while Dragging goes through
## [method derive_drag_plane_hit] instead of a fresh grid raycast, so the
## plane never drifts even when the cursor strays off the original block's
## edge into open air at that same height (the QA plan's named edge case).
## [method derive_drag_plane_hit] is a pure ray/horizontal-plane intersection
## (mirrors [method CameraInput.derive_ground_plane_intersection]'s
## established shape, generalized from the fixed ground plane to an arbitrary
## locked height) -- it never re-touches [VoxelWorldGrid] at all, so "off the
## edge" cells resolve geometrically even where nothing is actually built yet.
##
## **Ghost-anchored pick predicate** (ADR-0014 §4): [member _extra_solid],
## set via [method set_extra_solid], is forwarded UNCHANGED to every
## [method VoxelWorldGrid.raycast_cells] call -- this class adds no predicate
## of its own and no second pick path; wiring a real predicate against
## Building System's own project/blueprint cell data is a future story's job
## once that data model exists in code (none does yet -- only
## [ToolStateMachine] has landed as of this story).
##
## **Picked-block highlight** ([TR-building-system-092]): a single pooled
## `MeshInstance3D` (mirrors ADR-0014's established "pooled MeshInstance3D +
## `material_override` tint" ghost-rendering precedent, scaled down to ONE
## instance since only one cell is ever highlighted at a time) -- visible only
## while [ToolStateMachine] is ToolArmed/Dragging AND the current pick is a
## hit; overlay presentation only, never written into any committed-block
## material (Control Manifest: "State colors never render on world
## geometry"). The highlight's automated proof is therefore necessarily
## partial: [method is_highlight_visible]/[method get_highlight_world_position]
## are headlessly assertable (a property, not a rendered pixel); the actual
## visual result is ADVISORY manual/screenshot evidence per the Sprint 5 QA
## plan, deferred rather than skipped (this story's BLOCKING evidence is the
## pick-geometry unit test + the zero-physics grep).
##
## **Hover-pick guardrail** (Control Manifest: "hover picking is O(1) read;
## runs per-frame only while a tool is armed"): [method _process] is toggled
## via [method Node.set_process] on every [signal ToolStateMachine.state_changed]
## (mirrors [CameraInput]'s own cam-007 "disable when idle" precedent) rather
## than merely no-op'd internally, so the guardrail holds by construction, not
## just by convention.
##
## **Drag-ownership input switch** (ADR-0010 §3, this story's explicit scope):
## a press reaching [method _unhandled_input] while ToolArmed with a VALID
## pick calls [method ToolStateMachine.start_drag] and switches release-
## listening to [method _input] via [method Node.set_process_input] for the
## drag's duration; the release reaching [method _input] calls
## [method ToolStateMachine.complete_drag], claims the event via
## [method Viewport.set_input_as_handled], and reverts to
## [method _unhandled_input]-only listening -- mirroring [ToolStateMachine]'s
## own doc-comment precedent and the ADR's Key Interfaces pseudocode exactly.
## A press with NO valid pick is a no-op (never enters Dragging -- there is no
## plane to lock and nothing for a later commit to anchor to); this mirrors
## story-021's own "no valid pick is a no-op" edge case (AC38) applied at this
## story's boundary, one story early, since a driveless Dragging state would
## be meaningless. Click-vs-drag discrimination (GDD Formula F4,
## `cursor_travel_px` vs `drag_threshold_px`) and the actual commit are
## explicitly Story 021's scope (not committed this sprint per the Sprint 5
## QA plan) -- this class only owns the mechanical SM transition + plane lock,
## never F4 itself and never a write. Building UI's hover-suppression flag
## (ADR-0010 Decision §2) is not yet checked here -- no Building UI code exists
## in this codebase yet to check against; a future story wires that gate in
## once Building UI lands, without a second input-routing mechanism.
class_name PlacementPick
extends Node

## Opaque InputMap action this class listens to directly (button_index 1,
## `project.godot`) -- deliberately NOT routed through [CameraInput]'s
## [signal CameraInput.action_fired] passthrough, which only forwards the
## PRESS half of an action and can never report a release; the ADR-0010 §3
## drag-ownership switch needs both halves, so this class listens to the raw
## [InputEvent] directly, exactly like [CameraInput]'s own established
## direct-[InputEvent]-listening precedent for its OWN owned actions (Q/E,
## mouse-wheel).
const BUILD_PLACE_ACTION: StringName = &"build_place"

## Fires whenever [method resolve_pick]'s result actually changes (hit flag,
## cell, or normal) -- never a redundant re-fire for an unchanged pick held
## across multiple frames, mirroring [ToolStateMachine.state_changed]'s
## "only on actual change" precedent. A future ghost-preview story (023) can
## consume this without polling every frame itself.
signal pick_changed(result: RaycastHitResult)

## Injected-tier dependency (ADR-0001) -- the sole producer of the mouse
## world-ray this class forwards to [member voxel_world]'s DDA raycast
## [TR-camera-input-036].
@export var camera_input: CameraInput

## Injected-tier dependency (ADR-0001) -- owns the manual DDA raycast
## ([method VoxelWorldGrid.raycast_cells]) this class's entire pick path is
## built on; never any physics API.
@export var voxel_world: VoxelWorldGrid

## Injected-tier dependency (ADR-0001) -- the four-state tool machine (Story
## building-019) this class drives via [method ToolStateMachine.start_drag]/
## [method ToolStateMachine.complete_drag] and gates its own hover-pick/
## highlight behavior against.
@export var tool_state_machine: ToolStateMachine

## Tuning config dependency (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: PlacementPickConfig

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## The most recent [method resolve_pick] result -- an explicit miss
## ([RaycastHitResult.new(false)]) until the first resolution, mirroring
## [RaycastHitResult]'s own "explicit hit flag, never a bare sentinel"
## precedent.
var _current_pick: RaycastHitResult = RaycastHitResult.new(false)

## True while a drag's working plane is locked (Dragging, AC8) -- set by
## [method _unhandled_input] on a valid press, cleared by [method _input] on
## release.
var _has_locked_plane: bool = false

## The locked working-plane cell height (AC8) -- meaningless while
## [member _has_locked_plane] is false. Set to the ATTACH cell's Y (the
## surface a drag builds ON), never the picked block's own Y -- see class doc
## comment.
var _locked_plane_cell_y: int = 0

## Ghost-anchored pick predicate overlay (ADR-0014 §4), set via
## [method set_extra_solid] -- forwarded unchanged to every
## [method VoxelWorldGrid.raycast_cells] call. Default `Callable()` (invalid)
## matches that method's own "simply skipped" contract.
var _extra_solid: Callable = Callable()

## The single pooled highlight overlay node (TR-building-system-092) -- see
## class doc comment. Created once in [method setup] via
## [method _ensure_highlight_mesh]; never re-created afterward.
var _highlight_mesh: MeshInstance3D = null


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts every
## dependency was wired, applies ADR-0002's clamp+warn policy to
## [member config], creates the highlight overlay node, connects to
## [signal ToolStateMachine.state_changed] to toggle [method Node.set_process]
## per the hover-pick guardrail (see class doc comment), and initializes
## input-processing state to match [member tool_state_machine]'s CURRENT state
## (so a `setup()` call while a tool happens to already be armed does not
## leave hover-picking disabled until the next state change).
func setup() -> void:
	assert(camera_input != null, "PlacementPick.camera_input not wired")
	assert(voxel_world != null, "PlacementPick.voxel_world not wired")
	assert(tool_state_machine != null, "PlacementPick.tool_state_machine not wired")
	assert(config != null, "PlacementPick.config not wired")
	for issue: String in config.validate():
		push_warning(issue)
	_ensure_highlight_mesh()
	if not tool_state_machine.state_changed.is_connected(_on_tool_state_changed):
		tool_state_machine.state_changed.connect(_on_tool_state_changed)
	_apply_process_state_for(tool_state_machine.get_state())
	set_process_input(false)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Sets the ghost-anchored pick predicate overlay (ADR-0014 §4) -- see
## [member _extra_solid].
func set_extra_solid(predicate: Callable) -> void:
	_extra_solid = predicate


## Returns the most recent [method resolve_pick] result.
func get_current_pick() -> RaycastHitResult:
	return _current_pick


## Surface-aware ATTACH target (Core Rule 3): the empty cell adjacent to the
## current pick's hit face -- meaningless when [method get_current_pick] is a
## miss. See [method derive_attach_cell].
func get_attach_cell() -> Vector3i:
	return PlacementPick.derive_attach_cell(_current_pick.cell, _current_pick.normal)


## Surface-aware REPLACE target (Core Rule 3): the picked cell itself --
## meaningless when [method get_current_pick] is a miss.
func get_replace_cell() -> Vector3i:
	return _current_pick.cell


## Whether the highlight overlay is CURRENTLY visible -- a headlessly
## assertable property proxy for TR-building-system-092's visual contract
## (see class doc comment on the highlight's necessarily-partial automated
## proof).
func is_highlight_visible() -> bool:
	return _highlight_mesh != null and _highlight_mesh.visible


## The highlight overlay's current world-space position -- meaningless while
## [method is_highlight_visible] is false. Reads [member Node3D.position]
## (LOCAL, not [member Node3D.global_position]) -- see [method _update_highlight]'s
## doc comment for why this is the effective world position for this node.
func get_highlight_world_position() -> Vector3:
	return _highlight_mesh.position


## Forwards [member camera_input]'s CURRENT mouse world-ray to
## [method resolve_pick] -- the real per-frame runtime entry point (see
## [method _process]). Test suites needing exact control over the picked
## geometry call [method resolve_pick] directly with an explicit ray instead
## (this project's established direct-method-call test convention -- no live
## [CameraInput]/[Viewport] needed to prove pick geometry).
func update_pick() -> RaycastHitResult:
	var ray: WorldRay = camera_input.get_world_ray()
	return resolve_pick(ray.origin, ray.direction)


## Resolves a pick from an EXPLICIT ray -- the instance-level core both
## [method update_pick] (camera-driven) and the input handlers funnel
## through. Dispatches to [method derive_drag_plane_hit] (Dragging with a
## locked plane, AC8) or a direct [method VoxelWorldGrid.raycast_cells] call
## (hover picking, ToolArmed -- or Dragging before any plane was locked, which
## should not occur in normal operation but degrades to a plain raycast
## rather than crashing); an Idle/Suspended state always resolves to an
## explicit miss (no tool armed, nothing to pick). Emits
## [signal pick_changed] via [method _set_pick] only when the result actually
## changes.
func resolve_pick(ray_origin: Vector3, ray_direction: Vector3) -> RaycastHitResult:
	assert(is_set_up(), "PlacementPick.resolve_pick called before setup()")
	var state: ToolStateMachine.State = tool_state_machine.get_state()
	var result: RaycastHitResult
	if state == ToolStateMachine.State.DRAGGING and _has_locked_plane:
		result = PlacementPick.derive_drag_plane_hit(ray_origin, ray_direction, _locked_plane_cell_y)
	elif state == ToolStateMachine.State.TOOL_ARMED or state == ToolStateMachine.State.DRAGGING:
		result = voxel_world.raycast_cells(ray_origin, ray_direction, config.max_pick_distance, _extra_solid)
	else:
		result = RaycastHitResult.new(false)
	_set_pick(result)
	return _current_pick


## Pure surface-aware ATTACH derivation (Core Rule 3, [TR-building-system-043]):
## the empty cell adjacent to a hit face is simply the hit cell offset by its
## own entry-face normal. Stateless -- exercisable directly with arbitrary
## values, mirroring [method CameraInput.derive_position]'s established
## testable-pure-function shape.
static func derive_attach_cell(hit_cell: Vector3i, normal: Vector3i) -> Vector3i:
	return hit_cell + normal


## Pure locked-working-plane pick (Core Rule 3, AC8): intersects
## [param ray_origin]/[param ray_direction] with the HORIZONTAL plane through
## [param locked_plane_cell_y]'s cell center (mirrors [method CellContents]-
## adjacent [method VoxelWorldGrid.cell_to_world]'s own "+0.5 cell center"
## convention, avoiding boundary-precision ambiguity at an exact cell edge),
## then floors the intersection's X/Z to a cell coordinate while FORCING its Y
## back to [param locked_plane_cell_y] exactly (never re-derived from the
## intersection's own Y, which is only ever infinitesimally off due to float
## precision at the plane itself). Never touches [VoxelWorldGrid] -- a locked-
## plane pick resolves purely geometrically even for cells with nothing built
## there yet (dragging off the original block's edge into open air at the
## same height, the QA plan's named edge case, still returns a valid cell on
## the SAME plane). Returns an explicit miss ([RaycastHitResult.new(false)])
## only when the ray is parallel to the plane or points away from it --
## mirrors [method CameraInput.derive_ground_plane_intersection]'s identical
## miss contract, generalized from the fixed ground plane (`y = 0`) to an
## arbitrary locked height. The returned normal is always `(0, 1, 0)` -- a
## locked-plane pick always represents the UPWARD-facing working surface a
## drag builds on, never a picked block's own (possibly different) face.
## Stateless -- exercisable directly with arbitrary values, without an
## instance or [method setup].
static func derive_drag_plane_hit(
	ray_origin: Vector3, ray_direction: Vector3, locked_plane_cell_y: int
) -> RaycastHitResult:
	var plane_world_y: float = (float(locked_plane_cell_y) + 0.5) * VoxelWorldConfig.CELL_SIZE
	var intersection: GroundPlaneIntersectionResult = CameraInput.derive_ground_plane_intersection(
		ray_origin, ray_direction, plane_world_y
	)
	if not intersection.hit:
		return RaycastHitResult.new(false)
	var cell: Vector3i = VoxelWorldGrid.world_to_cell(intersection.position)
	cell.y = locked_plane_cell_y
	return RaycastHitResult.new(true, cell, Vector3i(0, 1, 0))


## Records [param result] as [member _current_pick], updates the highlight
## overlay, and emits [signal pick_changed] only when the hit flag, cell, or
## normal actually differs from the PREVIOUS pick -- never a redundant re-fire
## for an unchanged pick held across consecutive frames.
func _set_pick(result: RaycastHitResult) -> void:
	var changed: bool = (
		result.hit != _current_pick.hit
		or result.cell != _current_pick.cell
		or result.normal != _current_pick.normal
	)
	_current_pick = result
	_update_highlight()
	if changed:
		pick_changed.emit(result)


## Updates the highlight overlay's visibility/position from [member
## _current_pick] + [member tool_state_machine]'s current state -- visible
## only while ToolArmed/Dragging AND the pick is a hit (TR-building-system-092:
## "always visibly highlighted while a tool is armed," and clears when the
## pick becomes invalid, the QA plan's named edge case). A no-op if the
## highlight node was never created (defensive; [method setup] always creates
## it).
##
## Sets [member Node3D.position] (LOCAL), never [member Node3D.global_position] --
## this class's own root ([PlacementPick] itself, a plain `Node`) contributes
## no transform of its own, matching Voxel World's own world-space nodes'
## established zero-offset-ancestor assumption, so local position IS the
## effective world position here. This also sidesteps
## [method Node3D.global_position]'s engine requirement that the node already
## be inside a live [SceneTree] (a bare, untethered [PlacementPick] instance --
## this project's established direct-method-call test convention -- would
## otherwise silently read back `Vector3.ZERO` with a logged engine error).
func _update_highlight() -> void:
	if _highlight_mesh == null:
		return
	var state: ToolStateMachine.State = tool_state_machine.get_state()
	var should_show: bool = (
		_current_pick.hit
		and (state == ToolStateMachine.State.TOOL_ARMED or state == ToolStateMachine.State.DRAGGING)
	)
	_highlight_mesh.visible = should_show
	if should_show:
		_highlight_mesh.position = VoxelWorldGrid.cell_to_world(_current_pick.cell)


## Creates the single pooled highlight overlay [MeshInstance3D] (mirrors
## ADR-0014's established pooled-MeshInstance3D ghost-rendering precedent,
## scaled to ONE instance -- see class doc comment). A translucent, unshaded,
## colorblind-neutral tint (white) -- this is a cursor-tracking overlay, not
## the valid/invalid blue-orange ghost axis Story 023 owns. Overlay
## presentation only -- never written into [VoxelWorldGrid]/any committed-
## block material (Control Manifest: "State colors never render on world
## geometry"). Idempotent -- a no-op if already created.
func _ensure_highlight_mesh() -> void:
	if _highlight_mesh != null:
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE * VoxelWorldConfig.CELL_SIZE * 1.02
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	_highlight_mesh = MeshInstance3D.new()
	_highlight_mesh.mesh = box
	_highlight_mesh.material_override = material
	_highlight_mesh.visible = false
	add_child(_highlight_mesh)


## Handles [signal ToolStateMachine.state_changed] -- toggles
## [method Node.set_process] per the hover-pick guardrail (see class doc
## comment) and re-derives the highlight's visibility for the new state (a
## tool being cancelled/deactivated must clear the highlight immediately, not
## wait for the next frame's [method _process] call, which will not come if
## processing was just disabled).
func _on_tool_state_changed(_old_state: ToolStateMachine.State, new_state: ToolStateMachine.State) -> void:
	_apply_process_state_for(new_state)
	_update_highlight()


## Enables [method Node.set_process] (this class's [method _process] hover-
## pick hook) only for [constant ToolStateMachine.State.TOOL_ARMED]/
## [constant ToolStateMachine.State.DRAGGING] -- disabled for Idle/Suspended,
## satisfying "hover picking... runs per-frame only while a tool is armed" by
## construction rather than an internal no-op.
func _apply_process_state_for(state: ToolStateMachine.State) -> void:
	set_process(state == ToolStateMachine.State.TOOL_ARMED or state == ToolStateMachine.State.DRAGGING)


## Godot's per-frame engine callback -- the hover-pick driver while ToolArmed/
## Dragging (see [method _apply_process_state_for]). Delegates to
## [method update_pick] -- the camera-driven real runtime path.
func _process(_delta: float) -> void:
	update_pick()


## ADR-0010 §3 drag-ownership input switch, PRESS half: while
## [constant ToolStateMachine.State.TOOL_ARMED], a [constant BUILD_PLACE_ACTION]
## press resolves the current pick; a MISS is a no-op (never enters Dragging --
## see class doc comment). A HIT locks the working plane to the ATTACH cell's
## height (never the picked block's own height), calls
## [method ToolStateMachine.start_drag], and switches release-listening to
## [method _input] via [method Node.set_process_input] for the drag's
## duration -- mirrors the ADR's own Key Interfaces pseudocode exactly.
## Building UI's hover-suppression flag is not yet checked here -- see class
## doc comment.
func _unhandled_input(event: InputEvent) -> void:
	if not is_set_up():
		return
	if tool_state_machine.get_state() != ToolStateMachine.State.TOOL_ARMED:
		return
	if not event.is_action_pressed(BUILD_PLACE_ACTION):
		return
	update_pick()
	if not _current_pick.hit:
		return
	_locked_plane_cell_y = PlacementPick.derive_attach_cell(_current_pick.cell, _current_pick.normal).y
	_has_locked_plane = true
	tool_state_machine.start_drag()
	set_process_input(true)


## ADR-0010 §3 drag-ownership input switch, RELEASE half: fires on every
## node BEFORE any Control's `_gui_input()` can consume it (Godot's fixed
## propagation order), so a drag's release is caught regardless of HUD hover
## at release time. While [constant ToolStateMachine.State.DRAGGING], a
## [constant BUILD_PLACE_ACTION] release calls
## [method ToolStateMachine.complete_drag] (the pure SM transition back to
## ToolArmed -- the actual commit is Story 021's separate, not-yet-built
## concern), claims exclusive ownership of the event via
## [method Viewport.set_input_as_handled], clears the locked-plane state, and
## reverts to [method _unhandled_input]-only listening via
## [method Node.set_process_input].
func _input(event: InputEvent) -> void:
	if not is_set_up():
		return
	if tool_state_machine.get_state() != ToolStateMachine.State.DRAGGING:
		return
	if not event.is_action_released(BUILD_PLACE_ACTION):
		return
	tool_state_machine.complete_drag()
	_has_locked_plane = false
	get_viewport().set_input_as_handled()
	set_process_input(false)
