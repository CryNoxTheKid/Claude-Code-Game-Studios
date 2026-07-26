# Story 005: Analysis pass lifecycle, batched trigger, snapshot & never-blocks guards

> **Epic**: Build Validation & Navigability
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: ~1.5 agent-days
> **Manifest Version**: 2026-07-23
> **Last Updated**: —

## Context

**GDD**: `design/gdd/build-validation-navigability.md`
**Requirement**: `TR-build-validation-navigability-006`, `TR-build-validation-navigability-052`, `TR-build-validation-navigability-048`, `TR-build-validation-navigability-044`, `TR-build-validation-navigability-045`, `TR-build-validation-navigability-038`, `TR-build-validation-navigability-028`, `TR-build-validation-navigability-053`, `TR-build-validation-navigability-054`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0016 (Build-Project Entity Lifecycle) for the trigger seam; ADR-0007 (room analysis, incremental snapshot patching); ADR-0012 (Save/Load) for the not-serialized/full-re-derive rule
**ADR Decision Summary**: `ConstructionTickLoop.construction_completed(cells: Array[Vector3i])` fires exactly once per tick dispatch that completes at least one job, carrying every cell completed in that dispatch — explicitly built (story building-033, `TR-building-system-075`) as *"the seam Build Validation (M02) will consume to avoid one region re-analysis per completing cell."* Build Validation is **not deserialized** on load: all statuses are fully re-derived (ADR-0012).

**Engine**: Godot 4.7-stable | **Risk**: MEDIUM
**Engine Notes**: Godot signal connections are **synchronous by default** — load-bearing for Rule 10's "all emissions of one analysis pass are delivered synchronously within one frame; consumers may treat same-frame delivery as one pass." Do not add `CONNECT_DEFERRED` on the emission path.

