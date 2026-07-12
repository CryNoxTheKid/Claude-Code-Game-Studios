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
const GHOST_POOL_SIZE := 160  # > degradation threshold so per-cell ghosts never starve below it
const CORNER_POOL_SIZE := 8

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

# --- Private state ---
var _voxel_world: Node3D
var _camera_input: Node3D
var _hud: CanvasLayer

var _tool: int = Tool.NONE
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

# Ghost rendering (pooled)
var _box_mesh: BoxMesh
var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D
var _ghost_pool: Array[MeshInstance3D] = []
var _corner_pool: Array[MeshInstance3D] = []
var _blueprint_ghosts: Dictionary = {}       # Vector3i -> MeshInstance3D
var _blueprint_ghost_free: Array[MeshInstance3D] = []

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
	_build_ghost_pools()
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
	_emit_undo_state()

## Currently armed tool (see Tool enum; 0 = None).
func get_active_tool() -> int:
	return _tool

## True while any tool other than None is armed.
func is_tool_armed() -> bool:
	return _tool != Tool.NONE

## Combined Planned + UnderConstruction blueprint set. Returns a deep copy (safe to read, not to mutate).
func get_blueprint_cells() -> Dictionary:
	return _blueprint.duplicate(true)

## FIFO-by-commit-order claim of the next open cell whose support (if any) is already Built.
## Returns the claimed Vector3i cell, or null if nothing is claimable right now.
func claim_job(villager_id: int) -> Variant:
	for cell in _blueprint.keys():
		var entry: Dictionary = _blueprint[cell]
		if int(entry["claimed_by"]) != 0:
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
	if _occupancy_provider.is_valid() and bool(_occupancy_provider.call(cell)):
		entry["progress_ticks"] = def.build_ticks  # hold at threshold, retried next report (Edge Case 6)
		return
	_blueprint.erase(cell)
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
	if _tool == t:
		return
	if _is_pressed:
		_abort_drag()
	_tool = t
	_hide_all_ghosts()
	tool_changed.emit(_tool)

func _on_cancel() -> void:
	if _is_pressed:
		_abort_drag()
		return
	if _tool != Tool.NONE:
		_tool = Tool.NONE
		_hide_all_ghosts()
		tool_changed.emit(_tool)

func _abort_drag() -> void:
	_is_pressed = false
	_is_drag_active = false
	_hide_ghost_pool()
	_hide_corner_pool()

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
	_hide_ghost_pool()
	_hide_corner_pool()
	var mi: MeshInstance3D = _ghost_pool[0]
	if _camera_input.remove_modifier_held:
		var cell: Vector3i = hit.cell
		var valid: bool = _voxel_world.get_cell(cell) >= BUILT_CELL_MIN_VALUE
		mi.global_position = _cell_center(cell)
		mi.material_override = _mat_valid if valid else _mat_invalid
	else:
		var target: Vector3i = hit.cell + hit.normal
		var item: ResourceItemDatabase.ItemDef = _current_material()
		var valid2: bool = item != null and _is_cell_valid_for_commit(target, false)
		mi.global_position = _cell_center(target)
		mi.material_override = _mat_valid if valid2 else _mat_invalid
	mi.visible = true

func _update_furniture_ghost(hit: Dictionary) -> void:
	_hide_ghost_pool()
	_hide_corner_pool()
	var mi: MeshInstance3D = _ghost_pool[0]
	var target: Vector3i = hit.cell + hit.normal
	var valid: bool = _current_furniture() != null and _is_cell_valid_for_commit(target, true)
	mi.global_position = _cell_center(target)
	mi.material_override = _mat_valid if valid else _mat_invalid
	mi.visible = true

func _update_single_cell_preview(hit: Dictionary) -> void:
	var target: Vector3i = hit.cell + hit.normal
	var cells: Array[Vector3i] = _rasterize_for_tool(_tool, target, target, target.y)
	_render_drag_ghosts(cells)

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
	_render_drag_ghosts(clipped)

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
	_hide_ghost_pool()
	_hide_corner_pool()

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
	var target: Vector3i = hit.cell + hit.normal
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
	var valid_cells: Array[Vector3i] = []
	for c in clipped:
		if _is_cell_valid_for_commit(c, false):
			valid_cells.append(c)
	if valid_cells.is_empty():
		invalid_commit.emit(_cell_center(_drag_start_cell), "no valid cells")
		return
	_create_blueprint_cells(valid_cells, _drag_item_id, false)

func _remove_built_cell(cell: Vector3i) -> void:
	if not _voxel_world.is_in_region(cell):
		invalid_commit.emit(_cell_center(cell), "out of bounds")
		return
	var value: int = _voxel_world.get_cell(cell)
	if value < BUILT_CELL_MIN_VALUE:
		invalid_commit.emit(_cell_center(cell), "terrain not removable")
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

func _create_blueprint_cells(cells: Array, item_id: String, is_furniture: bool) -> void:
	var typed_cells: Array[Vector3i] = []
	for c in cells:
		typed_cells.append(c)
		_blueprint[c] = {
			"item_id": item_id,
			"progress_ticks": 0,
			"claimed_by": 0,
			"needs_support": is_furniture,
		}
	_push_command(typed_cells, item_id, is_furniture)
	blueprint_changed.emit()

