# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: full build->furnish->live loop, unguided <=5 min, cozy at scale
# Date: 2026-07-12
# Building System per design/gdd/building-system.md, slice-reduced:
# pick->preview->commit pipeline, wall(F1)/floor(F2)/roof-flat(F5) drag rasterization,
# blueprint-then-build with tick-driven construction (F3), undo/redo (max 50),
# pooled ghost previews (tool preview + blueprint progress), FIFO job queue,
# occupancy-provider deferral (Edge Case 6 / TR-building-system-037).
class_name BuildingSystem
extends Node3D

# --- Global constants (duplicated per file per CONTRACTS.md) ---
const AIR := 0
const BUILT_CELL_MIN_VALUE := 10  # WOOD(10)/STONE(11)/THATCH(12)/BED(20) -- player-built; terrain is 1..4
const TERRAIN_MIN_VALUE := 1      # TERRAIN_BASE per CONTRACTS.md -- 1..4 terrain height bands
const TERRAIN_MAX_VALUE := 4

enum Tool { NONE = 0, WALL = 1, FLOOR = 2, ROOF = 3, BLOCK = 4, FURNITURE = 5 }

const FORMATIONS: Array[String] = ["Flat", "Gable", "Hip", "Shed"]  # only Flat commits (VS scope)

# Tuning knobs (design/gdd/building-system.md Tuning Knobs)
const DEFAULT_WALL_HEIGHT := 3
const MIN_WALL_HEIGHT := 1
const MAX_WALL_HEIGHT := 8
const DRAG_THRESHOLD_PX := 6.0
const MAX_CELLS_PER_COMMAND := 512
const PREVIEW_DEGRADATION_THRESHOLD := 128
const UNDO_STACK_DEPTH := 50
const CORNER_POOL_SIZE := 8

# Boundary-face mesh data (flush cell_size=1.0, cell = integer MIN corner; mirrors
# voxel_world's face-culled mesher convention: emit a face only where the 6-neighbor
# is absent). Each face's 4 corners are wound CCW as seen from outside along its
# direction, matching Godot's front-face/CULL_BACK convention (verified via cross
# product per face during authoring -- see building-system.md ghost rendering fix).
const _FACE_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const _FACE_VERTS: Array = [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],  # +X
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],  # -X
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],  # +Y
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],  # -Y
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],  # +Z
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],  # -Z
]
# Same 4 local UV corners for every face (0,0)-(1,1) in TILE space, later remapped
# into the atlas sub-rect for that cell's value (_build_ghost_mesh). Order matches
# _FACE_VERTS' per-face winding; a slice-pragmatic simplification vs. voxel_world's
# per-direction UV orientation -- fine for a translucent preview, not the final build.
const _QUAD_UV: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

# Ghost tint (baked into vertex colors, multiplies the atlas texture underneath --
# see design/gdd/building-system.md Visual Requirements + the textured-ghost fix).
const GHOST_TINT_NEUTRAL := Color(0.85, 0.92, 1.0, 0.55)  # valid drag/single-cell tool preview
const GHOST_TINT_INVALID := Color(1.0, 0.6, 0.25, 0.6)    # invalid drag/single-cell preview subset
const GHOST_TINT_DRAFT := Color(0.85, 0.92, 1.0, 0.30)    # draft blueprint cells -- not yet released
const GHOST_TINT_RELEASED := Color(0.85, 0.92, 1.0, 0.45) # released-but-unbuilt blueprint cells

signal tool_changed(tool_id: int)
signal palette_changed(material_id: String)
signal wall_height_changed(h: int)
signal formation_changed(name: String)
signal undo_state_changed(can_undo: bool, can_redo: bool)
signal invalid_commit(world_pos: Vector3, reason: String)
signal construction_completed(cells: Array)
signal cells_removed(cells: Array)
signal blueprint_changed()
signal furniture_placed(cell: Vector3i, item_id: String)
signal furniture_removed(cell: Vector3i, item_id: String)
# CONTRACT ADDITION (FEATURE 1, this task): build/editor mode gate -- tools may
# only be armed while true; see set_build_mode()/get_build_mode(). Flagged for
# CONTRACTS.md update.
signal build_mode_changed(active: bool)

# --- Private state ---
var _voxel_world: Node3D
var _camera_input: Node3D
var _hud: CanvasLayer

var _tool: int = Tool.NONE
var _build_mode: bool = false  # FEATURE 1: tools may only arm while this is true
var _wall_height: int = DEFAULT_WALL_HEIGHT
var _formation_index: int = 0
var _material_index: int = 0

var _materials: Array = []       # ResourceItemDatabase.ItemDef, category "building_material"
var _furniture_items: Array = [] # ResourceItemDatabase.ItemDef, category "furniture_fixture"

# blueprint cell record: Vector3i -> {item_id: String, progress_ticks: int, claimed_by: int, needs_support: bool}
var _blueprint: Dictionary = {}
var _furniture_cells: Dictionary = {}  # Vector3i -> item_id (BUILT furniture only)

var _undo_stack: Array = []  # [{cells: Array[Vector3i], item_id: String, is_furniture: bool}]
var _redo_stack: Array = []

var _occupancy_provider: Callable = Callable()  # cb(cell: Vector3i) -> bool ; extra API, see summary
var _tick_count: int = 0  # reserved for future watchdog/unreachable-retry use (not implemented in slice)

var _pending_completions: Array[Dictionary] = []  # {cell, value, item_id, is_furniture} awaiting frame flush

