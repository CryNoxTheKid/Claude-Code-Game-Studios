# Voxel World / Grid Data System

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: None directly — Foundation infrastructure for Pillar 1 (The building IS the game)

## Summary

Voxel World / Grid Data System is the single source of truth for the
block-level composition of the entire game world — both the procedurally
generated valley terrain (ground, hills) and every player-placed building
block, sharing one bounded grid data structure. It owns not just storage but
every read query other systems need (what block is at a cell, raycast
picking, neighbor lookups), so Building System, Villager AI, and every other
consumer query through one consistent interface instead of reinventing grid
logic.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `None`

## Overview

Voxel World is the foundational data layer that represents the game world as
a bounded 3D grid of typed cells. At world creation, the valley's terrain —
its ground, hills, and natural shape — is procedurally generated and written
into this same grid; from that point on, every block the player places
(walls, floors, roofs, fixtures) lives in the identical data structure,
addressed the same way. The world has a finite extent (a "hand-shaped
valley," not an infinite/streaming terrain) even though its specific shape is
generated rather than hand-authored. This system owns two responsibilities:
(1) storing which cell holds which block type/material, and (2) answering
every read query about that data — "what's at this cell," "what does this
ray hit first," "what are this cell's neighbors" — so every other system
(Building, Villager AI, Combat) queries through one consistent interface
rather than each implementing its own grid logic. It does NOT decide what's
allowed to be placed, when placement is valid, or how a cell's content
renders — those are the Building System's and the (not-yet-decided)
rendering ADR's concerns respectively.

## Player Fantasy

The player never perceives Voxel World as a system in its own right — they
only feel its effects through the Building System (does building feel
structured and consistent?) and through the valley feeling like a real,
"hand-shaped" place rather than a flat plane. Success means the grid never
leaks into player awareness — no visible seams between terrain and
player-placed blocks, no inconsistency in how picking/placement behaves
across different parts of the world.

*(`creative-director` not consulted — Lean mode skips non-high-risk sections.)*

## Detailed Design

*(`systems-designer` / `godot-specialist` not consulted — Lean mode skips
non-high-risk sections. Review manually before production.)*

### Core Rules

1. The world is represented as a bounded 3D grid of cells, addressed by
   integer coordinates (`Vector3i`), with a minimum and maximum extent set at
   world generation. **The grid origin is fixed at (0,0,0) and no
   negative cell coordinates ever exist** — bounds checks are simple
   non-negative comparisons *(invariant promoted from AC4 by the
   2026-07-10 review; the Formulas section's `floor()` requirement is
   defensive hardening for near-zero world positions, not support for
   negative cells)*.
2. Every cell holds exactly one of: empty (no block), or a block record
   containing a block-type identifier and a material identifier. There is no
   "layering" — one cell = one occupant. The identifiers are ids defined by
   the Resource & Item Database; this system stores them as opaque values
   and never resolves their meaning (no runtime dependency in either
   direction — see that GDD's Interactions section).
3. At world generation, terrain cells (ground, hills) are populated
   procedurally within the bounded extent; every cell not part of generated
   terrain starts empty and is available for player building.
4. Terrain cells and player-placed cells are stored identically — there is no
   data-level flag distinguishing "natural" from "built." *(→ Open Question:
   do consuming systems need this distinction for gameplay purposes, e.g.
   "can't build directly on undisturbed terrain without clearing it first"?
   → hand off to the Building System GDD.)*
5. This system exposes a read API (get cell contents, raycast against
   occupied cells, get a cell's neighbors) and a low-level write API (set
   cell contents, clear a cell) — it does NOT expose whether a placement is
   valid, or undo of the last action; those are the Building System's
   responsibility, composed on top of these primitives.
6. Every write emits a signal identifying the changed cell and its
   before/after contents, so dependent systems (rendering, the Building
   System's undo stack, Villager AI navigation) can react without polling.

### States and Transitions

*(System lifecycle, not per-cell state.)*

| State | Entry Condition | Exit Condition | Behavior |
|-------|-----------------|-----------------|----------|
| Uninitialized | Before terrain generation runs | Terrain generation completes | No query is valid; the grid is empty/unallocated |
| Generated | Terrain generation completes | Never (persists for the session) | Grid holds terrain; ready for player mutation and queries |
| Mutating | A write operation is in progress | Write completes | Very brief; no concurrent writes (mutations are serialized one at a time) |

### Interactions with Other Systems

- **Scene/World Management** (Foundation sibling): hosting relationship —
  this system's root lives inside the scene Scene/World Management loads
  (same pattern as that GDD's Interactions section).
- **Building System** (MVP, downstream, primary consumer): calls the write
  API to place/remove blocks, and the read API (raycast picking) to
  determine what's under the cursor. Building System owns: placement
  validity rules, drag-to-area logic, undo/redo composition, ghost-preview
  rendering. Voxel World owns: the actual data mutation and raw picking.
- **Villager AI & Behavior** (MVP, downstream): queries the read API for
  pathfinding-relevant occupancy (which cells are solid/walkable) — does NOT
  mutate the grid.
- **Squad & Combat System / Wave Defense** (Vertical Slice, downstream):
  query occupancy for line-of-sight, cover, and collision; do not mutate the
  grid directly (whether/how a wave can destroy a wall is open — see Open
  Questions).
- **Save/Load & World Persistence** (Vertical Slice, downstream): needs to
  serialize/deserialize the grid's full cell contents. Interface: this
  system exposes an iteration API over occupied (non-empty) cells, so
  Save/Load doesn't need to know internal storage details.
- **Resource & Item Database** (Foundation sibling, shared vocabulary): the
  block-type/material identifiers stored in cells (Core Rule 2) are ids
  defined by the Resource & Item Database. This system treats them as
  opaque values and never queries that database; consumers that need
  meaning (Building System, rendering) resolve the ids there. No runtime
  dependency in either direction.
- **Build Validation & Navigability** (MVP, downstream): reads physical
  occupancy for its room/region analysis (read-only, event-driven on the
  Building System's signals) — does NOT mutate the grid.

## Formulas

*(`systems-designer` and `godot-specialist` consulted — mandatory for this
high-risk section even in Lean mode.)*

### Cell-Coordinate ↔ World-Position Conversion

`world_pos = Vector3(cell.x, cell.y, cell.z) * cell_size + Vector3(0.5, 0.5, 0.5) * cell_size`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| cell | `cell` | Vector3i | bounded by world extent (see Tuning Knobs) | Integer cell address |
| cell_size | `cell_size` | float | fixed = `1.0` (locked, Visual Direction Note) | Edge length of one cell; blocks are flush, no gap |
| world_pos | `world_pos` | Vector3 | practically bounded by world extent × cell_size | Cell **center** point in world space |

**Output range**: unbounded by the formula itself; practically bounded because
`cell` always lies within the world's extent.
**Example**: `cell = (2, 0, 5)` → `world_pos = (2.5, 0.5, 5.5)`.

Inverse — **World → Cell**:
`cell = Vector3i(floor(world_pos.x / cell_size), floor(world_pos.y / cell_size), floor(world_pos.z / cell_size))`

Uses `floor()`, not truncation — Core Rule 1 guarantees no negative cell
coordinates exist, but truncation and `floor()` diverge for world positions
fractionally below 0.0 (e.g. a ray grazing the world edge at x = −0.001),
and `floor()` maps those cleanly to an out-of-bounds cell instead of
aliasing them into cell 0 *(reworded 2026-07-10 review — the old text
implied negative cells were possible, contradicting AC4)*. If the result
falls outside the world's
bounds, the API must return an explicit "outside grid" result, NOT silently
clamp to the edge (see Edge Cases).

### Raycast / Cell-Picking — deliberately NOT a Formula

Raycast picking is a stepping search (a DDA-style grid walk), not an
input→output value-table case. It stays at the level already set in Core
Rule 5: "raycast against occupied cells" is part of the read API's
behavioral contract. Two technically distinct implementations are possible
(native physics collision vs. a manual DDA algorithm, as the concept
prototype used) — WHICH one is used is deliberately left to the future
rendering ADR, not decided in this GDD.

### Procedural Terrain Height (`procedural_terrain_height`)

`h(x, z) = clamp(round(base_height + amplitude * noise2D(x * frequency, z * frequency)), min_y, max_y)`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| x, z | `x, z` | int | within the world's horizontal extent | Horizontal cell coordinates |
| base_height | `base_height` | int | Tuning Knob | Valley-floor cell height |
| amplitude | `amplitude` | float | Tuning Knob, ≥ 0 | Max height variation from noise |
| frequency | `frequency` | float | Tuning Knob, > 0 | Noise scale (lower = broader hills) |
| noise2D | function | — | returns [-1, 1] | Deterministic, seeded 2D noise |
| min_y, max_y | `min_y, max_y` | int | = world's vertical bounds | Clamp range |
| h | `h` | int | `[min_y, max_y]` | Resulting terrain height at (x, z) |

**Output range**: hard-clamped to `[min_y, max_y]`.
**Example**: `base_height=4, amplitude=3, frequency=0.05, noise2D(...)=0.6` →
`h = clamp(round(4 + 1.8), 0, 16) = 6` *(bounds corrected 2026-07-10 review — the example previously showed a stale `max_y` of 15)*.

*(This defines only the height mechanism — the specific "hand-shaped valley"
silhouette is a later level-design decision via `amplitude`/`frequency` or an
added radial falloff term → see Open Questions.)*

### World Bounds Sizing — deliberately NOT a Formula

World extent is not a derived value — it's an authored choice trading scope
against memory/draw-call budget. See Tuning Knobs.

### Supporting Godot 4.7 facts

- `Vector3i` hashes correctly as a `Dictionary` key (value-equality hashing)
  and computes with exact integer arithmetic — neighbor-lookup offsets and
  bounds checks are exact comparisons, not epsilon-tolerant ones. Godot 4.4+
  typed Dictionaries (`Dictionary[Vector3i, ...]`) give static-type safety
  at negligible cost — use them *(2026-07-10 review note)*.
- Memory back-of-envelope *(2026-07-10 review note)*: a sparse Dictionary
  storing only occupied cells keeps a ~100×32×100 world in the tens of MB
  even at high occupancy — comfortably inside the 4 GB ceiling; the real
  memory/perf risk lives in the RENDERING representation (rendering ADR),
  not this data layer.
- Collider strategy is a rendering-ADR concern *(2026-07-10 review note)*:
  if raycast picking is implemented via physics (rather than manual DDA),
  per-cell colliders for tens of thousands of terrain cells are a known
  Jolt/scene-tree scalability trap — the ADR must decide picking mechanism
  and collider granularity together, not separately.
- A single read or write must be O(1) relative to grid size (see Acceptance
  Criteria).
- Bulk-write operations (drag-to-area placement) should emit ONE batched
  signal, not one per cell — otherwise the Building System's undo stack and
  any rendering listener are thrashed (see Edge Cases).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| Query/write for a cell outside the world's bounds | The API returns an explicit "outside grid" result — it does NOT silently clamp to the edge | Prevents silent bugs at boundary cases (see Formulas) |
| A bulk write operation (e.g., dragging a wall across many cells) | Exactly ONE batched change signal is emitted, not one per cell — and the batched payload (and the bulk-write API's return value) carries the per-cell previous contents for EVERY affected cell *(added 2026-07-10 review: Building's undo stack must restore each cell individually; a batch without per-cell before-states is un-undoable)* | Prevents thrashing the Building System's undo stack and rendering listeners while keeping undo lossless |
| Terrain generation populates the initial grid | The batched-signal mandate applies here too: generation emits at most ONE batched signal (or none, if listeners attach only after the Generated state) — never one signal per terrain cell *(added 2026-07-10 review)* | A valley floor is tens of thousands of cells; per-cell signals at boot would stall the Booting state |
| Writing to an already-occupied cell (terrain or another block) | Always overwrites and returns the previous contents; whether overwriting SHOULD be allowed is the caller's (Building System's) decision | This layer stays a pure primitive, not a rules check |
| `base_height` is misconfigured above `max_y` | The entire terrain clamps flat at `max_y` (no crash, but visibly wrong) | The formula clamps correctly; the designer must notice the tuning mistake — documented as a warning |
| Read/raycast queries are called very frequently per frame (e.g., every mouse-move for hover picking) | Never mutate grid state; remain cheap (O(1)) regardless of call frequency | Hover-picking is the most frequent query pattern in the Building System |
| Save/Load iterates occupied cells while a write is in progress | Iteration only observes fully-committed cell states, never a write in progress | Mutations are serialized (see States) — no torn reads |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|----------------------|
| *(none)* | This system depends on | Foundation layer — zero upstream dependencies |
| Scene/World Management | Depended on by (structural) | This system's root attaches under the scene Scene/World Management loads (hosting, not data) |
| Save/Load & World Persistence | Depended on by | Iterates occupied cells via the read API to serialize world state |
| Building System | Depended on by | Primary consumer — calls the write API to place/remove blocks, the read API for picking |
| Villager AI & Behavior | Depended on by | Queries the read API for pathfinding-relevant occupancy |
| Squad & Combat System | Depended on by (Vertical Slice) | Queries occupancy for line-of-sight/collision |
| Wave Defense | Depended on by (Vertical Slice) | Queries occupancy; may need to mutate the grid if waves can destroy blocks (see Open Questions) |
| Build Validation & Navigability | Depended on by | Reads physical occupancy for room/region analysis — read-only, event-driven (added 2026-07-10, cross-review bidirectional fix) |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------------|------------|---------------------|---------------------|
| `world_width_cells` | 64 | 32–256 | Larger valley, more room to build/explore; more cells to manage | Smaller valley, faster to fully populate; risk of feeling cramped |
| `world_depth_cells` | 64 | 32–256 | Same as width | Same as width |
| `min_y` | 0 | fixed at 0 (recommended) | Shifts all coordinates, rarely useful | — |
| `max_y` | 16 | 8–32 | Taller hills/multi-story buildings possible; more vertical cells to store | Flatter valley, less room for tall structures |
| `base_height` | 4 | 0 to max_y−1 | Higher valley floor overall | Lower valley floor, deeper basin feel |
| `amplitude` | 3 | 0–8 | More dramatic hills; risk of terrain interfering with flat buildable areas | Flatter, gentler terrain; risk of feeling featureless |
| `frequency` | 0.05 | 0.01–0.2 | More, smaller hills (busier terrain) | Broader, smoother hills |

*(All values are provisional starting points — final size/performance limits
depend on the still-open performance spike before Vertical Slice, see Open
Questions.)*

## Visual/Audio Requirements

This system has no visual/audio events of its own. All visible/audible
feedback about blocks (placement, textures, sounds) belongs to the Building
System and the still-open rendering ADR — Voxel World only provides data and
signals, never presentation. The one near-exception would be a loading
indicator during terrain generation, but Scene/World Management already
establishes there is no loading screen at MVP — terrain generation must
therefore run synchronously/near-instantly before the first visible scene.

## Game Feel

N/A — no player input touches this system directly (the Building System owns
all input). One indirect link is worth noting: the O(1) read/write
requirement (Acceptance Criterion 16) is the technical foundation that lets
building feel "instant" and "snappy" in the Building System — this system
supplies the speed, the Building System supplies the feel.

## UI Requirements

N/A — no direct UI. Any UI element that displays Voxel World data (build
preview, cell highlight) belongs to Building UI, not here.

## Cross-References

| This Document References | Target GDD | Specific Element Referenced | Nature |
|---------------------------|-----------|-------------------------------|--------|
| "Building System owns placement validity, drag-to-area logic, undo/redo" | `design/gdd/building-system.md` (not yet authored) | Placement-rule ownership boundary | Rule dependency |
| "Villager AI queries the read API for pathfinding-relevant occupancy" | `design/gdd/villager-ai-behavior.md` (not yet authored) | Occupancy query usage | Data dependency |
| "cell_size = 1.0, flush blocks, no gap" | `design/art/visual-direction-note.md` | §2b Classic blocky shape language | Rule dependency |
| "batched write signal feeds the Building System's undo stack" | `design/gdd/building-system.md` (not yet authored) | Undo composition | Data dependency |

*(Both target GDDs do not exist yet — marked as provisional assumptions, to be
cross-checked when each is authored.)*

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Verdict: GAPS on first draft → 5 missing/underspecified criteria added:
terrain/player-cell indistinguishability, torn-read prevention, base_height
misconfiguration, raycast correctness, Save/Load iteration contents.)*

1. **GIVEN** the game boots, **WHEN** terrain generation completes, **THEN**
   every cell within the world bounds holds either a terrain block or is
   empty, and the system transitions Uninitialized → Generated. *[Logic]*
2. **GIVEN** a valid cell coordinate within bounds, **WHEN** the read API is
   queried, **THEN** it returns the correct occupant matching the last write
   to that cell. *[Logic]*
3. **GIVEN** a cell coordinate outside the world bounds, **WHEN** the read or
   write API is called, **THEN** it returns an explicit "outside grid"
   result — never a silent clamp or crash. *[Logic]*
4. **GIVEN** a world-space point, **WHEN** converted via World→Cell, **THEN**
   `floor()` is used; the grid origin is fixed at (0,0,0) and no negative
   cell coordinates exist, so bounds checks are simple non-negative
   comparisons. *[Logic]*
5. **GIVEN** a cell coordinate, **WHEN** converted via Cell→World, **THEN**
   the result is the cell's center point. *[Logic]*
6. **GIVEN** a single cell write, **WHEN** it completes, **THEN** exactly one
   change signal is emitted identifying the cell and its before/after
   contents. *[Logic]*
7. **GIVEN** a bulk write affecting N cells, **WHEN** it completes, **THEN**
   exactly ONE batched change signal is emitted. *[Logic]*
8. **GIVEN** a write to an already-occupied cell, **WHEN** it completes,
   **THEN** it overwrites and returns the previous contents to the caller.
   *[Logic]*
9. **GIVEN** a terrain cell and a player-placed cell with identical
   block-type/material, **WHEN** read via the API, **THEN** the results are
   indistinguishable — no hidden origin flag. *[Logic]*
10. **GIVEN** the terrain height formula, **WHEN** evaluated at any (x,z)
    within bounds, **THEN** the output is always within `[min_y, max_y]`.
    *[Logic]*
11. **GIVEN** `base_height` > `max_y` (misconfiguration), **WHEN** terrain
    generates, **THEN** it clamps flat at `max_y`, no crash, and a warning
    is logged. *[Logic]*
12. **GIVEN** a raycast against placed cells, **WHEN** cast, **THEN** it
    correctly returns the first occupied cell along the ray (or none) —
    independent of the eventual rendering mechanism. *[Integration]*
13. **GIVEN** a raycast, **WHEN** called repeatedly (e.g., every frame during
    hover), **THEN** it never mutates grid state. *[Logic]*
14. **GIVEN** an iteration over occupied cells (Save/Load), **WHEN** a write
    occurs concurrently, **THEN** the iteration observes only
    fully-committed states, never a partial write. *[Integration]*
15. **GIVEN** the Save/Load iteration API is called, **WHEN** it runs,
    **THEN** it returns only non-empty (occupied) cells. *[Logic]*
16. **Performance**: a single cell read/write completes in O(1) time
    relative to grid size. *[Performance, Advisory — milestone-gated:
    verified at the pre-VS spike, not per-story; re-tiered 2026-07-10
    review (an algorithmic-complexity claim isn't per-commit testable)]*
17. No hardcoded values in implementation — world bounds, `base_height`,
    `amplitude`, `frequency` are read from config, not literals in code.
    *[Config/Data, Advisory]*

**Added by the 2026-07-10 design review:**
18. **GIVEN** a bulk write affecting N cells, **WHEN** the batched signal is emitted, **THEN** its payload contains the before/after contents for ALL N affected cells (per-cell granularity inside the single signal), and the bulk-write API's return value carries the same per-cell previous contents. *[Logic]*
19. **GIVEN** terrain generation at boot, **WHEN** the grid is populated, **THEN** at most one batched change signal is observed by any listener — never per-cell signals. *[Integration]*

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Do terrain and player-placed cells need a gameplay distinction after all (e.g. "can't build directly on undisturbed terrain")? | game-designer (Building System GDD) | When the Building System GDD is authored | **RESOLVED 2026-07-09: YES** — Building System Core Rule 15: terrain is not removable, built cells are; the game must distinguish them. Mechanism (data flag here vs. Building's own record) deferred to the building ADR (see building-system.md Open Question 3) |
| Can Wave Defense destroy cells (e.g. breach a wall), and if so, through which API? | game-designer (Wave Defense GDD) | After the `/prototype wave-defense` spike | — |
| What is the concrete "hand-shaped valley" silhouette beyond the base height formula (basin shape, radial falloff)? | level-designer / art-director | Before Vertical Slice | — |
| Which rendering implementation is used (GridMap vs. MultiMeshInstance3D vs. chunked mesher) — directly determines world-extent and performance limits? | technical-director | At `/create-architecture` (building ADR) | — |
| Which picking mechanism is used (native physics collision vs. manual DDA)? | godot-specialist | At `/create-architecture` (building ADR) | — |