# --- Undo / redo ---

func _push_command(cells: Array[Vector3i], item_id: String, is_furniture: bool) -> void:
	_undo_stack.append({"cells": cells.duplicate(), "item_id": item_id, "is_furniture": is_furniture})
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
	for cell in cmd["cells"]:
		if _blueprint.has(cell):
			_blueprint.erase(cell)  # still Planned/UnderConstruction -> cancel
		else:
			var v: int = _voxel_world.get_cell(cell)
			if v != AIR:
				built_removals.append({"cell": cell, "value": AIR})
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
	var valid_cells: Array[Vector3i] = []
	for cell in cmd["cells"]:
		if _is_cell_valid_for_commit(cell, is_furniture):
			valid_cells.append(cell)
	if valid_cells.is_empty():
		invalid_commit.emit(_cell_center(cmd["cells"][0]), "redo: no valid cells remain")
		_emit_undo_state()
		return
	for cell in valid_cells:
		_blueprint[cell] = {
			"item_id": cmd["item_id"],
			"progress_ticks": 0,
			"claimed_by": 0,
			"needs_support": is_furniture,
		}
	_undo_stack.append({"cells": valid_cells, "item_id": cmd["item_id"], "is_furniture": is_furniture})
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
	var writes: Array = []
	for c in _pending_completions:
		writes.append({"cell": c["cell"], "value": c["value"]})
	var applied: Array = _voxel_world.set_cells(writes)
	var completed_cells: Array[Vector3i] = []
	for i in applied.size():
		var res: Dictionary = applied[i]
		var meta: Dictionary = _pending_completions[i]
		completed_cells.append(res.cell)
		if bool(meta["is_furniture"]):
			_furniture_cells[res.cell] = meta["item_id"]
			furniture_placed.emit(res.cell, String(meta["item_id"]))
	_pending_completions.clear()
	construction_completed.emit(completed_cells)
	blueprint_changed.emit()

# --- Ghost pools (tool preview + blueprint progress) ---

func _build_ghost_pools() -> void:
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

	for i in GHOST_POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.visible = false
		add_child(mi)
		_ghost_pool.append(mi)

	for i in CORNER_POOL_SIZE:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh
		mi.scale = Vector3(0.25, 0.25, 0.25)
		mi.visible = false
		add_child(mi)
		_corner_pool.append(mi)

func _render_drag_ghosts(cells: Array[Vector3i]) -> void:
	_hide_ghost_pool()
	_hide_corner_pool()
	if cells.is_empty():
		return
	var roof_invalid_formation: bool = _tool == Tool.ROOF and FORMATIONS[_formation_index] != "Flat"
	if cells.size() > PREVIEW_DEGRADATION_THRESHOLD:
		_render_corner_markers(cells, not roof_invalid_formation)
		return
	var shown: int = mini(cells.size(), _ghost_pool.size())
	for i in shown:
		var cell: Vector3i = cells[i]
		var mi: MeshInstance3D = _ghost_pool[i]
		mi.global_position = _cell_center(cell)
		var valid: bool = (not roof_invalid_formation) and _is_cell_valid_for_commit(cell, _tool == Tool.FURNITURE)
		mi.material_override = _mat_valid if valid else _mat_invalid
		mi.visible = true

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
	_hide_ghost_pool()
	_hide_corner_pool()

func _hide_ghost_pool() -> void:
	for mi in _ghost_pool:
		mi.visible = false

func _hide_corner_pool() -> void:
	for mi in _corner_pool:
		mi.visible = false

func _refresh_blueprint_ghosts() -> void:
	var stale: Array[Vector3i] = []
	for cell in _blueprint_ghosts.keys():
		if not _blueprint.has(cell):
			stale.append(cell)
	for cell in stale:
		var mi: MeshInstance3D = _blueprint_ghosts[cell]
		mi.visible = false
		_blueprint_ghost_free.append(mi)
		_blueprint_ghosts.erase(cell)
	for cell in _blueprint.keys():
		var entry: Dictionary = _blueprint[cell]
		var mi: MeshInstance3D
		if _blueprint_ghosts.has(cell):
			mi = _blueprint_ghosts[cell]
		else:
			mi = _acquire_blueprint_ghost()
			_blueprint_ghosts[cell] = mi
		mi.global_position = _cell_center(cell)
		var def: ResourceItemDatabase.ItemDef = ResourceItemDatabase.get_by_id(String(entry["item_id"]))
		var progress_ratio: float = 0.0
		if def != null and def.build_ticks > 0:
			progress_ratio = float(entry["progress_ticks"]) / float(def.build_ticks)
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		mat.albedo_color.a = clampf(0.15 + progress_ratio * 0.55, 0.15, 0.85)
		mi.visible = true

func _acquire_blueprint_ghost() -> MeshInstance3D:
	if not _blueprint_ghost_free.is_empty():
		return _blueprint_ghost_free.pop_back()
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.3)
	mi.material_override = mat
	add_child(mi)
	return mi

func _cell_center(cell: Vector3i) -> Vector3:
	return Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
