# M02 Pre-Flight Technical Rulings — 2026-07-26

> **Status**: **PROVISIONAL — pending user ratification** (away-mode ruling).
> **Author**: technical-director. **Scope**: the technical conflicts raised in
> the "Landed-Code Deltas" sections of `production/epics/build-validation-navigability/EPIC.md`
> and `production/epics/needs-mood-system/EPIC.md`.
> **Binding intent**: these rulings are binding on Sprint 9 story authoring once
> ratified. Until then, treat them as the planning assumption.
>
> **This document does not rewrite any ADR.** Each ruling names its ADR home;
> the ADR edits are a separate, later pass. No production code was changed by
> this pass. Two documentation conflicts (items NM-5, NM-7) were checked against
> `neues-spiel/CONTRACTS.md` directly; only NM-7 required an edit (made).
>
> **Not ruled here** (routed to creative-director/designer): the
> `LoopPayoffSignalSurface` signal-shape question (BV-5) and the real-time
> pacing decision (needs-mood story 009).

## Verification basis

Every ruling below was checked against the landed source, not the epic
summaries. Files read in full or in relevant part:

- `neues-spiel/src/voxel_world/cell_contents.gd`, `voxel_world_grid.gd`
  (`bulk_write`, `_apply_write`, `_apply_write_to_resident_chunk`,
  `_queue_pending_write`, `_apply_pending_writes`, `_bg_regenerate_from_seed`,
  signal declarations)
- `neues-spiel/src/building_system/construction_tick_loop.gd`
  (`_on_tick`, `_complete_jobs`, `set_occupancy_predicate`,
  `set_seal_prevention_predicate`, `required_ticks_for`),
  `blueprint_cell.gd`, `commit_pipeline.gd` (furniture seams)
- `neues-spiel/src/villager_ai/villager_ai.gd`
  (`is_standable`, `is_step_legal`, `body_column`, `is_cell_in_body_column`,
  `_is_solid`/`_is_passable`, the `*_after_write` twins, `VILLAGER_CLEARANCE`,
  `MAX_STEP_HEIGHT`, `needs_provider`/`_has_urgent_need`),
  `villager_nav_graph.gd` (`predicate_source` parameter shape)
- `neues-spiel/src/resource_item_database/item_definition_resource.gd`,
  `item_definition.gd` (field inventory)
- `neues-spiel/CONTRACTS.md`, `docs/architecture/architecture.md`,
  `docs/architecture/control-manifest.md`, `docs/architecture/tr-registry.yaml`,
  ADR-0007, ADR-0016
- `design/gdd/build-validation-navigability.md` (Rules 1/5/8, signal table),
  `design/gdd/needs-mood-system.md` (Core Rule 4, F2 variable table, knob table)

---

## BV-1 — Furniture occupancy: where it lives, and what Build Validation injects

**Verified.** `CellContents` carries exactly `block_type_id` + `material_id` and
nothing else. `ConstructionTickLoop._on_tick()` collects
`changes[cell] = job.blueprint_cell.contents` for **every** completing job
regardless of `BlueprintCell.Category`, and `_complete_jobs()` issues them as a
single `voxel_world.bulk_write(changes)`. So a completed FURNITURE cell would
today write a solid block record into the data layer — it would read as
structure and would fail `is_standable`'s clearance loop. The conflict is real,
and its root is in the Building System's completion write, **not** in Build
Validation. Nothing regresses today: `CommitPipeline` never sets
`Category.FURNITURE` (its own doc comment names story building-028 as the future
real caller), so zero furniture cells exist in the landed build.

Also verified, and load-bearing: the GDD needs more than transparency. Rule 5,
Rule 8 and the signal table are written **per furniture item** —
`shelter_status_changed(item id, sheltered: bool)`, "need-functional furniture",
"one emission per transition per item". A cell-level "is furniture here" boolean
cannot satisfy that; Build Validation needs item identity.

### RULING

**Furniture is not voxel data. It never enters `VoxelWorldGrid`.**

1. **`CellContents` does not change.** No furniture flag, no third id, no
   sentinel block type. The voxel data layer stays "one cell = one block record"
   (Voxel World Core Rule 2), and it stays opaque about what those ids mean.
