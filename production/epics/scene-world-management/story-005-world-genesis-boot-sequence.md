# Story 005: World genesis in the boot sequence — the Valley boots a REAL world (terrain, roster, nav graph) before ACTIVE

> **Epic**: Scene / World Management
> **Status**: Ready
> **Layer**: Foundation (boot sequencing) → drives Foundation (Voxel World residency) + Core (Villager AI roster/nav)
> **Type**: Integration
> **Estimate**: 2.0 days *(relative-complexity anchor, not a calendar prediction — sprint-09.md sizing convention)*
> **Manifest Version**: 2026-07-23
> **Last Updated**: —

## Context

**The gap this closes (verified on disk 2026-07-26, five independent hits):** the shipped game boots
an EMPTY `VoxelWorldGrid` with one legacy villager. `VoxelWorldGrid.generate_terrain()` exists and is
tested (vox-006) but is called **nowhere in the boot chain** — `src/scene_world_management/valley.gd`'s
own class doc states it verbatim: *"Valley boots with an EMPTY `VoxelWorldGrid` — no `generate_terrain()`
call anywhere in the boot chain … a future world-generation story's job"*. That same file defers **three**
things to that unwritten story:

1. `VillagerNavGraph.build()` — *"a fresh grid has no terrain yet, so a graph built now would hold zero points"*
2. `Valley.spawn_starting_roster()` (villager-ai-021, landed 2026-07-26, commit b9e5530) — *"the ready-to-call,
   fully-tested surface a future world-generation story wires in once real terrain is confirmed resident"* —
   it is deliberately never called from `_ready()` and is therefore **dead code today**
3. terrain itself (the class-doc line above)