**Control Manifest Rules (this layer)**:
- Required: injected-tier module, all wiring in `setup()`; analysis is event-driven off the batched construction signal.
- Required (ADR-0012): on load, Build Validation is NOT deserialized — full re-derive.
- Forbidden: per-frame analysis; a full snapshot rebuild per event (that silently reintroduces O(world) cost and violates Rule 7's event-scoping); blocking/reverting a placement; any call into a villager movement or behavior API.
- Guardrail: at most one analysis pass per batched trigger.

**Known Conflicts to resolve before implementation** (see EPIC.md):
- **#2 — no "construction removed" signal exists.** Rule 7 names a completed/removed trigger pair; only `construction_completed` is landed (demolition is `building-009`). Interim removal trigger is `VoxelWorldGrid.cells_changed_batch`. Technical-director decides which surface this story binds.
- **#3 — batching is per-TICK, not per-frame.** AC19 is worded in frames; the landed emission is one per `_on_tick()` dispatch (base rate 4.0/s), which is coarser than per-frame and therefore satisfies the guarantee a fortiori. Write the AC19 test against tick dispatches.

---

## Acceptance Criteria

*From GDD `design/gdd/build-validation-navigability.md`, scoped to this story:*

- [ ] Analysis is **event-driven, never per-frame**: re-evaluation of the affected region runs when the Building System signals a construction completed or a built cell removed (its batched signals bound the event rate). Between events, all statuses are stable. [TR-006]
- [ ] **AC19**: **GIVEN** a batched construction signal covering N cells completed in one frame — spanning multiple commands and villagers, **WHEN** received, **THEN** exactly one re-analysis pass runs over the affected region(s) (assert analysis call-count = 1 per frame-batch, never per cell or per command). [TR-052]
- [ ] **AC20**: **GIVEN** no structure-change signals, **WHEN** N frames pass, **THEN** the instrumented analysis call-count stays 0 — event-driven, never per-frame. [TR-006]
- [ ] The system keeps a **transient, never-serialized snapshot** of the previous analysis result (per-cell region classification + per-item shelter flags), used ONLY to edge-detect transitions — it is memory for eventing, never a compute cache. [TR-048]
- [ ] **Snapshot updates are incremental**: after a pass, only the entries touched by that pass's affected region (cells + items) are patched; untouched entries persist unchanged. A full snapshot rebuild happens ONLY on the load pass. [TR-006]
- [ ] All current statuses are **queryable at any time** (state + events model) — the same consumption contract Needs & Mood established. [TR-044]
- [ ] **All emissions of one analysis pass are delivered synchronously within one frame**; consumers may treat same-frame delivery as one pass — the reconciliation unit. [TR-045]
- [ ] **AC33**: **GIVEN** a full analysis pass over any configuration with mocked villager interfaces, **WHEN** the pass completes, **THEN** zero calls into villager movement/behavior APIs are observed (Rule 9's second half — never moves villagers; call-count mock, companion to AC25's never-blocks half). [TR-038]
- [ ] Nothing is serialized — a full analysis pass runs once on load and all statuses are re-derived from the world (Rule 4 / ADR-0012). [TR-028]
- [ ] MVP analyzes **built structures only** — the Building System's combined planned-occupancy view is available but unused (Rule 7).

---

## Implementation Notes

*Derived from ADR-0016/0007/0012 Implementation Guidelines:*

- Bind `ConstructionTickLoop.construction_completed(cells)` in `setup()`. It never emits a zero-cell batch, so no empty-pass guard is needed on that path.
- One pass = seed the affected region from the batch's cells → form regions (story 003) → verdict each (story 004) → diff against the snapshot → emit → patch the snapshot. Emissions happen **inside** the pass, synchronously.
- The snapshot is two maps: `Dictionary[Vector3i, RegionClass]` and `Dictionary[item_id, bool]`. Patch only the keys the pass touched. **A full rebuild per event is the specific defect Rule 11 calls out** — it would reintroduce O(world) cost and violate Rule 7.
- The load pass is the one full-world pass: rebuild the whole snapshot, make statuses queryable, and fire **no transition events**. The transition-silencing mechanism belongs here; the load-pass emission assertions (AC31) are story 008's.
- The queryable surface is a plain getter API (region status by cell, shelter status by item id). UIs own the presentation; this module owns state + events only.
- AC33 is a negative assertion over a mocked `VillagerAi`: the module may call `is_standable`/`is_step_legal` (pure queries) and must call **nothing** that moves or drives a villager. Scope the mock's call-count assertion to movement/behavior methods, not to the predicates.
- Rule 7's per-frame batching claim is inherited from the Building System — this module adds no debounce of its own (Formulas: "warning debounce — inherited, a dependency, not a timing formula").

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 006/007/008: the four signals' payloads, edge-detection semantics, and pacing.
- Story 010: the property corpus.
- **AC26 (save/load re-derive equivalence) is deferred to Vertical Slice** per `milestone-02-mvp-completion.md` Out of Scope — do not implement a save round-trip test here.

---

## QA Test Cases

- **AC19**: Given one batched signal carrying N cells from multiple commands/villagers, When received, Then the instrumented pass count is exactly 1 (never N).
- **AC20**: Given no structure-change signals across N frames, When measured, Then pass count = 0.
- **AC33**: Given a full pass with a mocked `VillagerAi`, When it completes, Then movement/behavior API call-count = 0 (predicate calls excluded and asserted separately as > 0, proving the predicates ARE used).
- **Incremental snapshot**: Given a pass touching a small affected region inside a large previously-analyzed world, When it completes, Then snapshot entries outside the affected region are unchanged (identity-compared) and the touched entries are patched.
- **Load pass**: Given a world load, When the initial full pass runs, Then the whole snapshot is rebuilt and all statuses are queryable.
- **Synchronous delivery**: Given a pass emitting multiple signals, When observed, Then all arrive within the same frame as the trigger, in one synchronous burst.
- Edge cases: a batch whose cells span two disjoint regions → one pass, two regions evaluated; a batch that changes nothing structurally relevant → pass runs, no transitions detected, no emissions.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `neues-spiel/tests/integration/build_validation/analysis_pass_lifecycle_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: 001 (DI + config), 004 (verdict — a pass needs something to classify). **External**: removal-trigger surface decision (Epic Known Conflict 2).
- Unlocks: 006, 007, 008

