# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: full build->furnish->live loop, unguided <=5 min, cozy at scale
# Date: 2026-07-12
# HUD per design/ux/hud.md: zones Z1-Z6 built programmatically (no .tscn),
# flat chrome #262220 / text #EDE6DA / gold #F5A83C highlight, instant swaps,
# raw-delta only (never TimeTickSystem.game_delta, never SceneTree.paused).
# Duck-typed Node deps (building_system/camera_input/villager_ai/needs_mood/
# build_validation) — no shared interface/class_name exists yet for those
# modules at this stage of the slice; matches CONTRACTS.md's shape.
#
# CONTRACT ADDITION: setup() takes a 5th param `camera_input` not present in
# CONTRACTS.md's `setup(building_system, villager_ai, needs_mood, build_validation)`
# signature. It is required to wire the Z4 villager-pick flow (camera_input
# .build_click + .get_world_ray()) that CONTRACTS.md itself specifies for the
# villager panel. Flagged for CONTRACTS.md update; see task summary.
extends CanvasLayer

const VillagerPanelScript := preload("res://villager_panel.gd")

const TOOL_NONE := 0
const TOOL_WALL := 1
const TOOL_FLOOR := 2
const TOOL_ROOF := 3
const TOOL_BLOCK := 4
const TOOL_FURNITURE := 5

const TOOL_BUTTONS: Array[Dictionary] = [
	{"id": 1, "label": "Wall"},
	{"id": 2, "label": "Floor"},
	{"id": 3, "label": "Roof"},
	{"id": 4, "label": "Block"},
	{"id": 5, "label": "Bed"},
]

const ROOF_FORMATIONS := ["Flat", "Gable", "Hip", "Shed"]  # only Flat is functional this slice

const COLOR_CHROME := Color(0.149, 0.133, 0.125)     # #262220
const COLOR_TEXT := Color(0.929, 0.902, 0.855)       # #EDE6DA
const COLOR_GOLD := Color(0.961, 0.659, 0.235)       # #F5A83C
const COLOR_STATE_ORANGE := Color(0.86, 0.47, 0.20)  # [assumption] pending art-bible theme verification (hud.md A3 OPEN)
const COLOR_STATE_BLUE := Color(0.35, 0.58, 0.82)    # [assumption] pending art-bible theme verification (hud.md A3 OPEN)

const EDGE_MARGIN := 16.0
const ZONE_GAP := 8.0
const TOOLBAR_HEIGHT_ESTIMATE := 56.0
const CONTEXT_PANEL_HEIGHT := 120.0
const TIME_CONTROLS_HEIGHT_ESTIMATE := 48.0
const TOAST_HEIGHT_ESTIMATE := 40.0
const ZONE_HALF_WIDTH := 240.0     # toolbar/context shared width envelope (hud.md E4 rule)
const RIGHT_ZONE_WIDTH := 260.0    # time/toast/anchor column width

const TOAST_MAX_VISIBLE := 3
const TOAST_DISMISS_SECONDS := 30.0
const TOAST_STALE_SECONDS := 3.0   # auto-retire a key not re-emitted within this window


signal tool_button_pressed(tool_id: int)
signal material_selected(item_id: String)
signal formation_selected(formation_name: String)
signal wall_height_set(height: int)
signal undo_pressed()
signal redo_pressed()


var _building_system: Node
var _camera_input: Node
var _villager_ai: Node
var _needs_mood: Node
var _build_validation: Node

var _villager_panel: Control

var _current_tool: int = TOOL_NONE
var _current_material: String = ""
var _current_wall_height: int = 3
var _current_formation: String = "Flat"

var _tool_buttons: Dictionary = {}       # tool_id:int -> Button
var _undo_button: Button
var _redo_button: Button

var _context_panel: PanelContainer
var _context_content: VBoxContainer

var _pause_button: Button
var _speed_buttons: Dictionary = {}      # warp:int -> Button
var _pause_dim: ColorRect

var _toast_container: VBoxContainer
var _toasts: Dictionary = {}             # key:String -> {severity,text,first_seen,last_seen,dismissed_until}
var _toast_visible_keys: Array = []

