# Epic: Villager AI & Behavior

> **Layer**: Core
> **GDD**: design/gdd/villager-ai-behavior.md
> **Architecture Module**: Villager AI & Behavior (per-villager state machine; walkability predicates — canonical ground truth; job-claim consumption; F1–F4 movement/selection formulas)
> **Manifest Version**: 2026-07-23
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories villager-ai-behavior`

## Overview

Villager AI & Behavior owns everything a villager does: perceiving the world,
choosing an activity (build/sleep/eat/wander) via a plain explicit FSM, pathing to
it with `AStar3D`, and performing it. It owns the **canonical** walkability
predicates (`is_standable`/`is_step_legal`) that Build Validation (M02) must reuse
rather than redefine, the discrete `current_cell` body-column occupancy model
(the sole authoritative value, changing only at tick boundaries), deterministic
same-tick claim/movement ordering, the tick-driven Deciding-pass staggering with
the `max_deciding_per_tick` budget, and the anti-stuck watchdog + seal-prevention
that guarantee no villager is ever teleported, clipped, or trapped by ordinary
means. It is the labor half of the game loop, consuming Building System's job queue.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0007: AI Pathfinding, Navigation & Room Analysis | Custom `AStar3D` (graph built once at boot, incrementally patched on `cell_changed`, deterministic bit-packed point IDs); shared walkability predicates as the single source of truth; **zero `NavigationServer3D`/`NavigationAgent3D`/`NavigationRegion3D`** (grep-verifiable) | HIGH |
| ADR-0008: Villager AI Execution & Threading | Plain explicit FSM (`match`, discrete priority); FIFO Deciding queue + `max_deciding_per_tick` budget (spike-tuned initial value: 1); **zero `Thread`/`WorkerThreadPool` in Villager AI** for MVP/VS; unstuck watchdog telemetry | MEDIUM |
| ADR-0009: Deterministic Movement & Occupancy Ordering | Discrete `current_cell` body-column is authoritative; `current_cell` changes at exactly two tick-boundary points (travel arrival + watchdog rescue); visual lerp render-only; synchronous-signal race closure; seal-prevention read side | HIGH |
| ADR-0012 | `serialize()/deserialize()`; `deserialize()` owns stale claim/bed-id revalidation — **VS-tier orchestrator** | MEDIUM |
| ADR-0002 / ADR-0001 | AI tunables (budgets, watchdog thresholds) from typed `.tres` config; injected-tier module | MEDIUM |

Engine-risk basis (4.7 policy): **HIGH** — Navigation/AI-Pathfinding is a flagged
HIGH-risk domain with a critical post-cutoff fact: **`AStarGrid3D` does NOT exist
in Godot 4.7** (only `AStarGrid2D`), so manual `AStar3D` graph management is the
only built-in option, and `AStar3D` IDs are never auto-recycled on `remove_point()`.
`NavigationServer3D` is forbidden (navmesh cannot express the exact cell rules).
Default signal connections are synchronous (load-bearing for the ADR-0009 race
closure). Cross-reference `docs/engine-reference/godot/` before any nav API.

## GDD Requirements

77 TRs registered (`TR-villager-ai-behavior-*`). Coverage:

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-villager-ai-behavior-009 / -010 / -011 / -035 / -036 | Pathfinding, shared walkability predicates | ADR-0007 ✅ |
| TR-villager-ai-behavior-013 / -041 / -047 | Deciding staggering, tick-burst budget, threading model | ADR-0008 ✅ |
| TR-villager-ai-behavior-046 | Deterministic mid-path solidification ordering | ADR-0009 ✅ |
| TR-villager-ai-behavior-016 | Headless-mockable via DI | ADR-0001 ✅ |
| TR-villager-ai-behavior-027 | Serialize position/activity/claim/bed/needs; stale-id revalidation | ADR-0012 ✅ (VS) |

**Coverage summary**: All ADR-worthy TRs trace to Accepted ADRs; remaining TRs
are GDD-specified (F1–F4 formulas, FSM priority, bed ownership). No untraced
requirements.

**At-risk / deferred**: The one measured watch-item is Deciding-pass cost (avg
11 ms / p95 35 ms GDScript stand-in per the spike); mitigations before threading
are named (cheaper pre-filter, smaller BFS bound, pass slicing) — an accepted-risk
boundary, not an open decision. Threading remains the named escape hatch, not
built. Save orchestrator is VS-tier.

## Milestone 01 Notes — HOME OF ONE TECH DEBT (shared)

- **TECH DEBT 2 — Per-tick re-tuning pass (`max_deciding_per_tick` portion) lands
  here.** Milestone-01 Must-Ship "Per-tick re-tuning pass done." This epic owns
  the **`max_deciding_per_tick`** knob (ADR-0008, spike-tuned initial value 1),
  re-tuned against production load. The **tick-budget / base-tick-rate** half is
  owned by the `time-tick-system` epic — one coordinated config change spanning
  both, recorded once with shared rationale via the Foundation Spine `.tres`
  discipline.
- Delivers Must-Ship "Villager AI playable": FSM + AStar3D pathfinding, body-column
  occupancy, deterministic movement ordering (ADR-0009), threading model (ADR-0008),
  anti-stuck watchdog + seal prevention (watchdog telemetry exposed in F3).
- No CD-protected item lands here.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/villager-ai-behavior.md` are verified
- Grep proves zero `NavigationServer3D`/`NavigationAgent3D` and zero `Thread`/`WorkerThreadPool` in Villager AI
- Deterministic ordering, anti-stuck watchdog, and seal-prevention have passing logic unit tests
- The `max_deciding_per_tick` re-tune is recorded as a config change with rationale

## Next Step

Run `/create-stories villager-ai-behavior` to break this epic into implementable stories.
