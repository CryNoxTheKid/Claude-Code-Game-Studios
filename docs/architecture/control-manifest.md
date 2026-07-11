# Control Manifest

> **Engine**: Godot 4.7-stable
> **Last Updated**: 2026-07-11
> **Manifest Version**: 2026-07-11
> **ADRs Covered**: ADR-0001 … ADR-0014 (0003 Superseded by 0014 — large-world decision 2026-07-11, `prototypes/chunked-mesher/`; the rest Accepted)
> **Status**: Active — regenerate with `/create-control-manifest update` when ADRs change
> **Provenance**: TD-MANIFEST gate skipped — Lean mode (no `production/review-mode.txt`); generated during the user-delegated autonomous run 2026-07-11

`Manifest Version` is the date this manifest was generated. Story files embed
this date when created. `/story-readiness` compares a story's embedded version
to this field to detect stories written against stale rules.

This manifest is a programmer's quick-reference extracted from all Accepted ADRs,
technical preferences, and engine reference docs. For the reasoning behind each
rule, see the referenced ADR.

---

## Foundation Layer Rules

*Applies to: boot sequencing, DI/reference architecture, config loading, data definitions, save/load*

### Required Patterns
- **Hybrid reference model**: ONLY `TimeTickSystem` and `ResourceItemDatabase` are Autoloads — call them by global name in method bodies. Every other module is injected-tier: typed `@export` node references, wired exclusively in `GameWorld.tscn` via the editor Inspector — source: ADR-0001
- **All wiring/validation logic lives in an explicitly-callable `setup()`** that `GameWorld` calls in production and tests call directly; `setup()` asserts its dependencies are wired; `_ready()` does nothing beyond optionally calling `setup()` — source: ADR-0001
- **New systems default to injected-tier**; Autoload requires: genuinely single-instance, boot-early, no test-substitution need — source: ADR-0001
- **Tests**: instantiate with `Node.new()`, assign mocks to `@export` props (or pass to `setup()`), call methods directly — zero scene tree, zero Autoload registration — source: ADR-0001
- **Config**: one custom `Resource`-derived config class per module, typed `@export` fields (one per Tuning Knob, GDD defaults), stored as **`.tres` text files**; injected modules get config as another `@export`; Autoloads `load()` their own via `const CONFIG_PATH` — source: ADR-0002
- **Every config class exposes `validate() -> Array[String]`**, called once at boot in the owner's `setup()`. Single-field range issue → warn + clamp + proceed. GDD-declared BLOCKING cross-value invariant → terminal boot-halt (RID Failed pattern) — source: ADR-0002
- **Boot gate (unified)**: `GameWorld`'s Booting state gates ALL injected-tier `setup()` calls behind RID `Ready`/`Failed`. Check-then-connect: synchronous `is_ready()` first, `validation_complete.connect(..., CONNECT_ONE_SHOT)` fallback. On Failed: boot-halt screen, NO `setup()` calls, terminal. BootState: `{WAITING_FOR_DATABASE, WIRING, ACTIVE, HALTED}` — source: ADR-0005
- **Data definitions two-type split**: private `ItemDefinitionResource` (authoring, `@export`-editable) + public getter-only `ItemDefinition extends RefCounted` returned by `get_by_id()` — a fresh lightweight wrapper per call (wraps, never copies). `visual_asset` is a typed `Mesh` reference, never a path string. Boot validation: resource-null check BEFORE `visual_asset != null` check, distinct diagnostics, both terminal — source: ADR-0006
- **Save/load (VS-tier)**: plain `Dictionary` via `FileAccess.store_var()/get_var()`, single binary file, top-level keys `save_format_version` (=1 from day one), `voxel_world`, `building_system`, `villager_ai`, `needs_mood`. Each system exposes `serialize() -> Dictionary` / `deserialize(data)` — source: ADR-0012
- **Saves fire exclusively on `transition_ended(success=true)`** (cost hides behind the loading overlay) — source: ADR-0012

