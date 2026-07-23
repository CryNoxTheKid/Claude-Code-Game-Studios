# Epics Index

Last Updated: 2026-07-23
Engine: Godot 4.7-stable
Manifest Version referenced: 2026-07-23
Milestone: 01 — Foundation + Core (Playable Integrated Build)

Scope of this pass: Foundation + Core layers only (per architecture.md layer map).
Feature-layer systems (Build Validation & Navigability, Needs & Mood) and
Presentation-layer systems (Building UI, Villager Info UI) are **Milestone 02** —
their epics are created when those layers are approached (`/create-epics layer: feature`).

| Epic | Layer | System / Scope | GDD | Stories | Status |
|------|-------|----------------|-----|---------|--------|
| foundation-spine | Foundation | Boot/DI/config spine + test harness + CONTRACTS.md (cross-cutting; ADR-0001/0002/0005/0006) | N/A — ADR-driven | 5 stories | Ready |
| scene-world-management | Foundation | World Root + transition contract + boot-gate host | design/gdd/scene-world-management.md | 3 stories | Ready |
| voxel-world | Foundation | Grid data + chunked mesher + paged residency | design/gdd/voxel-world.md | 17 stories | Ready |
| camera-input | Foundation | Orbit camera + InputMap + world-ray API | design/gdd/camera-input.md | 9 stories | Ready |
| time-tick-system | Foundation | `game_delta`/pause/warp + `tick` signal | design/gdd/time-tick-system.md | 7 stories | Ready |
| resource-item-database | Foundation | Item/material definitions + boot gate + immutable queries | design/gdd/resource-item-database.md | 9 stories | Ready |
| building-system | Core | Project lifecycle, tools, change orders, undo, demolition | design/gdd/building-system.md | 33 stories (Block A foundation 019–033 + Block B slice 001–018) | Ready |
| villager-ai-behavior | Core | FSM, AStar3D, occupancy, threading, anti-stuck | design/gdd/villager-ai-behavior.md | 25 stories | Ready |

## Milestone 01 Tech-Debt & CD-Item Placement

| M01 Item | Type | Landed In | Note |
|----------|------|-----------|------|
| Mesher CW-winding rewrite + culling re-enable | Tech debt | voxel-world | Voxel World's mesher (ADR-0014 slice propagation) |
| ADR-0015 C1/C4 residency tuning | Tech debt | voxel-world | Residency tier is inside Voxel World (no separate storage module) |
| Per-tick re-tune — tick-budget/base-rate | Tech debt | time-tick-system | Coordinated with the Villager AI half |
| Per-tick re-tune — `max_deciding_per_tick` | Tech debt | villager-ai-behavior | ADR-0008 knob; recorded once with the Time & Tick half |
| Ambient-life wave 1 (CD-protected) | CD item | **Not placed** | Presentation/environment; no Foundation/Core module — see note below |
| Loop-payoff communication scaffolding (CD-protected) | CD item | **Not placed** | Presentation/experience; no Foundation/Core module — see note below |

**CD-protected items — mapping gap (surfaced honestly):** Ambient-life wave 1
(Art Bible §5/§6) and loop-payoff communication scaffolding (Art Bible §5.3/§5.6/§6.5)
are Milestone-01 Should-Ship, CD-protected experience work, but neither maps to
any Foundation or Core architectural module in architecture.md — they are
Presentation/environment concerns with no GDD module and no governing ADR. They
were therefore NOT forced into a Foundation/Core epic. Recommended home: a
dedicated Presentation-layer epic created during the Presentation pass, or tracked
as standalone M01 experience stories. Owner remains godot-specialist per the
milestone; cutting either still requires CD sign-off.

## Next Step

Run `/create-stories [epic-slug]` per epic (Foundation first, then Core).
Foundation + Core epics are the Pre-Production → Production gate input —
run `/gate-check production` once stories exist.
