# Story 034: Scaffolding — the builder gets real ground to walk on

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration (Building System + Villager AI nav + Build Validation)
> **Estimate**: 3 relative-complexity units (≈3× a single-module logic story). One
>   serial chain of three: **(1)** where a scaffold cell lives + the predicate read
>   source → **(2)** the ADR-0007 amendment landing in `VillagerNavGraph` → **(3)**
>   erect/dismantle lifecycle. Nothing in the chain parallelises. The real critical
>   path is the four **Open Decisions** below, not throughput — three of them are TD
>   rulings and one is a creative/design value.
> **Manifest Version**: 2026-07-23
> **Last Updated**: 2026-07-27

> **Numbering note**: this story was requested as `story-032-scaffolding.md`. `032` is
> already taken by `story-032-undo-redo-stack-core.md`, and `033` by
> `story-033-voxel-write-seam.md`. Filed as **034**, the next free number in
> `production/epics/building-system/`. (Second such collision today — see the
> `story-022` collision.)

## Context

**GDD**: `design/gdd/building-system.md` (Core Rules 11/12/14, F3 construction time,
Tuning Knobs), `design/gdd/villager-ai-behavior.md` (Rule 8/8a standability, Rule 9
step-legality, Rule 15/F5 unstuck watchdog, Rule 16/F6 seal prevention),
`design/gdd/build-validation-navigability.md` (Rule 1 candidate interior cell)
**ADR Governing Implementation**: **ADR-0007** (AStar3D pathfinding & shared
walkability predicates) — primary, and the one this story proposes to **amend**;
ADR-0009 (deterministic movement, occupancy, seal prevention), ADR-0016
(build-project entity lifecycle), ADR-0002 (config), ADR-0001 (DI)

**Engine**: Godot 4.7-stable | **Risk**: HIGH

---

### Why this story exists

`villager-ai-024` established the rule empirically and named it precisely:

> `VillagerNavGraph` never connects two cells in the **same column**. A step is
> defined as inherently horizontal — `HORIZONTAL_HALF_OFFSETS` /
> `HORIZONTAL_FULL_OFFSETS` never contain `(0, 0)`, with `|Δy| ≤ 1` riding along.
> And `VillagerWalkabilityRules.is_standable(cell)` requires the cell BELOW to be
> solid, so two stacked cells can never both be standable graph points at once. A
> same-column vertical edge is therefore not merely missing — **it is impossible by
> construction.**

The consequence, measured on the real booted game and not inferred: a wall's third
layer enters the graph as an **isolated point** with zero edges — `has_point == true`,
`find_path` from every occupied cell returns `[]` on every tick up to 5000. So
`VillagerJobSelector`'s true-path check can never succeed and the cell is excluded
from selection **before any claim is attempted** (`state == PLANNED`,
`claimed_by == -1`, `abandon_count == 0`).

**The landed fix works, and it works *around* the gap.** `villager-ai-024` moves the
builder discretely: `VillagerAi.climb_onto_self_sealed_cell()` when the seal-prevention
exemption fires, and `VillagerAi._relocate_if_marooned()` when the column finishes and
leaves it on a zero-edge point. That is two of ADR-0009's four sanctioned discrete
`current_cell` mutation points, spent on covering for a missing edge class.

**Scaffolding closes the gap instead of routing around it: the builder gets real
ground to walk on.**

### It also fixes a second, still-open symptom

`villager-ai-024`'s own **CORRECTION (2026-07-27, user-caught)** records that the
payoff demo's stall at 27/30 was not pacing (D10) — it was **stranding**:

    room walls: WAIT CAP (220s) hit with 27/30 cells BUILT — stopping honestly
    D10 check: 6 SLEEPING episode(s) observed this run:
      episode 1: GROUND sleep at (992, 9, 1003) (no bed owned yet)

Sleep coordinates at y=9 and y=10 against a build site at y=6 with walls to y=8 —
every one **on top of the structure**, `state=5` (WANDERING). The villager climbed up,
could not get down, wandered the roof plane and slept there. The symmetric descend fix
does **not** cover this path: it fires when a *column* completes, not when a builder is
left stranded on a *finished structure*.

**Stranding — not D10 — is what blocks `scene-009` and `presentation-005`'s open AC.**

---

### THE KEY PROPERTY: scaffolding is NOT a solid block

This is what makes the story cheap, and it must be stated explicitly because two
otherwise-expensive risks vanish for free because of it.

