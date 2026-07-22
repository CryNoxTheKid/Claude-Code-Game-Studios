# Slice Module Contracts (Day 1) — the integration source of truth

> VERTICAL SLICE — NOT FOR PRODUCTION. Every module implements EXACTLY these
> signatures so parallel-written modules integrate without rework. Slice-quality:
> constants instead of .tres configs are fine; keep the architecture SHAPE
> (setup() wiring, signals, clock split) from docs/architecture/control-manifest.md.

## Global constants (duplicated per file is fine in slice; keep values identical)

```gdscript
const CHUNK := 16
const MAX_Y := 32
const WORLD_SIZE := 2000              # cells per horizontal axis (full data world)
const REGION_RADIUS_CHUNKS := 12      # meshed/playable window radius around center
const SEED := 1337
# Cell ids (byte values in packed chunks)
const AIR := 0
const TERRAIN_BASE := 1               # 1..4 terrain height bands
const WOOD := 10
const STONE := 11
const THATCH := 12
const BED := 20
```

World center cell = `Vector3i(WORLD_SIZE/2, 0, WORLD_SIZE/2)`; the playable
region is the chunk window `center_chunk ± REGION_RADIUS_CHUNKS` (exclusive
upper bound), i.e. 384×384 cells. Camera pan and building are clamped to it.

## Clock rule (absolute)

Camera + UI + ghost preview run on **raw delta**. Simulation (construction
ticks, needs, villager movement progress) advances ONLY via
`TimeTickSystem.game_delta` / its `tick` signal. Never blend.

## TimeTickSystem (Autoload, res://time_tick_system.gd) — WRITTEN, do not modify

```gdscript
signal tick                            # fired per simulation tick (never while paused)
signal time_state_changed(paused: bool, warp: int)
var game_delta: float                  # read-only by convention, updated in _physics_process
func set_paused(p: bool) -> void
func toggle_paused() -> void
func set_warp(w: int) -> void          # 1, 2, 3
func get_paused() -> bool
func get_warp() -> int
# Constants: TICKS_PER_SECOND=4.0, MAX_TICKS_PER_FRAME=10, MAX_RAW_DELTA=0.1
```

## ResourceItemDatabase (Autoload, res://resource_item_database.gd) — WRITTEN, do not modify

```gdscript
func is_ready() -> bool
func get_by_id(id: String) -> ItemDef            # null if unknown
func list_by_category(category: String) -> Array[ItemDef]
# ItemDef (inner class, getter-only): id, display_name, category, cell_value(int),
#   color(Color), build_ticks(int)
# ids: "wood_block", "stone_block", "thatch_block", "bed"
# categories: "building_material", "furniture_fixture"
```

## VoxelWorld (res://voxel_world.gd, Node3D, injected)

```gdscript
signal cell_changed(changes: Array)    # Array of {cell: Vector3i, before: int, after: int} — ONE emission per write call (batched)
func setup() -> void                   # terrain gen (region window only) + initial mesh build; SYNCHRONOUS
func get_cell(cell: Vector3i) -> int   # 0 = air / out of bounds handled: returns -1 out of world bounds
func set_cells(changes: Array) -> Array          # [{cell, value}] -> returns [{cell, before, after}]; ONE cell_changed emission; remeshes affected chunks
func raycast_cells(origin: Vector3, dir: Vector3, max_dist := 200.0) -> Dictionary
    # DDA. {} on miss; else {cell: Vector3i, normal: Vector3i} (normal = face stepped through, for attach-placement)
func is_in_region(cell: Vector3i) -> bool        # inside the playable window AND 0 <= y < MAX_Y
func get_region_aabb() -> AABB                   # playable region in world units (for camera clamp)
func terrain_height(x: int, z: int) -> int      # deterministic noise height (for spawn placement)
```

Meshing: per-cell face culling (face emitted where cell borders AIR), one
ArrayMesh per 16×16-column chunk, vertex colors from ItemDef color / terrain
band colors, whole-chunk rebuild on change (adjacent chunk too when a border
cell changes). `vertex_color_use_as_albedo`, proper winding + backface culling.

## CameraInput (res://camera_input.gd, Node3D with child Camera3D, injected)