2. **Furniture occupancy lives in a Building-System-owned furniture registry**
   (`building-028`), keyed by placed-item identity, holding at minimum:
   item id, occupied cells (from `ItemDefinition.get_footprint()`), and the
   definition id. This is the same architectural move the codebase already made
   twice: unbuilt Planned blueprint cells are deliberately absent from the grid,
   and ghost/draft picking is an `extra_solid` **overlay predicate** on the DDA
   path rather than data written into the grid (Control Manifest, ADR-0014 §4).
3. **`ConstructionTickLoop` must exclude `Category.FURNITURE` from its
   `bulk_write` payload** and route a completing furniture cell to the furniture
   registry instead. `construction_completed` still names the cell. This is a
   **blocking AC on `building-028`**, with a regression test asserting that
   completing a FURNITURE-category job leaves `voxel_world.get_cell()` empty at
   that cell.
4. **Rule 1 (furniture evaluates as-if-empty) is then satisfied by
   construction**, with no branch anywhere in Build Validation and no change to
   `is_standable`. It is the identical mechanism `villager_ai.gd`'s
   `is_standable` doc comment already relies on for Planned blueprint cells.
5. **The seam Build Validation injects is the furniture registry, not a cell
   predicate.** Shape: a duck-typed, nil-safe `Object` dependency (the landed
   precedent is `VillagerAi.needs_provider` / `job_queue` / `population`),
   exposing an enumeration of placed furniture records. A `null` provider means
   "no furniture exists" — a correct, non-crashing default that is exactly true
   until `building-028` lands.
6. **"Need-functional" is Build Validation's own data-driven config knob**, not
   a new RID field. `ItemDefinitionResource` has no need-recovery flag and does
   not need one for MVP; it has `category: StringName`. Build Validation's
   config carries a typed `@export` list of need-functional categories/ids
   (ADR-0002), resolved through `ResourceItemDatabase.get_by_id(...)`. Do not
   hardcode `&"bed"`.

**Explicitly out of this ruling** (design, not architecture): whether furniture
should *block villager movement*. Under this ruling it does not, because it is
not in the walkability data. If the designer later wants beds to be
impassable, that is a walkability-overlay decision (the `extra_solid` pattern
again) — it is **never** to be solved by writing furniture into the voxel grid.
Flag to creative-director/game-designer; not an M02 blocker.

**ADR home**: ADR-0016 (Build-Project Entity Lifecycle) — it already owns
furniture-uniform demolition; the "furniture is registry-resident, never
grid-resident" clause belongs in its Decision section. Secondary note in
ADR-0007 that walkability is unaffected by furniture.

**Consequence for sequencing**: build-validation story 002's furniture-
transparency AC **loses its hard dependency on `building-028`** — it becomes a
proof-by-construction test (furniture cell reads empty). Story 002 can start as
soon as 001 does. Story **006 still needs `building-028`** for item enumeration,
but only for the registry query, and it can be developed against the mocked
provider and un-mocked later. The hard blocker moves off Cluster A's critical
path and onto `building-028`'s AC list.

---

## BV-2 — What Build Validation subscribes to for M02

**Verified, and the epic's framing understates the problem.** There is a
correctness hazard in triggering off `construction_completed`:
`ConstructionTickLoop._complete_jobs()` emits `construction_completed` from
`completed_jobs`, unconditionally, *after* calling `bulk_write`. But
`VoxelWorldGrid._apply_write()` (story vox-014, ADR-0015 "load-before-write")
**queues** a write whose chunk is not resident and returns `null` — the write
lands later, from `_apply_pending_writes()`, whenever the chunk pages in. So
`construction_completed(cells)` can name cells whose data is **not yet in the
grid**. A Build Validation pass triggered by it would analyse stale data and
emit a wrong verdict. `cells_changed_batch` fires only when a record actually
changed — including from `_apply_pending_writes()`, at the moment the deferred
write really lands.