var _anchor_zone: PanelContainer
var _anchor_button: Button
var _anchor_expanded_panel: PanelContainer
var _anchor_expanded_list: VBoxContainer
var _anchor_expanded: bool = false
var _anchor_entries_cache: Array = []

var _hover_flags: Dictionary = {}        # zone name:String -> bool

var _distress_icons: Dictionary = {}     # villager_id:int -> Node3D


func _ready() -> void:
	_build_toolbar()
	_build_context_panel()
	_build_time_controls()
	_build_toast_zone()
	_build_anchor()
	_build_villager_panel()


func _process(_delta: float) -> void:
	_reconcile_toasts()
	_update_distress_icons()


func _unhandled_input(event: InputEvent) -> void:
	if _building_system == null:
		return
	if event.is_action_pressed("build_cancel"):
		# P11 two-step: release HUD focus first, only then fall through to world (deselect).
		if _anchor_expanded:
			_anchor_expanded = false
			_anchor_expanded_panel.visible = false
			get_viewport().set_input_as_handled()
			return
		if _building_system.get_active_tool() == TOOL_NONE:
			_villager_panel.deselect()


## Wires injected systems. Called once by GameWorld after HUD enters the tree.
func setup(building_system: Node, camera_input: Node, villager_ai: Node, needs_mood: Node, build_validation: Node) -> void:
	_building_system = building_system
	_camera_input = camera_input
	_villager_ai = villager_ai
	_needs_mood = needs_mood
	_build_validation = build_validation

	_current_tool = building_system.get_active_tool()
	_refresh_toolbar_highlight()
	_refresh_context_panel()

	building_system.tool_changed.connect(_on_tool_changed)
	building_system.palette_changed.connect(_on_palette_changed)
	building_system.wall_height_changed.connect(_on_wall_height_changed)
	building_system.formation_changed.connect(_on_formation_changed)
	building_system.undo_state_changed.connect(_on_undo_state_changed)

	build_validation.sealed_space_warning.connect(_on_sealed_space_warning)
	build_validation.unsheltered_furniture_info.connect(_on_unsheltered_furniture_info)

	camera_input.build_click.connect(_on_build_click)

	_villager_panel.setup(villager_ai, needs_mood)


## OR of mouse-over across every HUD Control zone (P2 shared hover-suppression gate).
func is_hover_suppressing() -> bool:
	for hovering in _hover_flags.values():
		if hovering:
			return true
	return false


## Keyed refresh-in-place toast (P1). severity 0 = info, 1 = warning.
func show_toast(key: String, severity: int, text: String) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _toasts.has(key):
		var data: Dictionary = _toasts[key]
		data["severity"] = severity
		data["text"] = text
		data["last_seen"] = now
	else:
		_toasts[key] = {
			"severity": severity,
			"text": text,
			"first_seen": now,
			"last_seen": now,
			"dismissed_until": 0.0,
		}
	_refresh_toast_display()


## Removes a toast key entirely (no debounce), e.g. for external explicit clears.
func retire_toast(key: String) -> void:
	if not _toasts.has(key):
		return
	_toasts.erase(key)
	_refresh_toast_display()


# ---------------------------------------------------------------------------
# Z6 - Toolbar
# ---------------------------------------------------------------------------

func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.name = "Z6_Toolbar"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -ZONE_HALF_WIDTH
	panel.offset_right = ZONE_HALF_WIDTH
	panel.offset_top = -(EDGE_MARGIN + TOOLBAR_HEIGHT_ESTIMATE)
	panel.offset_bottom = -EDGE_MARGIN
	panel.mouse_entered.connect(_set_hover.bind("toolbar", true))
	panel.mouse_exited.connect(_set_hover.bind("toolbar", false))
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	for entry: Dictionary in TOOL_BUTTONS:
		var tool_id: int = entry["id"]
		var btn := Button.new()
		btn.text = String(entry["label"])
		btn.tooltip_text = "Key %d" % tool_id
		btn.custom_minimum_size = Vector2(64.0, 40.0)
		_apply_flat_button_style(btn)
		btn.pressed.connect(_on_tool_button_pressed.bind(tool_id))
		row.add_child(btn)
		_tool_buttons[tool_id] = btn

	row.add_child(VSeparator.new())

	_undo_button = Button.new()
	_undo_button.text = "Undo"
	_undo_button.tooltip_text = "Ctrl+Z"
	_undo_button.disabled = true
	_undo_button.custom_minimum_size = Vector2(56.0, 40.0)
	_apply_flat_button_style(_undo_button)
	_undo_button.pressed.connect(_on_undo_pressed)
	row.add_child(_undo_button)

	_redo_button = Button.new()
	_redo_button.text = "Redo"
	_redo_button.tooltip_text = "Ctrl+Y"
	_redo_button.disabled = true
	_redo_button.custom_minimum_size = Vector2(56.0, 40.0)
	_apply_flat_button_style(_redo_button)
	_redo_button.pressed.connect(_on_redo_pressed)
	row.add_child(_redo_button)


