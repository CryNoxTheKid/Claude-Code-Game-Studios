## Settlement overview capture — an honest look at the SHIPPED game.
##
## Every other capture tool in `tools/` frames one specific thing (a torch, a
## villager body) and several of them add their own placeholder ground plane
## for legibility. That is correct for the evidence they were written for, but
## it means none of them answers the plainest question there is:
##
##     If a human launched this game right now, what would they see?
##
## This tool answers exactly that and nothing else. It instantiates the REAL,
## UNMODIFIED `res://src/scene_world_management/game_world.tscn`, waits for its
## real boot gate to reach ACTIVE, lets the simulation run for a moment so
## villagers actually move, and then photographs the settlement from above and
## from an eye-level angle.
##
## Deliberate constraints, so the picture cannot flatter the build:
##  * NO placeholder ground plane. Whatever ground appears is the real meshed
##    voxel terrain, or there is no ground.
##  * NO fabricated villagers, buildings or props. Whatever figures appear were
##    spawned by the real roster spawn.
##  * The camera is supplied by this tool ONLY because the shipped scene hosts
##    no [Camera3D] at all (see the report line this tool prints). That is a
##    finding, not a fixture — when a camera-hosting story lands, this tool
##    should drive the shipped camera instead.
##
## Lighting IS applied here (the art bible's golden-hour recipe, same values as
## `tools/m01_c4_valley_ambient_capture.gd`) because an unlit scene renders as
## a black rectangle regardless of what is in it — that would hide content, not
## reveal it, which is the opposite of this tool's purpose.
##
## Run WINDOWED (a real viewport is required — this cannot run headless):
##   Godot_v4.7-stable_win64_console.exe --path neues-spiel res://tools/settlement_overview_capture.tscn
extends Node3D

const GameWorldScene: PackedScene = preload("res://src/scene_world_management/game_world.tscn")

const EVIDENCE_DIR := "res://../production/qa/evidence"

## Real seconds to let the simulation tick after ACTIVE, so villagers have
## actually decided and moved before the shutter opens.
const SETTLE_SEC := 3.0

## Hard wall-clock safety cap — force an early quit if the boot gate never
## settles, mirroring the self-quit precedent every other tool scene here uses.
const SAFETY_CAP_SEC := 60.0

@onready var _camera: Camera3D = $Camera3D
@onready var _light: DirectionalLight3D = $DirectionalLight3D
@onready var _world_environment: WorldEnvironment = $WorldEnvironment

var _world: Node
var _boot_start_usec: int = 0
var _active_usec: int = 0
var _phase: int = 0  # 0 = waiting for boot, 1 = settling, 2 = capturing, 3 = done
var _shot_index: int = 0


func _ready() -> void:
	_boot_start_usec = Time.get_ticks_usec()
	_apply_golden_hour_lighting()
	_world = GameWorldScene.instantiate()
	add_child(_world)


func _apply_golden_hour_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.85, 0.68, 0.5)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.98, 0.94, 0.86)
	environment.ambient_light_energy = 0.5
	environment.ssao_enabled = false
	_world_environment.environment = environment

	_light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	_light.light_color = Color(1.0, 0.93, 0.80)
	_light.light_energy = 1.7
	_light.shadow_enabled = true
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_light.directional_shadow_max_distance = 400.0
	_light.shadow_blur = 1.0

	_camera.current = true
	_camera.far = 4000.0


func _process(_delta: float) -> void:
	var elapsed: float = (Time.get_ticks_usec() - _boot_start_usec) / 1000000.0
	if elapsed > SAFETY_CAP_SEC and _phase != 3:
		push_warning("settlement_overview_capture: SAFETY CAP hit (%0.1fs) — forcing quit" % elapsed)
		get_tree().quit()
		return

	match _phase:
		0:
			_wait_for_boot_active(elapsed)
		1:
			if (Time.get_ticks_usec() - _active_usec) / 1000000.0 >= SETTLE_SEC:
				_phase = 2
		2:
			# Set the phase FIRST: _capture_all() awaits between shots, so
			# without this _process would re-enter it on the very next frame
			# and start a second, interleaved capture run.
			_phase = 3
			_capture_all()


func _wait_for_boot_active(elapsed: float) -> void:
	if not _world.has_method("get_boot_state"):
		return
	# BootState.ACTIVE == 2 in game_world.gd's own enum.
	if int(_world.get_boot_state()) != 2:
		return
	_active_usec = Time.get_ticks_usec()
	_phase = 1
	print("settlement_overview_capture: real GameWorld reached ACTIVE after %0.2fs" % elapsed)
	_report_what_the_shipped_scene_actually_hosts()


