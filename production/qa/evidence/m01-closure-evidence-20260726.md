# M01 Closure Evidence — Conditions C3 (automatable half) and C4 — 2026-07-26

**Owner**: godot-specialist · **Scope**: `production/milestones/milestone-01-review-2026-07-26.md`
conditions C3 (automatable half only — the `villager_unstuck` telemetry observation run) and C4
(#9 disposition — wire what can honestly be wired into the real Valley, golden-hour capture).
C1/C2 (ratification signatures) and C3's human build-and-inhabit demo half are explicitly **not**
covered here — those remain the user's/producer's own job.

---

## C4 — Ambient Sub-A wired into the real Valley

### What got wired

Of presentation-001 Sub-scope A's four ambient elements (`ChimneySmokeEmitter`, `TorchFlicker`,
`InteriorClutterPlacer`, `foliage_sway.gdshader`), **exactly one — `TorchFlicker` — is now a real,
`setup()`-driven hosted child of `Valley`**, wired via `src/scene_world_management/Valley.tscn` /
`valley.gd`:

- `AmbientTorchLight` (`OmniLight3D`, structural child of `Valley`, with a small placeholder
  emissive-sphere indicator child) + `TorchFlicker` (real injected-tier module, `config` wired via
  the Inspector to `res://data/config/ambient_life_config.tres`, `light` cross-wired in code via
  `Valley._wire_hosted_modules`, mirroring `VoxelWorldMeshStreamer`'s own established
  Node-typed-cross-reference precedent).
- `TorchFlicker` is appended to `Valley.get_injected_tier_modules()` — `GameWorld._setup_injected_tier`
  now calls its real `setup()` on every boot, exactly like every other hosted module.
- `Valley`'s child count moved from 9 → 11 (`AmbientTorchLight` + `TorchFlicker`); updated
  consciously in `tests/integration/scene_world_management/world_root_valley_attach_test.gd`
  (9 → 11, two new getter assertions) and `tests/integration/scene_world/gameworld_e2e_loop_test.gd`
  (`injected_tier_modules.size()` 9 → 10).

### Why the other three were NOT wired (honest gaps, not silently dropped)

- **`ChimneySmokeEmitter`** — its one gating input, `set_occupied_lit(bool)`, has no real
  occupied/lit data source anywhere in this codebase yet (that class's own doc comment says so
  explicitly). Wiring it would mean driving it from an invented signal — not done.
- **`InteriorClutterPlacer`** — needs a real room/building-interior fixture to place its
  scene-authored `clutter_transforms` inside. No fixture/building-interior entity exists yet.