func _refresh_toolbar_highlight() -> void:
	for tool_id in _tool_buttons.keys():
		_apply_active_button_style(_tool_buttons[tool_id], tool_id == _current_tool)


func _on_tool_button_pressed(tool_id: int) -> void:
	tool_button_pressed.emit(tool_id)


func _on_undo_pressed() -> void:
	undo_pressed.emit()


func _on_redo_pressed() -> void:
	redo_pressed.emit()


func _on_tool_changed(tool_id: int) -> void:
	_current_tool = tool_id
	_refresh_toolbar_highlight()
	_refresh_context_panel()
	if tool_id != TOOL_NONE:
		# Arming a tool clears the villager selection (TR-villager-info-ui-043).
		_villager_panel.deselect()


func _on_undo_state_changed(can_undo: bool, can_redo: bool) -> void:
	_undo_button.disabled = not can_undo
	_redo_button.disabled = not can_redo


# ---------------------------------------------------------------------------
# Z5 - Context panel (material palette / height stepper / formation picker / furniture)
# ---------------------------------------------------------------------------

func _build_context_panel() -> void:
	_context_panel = PanelContainer.new()
	_context_panel.name = "Z5_Context"
	_context_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_context_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_context_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_context_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_context_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_context_panel.offset_left = -ZONE_HALF_WIDTH
	_context_panel.offset_right = ZONE_HALF_WIDTH
	_context_panel.offset_bottom = -(EDGE_MARGIN + TOOLBAR_HEIGHT_ESTIMATE + ZONE_GAP)
	_context_panel.offset_top = _context_panel.offset_bottom - CONTEXT_PANEL_HEIGHT
	_context_panel.visible = false
	_context_panel.mouse_entered.connect(_set_hover.bind("context", true))
	_context_panel.mouse_exited.connect(_set_hover.bind("context", false))
	add_child(_context_panel)

	_context_content = VBoxContainer.new()
	_context_content.add_theme_constant_override("separation", 6)
	_context_panel.add_child(_context_content)


func _refresh_context_panel() -> void:
	for child in _context_content.get_children():
		child.queue_free()

	if _current_tool == TOOL_NONE:
		_context_panel.visible = false
		return

	_context_panel.visible = true

	match _current_tool:
		TOOL_WALL, TOOL_FLOOR, TOOL_ROOF, TOOL_BLOCK:
			_build_material_palette(ResourceItemDatabase.list_by_category("building_material"))
			if _current_tool == TOOL_WALL:
				_build_height_stepper()
			if _current_tool == TOOL_ROOF:
				_build_formation_picker()
		TOOL_FURNITURE:
			_build_material_palette(ResourceItemDatabase.list_by_category("furniture_fixture"))
		_:
			pass