## Prints the plain truth about the shipped scene, so the screenshot is read
## with the right expectations instead of being over- or under-interpreted.
func _report_what_the_shipped_scene_actually_hosts() -> void:
	var valley: Node = _world.get_valley() if _world.has_method("get_valley") else null
	if valley == null:
		print("settlement_overview_capture: REPORT — no Valley attached at all")
		return

	var villagers: Array = valley.get_villagers() if valley.has_method("get_villagers") else []
	print("settlement_overview_capture: REPORT — villagers spawned: %d" % villagers.size())

	var grid: Object = valley.get_voxel_world() if valley.has_method("get_voxel_world") else null
	if grid != null and grid.has_method("get_solid_cell_count"):
		print("settlement_overview_capture: REPORT — solid cells in grid: %d" % grid.get_solid_cell_count())

	var hosted_camera_count: int = _count_cameras(valley)
	print("settlement_overview_capture: REPORT — Camera3D nodes hosted by the shipped Valley: %d" % hosted_camera_count)
	if hosted_camera_count == 0:
		print("settlement_overview_capture: REPORT — the shipped game hosts NO camera; this tool supplies its own.")

	for villager in villagers:
		if villager.has_method("get_current_cell"):
			print("settlement_overview_capture: REPORT — villager at %s" % str(villager.get_current_cell()))


func _count_cameras(node: Node) -> int:
	var count: int = 1 if node is Camera3D else 0
	for child in node.get_children():
		count += _count_cameras(child)
	return count


## Frames the settlement — the world centre, which is where
## [VillagerRosterSpawner] actually places the starting roster.
##
## Deliberately NOT the mean of every villager position. The shipped scene
## hosts a default villager (villager_id 0) that the roster spawner never
## places, so it sits at cell (0, 0, 0) — the far world corner, ~1400 cells
## from the real settlement. Averaging the two put the camera in empty space
## between them and produced a photograph of nothing. That stray villager is a
## real finding (reported above by [method
## _report_what_the_shipped_scene_actually_hosts]), not something this tool
## should quietly frame around; the picture should show the settlement.
func _focus_point() -> Vector3:
	var valley: Node = _world.get_valley() if _world.has_method("get_valley") else null
	if valley == null:
		return Vector3.ZERO

	# Prefer the real, roster-placed villagers: everything except the stray at
	# the origin. If they all sit at the origin, fall back to the world centre.
	var villagers: Array = valley.get_villagers() if valley.has_method("get_villagers") else []
	var sum := Vector3.ZERO
	var counted: int = 0
	for villager in villagers:
		if not villager.has_method("get_current_cell"):
			continue
		var cell: Vector3i = villager.get_current_cell()
		if cell == Vector3i.ZERO:
			continue
		sum += Vector3(cell.x, cell.y, cell.z)
		counted += 1
	if counted > 0:
		return sum / float(counted)

	var grid: Object = valley.get_voxel_world() if valley.has_method("get_voxel_world") else null
	if grid != null and "config" in grid:
		var centre: Vector3i = VillagerRosterSpawner.world_center_cell(grid.config)
		return Vector3(centre.x, centre.y, centre.z)
	return Vector3.ZERO


## Each shot MUST be awaited. [method _shoot] moves the camera and then yields
## until the next completed draw; firing all three without awaiting would let
## the last camera position win before any of them rendered, and all three PNGs
## would be the identical frame (observed — this is a fix, not a precaution).
func _capture_all() -> void:
	var focus: Vector3 = _focus_point()
	print("settlement_overview_capture: focusing on %s" % str(focus))

	await _shoot(focus + Vector3(0.0, 70.0, 0.1), focus, "settlement-overview-topdown")
	await _shoot(focus + Vector3(-22.0, 14.0, 22.0), focus, "settlement-overview-eyelevel")
	await _shoot(focus + Vector3(-5.0, 2.5, 5.0), focus, "settlement-overview-closeup")

	# DIAGNOSTIC PAIR, not a retune. At the art bible's own golden-hour values
	# the terrain reads as near-white pale yellow, which raises a fair question:
	# is the terrain material actually colourless, or is it just blown out?
	# These extra frames answer it by dropping only the exposure and changing
	# nothing else. The art-bible frames above remain the reference; these are
	# labelled `-dimmed` precisely so nobody mistakes them for the shipped look.
	_light.light_energy = 0.95
	_world_environment.environment.ambient_light_energy = 0.28
	await _shoot(focus + Vector3(-22.0, 14.0, 22.0), focus, "settlement-overview-eyelevel-dimmed")
	await _shoot(focus + Vector3(0.0, 70.0, 0.1), focus, "settlement-overview-topdown-dimmed")

	get_tree().quit()


func _shoot(camera_position: Vector3, look_at_point: Vector3, name_stem: String) -> void:
	_camera.position = camera_position
	_camera.look_at(look_at_point, Vector3.UP)
	# Force the just-moved camera's own frame to be the one rendered.
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var evidence_dir: String = ProjectSettings.globalize_path(EVIDENCE_DIR)
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	_shot_index += 1
	var path: String = "%s/%s-%d.png" % [evidence_dir, name_stem, _shot_index]
	var err: Error = image.save_png(path)
	if err != OK:
		push_warning("settlement_overview_capture: save failed (%d) for %s" % [err, path])
		return
	print("settlement_overview_capture: saved %s" % path)
