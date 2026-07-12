# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: full build->furnish->live loop, unguided <=5 min, cozy at scale
# Date: 2026-07-12
# Root integrator: boot order, wiring, environment (fog/light per art bible),
# warmth-as-reward room lights. Slice-relaxed: code wiring instead of @export.
extends Node3D

const VoxelWorldScript := preload("res://voxel_world.gd")
const CameraInputScript := preload("res://camera_input.gd")
const BuildingSystemScript := preload("res://building_system.gd")
const VillagerAIScript := preload("res://villager_ai.gd")
const NeedsMoodScript := preload("res://needs_mood.gd")
const BuildValidationScript := preload("res://build_validation.gd")
const HudScript := preload("res://hud.gd")

const ROOM_LIGHT_COLOR := Color(0.96, 0.66, 0.24)  # Hearth Gold family
const FOG_COLOR := Color("6B8593")                  # Threshold Cool (art bible fog hue)

var voxel_world: Node3D
var camera_input: Node3D
var building_system: Node3D
var villager_ai: Node3D
var needs_mood: Node
var build_validation: Node
var hud: CanvasLayer

var _room_lights: Dictionary = {}  # anchor cell (Vector3i) -> OmniLight3D


func _ready() -> void:
	# Autoloads are fully ready before the main scene (boot gate, slice-reduced).
	assert(ResourceItemDatabase.is_ready(), "RID must be Ready before world boot")

	voxel_world = VoxelWorldScript.new()
	voxel_world.name = "VoxelWorld"
	add_child(voxel_world)
	voxel_world.setup()

	camera_input = CameraInputScript.new()
	camera_input.name = "CameraInput"
	add_child(camera_input)
	camera_input.setup(voxel_world.get_region_aabb())

	needs_mood = NeedsMoodScript.new()
	needs_mood.name = "NeedsMood"
	add_child(needs_mood)

	build_validation = BuildValidationScript.new()
	build_validation.name = "BuildValidation"
	add_child(build_validation)

	hud = HudScript.new()
	hud.name = "Hud"
	add_child(hud)

	building_system = BuildingSystemScript.new()
	building_system.name = "BuildingSystem"
	add_child(building_system)
	building_system.setup(voxel_world, camera_input, hud)

	villager_ai = VillagerAIScript.new()
	villager_ai.name = "VillagerAI"
	add_child(villager_ai)

	# Order matters: villager_ai connects to tick BEFORE needs_mood so
	# start/stop_recovery reports land before that tick's decay pass (GDD Rule 10).
	villager_ai.setup(voxel_world, building_system, needs_mood)
	needs_mood.setup(build_validation)
	build_validation.setup(voxel_world, building_system, VillagerAIScript)
	hud.setup(building_system, camera_input, villager_ai, needs_mood, build_validation)

	_wire_optional_providers()
	_wire_time_actions()
	_setup_environment()

	build_validation.room_recognized.connect(_on_room_recognized)
	if building_system.has_signal("cells_removed"):
		building_system.cells_removed.connect(func(_cells: Array) -> void: _revalidate_room_lights())


func _wire_optional_providers() -> void:
	# Contract additions reported by module agents — wire defensively.
	if villager_ai.has_method("set_shelter_provider"):
		villager_ai.set_shelter_provider(build_validation.is_cell_sheltered)
	if needs_mood.has_method("set_context_provider") and villager_ai.has_method("get_bed_context"):
		needs_mood.set_context_provider(villager_ai.get_bed_context)
	if needs_mood.has_method("set_distress_provider"):
		needs_mood.set_distress_provider(func(id: int) -> String:
			return villager_ai.get_info(id).get("distress", ""))


func _wire_time_actions() -> void:
	camera_input.action_fired.connect(_on_time_action)


func _on_time_action(action: String) -> void:
	match action:
		"time_pause":
			TimeTickSystem.toggle_paused()
		"time_speed_up":
			TimeTickSystem.set_warp(mini(TimeTickSystem.get_warp() + 1, 3))
		"time_speed_down":
			TimeTickSystem.set_warp(maxi(TimeTickSystem.get_warp() - 1, 1))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.45, 0.58, 0.72)
	sky_mat.sky_horizon_color = Color(0.78, 0.75, 0.68)   # warm-neutral horizon
	sky_mat.ground_bottom_color = Color(0.22, 0.20, 0.18)
	sky_mat.ground_horizon_color = Color(0.60, 0.56, 0.50)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	# Cozy-at-scale: distance fog keeps the settlement core intimate.
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = 0.0035  # slice tuning: keep the core warm/readable, fog owns the horizon
	env.fog_sky_affect = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.80)  # warm golden-hour key light
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _on_room_recognized(cells: Array, _celebrate: bool) -> void:
	# Warmth-as-reward: a recognized room earns a warm interior light.
	if cells.is_empty():
		return
	var sum := Vector3.ZERO
	for c: Vector3i in cells:
		sum += Vector3(c) + Vector3(0.5, 0.5, 0.5)
	var center := sum / float(cells.size())
	var anchor: Vector3i = cells[0]
	if _room_lights.has(anchor):
		return
	var light := OmniLight3D.new()
	light.position = center + Vector3(0, 0.8, 0)
	light.light_color = ROOM_LIGHT_COLOR
	light.light_energy = 1.3
	light.omni_range = 6.5
	add_child(light)
	_room_lights[anchor] = light


func _revalidate_room_lights() -> void:
	# A light survives only while its anchor cell is still sheltered.
	for anchor: Vector3i in _room_lights.keys():
		if not build_validation.is_cell_sheltered(anchor):
			(_room_lights[anchor] as OmniLight3D).queue_free()
			_room_lights.erase(anchor)
