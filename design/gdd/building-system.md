# Building System

> **Status**: Approved (2026-07-10 — full review NEEDS REVISION -> revised -> re-review APPROVED; see design/gdd/reviews/building-system-review-log.md)
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: Pillar 1 — The building IS the game (primary); Pillar 4 — Clarity over complexity (transparent costs/validity)

## Summary

The Building System is the game's central verb — it turns player intent into
structures. It owns the placement toolset (drag tools for walls/floors/roofs,
free single-block placement, furniture placement), placement validity, ghost
previews, undo/redo, material selection from the Resource & Item Database
palette, and build-over-time construction progress. It composes the
primitives owned by its four dependencies (Voxel World's grid writes and
raycast, Camera & Input's mouse-ray and action signals, the item database's
definitions, Time & Tick's game delta) into a fluid, expressive building
loop — the *planning* half of which (drag tools, surface-aware picking,
undo) was validated by the 2026-07-09 concept prototype (verdict:
PROCEED); the *construction* half (build-over-time) is a design hypothesis
pending the MVP playtest (see Game Feel).

> **Quick reference** — Layer: `Core/Gameplay` · Priority: `MVP` · Key deps: `Voxel World, Camera & Input, Resource & Item Database, Time & Tick System`

## Overview

**Player-facing:** Building is the game's primary means of expression
(Aesthetic #1) and its core loop's satisfying atom: "laying a room and
seeing it take shape." The player draws walls that extrude upright in one
action, places floors and roof formations over footprints, and freely sets
or replaces individual blocks and furniture within that structure — hybrid
drag-plus-free-place, exactly as the concept prototype validated. Undo/redo
is a first-class affordance: misclicks are never punished, so experimenting
stays fearless. Per Pillar 1, everything placed has mechanical meaning —
this system is where "the building IS the game" physically happens.

**System-facing:** the Building System is an interpreter and composer. It
receives raw signals (a `build_place` action fired; the mouse world-ray is
X) from Camera & Input, decides what they mean in the current tool context,
validates the result (in bounds? cell free or replaceable? material
selected?), and issues writes through Voxel World's low-level API. It owns
everything between raw input and grid mutation: tool modes, drag logic
locked to the picked surface, placement validity, the undo/redo stack,
ghost previews, and construction-over-time state driven by Time & Tick's
game delta (so building pauses when the game pauses). It never renders the
world (Voxel World's signal-driven rendering reacts to writes) and never
decides *what exists* to build with (the Resource & Item Database's
palette does).

Out of scope here: whether a finished room is *navigable/livable* for
villagers is Build Validation & Navigability's domain (a separate MVP
system); wave-vs-base spatial rules await the wave-defense prototype;
doors and windows arrive in the Vertical Slice per the concept's MVP
definition; the rendering/meshing implementation is the future building
ADR's decision.

## Player Fantasy

**"I am shaping a home with my own hands — and it's *mine*."**

This is the system that carries the game's #1 aesthetic (Expression) and
the concept's stated pride moment: *"pride when a plain plot becomes a
warm, furnished home."* The fantasy has three beats:

1. **Effortless intent.** I think "wall there" and a wall of ghosts rises
   there — one drag, full height, instant. The tools feel like an
   extension of my hands, not a form to fill out. (Prototype-proven for
   the *planning* interaction: vertical extrusion and surface-aware
   picking were exactly the moments the tester called out as *"hochziehen
   der Wände ist super"* — note the prototype's walls became real
   instantly; in production, what rises instantly is the blueprint.)
2. **Fearless play.** Misclicks are never punished: while planning, I can
   try a roof shape, hate it, and undo it freely — so I experiment until
   it's right. Undo/redo is not a convenience feature; it is what makes
   expression psychologically safe. (Undoing *already-constructed* work is
   equally allowed but carries honest emotional weight — a villager's
   visible labor is discarded. That asymmetry is accepted, not hidden.)
3. **Earned pride.** The house doesn't pop into existence — it goes up over
   time, so finishing it feels like something *happened*, and the result is
   visibly the sum of my choices: this material, this roofline, this block
   I placed by hand where the drag tool wouldn't. *(Design hypothesis —
   build-over-time was explicitly OUT of the prototype's scope; this beat
   is validated only when the MVP playtest confirms construction pacing
   feels earned rather than tedious. Second caveat, per the 2026-07-10
   cross-review: at MVP, walls carry no mechanical value — the minimal
   roof-on-pillars "carport" is the mechanical optimum (Build Validation
   Edge Case 6, an accepted known gap). Until the Vertical Slice
   wall-coverage rule lands, "earned pride" in elaborate builds rests on
   player expression, not system incentive — deliberate, not hidden.)*

Reference feeling: Stonehearth's self-built homes (the validated draw of
the whole concept) crossed with Minecraft's direct block-level authorship
(the Visual Direction Note's shape reference). NOT the fantasy: a CAD tool
(precision over feel), a free sandbox (structure exists — rooms, walls,
roofs are first-class objects), or a decorator placing stickers on a
finished stat-box (the building IS the stats, Pillar 1).

> `creative-director` not consulted — Lean mode (non-high-risk section).
> Fantasy framing sourced from game-concept.md Core Fantasy + prototype
> REPORT.md tester evidence. Review manually before production.

## Detailed Design

### Core Rules

**Toolset and mode model**

1. Building happens through a modal toolset of exactly six MVP tools: Wall,
   Floor, Roof, Block (place/remove), Furniture, and Undo/Redo (the latter
   always available, not modal). One tool is active at a time; activating a
   tool deactivates the previous one; cancel (right-click or Esc) returns to
   no-tool (camera-only) mode.
2. Every placement tool follows one pipeline: **pick → preview → commit**.
   The current mouse world-ray (Camera & Input) is forwarded to Voxel
   World's raycast to pick a cell/surface; a ghost preview shows exactly
   what a commit would create; the `build_place` action commits it.
   Nothing is ever created without its preview having been visible.
3. **Surface-aware targeting** (prototype-validated): placement attaches to
   the picked block's face, or replaces the picked block in place. Drag
   operations lock their working height/plane to the surface picked at
   drag start — never to a fixed ground plane.
4. **Wall tool**: a drag defines a line segment; on commit the wall
   extrudes upright to the current wall height (default 3 cells,
   adjustable 1–8) in one action. Walls are one-action full-height
   objects, never layer-by-layer slabs.
5. **Floor tool**: a drag defines a rectangle on the picked plane; commit
   fills it one cell thick with the selected material.
6. **Roof tool**: the player picks one of four formations — Flat, Gable,
   Hip, Shed (Flach/Sattel/Walm/Pult, prototype-validated) — and drags a
   footprint; commit generates the formation's cell set over it.
7. **Block tool**: single-cell place (attach/replace per Rule 3) or remove.
8. **Furniture tool**: places furniture entries from the Resource & Item
   Database (`furniture_fixture` category — MVP list: `bed` only, resolving
   that GDD's Open Question 1). Furniture requires support: the cell(s)
   below must be occupied (ground or built floor). Furniture occupies its
   cells like blocks do (one cell = one occupant, Voxel World Core Rule 2).

**Placement validity** (owned here, per Voxel World's ownership boundary)

9. A commit is valid iff: every target cell is inside world bounds; every
   target cell is empty (or is the picked cell in a replace-in-place); a
   material/furniture entry is selected and available (MVP: the tier-0 set
   plus `bed`); the command's total cell count is at most
   `max_cells_per_command` (default 512 — see Tuning Knobs); and furniture
   support (Rule 8) holds. Invalid commits are rejected with visible
   feedback (see UI Requirements) — never silently. The cell cap bounds
   every per-command quantity in this system at once: preview size, undo
   payload, and job-queue injection.
   *Furniture support clarification*: a blueprint floor cell counts as
   support for a furniture *blueprint* (you can plan a bed on a planned
   floor), but the furniture cell's construction may only start once its
   support cell is Built.
10. Validity here is *geometric availability* only. Whether a structure is
    navigable or livable for villagers (room enclosure, reachable door) is
    owned by Build Validation & Navigability — this system never blocks a
    placement for livability reasons.

**Blueprint-then-build** (build-over-time)

11. A valid commit does NOT write blocks into the grid. It creates
    **blueprint cells**: planned cells rendered as ghosts, owned by this
    system, invisible to Voxel World's data layer.
12. Blueprint cells are converted to real blocks by **villager
    construction**. The job contract:
    - **Every blueprint cell is one job.** The queue is ordered by commit
      time; ordering defines *availability for display and tie-breaking*,
      not forced servicing order — Villager AI may choose among available
      jobs by its own criteria (e.g., proximity).
    - **One job per villager at a time**; a villager finishes or abandons
      its current job before claiming another.
    - **Per-cell claims allow parallelism**: N villagers may simultaneously
      work N distinct cells, including cells of the same command (a
      15-cell wall can be built by several villagers at once).
    - **"On site"** means the villager occupies the target cell or an
      orthogonally adjacent cell (including directly below/above).
      Construction progress advances per game tick (Time & Tick System)
      only while a claiming villager is on site.
    - When a cell's build time elapses, this system issues the Voxel World
      write and retires the blueprint cell.
    *(Contract CONFIRMED 2026-07-10 by villager-ai-behavior.md — claim
    locking (its Rule 4, Edge Case 3), travel/arrival (its F1), and
    abandonment (its Rule 3, Edge Case 4) are all specified there. The
    queue semantics above remain owned HERE and are not renegotiable
    without revising this GDD.)*
13. Construction consumes game time, not raw time: while paused nothing
    builds; time-warp accelerates construction (Time & Tick's game delta /
    tick events).
14. **MVP cost rule**: tier-0 materials and the MVP bed are free — no
    resource is consumed by placement or construction (implements the
    tier-0 bootstrap, Resource & Item Database Core Rule 6). The blueprint
    pipeline is the future seam where Alpha resource costs attach (reserve/
    consume at construction, per the Stonehearth hauling model) — costs are
    NOT designed here.

**Removal and undo**

14b. **Occupancy authority split.** *Physical* occupancy (collision,
    pathing, line-of-sight) is Voxel World's authority — blueprint cells
    are deliberately non-solid until Built, so walking "through" a planned
    wall is correct behavior, and Edge Case 6 guarantees a cell never
    becomes solid under a character. *Planned* occupancy (what will exist:
    placement validity, Build Validation's enclosure analysis, future
    planners) must query this system's combined view (Voxel World blocks +
    blueprint cells). Consumers must never treat raw Voxel World state as
    "what the player has built or plans to build."

15. **Terrain is not removable.** Only player-built cells (blueprint or
    constructed) and player-placed furniture can be removed. This is the
    MVP implementation of the anti-pillar "no unbounded terraforming" —
    and it resolves Voxel World's Open Question ("do consuming systems
    need a natural/built distinction?") with **yes**: the game must be able
    to distinguish terrain cells from built cells. *(How — a Voxel World
    data flag vs. this system's own built-cell record — is an
    implementation choice for the building ADR.)*
16. Removal of built cells is instant in MVP (no deconstruction time, no
    villager involvement). Removing a blueprint cell simply cancels it.
    **17b — Furniture-revocation contract** *(added 2026-07-10, from the
    needs-mood review — Edge Case 11's interruption previously had no
    notification mechanism: Villager AI's Rule 10b covers only MOVING
    villagers and cannot inform a stationary sleeper)*: removing a piece
    of OWNED furniture (MVP: a bed with an owner) emits a
    furniture-revocation event to the owning villager, symmetric to the
    job-revocation contract in the blueprint lifecycle. Villager AI
    consumes it in its Edge Cases 5–6; Needs learns via the villager's
    `stop_recovery` call. Removal itself remains instant and never
    blocked (Edge Case 11).
17. **Undo/redo** operates on player *commands* (one wall drag = one
    command = one undo step, exactly as prototyped). Undoing a command
    cancels its blueprint cells; if some cells were already constructed,
    those blocks are removed instantly. Redo replays the command as new
    blueprint cells. The stack is bounded (default 50 commands); it is
    cleared when a scene transition **completes** (the transition-COMPLETE
    signal, never transition-begin — an aborted/failed transition must
    leave the stack untouched; per Scene/World Management's side-effect
    discipline rule, REVISED 2026-07-10 re-review) and never persists
    into save files.

### States and Transitions

**Tool state machine** (player-facing):

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Idle (no tool) | Boot, cancel, tool deactivation | Tool selected | Camera-only; no ghost, no commits |
| ToolArmed | Tool selected | Cancel / other tool / drag start | Ghost preview follows the pick each frame |
| Dragging | Drag threshold reached (`cursor_travel_px >= drag_threshold_px`, F4) with `build_place` held | Release (commit), cancel (abort), or other tool selected (abort) | Preview **re-rasterizes every frame** as the cursor moves — the full pending result (wall segment, floor rect, roof footprint) is always current, never frozen at drag start; above `preview_degradation_threshold` cells the preview degrades to an outline (see Tuning Knobs); working plane locked per Core Rule 3 |
| Suspended | Camera & Input enters Suspended (scene transition) | Camera & Input reactivates | All interaction halted mid-anything: an in-progress drag is aborted without commit |

**Blueprint cell lifecycle** (per cell):

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Planned | Valid commit created it | Job claimed, or canceled | Ghost visual; occupies no grid cell; counted as "pending" for its command's undo step |
| UnderConstruction | Villager claims its job and is on site | Build time elapses, or canceled | Progress accumulates per game tick; visually distinct from Planned (see Visual/Audio) |
| Built (terminal) | Build time complete | — (cell now lives in Voxel World) | This system writes the block via Voxel World and forgets the cell (undo bookkeeping aside) |
| Canceled (terminal) | Player removal/undo before Built | — | Ghost removed; any claimed job is revoked (villager abandons gracefully — provisional, Villager AI GDD) |

### Interactions with Other Systems

- **Voxel World** (upstream, MVP): the only mutation path — this system
  calls the write API (set/clear cell) when blueprint cells complete or
  built cells are removed, and the raycast/read API for picking and
  validity checks. It listens to Voxel World's write signals to keep undo
  bookkeeping honest (a cell changed by anything else invalidates affected
  undo entries) — with two contract rules:
  - **Self-write exemption**: writes originating from this system (cell
    completion, undo removal) are tagged and MUST be ignored by its own
    undo-invalidation listener. Godot signals are synchronous — without
    this rule, unwinding a command would re-enter the listener mid-unwind
    and could self-invalidate the very entries being processed.
  - **Batching**: when multiple cells complete or are removed in the same
    frame (parallel villagers, multi-cell undo), this system uses Voxel
    World's bulk-write API so ONE batched signal fires, per that GDD's
    explicit batching mandate (its Edge Cases) — never one signal per cell.
- **Camera & Input** (upstream, MVP): consumes InputMap action signals
  (`build_place`, `build_remove`, tool-select actions — the action list
  extends that GDD's set) and the mouse world-ray query. Enters Suspended
  with it (that GDD's Active/Suspended states). The open "pan margin"
  question from that GDD can now be answered: building must reach the
  world edge, so the pan bound needs no extra building-driven margin (see
  Open Questions).
- **Resource & Item Database** (upstream, MVP): queries the palette
  (`building_material` + `furniture_fixture`, tier-0 rule) and reads
  `material_family`/`visual_asset` for previews. Confirms that GDD's
  provisional "primary consumer" contract.
- **Time & Tick System** (upstream, MVP): construction progress advances
  by game ticks (2.0/s base); pause halts construction; time-warp
  accelerates it. Uses tick events, not raw delta.
- **Villager AI & Behavior** (MVP sibling, undesigned — PROVISIONAL):
  consumes the construction-job queue (claim job → path to site → work →
  report done). This GDD defines the queue's behavior; the AI GDD must
  confirm claiming, pathing-failure, and abandonment semantics.
- **Build Validation & Navigability** (MVP, downstream): reads completed
  structures (and possibly blueprints) to judge enclosure/livability.
  This system exposes "a construction completed" signals for it —
  **batched per FRAME** (the same batching mandate as the Voxel World
  bulk-writes above): N cells completing in one frame, across any number
  of commands and villagers, fire ONE completion signal. *(Contract
  required by that GDD's Edge Case 10/AC19 — added 2026-07-10 by its
  design review; without it, N parallel completions could trigger N
  region re-analyses in one frame.)*
- **Building UI** (MVP, downstream): renders the tool palette, material
  selection, wall-height stepper, roof-formation picker, and undo/redo
  buttons; displays validity feedback. All state it shows lives here.
- **Scene/World Management** (Foundation, upstream): hosting; the undo
  stack clears on transition-COMPLETE (Core Rule 17 — never on begin, so
  a load-failure abort leaves undo intact); tool state machine suspends
  via Camera & Input's Suspended state.
- **Save/Load & World Persistence** (Vertical Slice, downstream,
  provisional): must serialize open blueprint cells and construction
  progress (built cells live in Voxel World's data). The undo stack is
  explicitly NOT saved.

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section even in
Lean mode. Review produced 4 revisions and 3 additions; all incorporated.)*

### F1 — Wall cell set from a drag

`wall_cell_count = line_length(start_cell, end_cell) × wall_height`

The dragged segment is rasterized into a deterministic run of cells on the
locked working plane (Bresenham-style stepping for diagonals — equal
displacements always yield equal cell counts); each run cell extrudes
`wall_height` cells upward from the picked surface.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `start_cell`, `end_cell` | Vector3i | within world bounds, same working plane | Drag endpoints (start = pick at drag start, per Core Rule 3) |
| `line_length` | int | 1 – world-bounded | Rasterized run length; `start == end` degenerates to 1 (single column) |
| `wall_height` | int | 1–8, default 3 | Clamped at the input layer (UI stepper), not re-clamped here |

Example: a 5-cell drag at default height → 5 × 3 = **15 blueprint cells**.

### F2 — Floor cell set from a drag

`floor_cell_count = (|dx| + 1) × (|dz| + 1)` — a 1-cell-thick rectangle on
the locked plane. Zero-length drag degenerates to a single 1×1 tile. The
practical maximum is `max_cells_per_command` (512, Core Rule 9) — the
binding limit for any single commit; the world grid dimensions only bound
the preview clamp (Edge Case 1).

Example: dragging 3 cells in x and 4 in z → 4 × 5 = **20 blueprint cells**.

### F3 — Construction time per blueprint cell

`cell_build_ticks = base_build_ticks[category]`

A cell under active construction (villager on site) completes after
`base_build_ticks` tick events (Time & Tick System). Tick counts are
warp-invariant: time-warp changes wall-clock speed, never the tick count.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `base_build_ticks[block]` | int | ≥ 1, default 4 | 2.0s at 1x warp (ticks_per_second = 2.0) |
| `base_build_ticks[furniture]` | int | ≥ 1, default 8 | 4.0s at 1x warp — furniture is more deliberate |

**Burst rule (per villager/job)**: the tick budget applies **independently
per active job** — each villager with an UnderConstruction cell processes
tick bursts (up to `max_ticks_per_frame = 10` after a stall or at high
warp) on its own cell. Per job, a burst applies at most enough ticks to
complete the *current* cell; excess ticks do NOT roll over to that
villager's next cell — it starts with the next processed tick event.
Construction throughput therefore scales with the number of working
villagers (N villagers can complete at most N cells per frame), and each
individual construction stays visually plausible at any warp.

Example: a 3-run × 3-high wall = 9 cells × 4 ticks = 36 ticks = **18s of
game time at 1x warp** — *excluding villager travel time between cells and
assuming one villager. Total real-time-to-complete for an N-cell command is
deliberately NOT modeled here: it depends on villager count, pathing, and
job scheduling (Villager AI & Behavior's domain).*

### F4 — Click vs drag discrimination

`is_drag = cursor_travel_px >= drag_threshold_px` while `build_place` is
held; release below the threshold is a click (single commit).

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `cursor_travel_px` | float | ≥ 0 | Screen-space pixels (Camera & Input's unit), not world cells |
| `drag_threshold_px` | float | 4–12, default 6 | Prototype-validated |

### F5 — Roof and furniture cell counts (scalar stubs)

`roof_cell_count = f(formation, footprint)` — each formation (Flat/Gable/
Hip/Shed) defines a deterministic cell count over its footprint. **Flat is
specified now** (unblocking AC15 for MVP):
`flat_roof_cell_count = (|dx| + 1) × (|dz| + 1)` — identical to F2, one
cell thick on the plane above the footprint's highest picked surface.
Gable/Hip/Shed functions are specified alongside the shape algorithm at
Vertical Slice detail (see below). `furniture_cell_count = 1` for all MVP
furniture (`bed`).

### Deliberately NOT formulas (and why)

- **Roof shape generation** — a per-formation construction algorithm
  (which cells, at which heights), not a scalar computation; specified as
  shape rules in the roof asset/design spec at Vertical Slice detail. Only
  its cell *count* (F5) is a formula because F3's queue consumes it.
- **Pick raycast** — owned by Voxel World (its GDD: native/DDA, deferred
  to the building ADR).
- **Undo stack behavior** — rules (Core Rule 17), not math.

## Edge Cases

1. **Drag extends beyond world bounds.** The preview clamps to the bounded
   grid and shows only the in-bounds portion; commit creates exactly what
   the preview showed. A drag entirely out of bounds commits nothing.
2. **Replace-in-place targeting a terrain cell.** Invalid — replacing is
   removal + placement, and terrain is not removable (Core Rule 15).
   Attaching to a terrain cell's face remains valid (that's how building
   on the ground works).
3. **Commit targeting a cell that already holds a blueprint cell.**
   Invalid. Blueprint cells count as occupied for placement validity even
   though they are invisible to Voxel World's data layer — otherwise two
   commands could queue contradictory builds for one cell.
4. **No valid pick under the cursor** (ray misses the world). The ghost
   preview is hidden and `build_place` is a no-op — no error spam; the
   absence of a ghost IS the feedback (plus cursor state, see UI
   Requirements).
5. **Blueprint cell is unreachable for the villager** (player walled it
   in). The job stays in the queue and is retried periodically; the ghost
   persists indefinitely — never auto-canceled. **The failure is never
   silent**: once a job is reported unreachable, its ghost switches to a
   pulsing orange tint (the Visual Direction Note's state axis) and a
   small non-modal UI hint appears ("a build spot can't be reached") —
   this system owns the signal; the unreachability *detection* comes from
   Villager AI's pathing failures (its Rule 6). The player resolves it
   by undoing/removing either the blueprint or the obstruction. This
   deliberate patient-but-visible design protects the MVP's "earned pride"
   moment from silent failure (a first-timer who seals a room sees orange,
   not nothing). *(Retry cadence: `unreachable_retry_ticks`, owned by the
   Villager AI GDD's Tuning Knobs — confirmed 2026-07-10.)*
6. **Construction target cell is occupied by a character** (villager or
   other unit standing in it). The blueprint is valid; construction of
   that specific cell is deferred until the cell is clear. *(Nudge-aside
   is specified in Villager AI's Rule 7 + F4 — confirmed 2026-07-10; note
   its refinement: Working/Sleeping occupants are never interrupted.)*
7. **Undo of a partially built command.** Pending blueprint cells are
   canceled, already-built cells are removed instantly (Core Rule 17); any
   villager mid-construction on an affected cell has its job revoked and
   re-enters normal behavior *(graceful abandon — specified in Villager
   AI's Rule 3 + Edge Case 4, confirmed 2026-07-10)*.
8. **Redo into a changed world.** Redo re-validates every cell of the
   command; cells that are no longer valid (occupied since the undo) are
   dropped from the redo with the standard invalid-feedback, valid cells
   are re-created as blueprints. A redo where zero cells survive is a
   no-op with feedback.
9. **Undo stack overflow.** Beyond the bounded depth (default 50), the
   oldest command is discarded silently — it simply becomes permanent. Any
   new command clears the redo branch (standard undo semantics).
10. **Scene transition with pending blueprints.** Blueprints persist and
    the Valley keeps simulating during dungeon excursions (Scene/World
    Management Core Rule 4): the villager keeps building while the player
    is away. The undo stack, however, clears on transition-complete
    (Core Rule 17) — returning players cannot undo pre-transition
    commands.
11. **Furniture removed while in use** (bed removed while the villager
    sleeps in it). Allowed — removal is never blocked by usage; the
    furniture-revocation event (Core Rule 17b, added 2026-07-10) notifies
    the owner; the villager is interrupted and re-plans *(interruption semantics —
    specified in Villager AI's Edge Case 5 and Needs' Edge Case 3,
    confirmed 2026-07-10)*.
12. **Tool switched or Suspended entered mid-drag.** The drag aborts
    without commit (States table); no partial blueprint is ever created by
    an aborted drag.

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Voxel World | ✅ Designed | Write API (set/clear cell), raycast picking, read API for validity, write signals for undo bookkeeping |
| Camera & Input | ✅ Designed | InputMap action signals (`build_place`, `build_remove`, tool selects), mouse world-ray query, Suspended state |
| Resource & Item Database | ✅ Designed | Palette queries (`building_material`, `furniture_fixture`), `tier` (free set), `material_family`, `visual_asset` |
| Time & Tick System | ✅ Designed | Tick events for construction progress (F3); pause/warp semantics via game time |
| Villager AI & Behavior | ✅ Designed (2026-07-10) | Job claiming, on-site presence, pathing failure/abandon semantics for the construction queue (Core Rule 12) — **contract CONFIRMED** by villager-ai-behavior.md (its Core Rules 3–7 + F1 arrival rule, F4 nudge-aside); `unreachable_retry_ticks` is owned there |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Villager AI & Behavior | MVP | ✅ Designed | The mutual seam's other direction: consumes this system's construction-job queue as its work supply (its Rules 4–7) — listed upstream above for what this system consumes FROM it, listed here because it cannot do its Work activity without this queue (added 2026-07-10, cross-review fix) |
| Build Validation & Navigability | MVP | ✅ Designed | Completed structures + construction-completed signals (contract confirmed by build-validation-navigability.md) |
| Building UI | MVP | Undesigned | Tool state, palette selection, wall-height, roof formation, undo/redo state, validity feedback *(provisional)* |
| Onboarding / Tutorial | Vertical Slice | Undesigned | The MVP toolset as teachable verbs *(provisional)* |
| Township Progression | Alpha | Undesigned | Built structures as prosperity inputs *(provisional — prosperity variable itself still open)* |
| Economy Balance (Sinks) | Alpha | Undesigned | Future build costs as a resource sink *(provisional — costs not designed here, Core Rule 14)* |
| Save/Load & World Persistence | Vertical Slice | Undesigned | Blueprint cells + construction progress serialization; undo stack explicitly excluded *(provisional)* |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `wall_height` (player-adjustable stepper) | 3 | 1–8 | How tall a one-action wall extrudes (F1). Prototype-validated default. Raising the max above 8 risks accidental towers dominating the silhouette. **Lockstep invariant**: Build Validation's `max_room_height` (8) must stay ≥ this knob's maximum, and `villager_clearance` (3) equals this knob's default (= minimum walkable interior) — retune together (added 2026-07-10, cross-review fix) |
| `drag_threshold_px` | 6 | 4–12 | Click-vs-drag feel (F4). Too low: clicks become accidental drags; too high: short drags feel unresponsive. Prototype-validated |
| `base_build_ticks[block]` | 4 (= 2.0s at 1x) | 1–20 | Construction pacing per block (F3). The core "watching it take shape" pacing — tune against the MVP hypothesis (finishing a small house should feel earned, not tedious) |
| `base_build_ticks[furniture]` | 8 (= 4.0s at 1x) | 1–40 | Furniture construction pacing (F3) |
| `max_cells_per_command` | 512 | 128–2048 | Hard cap on blueprint cells per commit (Core Rule 9). 512 admits the longest possible wall (64-cell run × height 8); larger floors take multiple drags. Bounds preview draw calls, undo payload, and job-queue injection in one number |
| `preview_degradation_threshold` | 128 | 32–512 | Above this cell count, the live drag preview degrades from per-cell ghosts to an outline/bounding representation (Dragging state) — protects the frame budget on large drags while keeping the commit exact |
| `undo_stack_depth` | 50 | 10–200 | How far back a player can undo (Core Rule 17, Edge Case 9). Worst-case memory is now bounded and checkable: 200 commands × 512 cells × a small per-cell record ≈ low single-digit MB — negligible against the 4 GB ceiling. The cap exists for predictability |
| Unreachable-job retry cadence | see `unreachable_retry_ticks` (20) | — | Owned by the Villager AI GDD's Tuning Knobs (confirmed 2026-07-10) — pointer only, value not duplicated here |

All values are data-driven per the coding standard (no hardcoding); the
Building UI exposes only `wall_height` to the player — the rest are
designer-facing config.

## Visual/Audio Requirements

**Visual** (specs owned by art-director/art bible; requirements set here):

- **Picked-block highlight**: the block under the cursor is always visibly
  highlighted while a tool is armed (prototype-validated as essential).
- **Ghost previews** follow the Visual Direction Note's colorblind-safe
  blue–orange state axis: valid preview = cool blue-tinted translucent
  ghost; invalid = unmistakable orange tint. Never red-green.
- **Planned vs UnderConstruction** must be visually distinct: Planned =
  static translucent ghost; UnderConstruction = visible progress (e.g.
  scaffold/fill rising with tick progress — exact treatment to the art
  bible).
- **Materials** render per the database's `visual_asset` + the Note's
  material↔meaning families; blocks are FLUSH (cell_size 1.0, no gap —
  supersedes the prototype's 0.96).
- **New assets required**: ghost/preview materials (valid + invalid),
  under-construction treatment, picked-block highlight.

**Audio** (MVP-light):

- Commit confirm (soft placement sound), invalid-commit feedback (gentle
  negative, not punishing), per-cell completion tick, and a small
  "command complete" flourish when a whole wall/floor/roof finishes.
  Per-material placement sounds are a future schema field (Resource & Item
  Database Open Question 4) — not MVP.

## Game Feel

**Feel reference**: the 2026-07-09 concept prototype is the feel target
for the **planning loop** (pick → preview → commit, wall extrusion,
surface-aware editing, undo) — it was tuned hands-on until *"Ich finde
das super."* The **construction loop** (blueprint-then-build pacing,
watching blocks turn real) was explicitly OUT of the prototype's scope
and is a design hypothesis until the MVP playtest — its feel target is
Stonehearth's deliberate construction warmth crossed with Minecraft's
direct block authorship. *(The construction loop's felt weight is
delivered by Villager AI's visible labor — RESOLVED 2026-07-10: that GDD
is designed and owns the animation-to-progress lockstep in its Game Feel
section.)*

**Input responsiveness**:
- The ghost preview updates on the same frame as cursor movement (raw
  input path — Camera & Input uses raw delta precisely so this stays
  responsive even while the game is paused).
- Building while paused is fully allowed: tools, previews, commits, and
  undo all work in pause — only *construction progress* waits for game
  time. (Planning calmly while paused is core to "real-time with pause.")
- Commit feedback is immediate: blueprint ghosts appear the instant of a
  valid commit, even though blocks build over time.

**Impact moments** (triggers and channels specified here; exact asset
values to the art bible/audio spec, each with a measurable hook):
1. **Wall rise** — trigger: commit of a multi-cell command. Channels: all
   ghost cells appear on the SAME frame as the commit (never staggered),
   plus the commit-confirm sound (Visual/Audio Requirements).
2. **Per-cell completion** — trigger: a cell's Built transition. Channels:
   one completion tick sound per cell (rate-limited to at most one sound
   per frame when parallel villagers finish simultaneously — the batched
   write, Interactions) and a single-cell visual accent on the completed
   block (e.g., brief scale/brightness pop, ≤0.3s, non-blocking; exact
   curve to the art bible).
3. **Command completion** — trigger: the LAST cell of a command reaching
   Built. Channels: the "command complete" flourish sound (distinct from
   the per-cell tick) + a one-shot visual accent spanning the command's
   cells (≤1s; exact treatment to the art bible). Fires once per command
   regardless of size — a 1-cell command fires only this, not both a tick
   and a flourish.

**Weight profile**: planning is weightless (instant, fluid, undoable);
construction has weight (time, villager labor) — **delivered by Villager
AI's visible labor and animation-to-progress lockstep (its Game Feel
section), not by this system's timers alone**; this system supplies the
time cost (F3), Villager AI supplies the felt weight. This contrast IS
the design: expression stays frictionless while results feel earned.

**Feel acceptance criteria** (subjective, playtest-verified):
- A first-time player builds an enclosed room within minutes without
  instruction (re-verify the prototype result in the production build).
- No tester describes placement as "fiddly" or fights the camera/snapping.
- Undo is discovered and used naturally during free play.

## UI Requirements

Owned by the Building UI GDD (downstream); this system requires it to
present: tool palette (6 tools), material palette (tier-0 set, from the
database), wall-height stepper (1–8), roof-formation picker (4 formations),
undo/redo buttons with Ctrl+Z / Ctrl+Y bindings (prototype-validated; a
held key repeats at the OS key-repeat rate, each repeat = exactly one undo
step — no custom acceleration), and non-punishing invalid-commit feedback
near the cursor. All displayed state lives in this system; the UI renders
and triggers, never owns.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| Prototype feel findings + tuning values | `prototypes/building-concept/REPORT.md` | Wall extrusion, surface-aware picking, drag threshold, roof formations, undo | Source of validated values for `wall_height` and `drag_threshold_px` ONLY — `base_build_ticks` is a design hypothesis, NOT prototype-measured (build-over-time was out of prototype scope) |
| Flush blocks, material families, blue–orange state axis | `design/art/visual-direction-note.md` | §2b, material↔meaning language | Visual constraint |
| Grid write/read/raycast ownership; natural-vs-built open question | `design/gdd/voxel-world.md` | Core Rules 2/5, Open Questions | Ownership boundary; this GDD resolves its open question (Core Rule 15) |
| Action signals, mouse world-ray, Suspended state, pan margin question | `design/gdd/camera-input.md` | Core Rules 7–10, Open Questions | Input contract; this GDD answers the pan-margin question (see Open Questions) |
| Tick events, pause/warp, max_ticks_per_frame | `design/gdd/time-tick-system.md` | Core Rules, Formulas | F3's time base + burst rule |
| Palette, tier-0 set, `bed`, visual_asset | `design/gdd/resource-item-database.md` | Core Rules 5–8, Open Question 1 | Data contract; this GDD resolves its Open Question 1 (bed only) |
| MVP definition, Pillar 1, anti-pillar (no terraforming) | `design/gdd/game-concept.md` | MVP Definition, Pillars | Scope authority |
| Construction-job queue contract | `design/gdd/villager-ai-behavior.md` | Job claim/abandon (its Rules 3–7, F1, F4) | CONFIRMED 2026-07-10 |

## Acceptance Criteria

*(`qa-lead` consulted during authoring (5 rewrites/splits + 9 missing
criteria) AND a second fresh qa-lead pass ran in the 2026-07-09 full
design review (3 more rewrites/splits + 11 added criteria: AC6b, 15/15b,
36/36b splits and AC39–49). Criteria marked [PROVISIONAL] depend on the
undesigned Villager AI GDD or the Vertical Slice roof shape spec — their
Building-System-owned halves remain blocking unit tests now. Note: AC22/
AC23 and AC27/AC29 are intentionally similar but test different
boundaries — unit mock vs. Time & Tick integration; mixed-state undo vs.
batch atomicity.)*

**Tools and mode**
1. **GIVEN** no active tool, **WHEN** a tool is selected, **THEN** the state is ToolArmed and a ghost preview follows the pick each frame.
2. **GIVEN** Tool A armed, **WHEN** Tool B is selected, **THEN** A deactivates and B arms — exactly one tool is ever active.
3. **GIVEN** a tool armed, **WHEN** cancel fires (Esc/right-click), **THEN** the state returns to Idle and the ghost is hidden.

**Placement, validity, and formulas**
4. **GIVEN** an armed tool with a valid pick, **WHEN** `build_place` commits, **THEN** blueprint cells are created exactly matching the visible preview.
5. **GIVEN** a 5-cell wall drag at `wall_height` 3, **WHEN** committed, **THEN** exactly 15 blueprint cells exist (F1).
6. **GIVEN** a wall click below the drag threshold, **WHEN** committed, **THEN** exactly 1 column of `wall_height` cells is created via the click path (F4).
6b. **GIVEN** a drag where `cursor_travel_px >= drag_threshold_px` but `start_cell == end_cell`, **WHEN** committed, **THEN** exactly 1 column of `wall_height` cells is created via the Dragging path (F1 degenerate — distinct code path from AC6).
7. **GIVEN** a floor drag of 3 cells in x and 4 in z, **WHEN** committed, **THEN** exactly 20 blueprint cells exist (F2).
8. **GIVEN** a drag started on a block at height y > 0, **WHEN** dragging, **THEN** all preview/committed cells lie on that block's plane, never the ground plane (Core Rule 3).
9. **GIVEN** a drag extending past world bounds, **WHEN** committed, **THEN** only the in-bounds portion shown by the preview is created (Edge Case 1).
10. **GIVEN** a commit targets a cell already holding a constructed block or terrain (not replace-in-place), **WHEN** `build_place` fires, **THEN** it is rejected with visible feedback and no blueprint is created.
11. **GIVEN** a commit targets a cell holding a blueprint cell, **WHEN** `build_place` fires, **THEN** it is rejected (Edge Case 3).
12. **GIVEN** a terrain cell, **WHEN** `build_remove` targets it, **THEN** removal is rejected (Core Rule 15).
13. **GIVEN** a built cell, **WHEN** `build_remove` targets it, **THEN** it is removed instantly (Core Rule 16).
14. **GIVEN** a terrain cell, **WHEN** replace-in-place targets it, **THEN** the commit is rejected (Edge Case 2).
15. **GIVEN** the roof tool with the Flat formation and a 3×4 footprint drag, **WHEN** committed, **THEN** exactly 20 blueprint cells are created one plane above the footprint's highest picked surface (F5 Flat — testable now).
15b. **[PROVISIONAL — shape spec at VS]** **GIVEN** the roof tool with Gable/Hip/Shed and a footprint drag, **WHEN** committed, **THEN** a deterministic, non-zero cell set matching that formation is created, with the preview shown pre-commit (F5).
16. **GIVEN** the furniture tool with `bed` selected, **WHEN** targeting a cell with empty support below, **THEN** the commit is invalid; **WHEN** targeting a supported cell, **THEN** it is valid (Core Rule 8).
17. **GIVEN** furniture is in use, **WHEN** `build_remove` targets it, **THEN** removal succeeds immediately — never blocked by usage (Edge Case 11).
18. **GIVEN** the MVP data set, **WHEN** the palette is queried, **THEN** exactly the tier-0 materials and `bed` are offered (Core Rule 9).
19. **GIVEN** any MVP commit or completed construction, **WHEN** it occurs, **THEN** no resource is consumed (Core Rule 14).

**Construction and time**
20. **GIVEN** a blueprint cell fed `base_build_ticks` worth of tick events via a mocked on-site job, **WHEN** the last tick applies, **THEN** the Voxel World write occurs and the cell is Built (F3 — unit-testable without Villager AI).
21. **[PROVISIONAL — Villager AI]** **GIVEN** a real villager and a queued job, **WHEN** it claims, paths to site, and works, **THEN** the full claim→build→report cycle completes (integration test once that GDD lands).
22. **GIVEN** zero tick events are emitted over an interval, **WHEN** progress is checked, **THEN** UnderConstruction progress is unchanged (this system reacts only to ticks).
23. **GIVEN** the game is actually paused (integration), **WHEN** real time passes, **THEN** no construction progresses (companion to AC22, tested at the Time & Tick boundary).
24. **GIVEN** time-warp 2x, **WHEN** a cell builds, **THEN** wall-clock time halves but the tick count to complete is unchanged (F3 warp-invariance).
25. **GIVEN** a tick burst of 10, **WHEN** the current cell needs 2 more ticks, **THEN** that cell completes and no further queued cell receives leftover ticks that frame (F3 burst rule).
26. **GIVEN** the game is paused, **WHEN** a tool commits, **THEN** blueprint cells are created identically to the unpaused case (AC4); **WHEN** undo/redo fires, **THEN** the stack mutates and blueprints update exactly as when unpaused (building-while-paused, Game Feel).

**Undo/redo**
27. **GIVEN** a command with pending and already-built cells, **WHEN** undone, **THEN** pending cells are canceled and built cells are removed instantly (Core Rule 17, Edge Case 7).
28. **GIVEN** an undone command whose cells are now partially occupied, **WHEN** redone, **THEN** only still-valid cells are re-created; invalid ones are dropped with feedback (Edge Case 8).
29. **GIVEN** a 15-cell wall command, **WHEN** undo fires once, **THEN** all 15 cells cancel/remove in a single step (per-command granularity).
30. **GIVEN** the stack holds `undo_stack_depth` commands, **WHEN** a new command commits, **THEN** the oldest is discarded silently (Edge Case 9).
31. **GIVEN** any undo has occurred, **WHEN** a new command commits, **THEN** the redo branch is cleared.
32. **GIVEN** a scene transition, **WHEN** it completes, **THEN** the undo stack is empty (Core Rule 17).
32b. **GIVEN** a 3-command undo stack, **WHEN** a transition is triggered but ABORTS (target scene fails to load), **THEN** all 3 commands remain undoable — no begin-signal side effect touched the stack *(added 2026-07-10 re-review: the undo-abort trap fix)*.
33. **GIVEN** a command's built cell was modified by another system, **WHEN** that command is undone, **THEN** the stale entry is skipped without error or double-removal (undo bookkeeping, Interactions).

**Lifecycle and edge behavior**
34. **GIVEN** a scene transition, **WHEN** it completes, **THEN** pending blueprint cells and their construction progress persist — only the undo stack clears (Edge Case 10).
35. **GIVEN** a blueprint cell no villager can reach, **WHEN** any amount of game time passes, **THEN** the job remains queued and the ghost is never auto-canceled (Edge Case 5).
36. **GIVEN** a mocked "cell occupied" state for a construction-in-progress job, **WHEN** construction would start, **THEN** that cell's progress is skipped and the job stays queued while all other queued cells process normally (Edge Case 6 — Building-owned half, unit-testable now).
36b. **[PROVISIONAL — Villager AI]** **GIVEN** a real character occupying a construction target cell, **WHEN** construction would start, **THEN** the nudge-aside/deferral integration behaves per the Villager AI GDD (integration test once that GDD lands).
37. **GIVEN** Suspended is entered mid-drag, **WHEN** the transition starts, **THEN** the drag aborts with no commit and no partial blueprint (Edge Case 12).
38. **GIVEN** no valid pick (ray misses the world), **WHEN** `build_place` fires, **THEN** nothing happens and the ghost is hidden (Edge Case 4).

**Added by design review (2026-07-09)**
39. **GIVEN** a drag whose cell count would exceed `max_cells_per_command`, **WHEN** committed, **THEN** the commit is rejected with visible feedback and zero blueprint cells are created (Core Rule 9 cap).
40. **GIVEN** Suspended is entered (scene transition) while a cell is UnderConstruction, **WHEN** tick events continue, **THEN** construction progress continues to accumulate — Suspended halts tool interaction only, never construction (Edge Case 10).
41. **GIVEN** a Planned blueprint cell, **WHEN** the player directly removes it (not via undo), **THEN** it transitions to Canceled, the ghost is removed, and any claimed job is revoked (Blueprint lifecycle).
42. **GIVEN** an armed placement tool with no material/furniture selected, **WHEN** `build_place` fires on an otherwise valid pick, **THEN** the commit is rejected with visible feedback (Core Rule 9).
43. **GIVEN** a mocked job-claim for a Planned cell, **WHEN** the claim registers, **THEN** the cell transitions to UnderConstruction and its state is queryable as distinct from Planned (Blueprint lifecycle; feeds the visual-distinctness requirement).
44. **GIVEN** Dragging state, **WHEN** a different tool is selected mid-drag, **THEN** the drag aborts with no commit (Tool state table exit).
45. **GIVEN** two villagers with claimed jobs on distinct cells of the same command, **WHEN** a tick burst arrives, **THEN** each job's progress advances independently and at most one cell completes per villager that frame (F3 per-villager burst rule).
46. **GIVEN** this system completes a cell (its own Voxel World write), **WHEN** its undo-invalidation listener receives the resulting write signal, **THEN** the signal is recognized as self-originated and NO undo entry is invalidated (Interactions self-write exemption).
47. **GIVEN** N cells complete in the same frame (parallel villagers or multi-cell undo removal), **WHEN** the writes are issued, **THEN** Voxel World's bulk-write API is used and exactly ONE batched signal fires (Interactions batching rule).
48. **GIVEN** a job is reported unreachable, **WHEN** the report registers, **THEN** the affected ghost switches to the pulsing orange unreachable tint and the non-modal UI hint appears; **WHEN** the obstruction is removed and the job is claimed again, **THEN** the ghost returns to the normal Planned visual (Edge Case 5).
49. **GIVEN** the furniture tool, **WHEN** a bed blueprint targets a cell supported by a *blueprint* floor cell, **THEN** the commit is valid but the bed's construction cannot start until the support cell is Built (Core Rule 9 furniture clarification).

**Added by re-review (2026-07-10)**
50. **GIVEN** a drag whose pending cell count exceeds `preview_degradation_threshold`, **WHEN** the preview updates, **THEN** it renders as an outline/bounding representation rather than per-cell ghosts, while the eventual commit remains cell-exact (Dragging state, Tuning Knobs).
51. *(Cross-reference, not a Building AC)*: the full claim→build→report integration cycle promised by AC21 is concretely owned by **Villager AI AC40/40b** (added 2026-07-10); AC21 is fulfilled by those tests. Performance at population scale is gated by **Villager AI AC39** (milestone-gated) — this system's per-villager burst cost (F3) is part of what that AC measures.

## Open Questions

1. **Villager AI job contract** — **RESOLVED 2026-07-10**: the queue
   semantics are owned here (Core Rule 12); `villager-ai-behavior.md`
   confirms the contract and supplies every remaining half — claim
   mechanics + atomic race handling (its Rules 4, Edge Case 3), graceful
   abandon (its Rule 3), retry cadence (`unreachable_retry_ticks`, its
   Tuning Knobs), nudge-aside (its Rule 7 + F4), and the arrival/
   tick-boundary rule feeding F3 (its F1).
2. **Roof shape algorithms** — the per-formation cell-set functions behind
   F5 (Gable/Hip/Shed geometry over arbitrary footprints, odd-width
   ridges, minimum footprints). → *roof shape spec at Vertical Slice
   detail (game-designer + art-director)*
3. **Natural-vs-built distinction implementation** — Voxel World data flag
   vs. this system's own built-cell record (Core Rule 15 resolved the
   *design* question with "yes, needed"; the *mechanism* is architectural).
   → *building ADR via `/create-architecture`*
3b. **Mid-path solidification race** *(added by the 2026-07-10 re-review)*
   — villager movement is continuous game-delta interpolation (Villager AI
   F1), but Edge Case 6's "a cell never becomes solid under a character"
   guarantee is tick-discrete: whether a villager mid-interpolation INTO a
   cell counts as "occupying" it, and the intra-frame ordering of AI
   position update vs. occupancy check, are undefined. Related: a
   blueprint-only wall is walkable and can complete mid-transit (a
   consequence of the intentional non-solid-blueprints rule, Core Rule
   14b). Owned by NEITHER this GDD nor Villager AI alone — it is a seam.
   → *Building/AI integration section of the building ADR (cross-pointer
   in villager-ai-behavior.md OQ 3)*
3c. **Aggregate ghost ceiling + degraded-preview mechanism** *(added by
   the 2026-07-10 re-review)* — no settlement-wide cap exists on
   simultaneous Planned/UnderConstruction ghosts (only per-command 512 +
   per-preview 128), and the degraded outline preview has no stated
   draw-call story or re-rasterization cadence. Both are rendering-budget
   concerns for whichever approach the building ADR picks; the memory
   claim in Tuning Knobs should also gain an explicit per-record byte
   assumption there. → *building ADR + pre-VS performance spike*
4. **Rendering/meshing approach** — GridMap vs MultiMesh vs chunked/greedy
   mesher (inherited from game-concept; blueprint ghosts add a rendering
   requirement to whichever approach wins). → *building ADR*
5. **Alpha cost model** — where costs attach in the blueprint pipeline
   (reserve at commit vs consume at construction), hauling integration
   (Stonehearth model per user intent). → *Gathering & Production Chains +
   Storage & Inventory GDDs (Alpha)*
6. **Doors/windows at Vertical Slice** — how openings integrate with the
   wall tool (punch through existing walls? a dedicated fixture tool?).
   → *this GDD's VS revision*
7. **Should this system passively warn about unlivable structures** —
   **RESOLVED 2026-07-10**: fully split and owned. The
   unreachable-*blueprint* half lives here (Edge Case 5, orange ghosts);
   the completed-structure half lives in
   `build-validation-navigability.md` (sealed-space warnings, room
   detection, the 3-tier shelter recovery ladder). This system still
   never blocks (Core Rule 10 unchanged).