Minecraft's scaffolding has **no collision**: you pass through it, you stand on top of
it, and you climb it from the inside
(source: <https://minecraft.wiki/w/Scaffolding>). This story adopts that property
verbatim as its load-bearing design constraint, not as flavour.

**A scaffold cell is passable. It is never solid. It never satisfies any consumer's
`_is_solid` read.**

#### Risk that vanishes #1 — PHANTOM ROOMS

`BuildValidation` keys entirely on **solid** cells.
`CandidateCellRules.is_candidate_interior_cell` composes
`VillagerWalkabilityRules.is_standable` with `is_roofed`, and `is_roofed`'s upward scan
is `_is_solid(voxel_world, cell + (0, offset, 0))`, which is
`contents != null and not contents.is_empty()`. A non-solid scaffold cell can
**never** read as a wall or a roof, so scaffolding around a half-built house can never
declare it sheltered. **No scaffold-awareness is required anywhere in
`src/build_validation/`.** This is a structural guarantee from the passability
property, not a rule anyone has to remember.

#### Risk that vanishes #2 — SELF-SEALING

`VillagerSealPreventionGate` exists to stop a villager entombing itself behind a
Planned→Built write. **A villager cannot trap itself behind something it can walk
through.** Erecting scaffolding can never entrap anyone, so the gate needs **no**
scaffold-awareness, and `villager-ai-016`'s livelock escape is untouched. This story
changes zero lines in `villager_seal_prevention_gate.gd`.

> Corollary the implementer must not lose: because scaffolding is non-solid, it is
> also **not voxel data**. See Open Decision **D1** — this is the single largest
> unresolved question in the story.

---

### NAV-GRAPH CONSEQUENCE — a BOUNDED amendment, not general climbing

Two changes, both narrow, both scoped to scaffold cells only:

1. A scaffold cell is **standable without a solid cell beneath it** — it supports
   itself.
2. **Vertical edges become legal ONLY between two scaffold cells in the same column.**

**Nothing else about movement changes.** No ladders, no stairs, no jumping, no falling,
no general climbing. `max_step_height` stays 1. `villager_clearance` stays 3. Two
stacked non-scaffold cells still can never both be standable. This is deliberately the
smallest amendment that admits the missing edge class, and it needs a **technical-director
ruling** — this story proposes the wording, it does not edit the ADR.

---

## PROPOSED ADR-0007 AMENDMENT (exact wording — for TD ruling; DO NOT self-apply)

> **Owner**: technical-director. **This story does not edit
> `docs/architecture/adr-0007-ai-pathfinding-navigation-room-analysis.md`.** The text
> below is the proposal, written to drop in as-is if accepted.

Add to **Decision**, after §1:

> **§1a — Scaffold standability (amendment, story `building-034`).** A cell occupied by
> a **scaffold** is standable **without** a solid cell beneath it — scaffolding supports
> itself. The standability predicate reads:
>
> > `cell` is standable iff **(** the cell directly below it is solid **OR** `cell`
> > itself is a scaffold cell **)** AND `cell` plus the `villager_clearance - 1` cells
> > directly above it are all passable.
>
> A scaffold cell is **passable**: it is never solid, never occludes, and never
> satisfies any consumer's solidity read. It therefore can never contribute a wall or a
> roof to Build Validation's Room/Sealed verdict (§3 is unchanged and stays
> scaffold-blind), and can never entrap a villager for the purposes of ADR-0009's
> seal-prevention gate.
>
> **§1b — The predicates keep their single-source-of-truth status.** Scaffold occupancy
> is **not** voxel data (the same ruling BV-1 already applies to furniture: "furniture is
> not voxel data — it never enters `VoxelWorldGrid`"). §1a therefore requires the shared
> predicates to read a **second occupancy source** alongside `VoxelWorldGrid`. That
> source is supplied as an **explicit parameter** on the shared predicate functions —
> never a module-global, never a singleton read, and never a second copy of the rules
> living in a consumer. Both consumers (Villager AI's `AStar3D` graph and Build
> Validation's BFS) continue to call one implementation. A caller that supplies **no**
> scaffold source observes exactly today's behaviour, which is what keeps §3's
> independence and the "no duplicated rules or constants" guarantee structural rather
> than disciplinary.

Add to **Decision**, after §2:

> **§2a — Scaffold vertical edges (amendment, story `building-034`).** The travel graph
> gains **exactly one** new edge class and no other: a **vertical edge between two
> scaffold cells in the same column** — `Δx = 0`, `Δz = 0`, `Δy = ±1`, and **both**
> endpoints are scaffold cells — is a legal step. Every other same-column pair remains
> structurally unconnectable, exactly as the horizontal-offset sets already guarantee.
> The step-legality predicate is otherwise unchanged: `|Δy| ≤ max_step_height` still
> governs every non-scaffold step, and the diagonal flanking rule is untouched (a
> vertical scaffold edge is never diagonal, so the flank check never runs on it).
>
> **This amendment is bounded and is not general climbing.** It introduces no ladder,
> stair, jump, or fall mechanic; it does not raise `max_step_height`; it does not change
> `villager_clearance`; and it grants no vertical traversal to any cell that is not a
> scaffold cell.

Add to **Validation Criteria**:

> - A unit test asserts a scaffold cell is standable with **air** beneath it, and — in
>   the same test — that two stacked **non-scaffold** cells are still never both
>   standable. The amendment must not widen beyond scaffolding.
> - A unit test asserts the vertical step is refused when **only one** endpoint is a
>   scaffold cell, in both directions.
> - A unit test asserts `CandidateCellRules.is_roofed` returns `false` for a column
>   whose only occupant above the query cell is scaffolding — scaffolding is never a
>   roof.
> - Grep-verifiable: the scaffold occupancy source appears as a parameter on the shared
>   predicates and nowhere as a second implementation of standability or step-legality.

**Downstream doc updates the amendment implies** (also TD-owned, not this story's edits):
`docs/architecture/control-manifest.md` Feature Layer "Walkability = two shared pure
functions" bullet, and its Manifest Version bump.

---

## Acceptance Criteria

Ruling ACs (AC1–AC4) are the **user's four binding rulings**, transcribed. AC5–AC9 are
the structural properties the rulings depend on.

- [ ] **AC1 — TRIGGER: automatic, on demand.** The system detects an unreachable
      target cell and erects scaffolding **exactly there**. The player only draws the
      room; there is no scaffolding tool, no scaffolding button, and no scaffolding
      material in any palette. Scaffolding is erected **only when needed** — a room
      whose every cell is already reachable produces **zero** scaffold cells.
      *(See **D5**: the detector this AC assumes does not exist today.)*
- [ ] **AC2 — BUILD COST: a real construction job, but fast.** Erecting a scaffold cell
      is a worker-executed construction job on the same tick loop as any other cell —
      nothing appears from nothing. Its tick cost is **markedly lower** than a wall
      cell's, read from config (`base_build_ticks[scaffold]`), never a literal, and
      strictly less than `base_build_ticks[block]`. *(See **D7** for the value.)*
- [ ] **AC3 — LIFETIME: auto-dismantled on project completion, TOP-DOWN.** When the
      owning project completes, its scaffolding is automatically dismantled from the
      **top down**, so the worker **rides it down** and can never strand itself. A
      **player-initiated cancel MAY** instead collapse the whole structure **bottom-up
      with no worker**, Minecraft-style. Both paths terminate with zero scaffold cells
      remaining and no villager left on a zero-edge graph point. *(See **D3**, **D4**.)*
- [ ] **AC4 — THE 6-LIMIT: horizontal cantilever, not height.** A scaffold cell may sit
      at most **6 cells sideways** from its supporting column. The limit constrains
      **overhang only** — scaffold height is unbounded by this rule. The value is a
      **config knob from day one** (`scaffold_max_cantilever_cells`, default 6), never a
      literal anywhere in `src/`, because items and skills will later **raise** this
      reach as a progression stat. *(See **D6** for the unit and the support definition.)*
- [ ] **AC5 — Scaffolding is never solid.** Every solidity read in the codebase
      (`VillagerWalkabilityRules._is_solid`, `CandidateCellRules._is_solid`, the mesher's
      face-culling occupancy read) reports a scaffold cell as **not solid**. Asserted
      directly, not assumed.
- [ ] **AC6 — No phantom rooms.** A half-built house fully surrounded by scaffolding is
      **not** classified as a Room and its bed is **not** sheltered. `src/build_validation/`
      contains zero scaffold-aware code — the property holds because there is nothing for
      it to read.
- [ ] **AC7 — Seal prevention is untouched.** `villager_seal_prevention_gate.gd` is
      unmodified by this story. `seal_prevention_test.gd` and `unstuck_watchdog_test.gd`
      pass unchanged, at their current counts.
- [ ] **AC8 — The nav-graph amendment is bounded.** A scaffold cell is standable with
      air beneath it; two stacked non-scaffold cells are still never both standable; a
      vertical step is legal only when **both** endpoints are scaffold cells. No other
      movement rule changes.
- [ ] **AC9 — Determinism survives (ADR-0009).** Same world, same villager, same job
      order ⇒ the same scaffold cells erected, in the same order, and dismantled in the
      same order. *(See **D8** — the erection route is currently undetermined.)*
- [ ] **AC10 — The payoff demo stops stranding.** `tools/payoff_loop_demo.gd` run end to
      end reaches a fully enclosed, roofed, Room-classifiable structure, and its report
      records **zero** sleep episodes above the build-site ground plane. This retires
      `villager-ai-024`'s AC5/AC6 debt.

---

## Anti-Vacuity Lever

**Two assertions on the real booted game, plus one deletion probe.** Fixture checks are
the guard, not the lever — the strongest levers this project has produced were live
scene-tree counts and real-booted-game assertions.

### Lever 1 (primary) — the top course becomes reachable, in the shipped game

Boot the real `Valley` scene through `GameWorld`'s boot gate (the harness
`neues-spiel/tests/integration/scene_world_management/build_validation_gates_hosting_test.gd`
already establishes — real `TimeTickSystem` autoload tick, hosted `WallTool`, hosted
`ConstructionTickLoop`, hosted gates, one real villager). Draw a room at the shipped
`WallToolConfig.wall_height` (= 3). Then assert, against the **hosted**
`VillagerNavGraph`:

```
find_path(villager.get_current_cell(), <standing cell for the top wall course>) != []
```

**This is provably false on today's build.** `villager-ai-024` measured it directly, not
by inference: `has_point == true` and `find_path` returns `[]` from **every** occupied
cell, on **every** tick up to 5000. There is no configuration, tick budget, or room
shape in which today's build satisfies this — so it cannot pass vacuously, and it cannot
be satisfied by a tick-budget increase.

### Lever 2 — the builder comes back down, in the shipped game

Same booted run. At the moment the owning project reaches `ProjectState.DONE`, assert:

```
find_path(villager.get_current_cell(), <the villager's spawn/settlement ground cell>) != []
```

i.e. the villager finishes standing somewhere **connected to the settlement ground
graph**. On today's build the demo's villager finishes on the roof plane at y=9/y=10
(`state=5`, WANDERING) on a zero-edge point, so the path is empty. **Also provably false
today**, and it is a different failure from Lever 1 — Lever 1 can be satisfied while
Lever 2 still fails, which is exactly the `villager-ai-024` correction's finding.

### Lever 3 — deletion probe (required, per this project's standing rule)

Delete the scaffold-erection call site **once**, re-run Levers 1 and 2, and record the
observed failure — cell coordinates, `state`, `claimed_by_villager_id`, the empty
`find_path` result — in the commit body. A green suite that stays green with the
production call removed is a vacuous suite.

### Guard assertions (unit tier, not the lever)

- A scaffold cell is standable with air beneath it; two stacked non-scaffold cells are
  not both standable. Today the first line of `VillagerWalkabilityRules.is_standable` is
  `if not _is_solid(voxel_world, cell + Vector3i(0, -1, 0)): return false`, so the first
  assertion cannot pass today **by construction**.
- `CandidateCellRules.is_roofed` is `false` for a column roofed only by scaffolding.
- A vertical step with one scaffold endpoint and one ordinary endpoint is refused, both
  directions.

---

## Out of Scope

- **General climbing, ladders, stairs, jumping, falling, or gravity of any kind.** The
  amendment is bounded to scaffold-to-scaffold vertical edges. Nothing else.
- **Retiring `villager-ai-024`'s climb-up/climb-down discrete mutation.** Recommended
  below as an **open recommendation**, deliberately not done here — it needs a TD/user
  ruling and should land only after scaffolding is proven in the shipped game.
- **A player-facing scaffolding tool.** Ruling 1 is explicit: automatic, on demand, the
  player only draws the room. No palette entry, no button, no material.
- **Retuning `wall_height`.** Three is the designed height; a fix that only works at two
  is not a fix (`villager-ai-024`'s own Out of Scope, inherited).
- **Multi-villager scaffold sharing / contention.** One builder, as today.
- **Scaffolding for demolition, dig, or excavation projects.** Build projects only
  (`BuildProject.Kind.BUILD`). Dig-order reachability is a separate question.
- **Scaffold visual polish** — silhouette, material, tint tiers, LOD. This story needs
  scaffolding to be *visible and legible*; art direction of it is the art department's
  call, and **D2** flags who owns the rendering path at all.
- **The hen-and-egg pacing question (D10 in `villager-ai-024`).** The correction in that
  story downgraded it from blocker to open design question; it stays a creative-director
  call, not this story's.
- **Save/load of scaffold state.** ADR-0012's per-system `serialize()` contract absorbs
  it structurally, but a scaffold that is by construction transient (erected on demand,
  dismantled on completion) may reasonably not be persisted at all. Named, not decided —
  and folded into **D3**, since the answer depends on whether scaffolding is its own
  entity.

---

## Open Decisions — what the four rulings do not answer

These are the real critical path. Each is stated with the evidence that produced it,
the options, and a recommendation. **None is decided by this story.**

### D1 — Where does a scaffold cell LIVE? *(TD ruling — largest open item)*

**The finding.** A scaffold cell **cannot** live in `VoxelWorldGrid`. `CellContents`
has exactly one occupancy axis: `is_empty()` is `block_type_id == EMPTY_BLOCK_TYPE_ID`
(= 0). **Any** non-zero block id is solid to **every** `_is_solid` reader in the
codebase — walkability, the roof scan, and the chunked mesher's face-culling. There is
no "passable block" concept anywhere in Voxel World, and inventing one changes
`is_empty()`'s meaning project-wide, in a module whose GDD states "one cell = one
occupant" and whose storage is a packed byte array.

**The precedent that fits.** TD ruling **BV-1** already answered this exact shape for
furniture: *"Furniture is not voxel data. It never enters `VoxelWorldGrid`... occupancy
lives in a Building-System-owned furniture registry."* `FurnitureRegistry` is the
landed implementation of that ruling and is the obvious model.

**Where the analogy breaks, and why this is a real decision.** Furniture is
walkability-**transparent** *by having nothing to read* — `CandidateCellRules`' doc
comment states this explicitly: *"This class therefore has no furniture-registry
parameter of any kind; the transparency property holds because there is nothing for it
to read."* **Scaffolding must do the opposite**: it must *change* walkability. And
`VillagerWalkabilityRules` is a static, `RefCounted`, never-instantiated library whose
predicates read **only** `voxel_world`.

- **Option (a) — scaffold registry + explicit overlay parameter on the predicates.**
  A `ScaffoldRegistry` mirroring `FurnitureRegistry`, plus a new optional parameter on
  `is_standable` / `is_step_legal`. Every existing call site that passes nothing keeps
  today's exact behaviour. **Note the standing tech debt this collides with**:
  `villager_walkability_rules.gd`'s own Out-of-Scope block names *"an overlay-predicate
  parameter unifying [the `*_after_write` twins] with this class is a later story."*
  Scaffolding may be that story's forcing function, and the TD should decide whether to
  unify the two overlay concepts or keep them separate.
- **Option (b) — a passability flag on `CellContents`.** Cheapest at the call sites,
  but redefines `is_empty()` for the whole project and touches storage, the mesher, the
  DDA pick, save format, and every `_is_solid` reader. High blast radius.
- **Option (c) — reuse the `*_after_write` override-aware twins' shape** as the overlay
  mechanism, rather than adding a parallel one.

**Recommendation: (a)**, with the TD explicitly ruling on whether it subsumes the named
`*_after_write` debt. It preserves the single-source-of-truth guarantee structurally,
keeps Build Validation scaffold-blind for free (it simply passes nothing), and matches
the BV-1 precedent this codebase already runs on.

### D2 — What does a scaffold cell look like to the mesher? *(TD + art ruling)*

If D1 lands on (a) or (c), scaffolding is **not in `VoxelWorldGrid`**, so the chunked
mesher never sees it and it renders as **nothing**. It is not a terrain block type and
has no entry in `BlockAppearanceConfig`. The player would watch a villager walk on air.

Options: a pooled-`MeshInstance3D` presentation tier (the **ghost-preview precedent** —
already pooled, already tinted, already bounded by `max_cells_per_command`); a dedicated
MultiMesh; or an appearance-config entry if D1 lands on (b). Owner is unclear between
Building System (which owns ghosts) and Presentation. **Recommendation: reuse the ghost
pool's mechanism with a distinct opaque tier** — no new mechanism design — but the
ownership and the visual read are a TD + art call.

### D3 — Does scaffolding belong to the owning BuildProject, or is it its own project?

**This is not cosmetic — one option is self-contradictory.** `BuildProject.recompute_state()`
sets `DONE` iff **every** tracked cell is `BUILT`. If scaffold cells are members of the
owning project, then:

- the project cannot reach `DONE` while scaffolding stands, **and**
- AC3 dismantles scaffolding *on project completion*.

That is circular: the trigger for removing the scaffolding is a state the scaffolding
prevents. Options:

- **(a) Its own entity/project, linked by owner id.** Sidesteps the circularity; needs a
  link field and possibly a third `BuildProject.Kind` (`SCAFFOLD`) or a separate
  registry. Also cleanly answers the save question in Out of Scope.
- **(b) Member cells of the owning project, excluded from the `recompute_state()` roll-up.**
  Cheaper, but adds a per-cell exclusion to a method whose doc comment currently states
  the rule with no exceptions — and every future reader of `recompute_state` must know it.

**Recommendation: (a).** The circularity in (b) is real and the exclusion is exactly the
kind of invisible special case that produces the next `villager-ai-024`.

### D4 — Player cancels the room mid-build while scaffolding stands, with a worker on it

Ruling 3 permits a cancel to collapse scaffolding **bottom-up with no worker**. It does
not say what happens to a villager **standing on it at that instant**.

**This project has no gravity.** Villagers are `Area3D`-only, with no physics colliders
(technical-preferences, ADR-0004). A Minecraft player falls; this villager does not — it
is simply left on a cell that instantly stops being standable, i.e. **a zero-edge graph
point**. That is precisely the stranding bug this story exists to fix, reintroduced
through the cancel path.

Options: **(i)** cancel-with-worker-present falls back to the top-down dismantle;
**(ii)** cancel collapses immediately and the existing `_relocate_if_marooned()` safety
net catches it — which argues **against** the retirement recommendation below;
**(iii)** cancel collapses and the worker is discretely relocated, which would be a
**fifth** sanctioned ADR-0009 `current_cell` mutation point.

**Recommendation: (i).** It needs no new mutation point, keeps ruling 3's fast path for
the common case (no worker present), and does not depend on a safety net this story may
retire. **User/TD ruling required** — this is where ruling 3 stops.

### D5 — Who DETECTS the unreachable cell? *(the trigger in AC1 has no implementation today)*

**Verified in source, not assumed.** The existing "unreachable" seam
(`ConstructionJobQueue.report_unreachable` → `BlueprintCell.is_unreachable` →
`job_reported_unreachable`) is **never reached for the cells scaffolding exists to
serve.** `VillagerAi._report_job_unreachable`'s own doc comment states it verbatim:

> only `_abandon_travel()`'s WORK branch ever calls this, and only for a job **this
> villager had just claimed** and then failed to path to (**never for F2's own silent
> pre-claim reachability skip, which never claims or reports anything**).

And `villager-ai-024` measured that top-course cells are **never claimed at all** —
`state == PLANNED`, `claimed_by_villager_id == -1`, `abandon_count == 0`. So the one
existing detector is structurally blind to exactly this case.

Options: **(a)** a new pre-claim detector in the job queue — when a released project has
`get_building_eligible_cells()` non-empty but `VillagerJobSelector` returns a `null`
choice across a full candidate sweep, the excluded cells are the scaffold targets;
**(b)** make F2's silent pre-claim skip report, reusing `report_unreachable`, at the
`unreachable_retry_ticks` (= 20) cadence that already exists; **(c)** a periodic sweep
owned by the Building System over every `PLANNED` cell in a `BUILDING` project.

**Recommendation: (b)** — it reuses a landed seam, a landed cadence, and a landed signal
rather than inventing a fourth reachability concept, and it makes `is_unreachable`'s
existing pulsing-orange ghost tint honest at the same time. Note (b) changes F2's
documented "silent" contract, so it is a **TD ruling**, not an implementation choice.

### D6 — What exactly does "6 cells sideways from its support" measure?

Ruling 4 is unambiguous about the intent (overhang, not height; config from day one;
raisable by progression) and silent on three mechanics:

1. **What counts as a support?** Original terrain ground only, or also a built wall, or
   also another scaffold column? Each yields a different reachable set.
2. **Which metric?** Chebyshev, Manhattan, or per-axis. Six diagonal cells is 6
   Chebyshev but ~8.5 Euclidean.
3. **Measured from the nearest support, or from the column the cell descends from?**

**Recommendation**: `scaffold_max_cantilever_cells: int = 6`, safe range **1–32** (headroom
for the progression stat ruling 4 requires), **Chebyshev** from the **nearest cell that is
itself supported** — matching `VillagerJobSelector.chebyshev_distance`, the metric this
codebase already uses for spatial pre-filtering. Support = solid-below **or** another
supported scaffold cell. Ruling needed from the user (it is a design-feel value, and it
is the number a future item will modify).

### D7 — What is `base_build_ticks[scaffold]`? *(creative/design value)*

AC2 says "markedly fewer ticks than a wall." Shipped `base_build_ticks[block]` = 4
(= 2.0 s at 1× and the 4.0 ticks/sec base rate). Structurally this needs a **third**
`BlueprintCell.Category` value (`SCAFFOLD`), a third branch in
`ConstructionTickLoop.required_ticks_for` and `required_demolition_ticks_for`, and two
new `ConstructionTickLoopConfig` fields (`base_build_ticks_scaffold`,
`base_demolition_ticks_scaffold`) with `_MIN`/`_MAX` constants and `validate()` clamps,
plus two rows in the building-system GDD's Tuning Knobs table.

**Provisional default — marked provisional**: `base_build_ticks_scaffold = 1`
(= 0.5 s at 1×, a quarter of a wall cell), `base_demolition_ticks_scaffold = 1`.
Range 1–20 to match its siblings. A designer/creative call, not a producer one.

### D8 — The erection route is undetermined, and AC9 requires it not to be

"Erect scaffolding exactly there" fixes the **destination**. It does not fix the
**path**: which supporting column, and in which order the cells are laid. Two different
valid routes give two different scaffold sets from the same world state, which breaks
AC9's determinism requirement (ADR-0009).

**Recommendation**: nearest supported column by **Chebyshev**, ties broken by the F2
lexicographic `(y, x, z)` convention via the already-public
`VillagerJobSelector.lexicographic_cell_less_than` — reusing the codebase's one
established tie-break rather than deriving a second. Erect bottom-up within a column.
Needs to be **stated in the story before implementation**, per `villager-ai-024`'s AC2
precedent ("the root cause is named in the story before the fix lands").

### D9 — May a scaffold cell overlap a cell the plan will later fill?

Because scaffolding is non-solid, **nothing prevents this today**: a scaffold cell and a
`PLANNED` blueprint cell can silently co-occupy one address, and the construction write
into that address would land with the scaffold still notionally there. Options:
**(a)** forbid overlap outright — a scaffold cell may only occupy an address with no
blueprint cell in any project; **(b)** allow, and dismantle that scaffold cell
immediately before the build job on the same address is claimed; **(c)** allow, and let
the completion write simply supersede it.

**Recommendation: (a).** It is the cheapest to reason about, it is checkable in one
place (`BuildProjectRegistry.project_at_cell(cell) != -1`), and it keeps AC5's "never
solid" guarantee free of an ordering hazard. (b) creates a claim-order race; (c) leaves
a scaffold record pointing at a solid cell.

### D10 — Top-down dismantle removes the cell the worker is standing on

AC3's "the worker rides it down" is under-specified in one place that matters. If the
worker stands **on** the top scaffold cell and dismantles **that** cell, it removes its
own support and lands on a non-point — the inverse of self-sealing, and the same
stranding class this story is fixing.

Options: **(i)** the worker descends one scaffold cell first, then dismantles the cell
**above** it — no new mutation point, the descent is an ordinary scaffold-to-scaffold
vertical step the amendment already makes legal; **(ii)** the worker dismantles its own
cell and is discretely moved down — a **fifth** ADR-0009 sanctioned mutation point.

**Recommendation: (i).** It uses the edge class this story adds, needs no ADR-0009
amendment at all, and is what makes "rides it down" literally true.

---

## OPEN RECOMMENDATION (not a decision) — retire `villager-ai-024`'s discrete mutation

Once scaffolding lands and is proven in the shipped game, **retire
`VillagerAi.climb_onto_self_sealed_cell()` and `VillagerAi._relocate_if_marooned()`** —
ADR-0009's sanctioned `current_cell` mutation points **(c)** and **(d)**.

**Rationale**: a teleport trick sitting beside real geometry is worse than either alone.
Two mechanisms that both answer "the builder is somewhere the graph cannot reach" will
diverge, and the discrete one will fire first and mask scaffolding's failures — exactly
the pattern that made the 27/30 stall read as a pacing problem for a full day.

**Countervailing evidence the ruling must weigh**: D4 option (ii) would *keep*
`_relocate_if_marooned()` deliberately, as the safety net for a bottom-up cancel with a
worker aboard. The two decisions are coupled and should be ruled on together.

**Requires**: TD/user ruling, an ADR-0009 amendment removing points (c) and (d) (or
demoting them to a named safety net), and a `control-manifest.md` update to the
"`current_cell` changes at EXACTLY four sanctioned points" bullet. **Not this story's
scope** — record only.

**We will know retirement was right if**: the payoff demo reaches a roofed enclosure
with `villager_unstuck` telemetry counters at **zero** for the build phase. If the
counters are non-zero after scaffolding lands, scaffolding is not covering a case it
should, and the retirement must wait.

---

## Dependencies

| Depends on | Why | Status |
|---|---|---|
| `villager-ai-024` | Names the rule, supplies the measured evidence and the correction this story acts on | Complete (2026-07-27) |
| `scene-007` (build-tool + project-lifecycle hosting) | The lever boots the **hosted** tool chain; an unhosted chain makes both levers untestable | Verify on disk before scheduling |
| `scene-008` (gates hosting) | Supplies the real-boot integration harness the lever reuses | Complete (2026-07-27) |
| `building-029` / `building-030` (tick loop, job queue) | Scaffold erection is a job on this loop | Complete |
| **ADR-0007 amendment ruling** | AC8 cannot be implemented before the TD rules | **BLOCKING — not yet requested** |
| **D1 ruling (where a scaffold cell lives)** | Every other AC depends on it | **BLOCKING** |

## QA Test Cases

**AC1 — erected only when needed**
- Given: the real booted game, a room drawn at `wall_height = 1` (every cell reachable
  from original ground).
- Then: zero scaffold cells are erected, and the room still completes.

**AC1/AC10 — erected when needed**
- Given: the real booted game, a room drawn at the shipped `wall_height = 3`.
- Then: scaffolding is erected without player input; every wall cell reaches `BUILT`;
  at `DONE` the villager stands on a cell connected to the settlement ground graph.

**AC2 — a real job, faster than a wall**
- Given: a scaffold cell and a block cell, both claimed.
- Then: the scaffold cell completes in `base_build_ticks_scaffold` ticks, the block cell
  in `base_build_ticks_block`, and the former is strictly smaller. Neither completes in
  zero ticks.

**AC3 — top-down dismantle, worker rides it down**
- Given: a completed project with standing scaffolding and a worker on it.
- Then: scaffold cells are removed highest-first; at every intermediate step the worker
  stands on a cell that is still a graph point with at least one edge; the run ends with
  zero scaffold cells and the worker on the ground graph.

**AC4 — the 6-limit is config, not a literal**
- Given: an unreachable target 7 cells sideways from any support, with
  `scaffold_max_cantilever_cells = 6`.
- Then: no scaffold reaches it. Raise the knob to 7 in the test's own config instance and
  the same target is reached. Grep: no literal `6` governs cantilever anywhere in `src/`.

**AC5/AC6 — never solid, never a room**
- Given: a half-built house fully surrounded by scaffolding, with a bed inside.
- Then: `CandidateCellRules.is_roofed` is `false` for the interior; the interior is not a
  Room; `is_bed_sheltered()` is `false`. Complete the real roof and it becomes `true`.

**AC7 — seal prevention untouched**
- Given: `seal_prevention_test.gd` and `unstuck_watchdog_test.gd`, unmodified.
- Then: both pass at their current counts, and `git diff` shows zero changes to
  `villager_seal_prevention_gate.gd`.

**AC8 — the amendment is bounded**
- Given: a scaffold cell with air below; two stacked ordinary cells; a scaffold cell
  stacked on an ordinary standable cell.
- Then: the first is standable; the second pair is still never both standable; the
  vertical step in the third case is refused in both directions.

**AC9 — determinism**
- Given: the same world, villager, and job order, run twice.
- Then: identical scaffold cell sets, identical erection order, identical dismantle order.