# Pick / drag state
var _last_hit: Dictionary = {}
var _last_hit_valid: bool = false
var _is_pressed: bool = false
var _is_drag_active: bool = false
var _press_screen_pos: Vector2 = Vector2.ZERO
var _drag_start_cell: Vector3i = Vector3i.ZERO
var _drag_current_cell: Vector3i = Vector3i.ZERO
var _drag_plane_y: int = 0
var _drag_item_id: String = ""
var _drag_floor_replace: bool = false  # FEATURE 3: drag started on a terrain top surface

# Ghost rendering: merged, face-culled, TEXTURED meshes (real block tile per cell,
# translucent) -- one surface per tint, not per cell. Texture source: voxel_world's
# atlas (see get_atlas() addition, building_system.gd write-up).
var _atlas_texture: Texture2D
var _atlas_uv_rect: Callable = Callable()  # (cell_value: int) -> Rect2
var _mat_ghost_valid: StandardMaterial3D    # blueprint meshes + valid drag/single-cell preview
var _mat_ghost_invalid: StandardMaterial3D  # invalid drag/single-cell preview subset
# FEATURE 2: blueprint ghosts split into two meshes (tint carries per-vertex, so
# both share _mat_ghost_valid) -- draft cells render dimmer, released-but-unbuilt
# cells render stronger so the player can see which cells will start construction.
var _blueprint_draft_mesh_instance: MeshInstance3D
var _blueprint_released_mesh_instance: MeshInstance3D
var _preview_valid_mesh: MeshInstance3D
var _preview_invalid_mesh: MeshInstance3D

# Corner-marker degrade path only (>128-cell drags) -- still small boxes, still pooled
var _box_mesh: BoxMesh
var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D
var _corner_pool: Array[MeshInstance3D] = []

func _process(_delta: float) -> void:
	if _voxel_world == null or _camera_input == null:
		return
	if _tool != Tool.NONE and not (_hud != null and _hud.is_hover_suppressing()):
		_update_pick()
	else:
		_last_hit_valid = false
		_hide_all_ghosts()
	_flush_batched_signals()

## Wires the system to its three dependencies and builds the ghost pools. Call once at boot.
func setup(voxel_world: Node3D, camera_input: Node3D, hud: CanvasLayer) -> void:
	_voxel_world = voxel_world
	_camera_input = camera_input
	_hud = hud
	_materials = ResourceItemDatabase.list_by_category("building_material")
	_furniture_items = ResourceItemDatabase.list_by_category("furniture_fixture")
	_build_ghost_visuals()
	_camera_input.action_fired.connect(_on_action_fired)
	_camera_input.build_click.connect(_on_build_click)
	TimeTickSystem.tick.connect(_on_tick)
	blueprint_changed.connect(_on_blueprint_changed)
	if not _materials.is_empty():
		var item: ResourceItemDatabase.ItemDef = _materials[_material_index]
		palette_changed.emit(item.id)
	wall_height_changed.emit(_wall_height)
	formation_changed.emit(FORMATIONS[_formation_index])
	tool_changed.emit(_tool)
	build_mode_changed.emit(_build_mode)
	_emit_undo_state()

## Currently armed tool (see Tool enum; 0 = None).
func get_active_tool() -> int:
	return _tool

## True while any tool other than None is armed.
func is_tool_armed() -> bool:
	return _tool != Tool.NONE

## True while build/editor mode is active (FEATURE 1). Tools may only be armed
## while this is true; arming a tool while false auto-enables it (see _set_tool).
func get_build_mode() -> bool:
	return _build_mode

## Enables/disables build/editor mode. Disabling aborts any in-progress drag,
## disarms the current tool, and hides all ghosts. Enabling alone does not arm
## a tool (the toolbar stays available for the player to pick one).
func set_build_mode(active: bool) -> void:
	if _build_mode == active:
		return
	_build_mode = active
	if not active:
		if _is_pressed:
			_abort_drag()
		if _tool != Tool.NONE:
			_tool = Tool.NONE
			tool_changed.emit(_tool)
		_hide_all_ghosts()
	build_mode_changed.emit(_build_mode)

## FEATURE 2: flips every current DRAFT blueprint entry to released (buildable
## by villagers) and returns how many were flipped. No-op (returns 0) if there
## are no drafts.
func release_drafts() -> int:
	var count: int = 0
	for cell in _blueprint.keys():
		var entry: Dictionary = _blueprint[cell]
		if bool(entry.get("draft", false)):
			entry["draft"] = false
			count += 1
	if count > 0:
		blueprint_changed.emit()
	return count

## FEATURE 2: number of blueprint cells still in DRAFT state (not yet released).
func get_draft_count() -> int:
	var count: int = 0
	for entry in _blueprint.values():
		if bool(entry.get("draft", false)):
			count += 1
	return count

## Combined Planned + UnderConstruction blueprint set. Returns a deep copy (safe to read, not to mutate).
func get_blueprint_cells() -> Dictionary:
	return _blueprint.duplicate(true)

## FIFO-by-commit-order claim of the next open cell whose support (if any) is already Built.
## Returns the claimed Vector3i cell, or null if nothing is claimable right now.
func claim_job(villager_id: int) -> Variant:
	for cell in _blueprint.keys():
		var entry: Dictionary = _blueprint[cell]
		if bool(entry.get("draft", false)):
			continue  # FEATURE 2: drafts are not yet released for construction
		if int(entry["claimed_by"]) != 0 or bool(entry.get("ready", false)):
			continue
		if bool(entry["needs_support"]):
			var support_cell: Vector3i = cell + Vector3i(0, -1, 0)
			if _voxel_world.get_cell(support_cell) == AIR:
				continue  # support not yet Built -- skip, do not block the FIFO scan
		entry["claimed_by"] = villager_id
		return cell
	return null