```gdscript
signal action_fired(action_name: String)   # tool_select_1..5, build_cancel, undo, redo,
                                            # height_step_up/down, palette_next/prev, formation_next/prev,
                                            # time_pause, time_speed_up/down
signal build_click(pressed: bool)           # LMB press/release IN WORLD (only fired from _unhandled_input)
var remove_modifier_held: bool              # Ctrl held (slice shortcut for Block-tool remove)
func setup(world_aabb: AABB) -> void        # registers InputMap actions at runtime (slice shortcut), clamps pan to aabb
func get_world_ray() -> Dictionary          # {origin: Vector3, dir: Vector3} from current mouse pos — ALWAYS valid
func get_camera() -> Camera3D
```

Orbit rig per camera-input GDD: position derived target+spherical(distance,yaw,pitch),
pitch clamp 0.3..1.4 rad, distance 8..120, WASD pan yaw-relative scaled by
distance, Q/E yaw steps, middle-drag rotate, wheel zoom multiplicative. Raw
delta, clamped to 0.1. Pan target clamped to world_aabb (xz).

## BuildingSystem (res://building_system.gd, Node3D, injected)

```gdscript
signal tool_changed(tool_id: int)                 # 0=None, 1=Wall, 2=Floor, 3=Roof, 4=Block, 5=Furniture
signal palette_changed(material_id: String)      # current material item id
signal wall_height_changed(h: int)               # 1..8, default 3
signal formation_changed(name: String)           # "Flat" only functional; picker shows 4
signal undo_state_changed(can_undo: bool, can_redo: bool)
signal invalid_commit(world_pos: Vector3, reason: String)
signal construction_completed(cells: Array)      # batched per frame: Array[Vector3i] built this frame
signal cells_removed(cells: Array)               # batched: undo/remove of BUILT cells
signal blueprint_changed()                        # blueprint set changed (commit/cancel/complete)
signal furniture_placed(cell: Vector3i, item_id: String)
signal furniture_removed(cell: Vector3i, item_id: String)
func setup(voxel_world, camera_input, hud) -> void
func get_active_tool() -> int
func is_tool_armed() -> bool
func get_blueprint_cells() -> Dictionary          # Vector3i -> {item_id, progress_ticks, claimed_by}
func claim_job(villager_id: int) -> Variant       # nearest-by-air-dist open cell or null; locks it
func release_job(cell: Vector3i) -> void
func report_on_site(cell: Vector3i) -> void       # villager on site: progress++ per tick (called from its tick)
func is_cell_occupied_planned(cell: Vector3i) -> bool  # blocks + blueprints combined view
func get_furniture_cells() -> Dictionary          # Vector3i -> item_id (BUILT furniture only)
# --- Stonehearth build workflow (2026-07-21, user direction) ---
signal build_mode_changed(active: bool)
func set_build_mode(active: bool) -> void         # off: aborts drag, disarms, hides ghosts
func get_build_mode() -> bool                     # tools arm only in build mode (arming auto-enables)
func release_drafts() -> int                      # blueprints start as DRAFTS; villagers build only after release
func get_draft_count() -> int
```

Pipeline per building GDD: pick(DDA via voxel_world.raycast_cells with
camera_input.get_world_ray()) -> ghost preview (pooled MeshInstance3D,
blue translucent valid / orange invalid) -> LMB drag rasterize (wall = line ×
height, floor/roof = rect, per F1/F2/F5) -> release commits blueprint cells ->
jobs queue -> villager builds over time (report_on_site) -> set_cells write.
Construction of a cell DEFERRED while villager occupies it. Undo = command
level, max 50. Ghost hidden while hud.is_hover_suppressing() OR ray miss.

## VillagerAI (res://villager_ai.gd, Node3D, injected)

```gdscript
signal state_changed(villager_id: int, state: int)   # 0 Deciding,1 Traveling,2 Working,3 Sleeping,4 Breather,5 Wandering
signal distress_changed(villager_id: int, kind: String)  # "trapped"|"ground_sleeping"|"" (cleared)
func setup(voxel_world, building_system, needs_mood) -> void   # spawns 1 villager near region center; builds AStar3D graph
func get_villager_ids() -> Array[int]
func get_info(villager_id: int) -> Dictionary   # {name, state:int, state_label:String, cell:Vector3i, visual_pos:Vector3, distress:String, has_bed:bool}
func pick_villager(origin: Vector3, dir: Vector3, max_t: float) -> Variant   # id or null; slice: ray-vs-capsule math, no physics
static func is_standable(world, cell: Vector3i) -> bool
static func is_step_legal(world, from: Vector3i, to: Vector3i) -> bool
```