Also verified: `cells_changed_batch` is **not** noise. Page-in and
seed-regeneration are explicitly silent (`_bg_regenerate_from_seed`: "never
marks anything dirty and never emits any signal — page-in must be
silent/transparent to consumers"). `bulk_write` emits exactly once per call and
never emits an empty batch.

### RULING

**Build Validation subscribes to `VoxelWorldGrid.cells_changed_batch` as its
single structural trigger. It does not subscribe to
`ConstructionTickLoop.construction_completed` at all.**

Rationale, in the decision-framework order:

- **Correctness**: it is the only signal that guarantees the data Build
  Validation is about to read is present (deferred-write hazard above).
- **Simplicity**: one trigger, one subscription, no dedupe logic. Subscribing to
  both would double-fire every construction tick.
- **Completeness**: it is a strict superset — construction completion,
  demolition (`building-009`, when it lands), undo restores, and any future dig
  order all reach the grid through `_apply_write`. Build Validation needs **no
  code change** when demolition lands. The GDD Rule 7 trigger pair
  ("completed OR removed") is satisfied by one subscription rather than two.
- **Batching**: preserved. One `bulk_write` per tick dispatch → one batch
  signal → at most one analysis pass per tick, which is coarser than the GDD's
  per-frame guarantee (this is the epic's own Known Conflict 3, unchanged).

**Second trigger, when it exists**: furniture placement/removal does not touch
the grid under BV-1, so Build Validation additionally subscribes to the
**furniture registry's own placed/removed signal** (`building-028`). Two
orthogonal sources, one per data layer, no overlap, no double-fire. Until
`building-028` lands, `cells_changed_batch` alone is complete because no
furniture exists.

**Ordering note for the implementer**: `cells_changed_batch` fires *during*
`bulk_write`, i.e. before `BlueprintCell` micro-states flip to `BUILT` and
before `construction_completed`. Build Validation reads voxel data only and
mutates nothing, so it is order-insensitive with respect to the other
subscribers (`VillagerNavGraph` already subscribes to the same signal). Do not
introduce any read of `BlueprintCell` state from Build Validation.

**ADR home**: ADR-0007 (event-driven trigger) with a correction note in
ADR-0016, whose current text names `construction_completed` as the analysis
trigger. The ADR-0016 clause is **superseded for Build Validation only** —
`construction_completed` remains valid for consumers that care about *jobs*
completing rather than *data* changing.

**Consequence for sequencing**: build-validation story 005's trigger wiring is
unblocked and gets *simpler* (one subscription, no demolition follow-up story).
`building-009` no longer needs to ship a new signal for Build Validation's
benefit. Story 005 must carry an AC proving a deferred/paged write still
triggers a pass.

---

## BV-4 — Walkability predicate DI shape

**Verified.** `is_standable`, `is_step_legal`, `body_column` and
`is_cell_in_body_column` are instance methods on `VillagerAi` (a `Node` carrying
`villager_id`, `config`, `voxel_world`, scheduler, nav graph, telemetry…). But
their *bodies* read only `voxel_world` and the two class constants
`VILLAGER_CLEARANCE = 3` / `MAX_STEP_HEIGHT = 1`. They read **no** per-villager
state — no `villager_id`, no `config`. Every instance therefore returns
identical answers, which means "which villager do I inject?" has no meaningful
answer. `VillagerNavGraph` already works around this by taking a
`predicate_source: VillagerAi` parameter on `build()`, `patch_cells()`,
`subscribe_to_voxel_world()` and `_resync_points()`.

Note also what ADR-0007 actually says: "Villager AI owns the walkability
predicates **as shared pure functions**" and "Villager AI **exposes two pure
query functions**". The landed instance-method shape is a drift from the ADR,
not a decision the ADR made.

### RULING

**Extract a pure static twin. Build Validation injects nothing and holds no
villager reference.**

1. New file `neues-spiel/src/villager_ai/villager_walkability_rules.gd`,
   `class_name VillagerWalkabilityRules extends RefCounted`, **static
   functions only**, never instantiated:
   - `static func is_standable(voxel_world: VoxelWorldGrid, cell: Vector3i) -> bool`
   - `static func is_step_legal(voxel_world: VoxelWorldGrid, from_cell: Vector3i, to_cell: Vector3i) -> bool`
   - `static func body_column(cell: Vector3i) -> Array[Vector3i]`
   - the `_is_solid` / `_is_passable` helpers move with them
2. **The constants move too.** `VILLAGER_CLEARANCE` and `MAX_STEP_HEIGHT` are
   declared on `VillagerWalkabilityRules` and nowhere else. `VillagerAi` keeps
   `const VILLAGER_CLEARANCE: int = VillagerWalkabilityRules.VILLAGER_CLEARANCE`
   (and likewise for `MAX_STEP_HEIGHT`) as a re-export alias so every existing
   call site — including `VillagerNavGraph`'s `VillagerAi.VILLAGER_CLEARANCE`
   read — compiles unchanged. There is still exactly **one literal** in the
   codebase, so the epic's "zero duplicated walkability constants" grep guard
   holds (the guard must test for duplicated *literals*, not for the identifier).
3. **`VillagerAi`'s public methods stay, as one-line delegations.** Signatures
   unchanged. Every landed test, `VillagerNavGraph`'s `predicate_source` calls,
   the seal-prevention gate and the rescue BFS keep working untouched. This is
   what makes the refactor safe: the existing suite is the regression net.
4. **Build Validation calls `VillagerWalkabilityRules.is_standable(voxel_world, cell)`
   statically.** It already injects `voxel_world`. It gains **no** new
   dependency, holds **no** reference to a gameplay entity, and cannot be
   null-ref'd by a despawned villager. Cross-module static utility calls are
   already sanctioned and in use — `VillagerAi` itself calls
   `VoxelWorldGrid.cell_to_world(...)` statically.
5. `VillagerNavGraph`'s `predicate_source` parameter may be migrated to the
   static class in the same story or left as-is; leaving it is acceptable
   because it delegates to the same single implementation. Do not do both.
6. **Known residual, deliberately not fixed here**: the `*_after_write` twins
   (`_is_standable_after_write`, `_is_step_legal_after_write`) re-implement the
   same control flow with override-aware reads. That duplication exists today
   and is the one sanctioned copy. The clean fix is an overlay predicate
   parameter on the extracted functions; it is a **post-M02** item — record it
   as technical debt, do not expand this story's scope.

Why not "inject a `VillagerAi`": the predicates are instance-independent, so the
injection would encode a lie about the dependency; `villager-ai-021` makes the
roster plural and the "the one villager" assumption evaporates; a despawned
villager becomes a freed reference inside a system whose Rule 9 forbids it from
ever failing loudly at the player; and the shape would be baked into all ten
build-validation stories' `setup()` and test fixtures, making it expensive to
reverse. Extraction is a mechanical, test-covered, one-story refactor and
restores ADR-0007's stated shape.

**ADR home**: ADR-0007, Decision §1 (Key Interfaces update: the shared
predicates' canonical call form). No new ADR.

**Consequence for sequencing**: a **new prerequisite story on the villager-ai
epic** — "extract `VillagerWalkabilityRules`, behavior-preserving" — must land
before `build-validation-001`. Estimate it as small (mechanical extraction plus
alias, existing suite must stay green with zero test edits; if any test needs
editing, the extraction was not behavior-preserving). Build-validation story 001
then has a *smaller* DI surface than planned: config + `voxel_world` +
(later) the furniture provider.

---

## NM-5 — `start_recovery` canonical signature

**Verified — and the epic's premise about `CONTRACTS.md` is wrong.**
`neues-spiel/CONTRACTS.md` contains **no** `start_recovery` reference anywhere
(it is a Foundation-spine contract sheet: DI, config, boot gate, data
immutability, severity, engine constraints — it has no needs-mood API block).
The documents that actually carry the signature:

- `docs/architecture/architecture.md:373` —
  `func start_recovery(villager_id: int, need: StringName, source_enum: RecoverySource) -> void`
- `design/gdd/needs-mood-system.md:159` and Core Rule 10 — `start_recovery(need, source_enum)`
- `docs/architecture/tr-registry.yaml` TR-needs-mood-system-042 and
  TR-villager-ai-behavior (line 2222) — both written `start_recovery(need, source_enum)`

### RULING

**Canonical: `start_recovery(villager_id: int, need: StringName, source_enum: RecoverySource) -> void`**
(and symmetrically `stop_recovery(villager_id, need, reason)`).

Needs & Mood is a per-villager system with no implicit "current villager"; the
landed sibling seam on the same module boundary is already villager-keyed
(`has_urgent_need(villager_id) -> bool`, see NM-6). Two seams into the same
system with inconsistent keying would be a defect. `architecture.md` is correct
as written and needs no edit.

**No `CONTRACTS.md` edit made** — there was nothing there to correct.

**Doc-hygiene items for the GDD/registry owner (not mine to edit):**
`design/gdd/needs-mood-system.md` Core Rule 10, TR-needs-mood-system-042, and
the villager-ai TR at `tr-registry.yaml:2222` all elide the `villager_id`
parameter and should be corrected to the three-arg form.

**ADR home**: none needed — `architecture.md`'s API Boundaries block is the
home and is already right.

**Consequence for sequencing**: needs-mood story 003 implements the three-arg
form as specified; no story changes. The GDD/registry fix is a doc task the
producer can batch, not a blocker.

---

## NM-6 — `has_urgent_need(villager_id) -> bool`

**Verified.** `neues-spiel/src/villager_ai/villager_ai.gd:474` declares
`var needs_provider: Object = null`, duck-typed against exactly one member,
`func has_urgent_need(villager_id: int) -> bool`; `_has_urgent_need()` (line
1303) is nil-safe and returns `false` when unwired. It is exercised by
`tests/unit/villager_ai/priority_decision_loop_test.gd`. Confirmed by grep that
the name appears in **no** document under `docs/` or `design/`.

### RULING

**Canonized.** `has_urgent_need(villager_id: int) -> bool` is a **required**
part of Needs & Mood's public query API, in addition to the GDD's documented
query surface — not a replacement for it. The landed consumer defines the seam;
un-mocking the Villager AI FSM is impossible without it, and criterion #5's
live-pair test runs through it.

Two supporting constraints:

- **Nil-safety stays on the consumer side.** Do not add a null-provider branch
  to Needs & Mood. `VillagerAi._has_urgent_need()`'s existing guard is the
  correct and already-tested location.
- **It must be a pure query.** No signal emission, no state mutation, no
  lazy-initialisation of a villager's need record as a side effect of being
  asked. It is polled from the FSM's decision point every tick (ADR-0008:
  "polls need state at its decision points").

**Where it must be documented** (three places, in priority order):

1. `docs/architecture/architecture.md` — Needs & Mood's "Exposes" row and the
   API Boundaries signature block, alongside `start_recovery`/`stop_recovery`.
   **This is the blocking one** — do it before needs-mood story 002 starts.
2. `design/gdd/needs-mood-system.md` — the query-API section, with a TR of its
   own (the registry currently has no TR covering it). GDD-owner task.
3. `neues-spiel/CONTRACTS.md` — **when the module lands**, not now. CONTRACTS.md
   documents as-built spine contracts; adding a signature block for an
   unimplemented module would break its own stated purpose.

**No `CONTRACTS.md` edit made** — premature by that file's own charter.

**ADR home**: none — this is an API-boundary documentation fix, not an
architectural decision.

**Consequence for sequencing**: needs-mood story 002 gains an AC
("`has_urgent_need(villager_id)` returns the queryable Urgent state, pure
query"). Story 010's live pair depends on it existing; nothing is blocked.

---

## NM-7 — `CONTRACTS.md` §1 TR-ID citation

**Verified.** `tr-registry.yaml` defines `TR-needs-mood-system-025` as the
**live-pair integration test** (AC34: real Needs + real Villager AI, no mocks at
the seam). `CONTRACTS.md` §1 (Dependency Injection) listed it flatly among that
section's TR-IDs, implying it is a DI-pattern requirement. It is not.

It is also not a pure mistake worth deleting: ADR-0001's own Context cites
TR-025 as one of the *drivers* for the DI decision ("Needs & Mood's live-pair
integration infra TR-025"), and the needs-mood epic states the trace correctly —
headless-mockable DI is what makes the *un*-mocked pair constructible. The
citation's substance is legitimate; its unqualified placement was misleading.

### RULING

**Annotate, do not delete.** Traceability to ADR-0001's stated driver is kept;
the false implication that 025 is a DI requirement is removed.

**`CONTRACTS.md` edit MADE** (§1, Governing ADR / TR-IDs line):

`TR-needs-mood-system-025` now reads
`TR-needs-mood-system-025 (live-pair integration test — DI is its enabler per ADR-0001 Context, not itself a DI requirement)`.

**ADR home**: none — CONTRACTS.md citation hygiene.

**Consequence for sequencing**: none. Stories follow the registry: 025 → story
010, as the epic already assumed.

---

## NM-3 — F2 variable table vs Core Rule 4

**Verified.** `design/gdd/needs-mood-system.md:266` (F2 variable table) reads
`source_multiplier | float | 0–1 | Bed = 1.0; ground = ground_penalty = 0.4` —
two rungs. Core Rule 4 (lines ~118–127) defines three:
bed sheltered ×1.0 > `unsheltered_bed_multiplier` (0.7) > `ground_penalty`
(0.4), with the five-value source enum collapsing the three `ground_*` values
onto one rate row. AC28 tests the middle rung explicitly. AC29 and
TR-needs-mood-system-020 make the ordering invariant
`ground_penalty < unsheltered_bed_multiplier < 1.0` a **BLOCKING** config
invariant. The Tuning Knobs table (line 402) states outright that
`unsheltered_bed_multiplier` is "Owned HERE (this table is the source of
truth)".

### RULING

**Confirmed. Core Rule 4 is authoritative; the F2 variable table is stale.**

Three independent artefacts (Rule 4, AC28, TR-020's blocking invariant, plus the
knob table's explicit ownership claim) agree on three rungs; only the F2
variable row disagrees. Implement three rungs via the **source→rate table
lookup** the epic's Definition of Done already requires (AC10: a brand-new
source id must work with no code change) — which means F2's `source_multiplier`
is a table lookup keyed by the source enum, and the variable row should never
have enumerated values in the first place.

**Do not implement the two-multiplier form under any circumstance** — it would
make the BLOCKING ladder invariant unenforceable (there would be no middle rung
to order) and would silently delete the "the missing roof visibly costs"
mechanic, which is the mechanical meaning of Cluster A.

**Designer fix required (I have not edited the GDD):**
`design/gdd/needs-mood-system.md` line 266's F2 variable table row should read
`source_multiplier | float | 0–1 | Looked up from the Core Rule 4 source→rate
table by source enum (bed_sheltered 1.0 / bed_unsheltered
unsheltered_bed_multiplier / ground_* ground_penalty)` — or simply point at Rule
4 rather than restating values. Route to the needs-mood GDD owner.

**ADR home**: none — GDD-internal consistency.

**Consequence for sequencing**: none. Needs-mood story 003 (source→rate table)
implements three rungs as already specified; story 001's BLOCKING invariant is
unaffected. This is a doc-hygiene ticket, not a story blocker.

---

## Summary of downstream actions this record creates

| # | Action | Owner | Blocks |
|---|--------|-------|--------|
| 1 | New villager-ai story: extract `VillagerWalkabilityRules` (behavior-preserving) | lead-programmer / villager-ai | `build-validation-001` |
| 2 | `building-028` gains blocking AC: FURNITURE-category completion never `bulk_write`s to the grid; furniture registry owns occupancy + item identity | building-system | `build-validation-006` |
| 3 | `building-028` exposes a placed/removed signal + item enumeration query (duck-typed, nil-safe provider) | building-system | `build-validation-006` |
| 4 | `build-validation-005`: single trigger = `cells_changed_batch`; AC must cover a deferred/paged write | build-validation | — |
| 5 | `architecture.md`: add `has_urgent_need(villager_id) -> bool` to Needs & Mood's exposed API | technical-director | `needs-mood-002` |
| 6 | GDD/registry doc fixes: `start_recovery` three-arg form (GDD Rule 10, TR-042, TR at registry L2222); F2 variable table → Rule 4 lookup | game-designer / GDD owner | nothing |
| 7 | ADR pass (separate): ADR-0016 furniture-residency clause; ADR-0007 predicate call form + trigger note | technical-director | nothing |
| 8 | Tech-debt register: `*_after_write` predicate twins → overlay-predicate parameter (post-M02) | technical-director | nothing |
| 9 | Design question to CD/game-designer: should furniture block villager movement? (not M02) | creative-director | nothing |