## Releases a claim without canceling the blueprint cell (banked progress is kept).
func release_job(cell: Vector3i) -> void:
	if not _blueprint.has(cell):
		return
	var entry: Dictionary = _blueprint[cell]
	entry["claimed_by"] = 0

## Called by the villager once per tick while it is on site. Advances progress; on completion
## queues the cell for this frame's batched construction_completed flush (deferred if occupied).
func report_on_site(cell: Vector3i) -> void:
	if not _blueprint.has(cell):
		return
	var entry: Dictionary = _blueprint[cell]
	if bool(entry["needs_support"]):
		var support_cell: Vector3i = cell + Vector3i(0, -1, 0)
		if _voxel_world.get_cell(support_cell) == AIR:
			return  # TR-building-system-050: construction cannot start until support is Built
	var def: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_id(String(entry["item_id"]))
	if def == null:
		return
	entry["progress_ticks"] = int(entry["progress_ticks"]) + 1
	if int(entry["progress_ticks"]) < def.build_ticks:
		return
	if bool(entry.get("ready", false)):
		return  # already queued for write; the flush owns it now
	# Blueprint entry SURVIVES until the write actually lands (the flush
	# re-checks occupancy at write time and erases on success) — so
	# get_blueprint_cells() == empty always means "fully built".
	entry["ready"] = true
	_pending_completions.append({
		"cell": cell,
		"value": def.cell_value,
		"item_id": def.id,
		"is_furniture": bool(entry["needs_support"]),
	})

## Combined Voxel World blocks + blueprint view (TR-building-system-060).
func is_cell_occupied_planned(cell: Vector3i) -> bool:
	if _blueprint.has(cell):
		return true
	return _voxel_world.get_cell(cell) != AIR

## BUILT furniture only (Vector3i -> item_id). Returns a deep copy.
func get_furniture_cells() -> Dictionary:
	return _furniture_cells.duplicate(true)

## Extra API (not in CONTRACTS.md) -- see write-up: lets VillagerAI report whether a character
## currently occupies a cell, so construction can defer per Edge Case 6 / TR-building-system-037.
func set_occupancy_provider(cb: Callable) -> void:
	_occupancy_provider = cb

# --- Input routing ---

func _on_action_fired(action_name: String) -> void:
	match action_name:
		"tool_select_1":
			_set_tool(Tool.WALL)
		"tool_select_2":
			_set_tool(Tool.FLOOR)
		"tool_select_3":
			_set_tool(Tool.ROOF)
		"tool_select_4":
			_set_tool(Tool.BLOCK)
		"tool_select_5":
			_set_tool(Tool.FURNITURE)
		"build_cancel":
			_on_cancel()
		"undo":
			_undo()
		"redo":
			_redo()
		"height_step_up":
			_set_wall_height(_wall_height + 1)
		"height_step_down":
			_set_wall_height(_wall_height - 1)
		"palette_next":
			_cycle_palette(1)
		"palette_prev":
			_cycle_palette(-1)
		"formation_next":
			_cycle_formation(1)
		"formation_prev":
			_cycle_formation(-1)
		_:
			pass

func _on_build_click(pressed: bool) -> void:
	if pressed:
		_on_press()
	else:
		_on_release()

func _on_tick() -> void:
	_tick_count += 1  # reserved; construction progress itself is driven by report_on_site calls

func _on_blueprint_changed() -> void:
	_refresh_blueprint_ghosts()

# --- Tool / mode state machine ---

func _set_tool(t: int) -> void:
	# FEATURE 1: arming any tool while build mode is off auto-enables it.
	if t != Tool.NONE and not _build_mode:
		_build_mode = true
		build_mode_changed.emit(true)
	if _tool == t:
		return
	if _is_pressed:
		_abort_drag()
	_tool = t
	_hide_all_ghosts()
	tool_changed.emit(_tool)

func _on_cancel() -> void:
	# Heal stale press state (a release can be lost to HUD consumption or
	# synthetic input): only treat as drag-abort if LMB is REALLY down.
	if _is_pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_pressed = false
	if _is_pressed:
		_abort_drag()
		return
	if _tool != Tool.NONE:
		_tool = Tool.NONE
		_hide_all_ghosts()
		tool_changed.emit(_tool)
		return
	# FEATURE 1 Esc chain extension: no tool armed but build mode still on ->
	# exit build mode (the toolbar/context panel closes on the next Esc).
	if _build_mode:
		set_build_mode(false)

func _abort_drag() -> void:
	_is_pressed = false
	_is_drag_active = false
	_hide_all_ghosts()

func _set_wall_height(h: int) -> void:
	var clamped: int = clampi(h, MIN_WALL_HEIGHT, MAX_WALL_HEIGHT)
	if clamped == _wall_height:
		return
	_wall_height = clamped
	wall_height_changed.emit(_wall_height)

func _cycle_palette(direction: int) -> void:
	if _materials.is_empty():
		return
	_material_index = wrapi(_material_index + direction, 0, _materials.size())
	var item: ResourceItemDatabase.ItemDef = _materials[_material_index]
	palette_changed.emit(item.id)

func _cycle_formation(direction: int) -> void:
	_formation_index = wrapi(_formation_index + direction, 0, FORMATIONS.size())
	formation_changed.emit(FORMATIONS[_formation_index])

func select_material(item_id: String) -> void:
	for i in _materials.size():
		if _materials[i].id == item_id:
			_material_index = i
			palette_changed.emit(item_id)
			return