FSM per GDD: priority urgent-sleep > work > wander; tick-driven; movement =
current_cell atomic at tick boundary + visual lerp on game_delta; graph patched
on cell_changed (region-bounded); bed claim via building_system.get_furniture_cells();
sleeping reports needs_mood.start_recovery/stop_recovery with source enum
("bed_sheltered"/"bed_unsheltered"/"ground_..."). Villager visual: capsule/box
stack, warm-ish color, no physics body.

## NeedsMood (res://needs_mood.gd, Node, injected)

```gdscript
signal need_urgent(villager_id: int, need: String)
signal need_satisfied(villager_id: int, need: String)
signal mood_band_changed(villager_id: int, band: int)   # 0 Happy, 1 Content, 2 Low
func setup(build_validation) -> void
func register_villager(villager_id: int) -> void
func start_recovery(villager_id: int, need: String, source: String) -> void
func stop_recovery(villager_id: int, need: String, reason: String) -> void
func is_urgent(villager_id: int, need: String) -> bool
func get_display(villager_id: int) -> Dictionary  # {sleep: float 0..100, band: int, band_label: String, why: String}  why="" when happy
```

F1 decay / F2 recovery (rates x1.0 bed_sheltered, x0.7 bed_unsheltered, x0.4
ground), F3 mood EMA + snap, F4 spawn init 100, tick-driven, urgency threshold
25, satisfied 90. Why templates per GDD ("tired — no bed", "tired — trapped!",
"sleeping rough — no shelter", "tired — bed unreachable").

## BuildValidation (res://build_validation.gd, Node, injected)

```gdscript
signal room_recognized(cells: Array, celebrate: bool)
signal sealed_space_warning(cells: Array, item_ids: Array, why: String)
signal unsheltered_furniture_info(cell: Vector3i, why: String)
signal shelter_status_changed(cell: Vector3i, sheltered: bool)
func setup(voxel_world, building_system, villager_ai_script) -> void  # connects to construction_completed/cells_removed/furniture events
func is_cell_sheltered(cell: Vector3i) -> bool
```

Event-driven region BFS per GDD: candidate interior = standable + roofed
(solid within 8 above); region = orthogonal connectivity; room = >=4 cells +
walkable outside connection (movement-graph walk to open sky). Emits per pass.

## HUD (res://hud.gd, CanvasLayer, injected) — layout per design/ux/hud.md

```gdscript
signal tool_button_pressed(tool_id: int)
signal material_selected(item_id: String)
signal formation_selected(name: String)
signal wall_height_set(h: int)
signal undo_pressed() / redo_pressed()
func setup(building_system, villager_ai, needs_mood, build_validation) -> void
func is_hover_suppressing() -> bool
func show_toast(key: String, severity: int, text: String) -> void   # severity 0 info, 1 warning; keyed refresh-in-place
func retire_toast(key: String) -> void
```

Zones per hud.md: toolbar bottom-center (5 tools + undo/redo), context panel
above it, time controls top-right, toasts below, issues anchor. Flat #262220
panels, #EDE6DA text, gold #F5A83C active highlight. Instant swaps. Villager
panel (res://villager_panel.gd, part of HUD scene): per design/ux/villager-panel.md
zone Z4 left; selection owned by it (click via camera_input.build_click when no
tool armed + villager_ai.pick_villager); overhead distress icon full-billboard.

## GameWorld (res://game_world.gd + GameWorld.tscn, root) — WRITTEN by integrator

Boot: RID ready -> voxel_world.setup() -> others' setup() in dependency order ->
environment (fog per art bible: distance fog to #6B8593 Threshold Cool, warm
DirectionalLight), warmth-as-reward: OmniLight3D (amber #F5A83C, energy ~1.2)
spawned at recognized-room center on room_recognized, removed when room lost.