### Forbidden Approaches
- **Never `@export` an Autoload** (`ResourceItemDatabase`/`TimeTickSystem`) into any module — grep: `@export.*ResourceItemDatabase|@export.*TimeTickSystem` must return zero — source: ADR-0001
- **Never read `@export` dependencies inside your own `_ready()`** assuming code-assigned wiring, and never put validation in `_ready()` (headless `new()` never runs it — silent test/production mismatch) — source: ADR-0001
- **Never write to a config Resource field at runtime** — config is read-only from every consumer (grep: `config\.\w* *=` outside the config class's own clamp logic = zero). Runtime-adjustable values get their own owned state, never a shared config Resource — source: ADR-0002
- **Never `ConfigFile` or JSON for tuning data** (stringly-typed, silent-failure lookups / no typed Inspector) — source: ADR-0002
- **`ItemDefinition` has zero setters and zero writable `var`s**; nothing outside RID holds an `ItemDefinitionResource`; cross-system references are opaque string ids only — source: ADR-0006
- **Never defensive-copy via `duplicate()`** for definition queries (copies still have setters = silent-success mutation; plus per-query allocation cost) — source: ADR-0006
- **Never a custom `SaveGameData` Resource via `ResourceSaver`** (no benefit for Dictionary-only payloads; ADR-0002's Resource precedent does NOT extend to save files) and **no chunked/threaded saves** until a measured need (named escape hatch) — source: ADR-0012
- **Save data is never designer-authored, never Inspector-edited, never git-tracked** — source: ADR-0012
- **Never poll for boot readiness** (per-frame/`Timer` polling contradicts the event-driven principle — use the signal); no injected-tier `setup()` call site outside `GameWorld`'s Booting path — source: ADR-0005

### Performance Guardrails
- Wiring resolves once at scene load; revisit service-locator only if `@export` assignments exceed ~30 (MVP: 9 modules) — source: ADR-0001
- Config loads once at boot; RID tier-0 validation must stay low-single-digit ms; terrain gen stays "near-instant, no loading screen" — source: ADR-0002/0005
- Save/load synchronous at MVP/VS; Voxel World packed-chunk payload grows with the large world (~150–250 MB worst case at density — revisit compression when measured); population ceiling 20–30 villagers — source: ADR-0012 + ADR-0014

---

## Core Layer Rules

*Applies to: physics, picking, building pipeline, gameplay orchestration*

### Required Patterns
- **Jolt Physics 3D (4.6+ default), no override**; villagers carry a child `Area3D` + `CollisionShape3D`, `collision_layer = 1`, `collision_mask = 0` — source: ADR-0004
- **Block picking = manual DDA grid-walk** against Voxel World's cell data (chunked accessor), driven by Camera & Input's `get_world_ray()` — no collider of any kind involved — source: ADR-0014 (carried from ADR-0003 §3)
- **Occupancy two-layer model**: `current_cell: Vector3i` is the SOLE authoritative value for all logic (occupancy, F4 targeting, walled-in checks, `get_current_cell()`); it changes ONLY in `_on_tick()`, atomically at tick-boundary arrival. `_visual_position` is render-only — source: ADR-0009
- **Visual lerp**: `_visual_position = _from_cell.lerp(_to_cell, _intra_tick_progress)` each frame; `_intra_tick_progress` advances via `game_delta` ticks only — frozen during pause, no glide — source: ADR-0009
- **Villager visual node sets `physics_interpolation_mode = OFF` explicitly** (defends against project-wide setting flips causing double-interpolation) — source: ADR-0009
- **Race closure relies on synchronous signals**: Voxel World's `cell_changed` fires synchronously; the re-path filter redirects in the same call stack — source: ADR-0009
- **Collision-layer convention**: Layer 1 = villagers; 2–8 reserved for future gameplay; 9–20 untouched. Future ADRs extend, never redefine — source: ADR-0004
- **Building System placement pick calls ONLY the DDA step** (`raycast_cells()`) — structurally incapable of hitting villagers — source: ADR-0004
- **Drag ownership**: a drag validly begun via `_unhandled_input()` switches release-listening to `_input()` (`set_process_input(true)`) for the drag's duration; on release, immediately `get_viewport().set_input_as_handled()`, then revert to `_unhandled_input()` — source: ADR-0010
- **Cross-module config invariants** are validated by whichever module's GDD states them (documented per-instance exception, e.g. Build Validation reads Building System's config for `max_room_height >= wall_height`) — source: ADR-0002
- **Save/Load orchestrator** (new injected-tier module): collects/distributes per-system Dictionaries as opaque blobs; `save()` checks `FileAccess.open()` null (via `get_open_error()`) AND `store_var()`'s bool return; `load()` checks open-null before `get_var()`; on load Villager AI revalidates stale claims, Build Validation is NOT deserialized (full re-derive) — source: ADR-0012

### Forbidden Approaches
- **Zero physics API calls in Building System's pick path** — grep: `intersect_ray|PhysicsDirectSpaceState3D` in `src/building_system/` = zero — source: ADR-0004
- **Never `StaticBody3D`/`CharacterBody3D` on villagers** (implies unwanted collision response; movement is cell-interpolation) — source: ADR-0004
- **Never `MOUSE_MODE_CAPTURED` during placement drags** (cursor must stay visible and free) — source: ADR-0010
- **Camera & Input never interprets action names** and never emits a world action for a UI-consumed click (exactly-one-owner) — source: ADR-0010
- **Never silently swallow save/write failures** — detect, `push_error`, return false — source: ADR-0012
- **`_visual_position` is never read outside the movement/rendering path** (grep-verifiable); never integrate raw `_delta` into `_intra_tick_progress`; never flip `current_cell` at interpolation midpoint — source: ADR-0009
- **Zero `PhysicsServer3D`/`RayCast3D` in any picking path** (Voxel World AND Building System, grep-verifiable) — source: ADR-0014 (carried from ADR-0003)

### Performance Guardrails
- Villager-hit query runs once per click (event-driven, never per-frame) — source: ADR-0004
- `_input()` is actively listened to only during an in-progress drag window — source: ADR-0010

---

## Feature Layer Rules

*Applies to: AI systems, pathfinding, villager behavior*

### Required Patterns
- **Walkability = two shared pure functions** owned by Villager AI: `is_standable(cell) -> bool` (solid below + 3-cell clearance) and `is_step_legal(from, to) -> bool` (|dy| ≤ 1; diagonal only if both flanking orthogonals passable). EVERY consumer (pathfinder, Build Validation) calls these — single source of truth — source: ADR-0007
- **Travel pathfinding via `AStar3D`**: graph built once at boot, incrementally patched on `cell_changed` (never rebuilt); point IDs are deterministic bit-packed `Vector3i → int64` (`x&0x1FFFFF | y<<21 | z<<42`), never an incrementing counter — source: ADR-0007
- **Build Validation runs its own independent BFS** calling the shared predicates; it never touches Villager AI's `AStar3D` instance — source: ADR-0007
- **AI is a plain explicit FSM**: 6-state enum + `match`, strict discrete priority (Urgent need > Work > Idle/Wander); tick-driven via Time & Tick's signal, never raw delta in `_physics_process` — source: ADR-0008
- **Deciding staggering**: FIFO `Array[int]` queue + `max_deciding_per_tick` budget (config knob per ADR-0002; **spike-tuned initial value: 1**); budget caps new passes STARTED per tick, never interrupts an in-progress pass; dequeue in stable villager order — source: ADR-0008
- Villager AI exposes `serialize()/deserialize()`; `deserialize()` owns stale claim/bed-id revalidation — source: ADR-0012

### Forbidden Approaches
- **Zero `NavigationServer3D`/`NavigationAgent3D`/`NavigationRegion3D`** anywhere in Villager AI or Build Validation (grep-verifiable) — navmesh cannot express the exact cell rules — source: ADR-0007
- **Zero `Thread`/`WorkerThreadPool` in Villager AI** for MVP/VS (grep-verifiable) — occupancy dict, AStar3D graph, Needs state are not thread-safe; threading is the escape hatch only on measured need — source: ADR-0008
- **Never duplicate walkability rules or constants** — no plain 4/8-neighbor flood-fill in Build Validation, no second copy of clearance/step values — source: ADR-0007
- **Never a behavior tree or utility-AI addon** (would breach the empty Allowed-Libraries list; priorities are discrete, not scored) — source: ADR-0008

### Performance Guardrails
- Population ceiling 20–30; frame budget must hold at 1x AND 3x warp (spike-verified: p95 16.7 ms at 3x with `max_deciding_per_tick = 1`) — source: ADR-0008 + spike report
- **Watch-item**: one Deciding pass measured avg 11 ms p95 35 ms (GDScript stand-in) — mitigations before threading: cheaper pre-filter, smaller BFS bound, pass slicing — source: spike report
- `max_selection_candidates = 15` per-villager F2 budget; Build Validation BFS exceeds one frame above ~12k connected cells (documented accepted-risk boundary) — source: ADR-0007 + spike report

---

## Presentation Layer Rules

*Applies to: UI, HUD, input arbitration surface, UI timers*

### Required Patterns
- **Committed blocks render via the chunked mesher**: 16×16-column chunks, one `ArrayMesh` per chunk, faces emitted only where a cell borders air; whole-chunk rebuild on any cell change (~1.1 ms measured); view-window streaming with per-frame budgets for BOTH chunk builds AND unloads (`queue_free` bursts caused the prototype's only hitch); `visibility_range_end` on chunk instances — source: ADR-0014
- **World storage = packed chunk arrays** (~1–4 B/cell) behind the UNCHANGED Voxel World accessor API (O(1) get/set by `Vector3i`, `cell_changed`, `raycast_cells`); `Dictionary` remains fine for small lookup tables, never for bulk cells — source: ADR-0014
- **Blueprint ghosts = pooled `MeshInstance3D` nodes** with `material_override` tint; bounded by `max_cells_per_command = 512`, outline-degrade above `preview_degradation_threshold` — source: ADR-0014 (carried from ADR-0003 §4)
- **Multi-scene (Valley+Dungeon, VS+): ONE shared `World3D`**, Dungeon at fixed spatial offset (100_000 units, documented at definition site); exactly ONE `WorldEnvironment` node with swapped `.environment` resource; per-scene toggles for `Camera3D.current`, `AudioListener3D`, `DirectionalLight3D.visible` — ALL centralized in one `_activate_scene`/`_deactivate_scene` pair — source: ADR-0013
- **New-click ownership via native propagation**: HUD Controls keep default `mouse_filter = STOP`; world systems listen in `_unhandled_input()`; Camera & Input needs zero new code — source: ADR-0010
- **Hover-suppression flag**: Building UI ORs hover across its three HUD zones via `mouse_entered`/`mouse_exited` (event-driven, NEVER per-frame polling), exposed as `is_hover_suppressing_world_pick() -> bool`; consumers check it before starting any new pick/drag/selection; it also gates ghost-preview updates — source: ADR-0010
- **Villager click pick** (Idle only): DDA block distance + `intersect_ray()` with `collision_mask = 1`, **`collide_with_areas = true`, `collide_with_bodies = false`**; nearest wins, villager wins within `pick_tie_epsilon` — source: ADR-0004
- **UI timers**: ONE centralized `UITimerManager` (plain class owned by Building UI — not an Autoload, not a module) with `Dictionary[StringName, TimerRecord]` + one shared `_process(delta)` on **raw delta**; API `start_timer/cancel_timer/has_timer/get_remaining/on_suspended_begin/on_suspended_end` — source: ADR-0011
- **Suspended handling**: single `_suspended` guard at the top of the shared loop; timers freeze ONLY on Suspended (scene transitions), never on game pause; decoupled from Control visibility — source: ADR-0011
- **Two-pass expiry** (collect keys, then fire+erase); grace-expiry callbacks re-query Build Validation's current state, never trust the triggering event — source: ADR-0011
- **Every visual `Tween` pauses/resumes explicitly** (`tween.pause()/play()`) tied to the same Suspended signal — source: ADR-0011

### Forbidden Approaches
- **Never `GridMap` for committed-block rendering** (fails measurably at the large-world bound: >16 GB at 2000², 65k draw calls at 1000²); never full greedy meshing or a GDExtension mesher until measurement demands them (named reserves); never per-instance custom-data plumbing for ghost tint — source: ADR-0014
- **Never separate SubViewports with own `World3D`s** for scene concurrency; never a second `WorldEnvironment` node (grep-verifiable); never assume SubViewports isolate `_input()` (they don't); no GI system under ADR-0013 — source: ADR-0013
- **Never restructure `mouse_filter` geometry to solve drag-release** (brittle; releases legitimately land on widgets) — source: ADR-0010
- **Never N per-issue `Timer` nodes** for toast/grace/debounce timing (node churn + still needs the dictionary + violates the no-per-consumer-timers precedent) — source: ADR-0011
- **Never rely on Control visibility to pause timers/tweens** — hiding a Control pauses nothing — source: ADR-0011

### Performance Guardrails
- Timer manager iterates dozens of records max in one `_process`; suspend/resume costs one boolean flip — source: ADR-0011
- Hover flag memory: one 3-bool array; boundary-crossing events only — source: ADR-0010

---

## Global Rules (All Layers)

### Naming Conventions (technical-preferences.md)
| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `PlayerController` |
| Variables | snake_case | `move_speed` |
| Signals/Events | snake_case past tense | `health_changed` |
| Files | snake_case matching class | `player_controller.gd` |
| Scenes | PascalCase matching root node | `PlayerController.tscn` |
| Constants | UPPER_SNAKE_CASE | `MAX_HEALTH` |

### Performance Budgets (technical-preferences.md)
| Target | Value |
|--------|-------|
| Framerate | 60 FPS |
| Frame budget | 16.6 ms |
| Draw calls | ≤ 2000 (PC mid-range) |
| Memory ceiling | 4 GB |

### Approved Libraries / Addons
- **GdUnit4 v6.1.3** (`neues-spiel/addons/gdUnit4/`) — test framework (approved 2026-07-11)

### Forbidden Patterns (technical-preferences.md — project-wide, absolute)
- **`SceneTree.paused`** — pause is owned by Time & Tick (`game_delta = 0`); engine-global pause would freeze camera/UI/overlays that must run on raw delta
- **`Engine.time_scale`** — warp is owned by Time & Tick (`game_delta` multiplier)

### Forbidden / Deprecated APIs (Godot 4.7 — engine-reference/deprecated-apis.md)
Use the replacement, never the deprecated form:
- `yield()` → `await signal` · string-`connect()` → `signal.connect(callable)` · `instance()` → `instantiate()` · `get_world()` → `get_world_3d()` · `OS.get_ticks_msec()` → `Time.get_ticks_msec()`
- `TileMap` → `TileMapLayer` · `VisibilityNotifier2D/3D` → `VisibleOnScreenNotifier2D/3D` · `YSort` → `y_sort_enabled` · `Navigation2D/3D` → `NavigationServer2D/3D`
- Hardcoded input device ID `0` → `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD` (4.7 — `0` no longer guaranteed)
- `$NodePath` in `_process()` → `@onready` cached reference · untyped `Array`/`Dictionary` → typed (`Array[Type]`)
- GodotPhysics3D for new 3D work → Jolt (4.6 default; matches ADR-0004)
- NOTE: `duplicate_deep()` (4.5+) exists but ADR-0002/0006/0012 **deliberately avoid it** — do not introduce it for config/definitions/saves

### Engine Facts That Differ From LLM Instinct (verified for 4.7)
- Scene tree readies **bottom-up**: child `_ready()` before parent `_ready()`; scene-file `@export`s are populated by then, code-assigned wiring is NOT — source: ADR-0001
- `load()` on the same `.tres` path returns the **same shared object** (ResourceLoader cache) — mutations are visible project-wide; the reason config is read-only — source: ADR-0002
- `PhysicsRayQueryParameters3D` defaults: `collide_with_bodies = true`, **`collide_with_areas = false`** — an Area3D-only query without the explicit flag silently returns nothing, every time — source: ADR-0004
- Autoloads fully `_ready()` **before** the Main Scene loads (declared order, synchronous) — source: ADR-0005
- GDScript `Object.get("/_private")` bypasses the getter-only pattern — immutability guards against idiomatic misuse, not reflection — source: ADR-0006
- `FileAccess.store_*` returns `bool` since 4.4 — **check it**; `get_var()` has no success signal — the check point is `FileAccess.open()` null — source: ADR-0012
- Input routing order: `_input()` → `_gui_input()` → `_unhandled_input()`; `set_input_as_handled()` from `_input()` stops later stages — source: ADR-0010
- `Timer`/`Tween` are NOT paused by hiding their Control — source: ADR-0011
- Godot 4.6 dual-focus system separates mouse focus from keyboard/gamepad focus (hover signals unaffected) — flagged BLOCKING for HUD focus-cycling implementation (building-ui OQ7)
- **`AStarGrid3D` does NOT exist in Godot 4.7** (only `AStarGrid2D`) — manual `AStar3D` graph management is the only built-in option; `AStar3D` IDs are never auto-recycled on `remove_point()` — source: ADR-0007
- (Historical, GridMap now forbidden for blocks:) GridMap collision is octant-batched, NOT per-cell — source: ADR-0003 (Superseded)
- Default signal connections are **synchronous** (in the `emit()` call stack, connection order) — load-bearing for the ADR-0009 race closure — source: ADR-0009
- `_input()`/`_unhandled_input()` are dispatched **SceneTree-global, not per-Viewport**; `DirectionalLight3D` affects the whole `World3D` regardless of distance (hence the explicit visibility toggle); `Camera3D.current`/listener exclusivity is per-Viewport — source: ADR-0013

### Tooling
- **ripgrep has no `gdscript` type** — `rg --type gdscript` errors. Always `rg --glob "*.gd"`. All grep-verifiable ADR checks above depend on this.
- Test naming/evidence rules: see `tests/README.md` and coding-standards.md — Logic stories need a passing GdUnit4 unit test before Done.

### Cross-Cutting Constraints
- **Event-driven, not polled** — boot gate (ADR-0005), hover flag (ADR-0010), timer expiry (ADR-0011): no per-frame polling for state that has a signal
- **One terminal-halt severity model** (RID Failed pattern) — reused by config blocking-invariants (ADR-0002) and data-definition validation (ADR-0006); never invent a new severity scheme
- **Escape hatches are named, not preemptively built**: greedy meshing / GDExtension mesher (ADR-0014), AI threading (ADR-0008), chunked/async saves (ADR-0012) — adopt only on measured need
- **Raw delta vs `game_delta`**: camera/UI/overlays run on raw engine delta; simulation runs on Time & Tick's `game_delta`; never blend the two clocks for one piece of state