func set_formation(formation_name: String) -> void:
	var idx: int = FORMATIONS.find(formation_name)
	if idx >= 0:
		_formation_index = idx
		formation_changed.emit(formation_name)

func _current_material() -> ResourceItemDatabase.ItemDef:
	if _materials.is_empty():
		return null
	return _materials[_material_index]

func _current_furniture() -> ResourceItemDatabase.ItemDef:
	if _furniture_items.is_empty():
		return null
	return _furniture_items[0]

# --- Per-frame pick + preview ---

func _update_pick() -> void:
	var ray: Dictionary = _camera_input.get_world_ray()
	var hit: Dictionary = _voxel_world.raycast_cells(ray.origin, ray.dir)
	if hit.is_empty():
		_last_hit_valid = false
		_hide_all_ghosts()
		return
	_last_hit_valid = true
	_last_hit = hit
	match _tool:
		Tool.BLOCK:
			_update_block_ghost(hit)
		Tool.FURNITURE:
			_update_furniture_ghost(hit)
		Tool.WALL, Tool.FLOOR, Tool.ROOF:
			if _is_pressed:
				_update_drag_shape(hit)
			else:
				_update_single_cell_preview(hit)

func _update_block_ghost(hit: Dictionary) -> void:
	_hide_corner_pool()
	if _camera_input.remove_modifier_held:
		var cell: Vector3i = hit.cell
		var existing_value: int = _voxel_world.get_cell(cell)
		var valid: bool = existing_value >= BUILT_CELL_MIN_VALUE
		# Removal preview textures with the REAL existing block, not a selection.
		_render_tool_preview([cell] if valid else [], [] if valid else [cell], existing_value)
	else:
		var target: Vector3i = hit.cell + hit.normal
		var item: ResourceItemDatabase.ItemDef = _current_material()
		var valid2: bool = item != null and _is_cell_valid_for_commit(target, false)
		var value: int = item.cell_value if item != null else 0
		_render_tool_preview([target] if valid2 else [], [] if valid2 else [target], value)

func _update_furniture_ghost(hit: Dictionary) -> void:
	_hide_corner_pool()
	var target: Vector3i = hit.cell + hit.normal
	var item: ResourceItemDatabase.ItemDef = _current_furniture()
	var valid: bool = item != null and _is_cell_valid_for_commit(target, true)
	var value: int = item.cell_value if item != null else 0
	_render_tool_preview([target] if valid else [], [] if valid else [target], value)

func _update_single_cell_preview(hit: Dictionary) -> void:
	var target: Vector3i = hit.cell + hit.normal
	_drag_floor_replace = false
	if _tool == Tool.FLOOR and _is_terrain_top_surface(hit):
		# FEATURE 3: floor picked on a terrain top surface digs INTO that plane
		# instead of sitting one cell above it (Stonehearth flush floors).
		target = hit.cell
		_drag_floor_replace = true
	var cells: Array[Vector3i] = _rasterize_for_tool(_tool, target, target, target.y)
	var item: ResourceItemDatabase.ItemDef = _current_material()
	_render_drag_ghosts(cells, item.cell_value if item != null else 0)

func _update_drag_shape(hit: Dictionary) -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	if not _is_drag_active and mouse_pos.distance_to(_press_screen_pos) >= DRAG_THRESHOLD_PX:
		_is_drag_active = true
	var current_cell: Vector3i = hit.cell + hit.normal
	_drag_current_cell = current_cell
	var end_cell: Vector3i = current_cell if _is_drag_active else _drag_start_cell
	var raw_cells: Array[Vector3i] = _rasterize_for_tool(_tool, _drag_start_cell, end_cell, _drag_plane_y)
	var clipped: Array[Vector3i] = []
	for c in raw_cells:
		if _voxel_world.is_in_region(c):
			clipped.append(c)
	# Material is LOCKED at drag-press (_drag_item_id), not re-read live, so a
	# palette change mid-drag doesn't retexture an in-progress preview.
	var locked_item: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_id(_drag_item_id)
	_render_drag_ghosts(clipped, locked_item.cell_value if locked_item != null else 0)

## FEATURE 3: true when a pick hit a raw terrain cell (value 1..4) on its top
## face (+Y normal) -- the surface the Floor tool digs into rather than
## building one cell above.
func _is_terrain_top_surface(hit: Dictionary) -> bool:
	var value: int = _voxel_world.get_cell(hit.cell)
	return value >= TERRAIN_MIN_VALUE and value <= TERRAIN_MAX_VALUE and hit.normal == Vector3i(0, 1, 0)

func _rasterize_for_tool(tool_id: int, start: Vector3i, cur: Vector3i, plane_y: int) -> Array[Vector3i]:
	match tool_id:
		Tool.WALL:
			return _rasterize_wall(start, cur, plane_y, _wall_height)
		Tool.FLOOR:
			return _rasterize_floor(start, cur, plane_y)
		Tool.ROOF:
			return _rasterize_roof_flat(start, cur, plane_y)
		_:
			return []

# --- Formulas F1/F2/F5 ---