func _build_material_palette(items: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_context_content.add_child(row)

	if items.is_empty():
		# Explicit empty state, never a broken panel (TR-resource-item-database-044).
		var empty_label := Label.new()
		empty_label.text = "No items available"
		empty_label.add_theme_color_override("font_color", COLOR_TEXT)
		empty_label.add_theme_font_size_override("font_size", 16)
		row.add_child(empty_label)
		return

	for item in items:
		var item_id: String = item.id
		var item_box := HBoxContainer.new()
		item_box.add_theme_constant_override("separation", 4)

		var swatch := ColorRect.new()
		swatch.color = item.color
		swatch.custom_minimum_size = Vector2(16.0, 16.0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_box.add_child(swatch)

		var btn := Button.new()
		btn.text = String(item.display_name)
		btn.tooltip_text = String(item.display_name)
		btn.custom_minimum_size = Vector2(72.0, 32.0)
		_apply_flat_button_style(btn)
		_apply_active_button_style(btn, item_id == _current_material)
		btn.pressed.connect(_on_material_button_pressed.bind(item_id))
		item_box.add_child(btn)

		row.add_child(item_box)


func _on_material_button_pressed(item_id: String) -> void:
	material_selected.emit(item_id)


func _on_palette_changed(item_id: String) -> void:
	_current_material = item_id
	_refresh_context_panel()


func _build_height_stepper() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_context_content.add_child(row)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.tooltip_text = "F"
	minus_btn.custom_minimum_size = Vector2(32.0, 32.0)
	_apply_flat_button_style(minus_btn)
	minus_btn.pressed.connect(_on_height_step.bind(-1))
	row.add_child(minus_btn)

	var value_label := Label.new()
	value_label.text = str(_current_wall_height)
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", COLOR_TEXT)
	value_label.custom_minimum_size = Vector2(32.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.tooltip_text = "R"
	plus_btn.custom_minimum_size = Vector2(32.0, 32.0)
	_apply_flat_button_style(plus_btn)
	plus_btn.pressed.connect(_on_height_step.bind(1))
	row.add_child(plus_btn)


func _on_height_step(delta: int) -> void:
	var new_height: int = clampi(_current_wall_height + delta, 1, 8)
	wall_height_set.emit(new_height)


func _on_wall_height_changed(h: int) -> void:
	_current_wall_height = h
	_refresh_context_panel()


func _build_formation_picker() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_context_content.add_child(row)

	for formation_name: String in ROOF_FORMATIONS:
		var functional: bool = formation_name == "Flat"
		var btn := Button.new()
		btn.text = formation_name
		btn.custom_minimum_size = Vector2(64.0, 32.0)
		btn.disabled = not functional
		_apply_flat_button_style(btn)
		if functional:
			_apply_active_button_style(btn, formation_name == _current_formation)
			btn.pressed.connect(_on_formation_button_pressed.bind(formation_name))
		else:
			btn.tooltip_text = "Not implemented in this slice"
		row.add_child(btn)


func _on_formation_button_pressed(formation_name: String) -> void:
	formation_selected.emit(formation_name)


func _on_formation_changed(formation_name: String) -> void:
	_current_formation = formation_name
	_refresh_context_panel()


# ---------------------------------------------------------------------------
# Z1 - Time controls (pause + speed) + pause dim
# ---------------------------------------------------------------------------

func _build_time_controls() -> void:
	var panel := PanelContainer.new()
	panel.name = "Z1_TimeControls"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = -(EDGE_MARGIN + RIGHT_ZONE_WIDTH)
	panel.offset_right = -EDGE_MARGIN
	panel.offset_top = EDGE_MARGIN
	panel.offset_bottom = EDGE_MARGIN + TIME_CONTROLS_HEIGHT_ESTIMATE
	panel.mouse_entered.connect(_set_hover.bind("time", true))
	panel.mouse_exited.connect(_set_hover.bind("time", false))
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	_pause_button = Button.new()
	_pause_button.custom_minimum_size = Vector2(36.0, 32.0)
	_apply_flat_button_style(_pause_button)
	_pause_button.pressed.connect(_on_pause_button_pressed)
	row.add_child(_pause_button)

	row.add_child(VSeparator.new())

	for warp: int in TimeTickSystem.WARPS:
		var btn := Button.new()
		btn.text = "%dx" % warp
		btn.custom_minimum_size = Vector2(36.0, 32.0)
		_apply_flat_button_style(btn)
		btn.pressed.connect(_on_speed_button_pressed.bind(warp))
		row.add_child(btn)
		_speed_buttons[warp] = btn

	_pause_dim = ColorRect.new()
	_pause_dim.name = "PauseDim"
	_pause_dim.color = Color(0.0, 0.0, 0.0, 0.15)
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_dim.visible = false
	add_child(_pause_dim)
	move_child(_pause_dim, 0)  # behind all other HUD chrome, in front of the 3D world

	TimeTickSystem.time_state_changed.connect(_on_time_state_changed)
	_refresh_time_controls(TimeTickSystem.get_paused(), TimeTickSystem.get_warp())


func _on_pause_button_pressed() -> void:
	TimeTickSystem.set_paused(not TimeTickSystem.get_paused())


func _on_speed_button_pressed(warp: int) -> void:
	TimeTickSystem.set_warp(warp)


func _on_time_state_changed(paused: bool, warp: int) -> void:
	_refresh_time_controls(paused, warp)


func _refresh_time_controls(paused: bool, warp: int) -> void:
	_pause_button.text = "▶" if paused else "⏸"
	_pause_button.tooltip_text = "Resume (Space)" if paused else "Pause (Space)"
	_pause_dim.visible = paused
	for w in _speed_buttons.keys():
		_apply_active_button_style(_speed_buttons[w], w == warp)


# ---------------------------------------------------------------------------
# Z2 / Z3 - Toast stack + issues anchor
# ---------------------------------------------------------------------------

func _build_toast_zone() -> void:
	var panel := PanelContainer.new()
	panel.name = "Z2_Toasts"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = -(EDGE_MARGIN + RIGHT_ZONE_WIDTH)
	panel.offset_right = -EDGE_MARGIN
	panel.offset_top = EDGE_MARGIN + TIME_CONTROLS_HEIGHT_ESTIMATE + ZONE_GAP
	panel.offset_bottom = panel.offset_top + TOAST_MAX_VISIBLE * (TOAST_HEIGHT_ESTIMATE + ZONE_GAP)
	panel.mouse_entered.connect(_set_hover.bind("toast", true))
	panel.mouse_exited.connect(_set_hover.bind("toast", false))
	add_child(panel)

	_toast_container = VBoxContainer.new()
	_toast_container.add_theme_constant_override("separation", 6)
	panel.add_child(_toast_container)


func _refresh_toast_display() -> void:
	for child in _toast_container.get_children():
		child.queue_free()

	var now: float = Time.get_ticks_msec() / 1000.0
	var eligible: Array = []
	for key in _toasts.keys():
		var data: Dictionary = _toasts[key]
		if float(data["dismissed_until"]) <= now:
			eligible.append(key)
	eligible.sort_custom(_sort_toast_keys)

	_toast_visible_keys = eligible.slice(0, TOAST_MAX_VISIBLE)
	for key in _toast_visible_keys:
		_toast_container.add_child(_make_toast_row(key, _toasts[key]))

	_refresh_anchor()


func _sort_toast_keys(a: String, b: String) -> bool:
	var da: Dictionary = _toasts[a]
	var db: Dictionary = _toasts[b]
	if da["severity"] != db["severity"]:
		return da["severity"] > db["severity"]  # warning outranks info
	return da["first_seen"] < db["first_seen"]  # longest-waiting first


func _make_toast_row(key: String, data: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _make_panel_style())
	row.custom_minimum_size = Vector2(0.0, TOAST_HEIGHT_ESTIMATE)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var is_warning: bool = int(data["severity"]) == 1

	var icon := Label.new()
	icon.text = "!" if is_warning else "i"
	icon.add_theme_color_override("font_color", COLOR_STATE_ORANGE if is_warning else COLOR_STATE_BLUE)
	icon.add_theme_font_size_override("font_size", 18)
	hbox.add_child(icon)

	var text_label := Label.new()
	text_label.text = String(data["text"])
	text_label.add_theme_color_override("font_color", COLOR_TEXT)
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_label)

	var dismiss_btn := Button.new()
	dismiss_btn.text = "X"
	dismiss_btn.tooltip_text = "Dismiss"
	dismiss_btn.custom_minimum_size = Vector2(24.0, 24.0)
	_apply_flat_button_style(dismiss_btn)
	dismiss_btn.pressed.connect(_on_toast_dismiss_pressed.bind(key))
	hbox.add_child(dismiss_btn)

	return row


func _on_toast_dismiss_pressed(key: String) -> void:
	if not _toasts.has(key):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	_toasts[key]["dismissed_until"] = now + TOAST_DISMISS_SECONDS
	_refresh_toast_display()


func _reconcile_toasts() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var stale_keys: Array = []
	for key in _toasts.keys():
		if now - float(_toasts[key]["last_seen"]) > TOAST_STALE_SECONDS:
			stale_keys.append(key)
	if stale_keys.is_empty():
		return
	for key in stale_keys:
		_toasts.erase(key)
	_refresh_toast_display()


func _on_sealed_space_warning(cells: Array, _item_ids: Array, why: String) -> void:
	if cells.is_empty():
		return
	show_toast("sealed:%s" % str(cells[0]), 1, why)


func _on_unsheltered_furniture_info(cell: Vector3i, why: String) -> void:
	show_toast("unshelter:%s" % str(cell), 0, why)


func _build_anchor() -> void:
	_anchor_zone = PanelContainer.new()
	_anchor_zone.name = "Z3_Anchor"
	_anchor_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_anchor_zone.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_anchor_zone.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_anchor_zone.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_anchor_zone.grow_vertical = Control.GROW_DIRECTION_END
	_anchor_zone.offset_left = -(EDGE_MARGIN + RIGHT_ZONE_WIDTH)
	_anchor_zone.offset_right = -EDGE_MARGIN
	_anchor_zone.offset_top = EDGE_MARGIN + TIME_CONTROLS_HEIGHT_ESTIMATE + ZONE_GAP \
		+ TOAST_MAX_VISIBLE * (TOAST_HEIGHT_ESTIMATE + ZONE_GAP)
	_anchor_zone.offset_bottom = _anchor_zone.offset_top + 200.0  # room for chip + expanded list
	_anchor_zone.visible = false
	_anchor_zone.mouse_entered.connect(_set_hover.bind("anchor", true))
	_anchor_zone.mouse_exited.connect(_set_hover.bind("anchor", false))
	add_child(_anchor_zone)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_anchor_zone.add_child(vbox)

	_anchor_button = Button.new()
	_anchor_button.custom_minimum_size = Vector2(80.0, 28.0)
	_apply_flat_button_style(_anchor_button)
	_anchor_button.pressed.connect(_on_anchor_button_pressed)
	vbox.add_child(_anchor_button)

	_anchor_expanded_panel = PanelContainer.new()
	_anchor_expanded_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_anchor_expanded_panel.visible = false
	vbox.add_child(_anchor_expanded_panel)

	_anchor_expanded_list = VBoxContainer.new()
	_anchor_expanded_list.add_theme_constant_override("separation", 4)
	_anchor_expanded_panel.add_child(_anchor_expanded_list)


func _refresh_anchor() -> void:
	var overflow_keys: Array = []
	for key in _toasts.keys():
		if not _toast_visible_keys.has(key):
			overflow_keys.append(key)
	_anchor_entries_cache = overflow_keys

	if overflow_keys.is_empty():
		_anchor_zone.visible = false
		_anchor_expanded = false
		_anchor_expanded_panel.visible = false
		return

	_anchor_zone.visible = true
	_anchor_button.text = "%d !" % overflow_keys.size()
	_anchor_expanded_panel.visible = _anchor_expanded
	if _anchor_expanded:
		_rebuild_anchor_list()


func _on_anchor_button_pressed() -> void:
	_anchor_expanded = not _anchor_expanded
	_anchor_expanded_panel.visible = _anchor_expanded
	if _anchor_expanded:
		_rebuild_anchor_list()


func _rebuild_anchor_list() -> void:
	for child in _anchor_expanded_list.get_children():
		child.queue_free()

	var sorted_keys: Array = _anchor_entries_cache.duplicate()
	sorted_keys.sort_custom(_sort_toast_keys)

	for key in sorted_keys:
		if not _toasts.has(key):
			continue
		var data: Dictionary = _toasts[key]
		var label := Label.new()
		var prefix: String = "!" if int(data["severity"]) == 1 else "i"
		label.text = "%s %s" % [prefix, String(data["text"])]
		label.add_theme_color_override("font_color", COLOR_TEXT)
		label.add_theme_font_size_override("font_size", 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_anchor_expanded_list.add_child(label)


# ---------------------------------------------------------------------------
# Z4 - Villager panel host + selection wiring + overhead distress icons
# ---------------------------------------------------------------------------

func _build_villager_panel() -> void:
	_villager_panel = VillagerPanelScript.new()
	_villager_panel.name = "Z4_VillagerPanel"
	add_child(_villager_panel)
	_villager_panel.mouse_entered.connect(_set_hover.bind("villager_panel", true))
	_villager_panel.mouse_exited.connect(_set_hover.bind("villager_panel", false))


func _on_build_click(pressed: bool) -> void:
	if not pressed:
		return
	if _building_system.get_active_tool() != TOOL_NONE:
		return
	var ray: Dictionary = _camera_input.get_world_ray()
	var villager_id: Variant = _villager_ai.pick_villager(ray["origin"], ray["dir"], 200.0)
	if villager_id == null:
		_villager_panel.deselect()
	else:
		_villager_panel.select(villager_id)


func _update_distress_icons() -> void:
	if _villager_ai == null:
		return

	var ids: Array = _villager_ai.get_villager_ids()
	var seen: Dictionary = {}

	for id in ids:
		var info: Dictionary = _villager_ai.get_info(id)
		var distress: String = String(info.get("distress", ""))
		if distress == "":
			if _distress_icons.has(id):
				_distress_icons[id].queue_free()
				_distress_icons.erase(id)
			continue

		seen[id] = true
		var marker: Node3D = _distress_icons.get(id)
		if marker == null:
			marker = _make_distress_marker()
			_distress_icons[id] = marker

		var visual_pos: Vector3 = info.get("visual_pos", Vector3.ZERO)
		marker.global_position = visual_pos + Vector3(0.0, 1.4, 0.0)

	var stale_ids: Array = []
	for id in _distress_icons.keys():
		if not seen.has(id):
			stale_ids.append(id)
	for id in stale_ids:
		_distress_icons[id].queue_free()
		_distress_icons.erase(id)


func _make_distress_marker() -> Node3D:
	var marker := Node3D.new()
	marker.name = "DistressIcon"

	var label := Label3D.new()
	label.text = "!"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # full billboard (P13, user decision 2026-07-11)
	label.modulate = COLOR_STATE_ORANGE
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.font_size = 72
	label.outline_size = 12
	label.pixel_size = 0.01
	label.no_depth_test = true  # readability outranks physicality for a distress signal
	marker.add_child(label)

	add_child(marker)
	return marker


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _set_hover(zone: String, hovering: bool) -> void:
	_hover_flags[zone] = hovering


func _make_panel_style(bg: Color = COLOR_CHROME) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _apply_flat_button_style(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _make_panel_style(COLOR_CHROME))
	btn.add_theme_stylebox_override("hover", _make_panel_style(COLOR_CHROME.lightened(0.12)))
	btn.add_theme_stylebox_override("pressed", _make_panel_style(COLOR_CHROME.lightened(0.20)))
	btn.add_theme_stylebox_override("disabled", _make_panel_style(COLOR_CHROME))
	btn.add_theme_stylebox_override("focus", _make_panel_style(COLOR_CHROME.lightened(0.08)))
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	btn.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT.darkened(0.4))
	btn.add_theme_font_size_override("font_size", 16)


func _apply_active_button_style(btn: Button, active: bool) -> void:
	if not active:
		_apply_flat_button_style(btn)
		return
	var gold := _make_panel_style(COLOR_GOLD)
	btn.add_theme_stylebox_override("normal", gold)
	btn.add_theme_stylebox_override("hover", gold)
	btn.add_theme_stylebox_override("pressed", gold)
	btn.add_theme_stylebox_override("focus", gold)
	btn.add_theme_color_override("font_color", COLOR_CHROME)
	btn.add_theme_color_override("font_hover_color", COLOR_CHROME)
	btn.add_theme_color_override("font_pressed_color", COLOR_CHROME)
	btn.add_theme_font_size_override("font_size", 16)
