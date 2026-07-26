# Epics Index

Last Updated: 2026-07-26
Engine: Godot 4.7-stable
Manifest Version referenced: 2026-07-23
Milestone: 01 — Foundation + Core (Playable Integrated Build) · 02 — MVP Completion (Feature layer opening)

Scope of this pass: Foundation + Core layers (per architecture.md layer map), plus
the **presentation-experience** micro-epic which houses the two M01 CD-protected
experience items (exception to the layer order — Art-Bible-driven, not a full
Presentation-layer pass).

**Feature layer opened 2026-07-26** (`/create-epics layer: feature`, first half):
**build-validation-navigability** is created and storied as a gate on Sprint 09
planning (M02 risk R2). Still outstanding for M02: the **needs-mood-system**
Feature epic and the Presentation-layer UI epics (Building UI, Villager Info UI).

| Epic | Layer | System / Scope | GDD | Stories | Status |
|------|-------|----------------|-----|---------|--------|
| foundation-spine | Foundation | Boot/DI/config spine + test harness + CONTRACTS.md (cross-cutting; ADR-0001/0002/0005/0006) | N/A — ADR-driven | 5 stories | Ready |
| scene-world-management | Foundation | World Root + transition contract + boot-gate host + **GameWorld assembly / E2E LOOP** (story-004, added 2026-07-24) | design/gdd/scene-world-management.md | 4 stories | Ready |
| voxel-world | Foundation | Grid data + chunked mesher + paged residency | design/gdd/voxel-world.md | 17 stories | Ready |
| camera-input | Foundation | Orbit camera + InputMap + world-ray API | design/gdd/camera-input.md | 9 stories | Ready |
| time-tick-system | Foundation | `game_delta`/pause/warp + `tick` signal | design/gdd/time-tick-system.md | 7 stories | Ready |
| resource-item-database | Foundation | Item/material definitions + boot gate + immutable queries | design/gdd/resource-item-database.md | 9 stories | Ready |
| building-system | Core | Project lifecycle, tools, change orders, undo, demolition | design/gdd/building-system.md | 33 stories (Block A foundation 019–033 + Block B slice 001–018) | Ready |
| villager-ai-behavior | Core | FSM, AStar3D, occupancy, threading, anti-stuck | design/gdd/villager-ai-behavior.md | 25 stories | Ready |
| build-validation-navigability | Feature | Room/enclosure detection, own BFS reachability trace, shelter classification, four-signal contract + AC36 property corpus (**M02 Cluster A head — PROTECTED**; created 2026-07-26) | design/gdd/build-validation-navigability.md | 10 stories | Ready |
| presentation-experience | Presentation | Ambient-life wave 1 + loop-payoff communication scaffolding (the two M01 CD-protected items) | N/A — Art Bible §6.5/§5.6 (GDD-less, foundation-spine precedent) | 2 stories | Ready |

## Milestone 01 Tech-Debt & CD-Item Placement

| M01 Item | Type | Landed In | Note |
|----------|------|-----------|------|
| Mesher CW-winding rewrite + culling re-enable | Tech debt | voxel-world | Voxel World's mesher (ADR-0014 slice propagation) |
| ADR-0015 C1/C4 residency tuning | Tech debt | voxel-world | Residency tier is inside Voxel World (no separate storage module) |
| Per-tick re-tune — tick-budget/base-rate | Tech debt | time-tick-system | Coordinated with the Villager AI half |
| Per-tick re-tune — `max_deciding_per_tick` | Tech debt | villager-ai-behavior | ADR-0008 knob; recorded once with the Time & Tick half |
| Ambient-life wave 1 (CD-protected) | CD item | **presentation-experience / story-001** | Presentation micro-epic (created 2026-07-24) — Art Bible §6.5 |
| Loop-payoff communication scaffolding (CD-protected) | CD item | **presentation-experience / story-002** | Presentation micro-epic (created 2026-07-24) — Art Bible §5.6 + milestone split |

**CD-protected items — mapping gap RESOLVED (2026-07-24):** Ambient-life wave 1
(Art Bible §6.5) and loop-payoff communication scaffolding (Art Bible §5.3/§5.6/§6.5
+ milestone exit criterion #10) now have an explicit home: the **presentation-experience**
micro-epic (2 stories). Both were previously "Not placed", a silent-deferral risk
against CD protection flagged by the milestone review (Action Item #3). The micro-epic
follows the foundation-spine GDD-less precedent (Art Bible is the source of truth, no
GDD module, no decision-owning ADR). The stories are dependency-gated (mesher vox-007 +
villager FSM/movement) and scheduled for the Presentation pass (Sprint 5+), not Sprint 4.
Owner remains godot-specialist per the milestone; **cutting either still requires CD sign-off.**

## Milestone 02 Epic Placement

| M02 Criterion | Type | Lands In | Note |
|---------------|------|----------|------|
| #1 Build Validation implemented (AC1–35, 37, 38) | Cluster A (PROTECTED) | **build-validation-navigability** | AC26 deferred to VS with Save/Load |
| #2 Reachability property corpus green ≤ 60 s in CI | Cluster A (PROTECTED) | **build-validation-navigability / story-010** | M02 risk R3 — technical-director-owned |
| #5 Payoff loop closes (analysis half — shelter flag) | Cluster A (PROTECTED) | **build-validation-navigability / story-006** | `shelter_status_changed` is what the needs-mood epic consumes |
| #7 Loop-payoff scaffolding fires real signals | Cluster A (PROTECTED) | **build-validation-navigability / story-009** | Wires into `presentation-experience / story-002`'s surface |
| #3 / #4 Needs & Mood + real-time-rate pass | Cluster A (PROTECTED) | needs-mood-system | **Epic not yet created** |
| #10 Building UI / Villager Info UI | Cluster D | building-ui, villager-info-ui | **Epics not yet created** |

**Cross-epic dependencies introduced 2026-07-26**: build-validation stories 002
and 006 hard-depend on `building-028` (furniture placement) — the voxel layer has
no furniture representation today. Story 009 depends on
`presentation-experience / story-002`'s landed surface. See that epic's
**Known Conflicts With Landed Code** section for the five items that need a
decision before the stories they block.

## Next Step

Run `/create-stories [epic-slug]` per epic (Foundation first, then Core).
Foundation + Core epics are the Pre-Production → Production gate input —
run `/gate-check production` once stories exist.

For Milestone 02: create the remaining three epics (`needs-mood-system`,
`building-ui`, `villager-info-ui`) before S09 planning closes — R2 treats this as
a gate on S09, not as S09 content.