func _rasterize_wall(start: Vector3i, cur: Vector3i, plane_y: int, height: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var line: Array[Vector2i] = _bresenham_line(Vector2i(start.x, start.z), Vector2i(cur.x, cur.z))
	for p in line:
		for h in range(height):
			cells.append(Vector3i(p.x, plane_y + h, p.y))
	return cells

func _rasterize_floor(start: Vector3i, cur: Vector3i, plane_y: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var x0: int = mini(start.x, cur.x)
	var x1: int = maxi(start.x, cur.x)
	var z0: int = mini(start.z, cur.z)
	var z1: int = maxi(start.z, cur.z)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			cells.append(Vector3i(x, plane_y, z))
	return cells

func _rasterize_roof_flat(start: Vector3i, cur: Vector3i, plane_y: int) -> Array[Vector3i]:
	# Flat only (F5); one plane above the picked start surface (slice-reduced from "highest picked").
	return _rasterize_floor(start, cur, plane_y + 1)

func _bresenham_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points

# --- Press / commit handling ---

func _on_press() -> void:
	if _tool == Tool.NONE:
		return
	if _hud != null and _hud.is_hover_suppressing():
		return
	if not _last_hit_valid:
		return
	match _tool:
		Tool.BLOCK:
			_handle_block_press(_last_hit)
		Tool.FURNITURE:
			_handle_furniture_press(_last_hit)
		Tool.WALL, Tool.FLOOR, Tool.ROOF:
			_handle_drag_press(_last_hit)

func _on_release() -> void:
	if not _is_pressed:
		return
	match _tool:
		Tool.WALL, Tool.FLOOR, Tool.ROOF:
			_commit_drag()
		_:
			pass
	_is_pressed = false
	_is_drag_active = false
	_hide_all_ghosts()

func _handle_block_press(hit: Dictionary) -> void:
	if _camera_input.remove_modifier_held:
		_remove_built_cell(hit.cell)
		return
	var item: ResourceItemDatabase.ItemDef = _current_material()
	if item == null:
		invalid_commit.emit(_cell_center(hit.cell), "no material selected")
		return
	var target: Vector3i = hit.cell + hit.normal
	if not _is_cell_valid_for_commit(target, false):
		invalid_commit.emit(_cell_center(target), "invalid target")
		return
	_create_blueprint_cells([target], item.id, false)

func _handle_furniture_press(hit: Dictionary) -> void:
	var item: ResourceItemDatabase.ItemDef = _current_furniture()
	if item == null:
		invalid_commit.emit(_cell_center(hit.cell), "no furniture selected")
		return
	var target: Vector3i = hit.cell + hit.normal
	if not _is_cell_valid_for_commit(target, true):
		invalid_commit.emit(_cell_center(target), "no support")
		return
	_create_blueprint_cells([target], item.id, true)

func _handle_drag_press(hit: Dictionary) -> void:
	var item: ResourceItemDatabase.ItemDef = _current_material()
	_drag_item_id = item.id if item != null else ""
	_is_pressed = true
	_is_drag_active = false
	_press_screen_pos = get_viewport().get_mouse_position()
	# FEATURE 3: floor drags that START on a terrain top surface target that
	# surface's own plane (dig-in) instead of attaching one cell above it.
	_drag_floor_replace = _tool == Tool.FLOOR and _is_terrain_top_surface(hit)
	var target: Vector3i = hit.cell if _drag_floor_replace else hit.cell + hit.normal
	_drag_start_cell = target
	_drag_current_cell = target
	_drag_plane_y = target.y

func _commit_drag() -> void:
	if not _last_hit_valid or (_hud != null and _hud.is_hover_suppressing()):
		return  # Suspended/miss mid-release: abort without commit (Edge Case 12)
	if _tool == Tool.ROOF and FORMATIONS[_formation_index] != "Flat":
		invalid_commit.emit(_cell_center(_drag_start_cell), "VS scope")
		return
	var end_cell: Vector3i = _drag_current_cell if _is_drag_active else _drag_start_cell
	var raw_cells: Array[Vector3i] = _rasterize_for_tool(_tool, _drag_start_cell, end_cell, _drag_plane_y)
	var clipped: Array[Vector3i] = []
	for c in raw_cells:
		if _voxel_world.is_in_region(c):
			clipped.append(c)
	if clipped.is_empty():
		invalid_commit.emit(_cell_center(_drag_start_cell), "out of bounds")
		return
	if clipped.size() > MAX_CELLS_PER_COMMAND:
		invalid_commit.emit(_cell_center(_drag_start_cell), "exceeds max_cells_per_command")
		return
	if _drag_item_id.is_empty():
		invalid_commit.emit(_cell_center(_drag_start_cell), "no material selected")
		return
	var floor_replace: bool = _tool == Tool.FLOOR and _drag_floor_replace
	var valid_cells: Array[Vector3i] = []
	for c in clipped:
		var ok: bool = _is_cell_valid_for_floor_replace(c) if floor_replace else _is_cell_valid_for_commit(c, false)
		if ok:
			valid_cells.append(c)
	if valid_cells.is_empty():
		invalid_commit.emit(_cell_center(_drag_start_cell), "no valid cells")
		return
	_create_blueprint_cells(valid_cells, _drag_item_id, false, floor_replace)

func _remove_built_cell(cell: Vector3i) -> void:
	if not _voxel_world.is_in_region(cell):
		invalid_commit.emit(_cell_center(cell), "out of bounds")
		return
	var value: int = _voxel_world.get_cell(cell)
	if value < BUILT_CELL_MIN_VALUE or value >= 30:
		invalid_commit.emit(_cell_center(cell), "only built cells are removable")
		return
	var applied: Array = _voxel_world.set_cells([{"cell": cell, "value": AIR}])
	var removed: Array[Vector3i] = []
	for entry in applied:
		removed.append(entry.cell)
	if _furniture_cells.has(cell):
		var fid: String = _furniture_cells[cell]
		_furniture_cells.erase(cell)
		furniture_removed.emit(cell, fid)
	cells_removed.emit(removed)

func _is_cell_valid_for_commit(cell: Vector3i, is_furniture: bool) -> bool:
	if not _voxel_world.is_in_region(cell):
		return false
	if _voxel_world.get_cell(cell) != AIR:
		return false
	if _blueprint.has(cell):
		return false
	if is_furniture:
		var below: Vector3i = cell + Vector3i(0, -1, 0)
		var below_built: bool = _voxel_world.get_cell(below) != AIR
		if not below_built and not _blueprint.has(below):
			return false
	return true

## FEATURE 3: replace-mode validity for a Floor drag that digs into terrain --
## a covered cell is buildable if it is raw terrain (1..4, uneven ground gets
## flattened) OR air (fills dips), and not already claimed by another blueprint.
func _is_cell_valid_for_floor_replace(cell: Vector3i) -> bool:
	if not _voxel_world.is_in_region(cell):
		return false
	if _blueprint.has(cell):
		return false
	var value: int = _voxel_world.get_cell(cell)
	return value == AIR or (value >= TERRAIN_MIN_VALUE and value <= TERRAIN_MAX_VALUE)

func _create_blueprint_cells(cells: Array, item_id: String, is_furniture: bool, is_floor_replace: bool = false) -> void:
	var typed_cells: Array[Vector3i] = []
	var restore_values: Dictionary = {}
	for c in cells:
		typed_cells.append(c)
		# FEATURE 3: capture the cell's PRE-EXISTING value (terrain id for a
		# floor-replace dig, AIR for every normal build) so undo restores the
		# correct thing instead of assuming AIR.
		var restore_value: int = _voxel_world.get_cell(c)
		restore_values[c] = restore_value
		_blueprint[c] = {
			"item_id": item_id,
			"progress_ticks": 0,
			"claimed_by": 0,
			"needs_support": is_furniture,
			"draft": true,  # FEATURE 2: new blueprint cells start as drafts
			"restore_value": restore_value,
		}
	_push_command(typed_cells, item_id, is_furniture, restore_values, is_floor_replace)
	blueprint_changed.emit()

# --- Undo / redo ---

func _push_command(cells: Array[Vector3i], item_id: String, is_furniture: bool, restore_values: Dictionary, is_floor_replace: bool = false) -> void:
	_undo_stack.append({
		"cells": cells.duplicate(),
		"item_id": item_id,
		"is_furniture": is_furniture,
		"restore_values": restore_values.duplicate(),
		"is_floor_replace": is_floor_replace,
	})
	if _undo_stack.size() > UNDO_STACK_DEPTH:
		_undo_stack.pop_front()  # Edge Case 9: oldest discarded silently
	_redo_stack.clear()
	_emit_undo_state()

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var cmd: Dictionary = _undo_stack.pop_back()
	var built_removals: Array = []
	var is_furniture: bool = bool(cmd["is_furniture"])
	var restore_values: Dictionary = cmd.get("restore_values", {})
	for cell in cmd["cells"]:
		if _blueprint.has(cell):
			_blueprint.erase(cell)  # still Planned/UnderConstruction -> cancel
		else:
			# Cell was actually completed (blueprint entry already flushed) --
			# restore its captured pre-existing value (FEATURE 3: terrain for a
			# floor-replace dig, AIR otherwise) instead of assuming AIR.
			var restore_to: int = int(restore_values.get(cell, AIR))
			var v: int = _voxel_world.get_cell(cell)
			if v != restore_to:
				built_removals.append({"cell": cell, "value": restore_to})
	if not built_removals.is_empty():
		var applied: Array = _voxel_world.set_cells(built_removals)
		var removed: Array[Vector3i] = []
		for entry in applied:
			removed.append(entry.cell)
			if is_furniture and _furniture_cells.has(entry.cell):
				var fid: String = _furniture_cells[entry.cell]
				_furniture_cells.erase(entry.cell)
				furniture_removed.emit(entry.cell, fid)
		cells_removed.emit(removed)
	_redo_stack.append(cmd)
	blueprint_changed.emit()
	_emit_undo_state()

func _redo() -> void:
	if _redo_stack.is_empty():
		return
	var cmd: Dictionary = _redo_stack.pop_back()
	var is_furniture: bool = bool(cmd["is_furniture"])
	var is_floor_replace: bool = bool(cmd.get("is_floor_replace", false))
	var valid_cells: Array[Vector3i] = []
	for cell in cmd["cells"]:
		var ok: bool = _is_cell_valid_for_floor_replace(cell) if is_floor_replace else _is_cell_valid_for_commit(cell, is_furniture)
		if ok:
			valid_cells.append(cell)
	if valid_cells.is_empty():
		invalid_commit.emit(_cell_center(cmd["cells"][0]), "redo: no valid cells remain")
		_emit_undo_state()
		return
	var restore_values: Dictionary = {}
	for cell in valid_cells:
		var restore_value: int = _voxel_world.get_cell(cell)
		restore_values[cell] = restore_value
		_blueprint[cell] = {
			"item_id": cmd["item_id"],
			"progress_ticks": 0,
			"claimed_by": 0,
			"needs_support": is_furniture,
			"draft": false,  # redo restores directly to released (see task summary)
			"restore_value": restore_value,
		}
	_undo_stack.append({
		"cells": valid_cells,
		"item_id": cmd["item_id"],
		"is_furniture": is_furniture,
		"restore_values": restore_values,
		"is_floor_replace": is_floor_replace,
	})
	if _undo_stack.size() > UNDO_STACK_DEPTH:
		_undo_stack.pop_front()
	blueprint_changed.emit()
	_emit_undo_state()

func _emit_undo_state() -> void:
	undo_state_changed.emit(not _undo_stack.is_empty(), not _redo_stack.is_empty())

# --- Batched construction completion (per-frame flush) ---

func _flush_batched_signals() -> void:
	if _pending_completions.is_empty():
		return
	# RACE CLOSURE (found by loop_test with tick bursts): occupancy must be
	# re-checked AT WRITE TIME — between report_on_site's tick and this frame
	# flush the villager can step INTO a completing cell's body column.
	# Occupied entries stay pending and retry next flush.
	var writes: Array = []
	var write_meta: Array = []
	var still_pending: Array[Dictionary] = []
	for c in _pending_completions:
		if _occupancy_provider.is_valid() and bool(_occupancy_provider.call(c["cell"])):
			still_pending.append(c)
			continue
		writes.append({"cell": c["cell"], "value": c["value"]})
		write_meta.append(c)
	_pending_completions = still_pending
	if writes.is_empty():
		return
	var applied: Array = _voxel_world.set_cells(writes)
	var completed_cells: Array[Vector3i] = []
	for i in applied.size():
		var res: Dictionary = applied[i]
		var meta: Dictionary = write_meta[i]
		_blueprint.erase(res.cell)
		completed_cells.append(res.cell)
		if bool(meta["is_furniture"]):
			_furniture_cells[res.cell] = meta["item_id"]
			furniture_placed.emit(res.cell, String(meta["item_id"]))
	construction_completed.emit(completed_cells)
	blueprint_changed.emit()

# --- Ghost pools (tool preview + blueprint progress) ---

func _build_ghost_visuals() -> void:
	# Merged, face-culled, TEXTURED ghost meshes: one shared material per tint
	# (blueprint + valid-preview share the neutral tint; invalid-preview gets its
	# own), one persistent MeshInstance3D per role. The atlas texture supplies the
	# real block look; tint is baked into each mesh's own vertex colors
	# (_build_ghost_mesh) and multiplies the sampled texel underneath.
	var atlas: Dictionary = _voxel_world.get_atlas()
	_atlas_texture = atlas.get("texture")
	_atlas_uv_rect = atlas.get("uv_rect", Callable())
	_mat_ghost_valid = _make_textured_ghost_material()
	_mat_ghost_invalid = _make_textured_ghost_material()
	_blueprint_draft_mesh_instance = _make_ghost_mesh_instance(_mat_ghost_valid)
	_blueprint_released_mesh_instance = _make_ghost_mesh_instance(_mat_ghost_valid)
	_preview_valid_mesh = _make_ghost_mesh_instance(_mat_ghost_valid)
	_preview_invalid_mesh = _make_ghost_mesh_instance(_mat_ghost_invalid)

	# Corner-marker degrade path: small solid boxes, simple albedo-tinted materials
	# (no vertex colors/UVs on a bare BoxMesh here -- kept as its own simple,
	# untextured material pair; an outline doesn't need to show the real tile).
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE

	_mat_valid = StandardMaterial3D.new()
	_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_valid.albedo_color = Color(0.35, 0.55, 0.9, 0.45)

	_mat_invalid = StandardMaterial3D.new()
	_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_invalid.albedo_color = Color(0.95, 0.55, 0.15, 0.45)

	for i in CORNER_POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.scale = Vector3(0.25, 0.25, 0.25)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_corner_pool.append(mi)

func _make_textured_ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _atlas_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat

func _make_ghost_mesh_instance(mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

## Boundary-face mesh for an arbitrary cell set: emits a quad only where the
## 6-neighbor is absent FROM THE SET (world contents are irrelevant here). Each
## cell samples its OWN atlas tile (cell_values: Vector3i -> cell_value) so a
## mixed blueprint (wood + thatch + bed) renders each cell's real texture; a
## uniform tint is baked into every vertex color and multiplies the sampled
## texel underneath. One surface -- see _FACE_DIRS/_FACE_VERTS/_QUAD_UV.
func _build_ghost_mesh(cell_values: Dictionary, tint: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cell_values.is_empty():
		return mesh
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for c in cell_values.keys():
		var cell: Vector3i = c
		var origin: Vector3 = Vector3(cell.x, cell.y, cell.z)
		var uv_rect: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
		if _atlas_uv_rect.is_valid():
			uv_rect = _atlas_uv_rect.call(int(cell_values[c]))
		for i in _FACE_DIRS.size():
			var dir: Vector3i = _FACE_DIRS[i]
			if cell_values.has(cell + dir):
				continue  # interior face -- neighbor is in the same set, cull it
			var base_index: int = verts.size()
			var normal: Vector3 = Vector3(dir.x, dir.y, dir.z)
			var face_verts: Array = _FACE_VERTS[i]
			for j in face_verts.size():
				verts.append(origin + face_verts[j])
				normals.append(normal)
				colors.append(tint)
				var local_uv: Vector2 = _QUAD_UV[j]
				uvs.append(Vector2(
					uv_rect.position.x + local_uv.x * uv_rect.size.x,
					uv_rect.position.y + local_uv.y * uv_rect.size.y))
			indices.append(base_index)
			indices.append(base_index + 1)
			indices.append(base_index + 2)
			indices.append(base_index)
			indices.append(base_index + 2)
			indices.append(base_index + 3)
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Builds a Vector3i -> cell_value Dictionary for a cell list that shares ONE
## material (drag/single-cell previews are always one tool + one selection).
func _uniform_cell_values(cells: Array[Vector3i], value: int) -> Dictionary:
	var out: Dictionary = {}
	for c in cells:
		out[c] = value
	return out

func _render_drag_ghosts(cells: Array[Vector3i], cell_value: int) -> void:
	_hide_corner_pool()
	if cells.is_empty():
		_preview_valid_mesh.visible = false
		_preview_invalid_mesh.visible = false
		return
	var roof_invalid_formation: bool = _tool == Tool.ROOF and FORMATIONS[_formation_index] != "Flat"
	if cells.size() > PREVIEW_DEGRADATION_THRESHOLD:
		_preview_valid_mesh.visible = false
		_preview_invalid_mesh.visible = false
		_render_corner_markers(cells, not roof_invalid_formation)
		return
	var valid_cells: Array[Vector3i] = []
	var invalid_cells: Array[Vector3i] = []
	var floor_replace: bool = _tool == Tool.FLOOR and _drag_floor_replace
	for cell in cells:
		var valid: bool = false
		if not roof_invalid_formation:
			valid = _is_cell_valid_for_floor_replace(cell) if floor_replace else _is_cell_valid_for_commit(cell, _tool == Tool.FURNITURE)
		if valid:
			valid_cells.append(cell)
		else:
			invalid_cells.append(cell)
	_render_tool_preview(valid_cells, invalid_cells, cell_value)

## Rebuilds the two merged tool-preview meshes from an already-split cell set.
## Shared by the drag/hover preview (WALL/FLOOR/ROOF) and the single-cell
## BLOCK/FURNITURE preview (called with a 1-cell array on whichever side is
## valid). cell_value is uniform across one call -- only one tool/material is
## ever armed at a time (WALL/FLOOR/ROOF lock it at drag-press; see _drag_item_id).
func _render_tool_preview(valid_cells: Array, invalid_cells: Array, cell_value: int) -> void:
	# Untyped on purpose: call sites use inline `[x] if cond else []` literals,
	# which are plain Arrays — typed params raised runtime errors (user crash).
	if valid_cells.is_empty():
		_preview_valid_mesh.visible = false
	else:
		_preview_valid_mesh.mesh = _build_ghost_mesh(_uniform_cell_values(valid_cells, cell_value), GHOST_TINT_NEUTRAL)
		_preview_valid_mesh.visible = true
	if invalid_cells.is_empty():
		_preview_invalid_mesh.visible = false
	else:
		_preview_invalid_mesh.mesh = _build_ghost_mesh(_uniform_cell_values(invalid_cells, cell_value), GHOST_TINT_INVALID)
		_preview_invalid_mesh.visible = true

func _render_corner_markers(cells: Array[Vector3i], valid: bool) -> void:
	var min_c: Vector3i = cells[0]
	var max_c: Vector3i = cells[0]
	for c in cells:
		min_c = Vector3i(mini(min_c.x, c.x), mini(min_c.y, c.y), mini(min_c.z, c.z))
		max_c = Vector3i(maxi(max_c.x, c.x), maxi(max_c.y, c.y), maxi(max_c.z, c.z))
	var corners: Array[Vector3i] = [
		Vector3i(min_c.x, min_c.y, min_c.z), Vector3i(max_c.x, min_c.y, min_c.z),
		Vector3i(min_c.x, max_c.y, min_c.z), Vector3i(max_c.x, max_c.y, min_c.z),
		Vector3i(min_c.x, min_c.y, max_c.z), Vector3i(max_c.x, min_c.y, max_c.z),
		Vector3i(min_c.x, max_c.y, max_c.z), Vector3i(max_c.x, max_c.y, max_c.z),
	]
	for i in corners.size():
		var mi: MeshInstance3D = _corner_pool[i]
		mi.global_position = _cell_center(corners[i])
		mi.material_override = _mat_valid if valid else _mat_invalid
		mi.visible = true

func _hide_all_ghosts() -> void:
	_preview_valid_mesh.visible = false
	_preview_invalid_mesh.visible = false
	_hide_corner_pool()

func _hide_corner_pool() -> void:
	for mi in _corner_pool:
		mi.visible = false

## Rebuilds the two merged blueprint meshes (draft / released) from the current
## cell set (Planned + UnderConstruction combined -- no per-cell progress-alpha;
## see design/gdd/building-system.md Visual Requirements). Each cell textures
## with ITS OWN atlas tile (a mixed wood+thatch+bed blueprint renders each
## cell's real tile), since a command's cells can span multiple past commits.
## FEATURE 2: split by draft state so players can see what release_drafts()
## will affect (dim = draft, stronger = released-but-unbuilt).
func _refresh_blueprint_ghosts() -> void:
	var draft_values: Dictionary = {}
	var released_values: Dictionary = {}
	for cell in _blueprint.keys():
		var entry: Dictionary = _blueprint[cell]
		var def: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_id(String(entry["item_id"]))
		var value: int = def.cell_value if def != null else 0
		if bool(entry.get("draft", false)):
			draft_values[cell] = value
		else:
			released_values[cell] = value
	if draft_values.is_empty():
		_blueprint_draft_mesh_instance.visible = false
	else:
		_blueprint_draft_mesh_instance.mesh = _build_ghost_mesh(draft_values, GHOST_TINT_DRAFT)
		_blueprint_draft_mesh_instance.visible = true
	if released_values.is_empty():
		_blueprint_released_mesh_instance.visible = false
	else:
		_blueprint_released_mesh_instance.mesh = _build_ghost_mesh(released_values, GHOST_TINT_RELEASED)
		_blueprint_released_mesh_instance.visible = true

func _cell_center(cell: Vector3i) -> Vector3:
	return Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