Two more hits from outside that file: the **M01 C4 evidence run** could not wire `ChimneySmokeEmitter`,
`InteriorClutterPlacer` or `foliage_sway.gdshader` into the Valley because none of them has a real host over
real terrain (`valley.gd`'s "Honest scope note"); and **vox-018** measured a real world only because its own
standalone tool hand-built terrain — it never ran against the production boot chain.

**Consequence:** no human playtest of the build is meaningful, `building-023`'s ghost preview has nothing to
pick against (the DDA finds no cell in an empty grid, so no ghost renders and no evidence screenshot is
possible), and villager-ai-021's roster surface sits ready and uncalled.

**GDD**: `design/gdd/scene-world-management.md` (boot/Booting state) + `design/gdd/voxel-world.md`
(terrain generation, residency) + `design/gdd/villager-ai-behavior.md` (Rule 14b starting roster)
**Requirement**:
- `TR-voxel-world-026` — *"Terrain generation must run synchronously before the first visible scene; at the
  2000×2000×32 scale the initial view-window mesh build runs behind Scene/World Management's transition
  overlay"* — **the primary TR. This story is the only place it can be satisfied.**
- `TR-voxel-world-029` — Uninitialized → **Generated** at world generation
- `TR-voxel-world-039` — deterministic, seeded noise
- `TR-voxel-world-044` — at most ONE batched change signal from generation, never per-cell
- `TR-voxel-world-053` — paged/on-demand residency; no synchronous per-frame I/O or generation
- `TR-scene-world-management-004` / `-034` — boot gate: Valley attaches after RID Ready, before Building
  System / Villager AI initialize; no intermediate loading screen at MVP
- `TR-villager-ai-behavior-065` — *"at world generation this system places `starting_villager_count`
  villagers at valid standable cells near the world center"* — **"at world generation" has had no world
  generation to hang off until this story.**

*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing Implementation**: **ADR-0005** (Boot Sequencing & Initialization Gate) — primary;
**ADR-0015** (Large-World Storage & Residency, 16k target) — primary for the *shape* of genesis;
**ADR-0014** (Chunked Voxel Rendering) — secondary (the initial mesh window); **ADR-0001** (Inter-System
Reference & DI) — secondary; **ADR-0002** (config-driven tunables) — secondary.

**ADR Decision Summary**: ADR-0005 makes `GameWorld._on_database_settled()` the one boot orchestration
site: Valley attaches, injected-tier `setup()` sweeps, then — and only then — ACTIVE. **ADR-0015 already
superseded ADR-0014's "full world at boot" clause**; the accepted model is paged region-file residency
where a chunk with no persisted file is regenerated **deterministically from `terrain_seed` on a
`WorkerThreadPool` task**, under a time-based budget, with **no synchronous per-frame I/O or generation**.
This story does not decide a new model — it applies the accepted one at the one call site that never got
wired. World genesis at production scale IS the residency page-in of the boot window, not a full-extent
`generate_terrain()` call.

**Engine**: Godot 4.7-stable | **Risk**: **HIGH** — boot-time wall clock at 2000×2000 is an *unmeasured*
unknown, and there is no boot-time loading overlay in this codebase (`game_world.gd`'s own honest note), so
whatever this costs happens on a frozen window.

### The large-world question, answered honestly with measured numbers

`generate_terrain()` accumulates the whole world into one `Dictionary[Vector3i, CellContents]` and
`bulk_write`s it. **Measured** (`production/qa/evidence/voxel-world-60fps-culling-evidence-20260725.md`,
Methodology): ~63 µs/column, linear through 900×900 — 700²→30.9 s, 800²→40.4 s, 900²→52.2 s — and then
**severely super-linear: 1000×1000 did not complete in over 200 s** (headless, no rendering at all; a
`Dictionary` resize/rehash cost cliff, confirmed headless *and* windowed). vox-018 chose 896×896 for exactly
this reason and recorded the deviation. The shipped `VoxelWorldConfig` default is **2000×2000** — four million
columns, well past the measured cliff. **A full-extent boot-time `generate_terrain()` at the shipped config is
not slow, it is non-viable, and this story must not pretend otherwise.**

What is actually cheap is the thing ADR-0015 already built. Per-chunk regeneration from seed is **measured at
avg 0.166 ms / p95 0.212 ms / worst 0.226 ms** per 16×16 chunk (vox-016, `max_chunk_generation_cost_ms` doc
comment + `production/qa/smoke-2026-07-26.md`), dispatched across `max_concurrent_async_tasks = 32` worker
tasks. The boot window at `view_radius_chunks = 24` is at most 49×49 = **2,401 chunks** ≈ **0.4 s of pure
generation compute**, parallelised — sub-second wall clock.

**The real boot cost is the MESH, not the data.** `build_initial_window()` is unbounded by design and measured
at **~7.7 ms/chunk** post-vox-019 (7,395.9 ms for 961 chunks). An unclipped 49×49 window projects to
**~18.5 s**. That is the number this story has to confront, and it is why AC-BOOT-BUDGET below is a
measure-and-lever AC rather than an assumption. Note also that `TR-voxel-world-026`'s parenthetical
"~2.6 s initial view-window mesh build" is a **stale ADR-0014 prototype figure** — file the correction.

**Control Manifest Rules (this layer — boot sequencing):**
- **Required**: genesis runs inside `GameWorld`'s WIRING phase, strictly before `BootState.ACTIVE`
  (ADR-0005); every tunable comes from config `.tres` (ADR-0002) — no literal extents, radii or counts in
  code; genesis is driven through the already-landed public surfaces (`update_residency`,
  `drain_pending_async_reads`, `build_initial_window`, `spawn_starting_roster`, `VillagerNavGraph.build`),
  never by reimplementing any of them; the boot loop is **bounded** (a wall-clock ceiling and a deterministic
  outcome when it is hit) — never an unbounded spin.
- **Forbidden**: calling `VoxelWorldGrid.generate_terrain()` from any production `src/` path (see
  AC-NO-FULL-EXTENT-GEN); any synchronous region-file I/O or terrain generation on the per-frame path
  (ADR-0015 Decision §6 — *"a synchronous fallback IS the failure mode"*); calling
  `drain_pending_async_reads()` / `wait_for_async_residency_idle()` from `_process` or any per-frame path;
  a second `setup()` call site (ADR-0005 — `_setup_injected_tier` stays the only one; `spawn_starting_roster`'s
  own on-demand `setup()` is villager-ai-021's already-sanctioned exception, not a new one);
  `SceneTree.paused` / `Engine.time_scale`; reaching into any private member of another module
  (`CameraInput._target` in particular).
- **Guardrail**: the initial mesh window is built **after** genesis completes and before ACTIVE — a chunk
  meshed while its data is not yet resident is a **permanent hole** (`VoxelWorldMeshStreamer` subscribes to
  nothing and has no invalidation path — verified: zero occurrences of `cells_changed_batch` in
  `voxel_world_mesh_streamer.gd`).

---

## Acceptance Criteria

- [ ] **AC-GENESIS-BEFORE-ACTIVE**: `GameWorld`'s success path runs a world-genesis phase during WIRING —
      after `_setup_injected_tier()` returns and **before** `_build_initial_voxel_mesh_window()` and before
      `_boot_state` is ever set to `BootState.ACTIVE`. Asserted headlessly: at the instant boot state first
      reads ACTIVE, `grid.get_resident_chunk_keys()` is non-empty and at least one **standable** cell exists
      within the roster's search radius of the start-focus cell. A boot that HALTs (RID Failed, or a BLOCKING
      config invariant) never reaches genesis — the existing halt semantics are unchanged and still terminal.
      [TR-voxel-world-026, TR-scene-world-management-004]
- [ ] **AC-NO-FULL-EXTENT-GEN**: no production `src/` path calls `VoxelWorldGrid.generate_terrain()` —
      **grep-guarded by test** (the only permitted occurrences in `neues-spiel/src/` are its own definition and
      doc-comment references; `tests/` fixtures and `tools/` may keep calling it). Genesis is instead driven
      through `VoxelWorldGrid.update_residency(camera_focus_cell, settlement_anchor_cell)` (ADR-0015), so
      every non-persisted chunk in the boot window regenerates from `terrain_seed` on a worker thread and the
      cost scales with the **window**, never the world extent. The rationale — the measured 900×900 → 1000×1000
      rehash cliff, and ADR-0015 having already superseded ADR-0014's full-world-at-boot clause — is recorded in
      the doc comment at the genesis call site, and `generate_terrain()`'s own doc comment gains a one-line
      "small-extent / fixture / tool path only; production genesis is the residency page-in" note.
      [TR-voxel-world-053]
- [ ] **AC-DETERMINISTIC-BY-SEED**: two boots with identical config produce **identical world content** —
      a deterministic sampled cell set (or a content hash) over the boot window compares equal across two
      independent boots with the same `terrain_seed`, and **differs** for a different `terrain_seed`. No RNG is
      consulted at boot outside the seeded `FastNoiseLite` path, and the result does not depend on how many
      frames or worker threads the page-in happened to take. [TR-voxel-world-039, TR-voxel-world-029]
- [ ] **AC-GENERATED-STATE**: once genesis completes, `VoxelWorldGrid.get_state()` reports `GENERATED`
      (today it stays `UNINITIALIZED` forever on the residency path, because only `generate_terrain()` sets it).
      If satisfying this needs a small additive surface on `VoxelWorldGrid` (voxel-world's file), keep it
      minimal, name it in the commit body, and do not duplicate any generation logic. If the technical-director
      prefers to leave the state untouched, record it as a **documented `TR-voxel-world-029` deviation** in the
      commit body — do not silently drop the criterion. [TR-voxel-world-029]
- [ ] **AC-BATCHED-SIGNAL-DISCIPLINE**: boot genesis emits **no per-cell `cell_changed` signals** — the
      residency page-in path integrates chunks wholesale and must not degrade into per-cell notification.
      Asserted by a listener that counts signals across a full boot. [TR-voxel-world-044]
- [ ] **AC-ONE-START-FOCUS**: boot establishes exactly **one** start-focus cell, derived deterministically from
      config (`VillagerRosterSpawner.world_center_cell(config)` is the already-shipped derivation), and the
      **same** cell is used as: the residency settlement anchor, the initial mesh-window centre, the camera's
      start target, and the roster's placement centre. Asserted headlessly by comparing all four. **Known
      collision to resolve, not to ignore**: `CameraInput._target` is private and set to `Vector3.ZERO` in
      `setup()` with no public setter, while the roster centre is `(world_width/2, …, world_depth/2)` = cell
      (1000, 8, 1000) at the shipped config — today the player would boot looking at an empty world corner
      1,000 cells from the villagers. If parity requires a public surface on `CameraInput`, keep it minimal and
      additive (camera-input epic file — name it in the commit body); **never** write a private field.
- [ ] **AC-MESH-WINDOW-AFTER-GENESIS**: `_build_initial_voxel_mesh_window()` still runs exactly once, still
      strictly before ACTIVE, and now strictly **after** genesis — proven by an ordering assertion, not by
      reading the code. Rationale in-file: the streamer has no invalidation path, so a chunk meshed before its
      data lands is a permanent hole. [TR-voxel-world-026]
- [ ] **AC-ROSTER-AFTER-WORLD**: `Valley.spawn_starting_roster()` (villager-ai-021's ready-and-uncalled
      surface) is called **exactly once**, from the boot sequence, after genesis and before ACTIVE. With
      `starting_villager_count > 1` in a test config it returns that many villagers, each on a distinct
      standable cell, and `Valley.get_villagers()` reports `1 + spawned` (villager 0 unchanged). With the
      shipped MVP default it returns 1. A partial or zero placement is a valid, deterministic outcome (never a
      crash) and is logged, not swallowed. [TR-villager-ai-behavior-065]
- [ ] **AC-NAV-GRAPH-BUILT**: `VillagerNavGraph.build(voxel_world, predicate_source, region_center,
      region_size)` runs once during genesis — `region_center` = the start-focus cell, `region_size` =
      `VillagerAIConfig.nav_region_size` (config-driven, never a literal) — **after** terrain is resident, so
      the graph holds a non-zero point count. Asserted headlessly (point count > 0 and a path query between two
      standable cells in the region succeeds). This closes `valley.gd`'s third named deferral.
- [ ] **AC-NO-SYNC-IO-IN-FRAME-PATH**: the per-frame path performs **no synchronous region-file I/O and no
      synchronous terrain generation**. `Valley._process()` drives residency through the **budgeted**
      `update_residency()` only, ordered **before** the existing `update_view_window()` call, both against the
      same focus cell; `drain_pending_async_reads()` / `wait_for_async_residency_idle()` appear **nowhere** in
      any `_process`/`_physics_process` call graph — grep-guarded by test. Boot-time draining is bounded by a
      config-driven wall-clock ceiling and terminates deterministically when it is hit. [TR-voxel-world-053,
      ADR-0015 Decision §6]
- [ ] **AC-BOOT-BUDGET (Advisory, measured, time-boxed)**: a windowed run at the **shipped 2000×2000 config**
      records boot-to-ACTIVE wall clock, split into its phases (residency page-in / nav-graph build / initial
      mesh window / roster spawn), into a dated evidence doc under `production/qa/evidence/`, on the
      `vox-018`/`vox-019` tool precedent (hardware, engine build and launch command stated verbatim; **VSync
      OFF** — S8 proved VSync floors frame-time measurement at 16.67 ms). **Producer-set provisional ceiling:
      5 s** (this codebase has no boot loading overlay, so boot time is a frozen window — the real ceiling is a
      technical-director boot-budget decision that does not exist yet; see Open Decisions). **If the ceiling is
      missed: apply ONE named lever, re-measure once, then escalate to technical-director.** Named levers, in
      order: (1) a **boot-scoped initial mesh radius** smaller than the steady-state `view_radius_chunks`
      (additive `VoxelWorldConfig` field — a shape decision that belongs to the technical-director, not to this
      story); (2) reduce `view_radius_chunks` itself; (3) reduce `VillagerAIConfig.nav_region_size` (a pure
      `.tres` data change — 200×200×17 ≈ 680k predicate evaluations at the current default). Record which lever
      was applied and the before/after numbers. Do **not** manufacture the number by shrinking the world extent.

---

## Implementation Notes

*Derived from ADR-0005 (the one boot orchestration site), ADR-0015 (residency shape + budget discipline),
ADR-0014 (initial mesh window), ADR-0001/0002 (DI + config):*

- **One new private method on `GameWorld`**, called from `_on_database_settled()` between
  `_setup_injected_tier()` and `_build_initial_voxel_mesh_window()`, duck-typed against the Valley exactly like
  the two existing seams (`_gather_valley_tier_modules` / `_build_initial_voxel_mesh_window` both guard with
  `_valley == null` and `has_method`) so every pre-existing DI/boot-gate-only test Valley stand-in stays
  unaffected. Do not add a second `setup()` call site.
- **Genesis loop shape**: `update_residency(start_focus, start_focus)` bounds its own page-in dispatch to
  `page_budget_ms` (4.0 ms) per call and `max_concurrent_async_tasks` (32) in flight, so one call does not make
  the window resident. Alternate `update_residency()` with `drain_pending_async_reads()` until
  `is_chunk_resident()` holds for the desired set **or** the config-driven wall-clock ceiling elapses — bounded,
  never a spin. `drain_pending_async_reads()` is the correct primitive here (it never re-drives residency and
  never evicts); `wait_for_async_residency_idle()`'s own doc comment explains why it is the wrong one for a
  side-channel dispatch. Both are documented as "tests and explicit, infrequent synchronisation points ONLY" —
  a boot phase is exactly that, and it is the last such call site the production build should ever have.
- **Order inside genesis is load-bearing**: terrain resident → nav graph build → roster spawn → (return to
  `GameWorld`) initial mesh window → ACTIVE. The roster's standable-cell search and the nav graph's predicate
  walk both read the grid; both are silently empty if they run first. That ordering *is* the story.
- **Per-frame residency drive** is one added line in `Valley._process()`, before the existing
  `update_view_window()` call, using the same `CameraInput.get_target() → world_to_cell` focus the streamer
  already uses, with the start-focus as the settlement anchor. vox-018 explicitly named this seam and scoped it
  out: *"`VoxelWorldGrid.update_residency()` live-loop wiring is a separate seam … If a shared per-frame
  focus-drive call site is the natural home for both, note it."* It is; this is the note being cashed.
- **Config, not literals** (ADR-0002): the boot wall-clock ceiling is a new typed `@export` on the relevant
  config `.tres` with a rationale doc comment in the established Foundation-Spine pattern. Start-focus,
  roster size, nav region size and window radii all already have config homes — use them.
- Cross-reference `docs/engine-reference/godot/` before touching any engine API (**BLOCKING**, as in M01).
  `WorkerThreadPool` and `FastNoiseLite` behaviour is already established by vox-010→017 — reuse those call
  patterns rather than inventing new ones.

---

## Out of Scope

*Handled elsewhere, or surfaced as missing — do not implement here:*

- **Mesh invalidation on cell change — MISSING STORY, surfaced not fabricated.** `VoxelWorldMeshStreamer`
  subscribes to no signal and rebuilds nothing: a chunk already meshed is never re-meshed when its cells
  change, and a chunk meshed while its data was not yet resident stays a permanent hole. This story's
  genesis-before-mesh ordering avoids the boot case; it does **not** fix the general case (a placed block
  appearing, or the leading edge of a moving camera outrunning async page-in). **No story in any epic covers
  this — it needs a decision and a new story from the technical-director. It is not invented here.**
- A boot-time **loading overlay** Control (`TR-scene-world-management-032`). Still absent; running genesis
  during WIRING before ACTIVE remains the best available proxy, exactly as `game_world.gd`'s existing honest
  note says. A later scene-world-management story slots an overlay in front of this same call site without
  changing it.
- **Save/load of generated terrain** (ADR-0012, VS-tier) — genesis is seed-deterministic; persistence of
  player-dirtied chunks is already ADR-0015's region-file path and needs nothing here.
- **Ambient hosts** (`ChimneySmokeEmitter`, `InteriorClutterPlacer`, `foliage_sway.gdshader`) — this story
  creates the terrain they were blocked on, but wiring them stays presentation-experience's Sub-B/wave-2
  backlog (`ambient-life-wave-1-evidence.md`). It **unblocks** them; it does not do them.
- **Greedy meshing / mesher optimisation** — ADR-0014's named reserve, `vox-019`'s domain. If AC-BOOT-BUDGET
  misses after its named levers, that is an escalation, not an in-story rewrite.
- **Multi-scene / Dungeon genesis** (ADR-0013) — VS-tier.

---

## QA Test Cases

- **AC-GENESIS-BEFORE-ACTIVE**: Given a headless boot with a real grid + Valley, When the RID reports Ready,
  Then at the first observation of `BootState.ACTIVE` the resident chunk set is non-empty and a standable cell
  exists near the start focus. Given a RID `Failed` outcome, Then genesis never runs and the halt stays terminal.
- **AC-NO-FULL-EXTENT-GEN**: Given the source tree, When `neues-spiel/src/` is scanned for `generate_terrain(`
  call sites, Then only its own definition/doc references are found.
- **AC-DETERMINISTIC-BY-SEED**: Given two boots with the same `terrain_seed`, Then the sampled cell set /
  content hash over the boot window is equal; Given a different seed, Then it differs.
- **AC-GENERATED-STATE**: Given a completed boot, Then `grid.get_state() == GENERATED`.
- **AC-BATCHED-SIGNAL-DISCIPLINE**: Given a listener connected before boot, When boot completes, Then zero
  `cell_changed` signals were observed from genesis.
- **AC-ONE-START-FOCUS**: Given a completed boot, Then residency anchor, mesh-window centre, camera start
  target and roster centre all equal the one config-derived start-focus cell.
- **AC-MESH-WINDOW-AFTER-GENESIS**: Given an instrumented boot, Then the first `build_initial_window` call is
  observed strictly after the last genesis page-in integration and strictly before ACTIVE.
- **AC-ROSTER-AFTER-WORLD**: Given `starting_villager_count = 3` in a test config, When boot completes, Then
  `get_villagers()` returns 4 (villager 0 + 3), all on distinct standable cells. Given a world with too few
  standable cells, Then fewer are returned, deterministically, with no crash.
- **AC-NAV-GRAPH-BUILT**: Given a completed boot, Then the nav graph point count is > 0 and a query between two
  standable cells inside the region returns a path.
- **AC-NO-SYNC-IO-IN-FRAME-PATH**: Given the source tree, When `_process`/`_physics_process` call graphs are
  scanned, Then no `drain_pending_async_reads` / `wait_for_async_residency_idle` occurrence is found; Given a
  boot that exceeds the ceiling, Then the loop terminates deterministically and logs.
- **AC-BOOT-BUDGET**: Given a windowed run at the shipped 2000×2000 config with VSync OFF, When boot completes,
  Then phase-split wall clock is recorded in a dated evidence doc with hardware, engine build and launch
  command stated; PASS/MISS declared against the 5 s provisional ceiling with the applied lever named.

---

## Test Evidence

**Story Type**: Integration (BLOCKING) + one Advisory performance measurement
**Required evidence**:
- `neues-spiel/tests/integration/scene_world/world_genesis_boot_test.gd` — must exist, pass headless, and run
  in the commit gate alongside the existing E2E LOOP test.
- Grep-guard tests for AC-NO-FULL-EXTENT-GEN and AC-NO-SYNC-IO-IN-FRAME-PATH (the established non-writer /
  literal-guard precedent from building-023 and build-validation-002).
- `production/qa/evidence/world-genesis-boot-budget-<date>.md` — Advisory, windowed, VSync OFF.

**Status**: [ ] Not yet created

---

## Dependencies

- **Depends on** (all Complete): vox-006 (`generate_terrain` + the seeded height formula the background regen
  reuses), vox-007 (mesher), vox-010→014 (region-file residency, async I/O, budget, read-through, load-before-
  write), vox-015 (`build_initial_window` / `update_view_window`), vox-016/017 (measured caps + completion-driven
  drain), vox-018/019 (live streamer wiring + the `_build_initial_voxel_mesh_window` call site this inserts in
  front of), scene-001/002/004 (World Root, boot gate, GameWorld assembly seam), spine-002/003 (BootState +
  config pattern), villager-ai-007 (`VillagerNavGraph.build`), **villager-ai-021 (`spawn_starting_roster`, landed
  2026-07-26 — this story is its named caller)**, cam-001/002 (`CameraInput`).
- **Blocked on**: nothing. Every surface it calls is already landed and tested.
- **Unlocks**:
  - `villager-ai-021`'s roster surface stops being dead code — the Valley boots **populated**
  - `building-023` (ghost preview): the pick DDA has terrain to hit, so a ghost can render and its Visual/Feel
    evidence screenshot becomes possible at all
  - **any human playtest of the build** (M02 risk R11's real precondition)
  - the ambient hosts C4 could not wire (chimney smoke, interior clutter, foliage) — unblocked, not done
  - `build-validation` and `needs-mood` integration work that wants a real world instead of a hand-built fixture
- **Open decisions this story surfaces (producer → user / technical-director)**:
  1. **No boot-time budget exists as a project decision.** The 5 s ceiling in AC-BOOT-BUDGET is
     producer-provisional. Owner: technical-director.
  2. **Boot-scoped mesh radius** — whether the initial window should use a smaller radius than the steady-state
     `view_radius_chunks`. A shape decision, deliberately not made here.
  3. **`TR-voxel-world-026`'s "~2.6 s initial view-window mesh build" is stale** (ADR-0014 prototype figure;
     measured is ~7.7 ms/chunk → ~7.4 s at 961 chunks, ~18.5 s projected at a full 49×49 window). File the
     registry/GDD correction.
  4. **Mesh invalidation on cell change has no story anywhere** (see Out of Scope). Needs an owner.