- **`foliage_sway.gdshader`** — needs a real vegetation-placement host over real terrain.
- All three are blocked by the SAME underlying fact: **the real `Valley` boots with a genuinely
  empty `VoxelWorldGrid`** — grep-confirmed, `generate_terrain()` is never called anywhere in the
  boot chain (`GameWorld`/`Valley`), by design (`Valley`'s own class doc comment: "a fresh grid has
  no terrain yet... a future world-generation story re-derives/patches it"). `TorchFlicker` alone
  needs neither a fixture, a room, nor terrain — only a positioned `Light3D` — which is exactly why
  it is the one element this condition can honestly close today. The other three remain the CD's
  own already-tracked Sub-B/wave-2 backlog (`ambient-life-wave-1-evidence.md`), unchanged by this
  task.

### Golden-hour capture — real build, windowed, real GPU

Tool: `neues-spiel/tools/m01_c4_valley_ambient_capture.gd`/`.tscn`. Instantiates the **real,
unmodified `res://src/scene_world_management/game_world.tscn`** (the project's actual
`run/main_scene`) and lets it boot through the **real `ResourceItemDatabase` autoload** — not a
hand-rebuilt stand-in — confirming `TorchFlicker` reached `BootState.ACTIVE` as a genuinely wired
production module. Golden-hour lighting (`design/art/art-bible.md` §2.1's "permanent golden-hour
bias") is supplied by the CAPTURE TOOL only, reusing the exact already-validated recipe from
`prototypes/last-seal-vertical-slice/game_world.gd`'s own A/B-rendered values — never written into
`Valley.tscn`/`GameWorld.tscn` themselves (neither scene owns any lighting/environment node today;
adding one permanently is a separate, larger art/technical decision, out of this condition's
scope). A small placeholder ground plane (capture-tool-only, mirrors
`tools/ambient_life_evidence.gd`'s own "crude placeholder" precedent) gives the light something to
illuminate, since the real Valley's world is genuinely empty at this stage.

Run (windowed, real GPU, RX 7900 XT):
```
Godot_v4.7-stable_win64_console.exe --path neues-spiel res://tools/m01_c4_valley_ambient_capture.tscn
```
Console output:
```
m01_c4_valley_ambient_capture: real GameWorld reached ACTIVE
m01_c4_valley_ambient_capture: saved .../m01-c4-valley-golden-hour-20260726-1.png
m01_c4_valley_ambient_capture: saved .../m01-c4-valley-golden-hour-torch-closeup-20260726-2.png
m01_c4_valley_ambient_capture: capture complete, quitting
```
Scene self-quit on completion (no manual intervention). Evidence:
- `production/qa/evidence/m01-c4-valley-golden-hour-20260726-1.png`
- `production/qa/evidence/m01-c4-valley-golden-hour-torch-closeup-20260726-2.png`
  (captured 0.6s apart so `TorchFlicker`'s live sub-3Hz waveform is visibly different between the
  two frames — the indicator sphere's emission is synced each frame to the SAME real
  `light_energy` value driving the actual `OmniLight3D`, mirroring
  `tools/ambient_life_evidence.gd`'s own `_update_torch_indicator` convention).

### Disposition

**#9 closed at "TorchFlicker-present, honest scope note" rather than "all four Sub-A elements
live"** — per the milestone review's own recommendation (i), retiring the CD's advisory #2 for
this one element while explicitly leaving the other three open, unchanged, for Sub-B/wave-2 as
already planned.

---

## C3 (automatable half) — `villager_unstuck` telemetry observation run

Harness: `neues-spiel/tests/performance/villager_ai/villager_unstuck_watchdog_observation_test.gd`
(Advisory tier — lives under `tests/performance`, never joins `tests/run-tests.cmd`'s BLOCKING
unit+integration glob, mirroring `stress_30_villager_test.gd`'s own established posture). Run via:
```
Godot_v4.7-stable_win64.exe --headless --path neues-spiel -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode \
  -a res://tests/performance/villager_ai/villager_unstuck_watchdog_observation_test.gd
```
Result: **2/2 test cases PASSED, 0 errors, 0 failures, 0 orphans.**

### Scenario 1 — natural long run (real population, real construction, no adversarial setup)

**Run parameters**: 15 real `VillagerAi` instances (full `setup()`, real `VillagerDecidingScheduler`/
`VillagerNavGraph`/`VillagerOnSiteGate`/`VillagerSealPreventionGate` — the SAME anti-stuck stack
`Valley` wires in production), a real `ConstructionJobQueue`/`ConstructionTickLoop` with 80 real
BUILD job targets over a 20×20 flat platform, driven for **600 real ticks** at
**production-default** `VillagerAIConfig` (`unstuck_watchdog_threshold_ticks=12`,
`unstuck_rescue_search_radius=6`, `unstuck_rescue_max_radius=24` — nothing shortened).

**Measured**: `built=15` (real construction work happened) · **watchdog fire count = 0** ·
**recovery count = 0** · **`unstuck_search_failed` count = 0** · **permanent-stuck count = 15**.

**Honest finding, not smoothed over**: the natural run's `watchdog_fire_count=0` is exactly what
the milestone review expected of ordinary (non-adversarial) traffic — nobody gets walled in by an
outside write. But the run's own `permanent_stuck_count` sweep is **not** zero, and that is a real,
newly-surfaced, reproducible finding: every villager that completes a single-cell BUILD job lands
in the already-documented "self-seal" case (`VillagerSealPreventionGate`'s own class doc comment:
the villager ends up standing inside now-solid content it just built, "cleaned up later by the
Unstuck Watchdog... on its normal schedule"). What this observation shows, for the first time at
real population/tick scale, is that the "normal schedule" never actually arrives for THIS specific
case: `VillagerAi._tick_working()` transitions `WORKING → DECIDING` the **same tick** it detects
its own completion, so the self-sealed villager accumulates exactly **one** stuck tick in a
rescuable state — structurally short of the 12-tick threshold — before leaving `WORKING` for good.
Once in `DECIDING`/`WANDERING` (never rescuable, by Rule 15's own explicit TRAVELING/WORKING-only
scope), it stays `is_distressed() == true` indefinitely, because `_tick_wandering()` is still an
empty stub (no later story has landed real wander movement, so nothing ever re-attempts a path off
the now-solid cell). Every earlier seal-prevention/watchdog test in this codebase either hand-pokes
a bare, never-`setup()`-wired villager as its claim-holder, or stops asserting the instant the
write commits — none of them drive a real villager's own tick handler far enough afterward to see
this. **This is real production code behavior, reproduced deterministically, not a harness
artifact** — recommended as a follow-up `villager-ai` story (`_tick_wandering` real behavior, or a
narrower re-path-from-self-fix), out of this task's own scope to fix. It is **not** the same gap
condition C3/the CD ruling's #7 design test is about (see Scenario 2) — the watchdog's coverage of
"walled in by someone ELSE's write while genuinely traveling" is intact and proven below.

### Scenario 2 — adversarial: workers seal two rooms around bystanders (story-016 fixture)

**Run parameters**: reuses `seal_prevention_real_build_write_test.gd`'s own proven `_wall_off_room`
sealed-1-cell-room geometry, TWICE, in one real world. Two bystanders (real, `setup()`-wired
`VillagerAi`, genuinely `State.TRAVELING`, sharing the SAME real tick source and the SAME
production-default `VillagerAIConfig` as everything else) are placed inside; two separate, real,
un-trapped WORKER villagers (on-site per `VillagerOnSiteGate`'s own Rule 5 requirement, but never
themselves trapped) complete each room's doorway as a real BUILD job through the real
`ConstructionTickLoop`/`ConstructionJobQueue` write path — the actual mechanism that seals each
bystander in. `unstuck_watchdog_threshold_ticks + 5 = 17` real ticks are then driven after both
doorways commit.

**Measured**: **watchdog fire count = 2** · **recovery count = 2** · **`unstuck_search_failed`
count = 0** · **permanent-stuck count = 0**.

Both bystanders were genuinely walled in by a **different villager's** real write while
**genuinely TRAVELING** (the case Rule 15/F5 and the CD ruling's own #7 design test are about), and
the real Unstuck Watchdog fired for both, found a real rescue cell via the real F5 BFS, released
each bystander's (fake, in this fixture) claim, teleported both to a genuinely standable cell, and
re-entered them into Deciding — all at **production-default tuning**, all against **real production
classes**. Zero permanent stuck. Zero search failures.

### C3 disposition

**Closes #13 clause 3** (the `villager_unstuck` telemetry observation the S8 Definition of Done
named but never ran) **and executes the CD ruling's own #7 design test** (the watchdog fires and
recovers a genuinely-traveling villager walled in by someone else's write, at production tuning,
against real code) — Scenario 2 is the clean, unambiguous positive proof; Scenario 1 is the honest
natural-traffic baseline plus one real, separately-flagged, out-of-scope-to-fix finding.

**Not covered here**: C3's other half — "the ruling's own #6 design test... captured as a short
walkthrough + screenshots" (a human draws a room, workers build it, a villager moves in) — that is
explicitly the producer's/human demo session, not this task's scope.

---

## Verification

Full blocking suite (`cd neues-spiel && ..\tests\run-tests.cmd`) run after all changes above —
see the parent orchestration turn's own tail for the exact pass/fail/orphan counts at time of
delivery.
