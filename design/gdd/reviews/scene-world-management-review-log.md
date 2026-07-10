# Review Log — Scene/World Management

## Review — 2026-07-10 — Verdict: NEEDS REVISION
Scope signal: S
Specialists: game-designer, systems-designer, qa-lead + creative-director (senior synthesis; Foundation-batch review with voxel-world, camera-input, time-tick-system)
Blocking items: 3 | Recommended: ~8
Summary: First full review. Three real rule defects: (1) the warp-reset-to-1x
on transition created an irreversible warp trap — Building UI (sole warp
owner) doesn't exist in dungeon scenes, so "manually re-engage" was
impossible and the background Valley silently dropped to 1x against the
player's setting; (2) the reset-call vs. transition-signal ordering was an
unspecified race; (3) the Booting state lacked the boot-order requirement
(Resource & Item DB Ready before dependents). Plus advisories: AC6's "exact
state" contradicted Core Rule 4's continuous simulation, missing
transition-while-paused edge case, missing Building undo-clear dependency
row, MVP/VS scope tags, 2 missing ACs, AC12 formalization.
Prior verdict resolved: First review

**Post-review revision (same session, 2026-07-10):** all 3 blockers resolved
with user decision "Warp bei Rückkehr wiederherstellen": warp now PERSISTS
unchanged across transitions (global state, reset call retired — Time & Tick
GDD reciprocally updated, its AC8 replaced); the ordering race dissolved with
the call's removal (all effects now signal-only); boot-order requirement
recorded as an Edge Case row pointing at the boot-order ADR. Advisories all
applied: AC6 reworded (position/camera restored, simulation elapsed), AC3
split from timing (AC12a owns tolerance), transition-while-paused edge case,
Building undo-clear dependency row, scope tags (AC1–2 MVP, AC3+ VS+), AC7
re-tiered Logic, AC14–16 added, 3 OQs added (teardown signal ordering,
background-scene process mode, boot-order mechanism).
**Re-review NOT yet run** — run
`/design-review design/gdd/scene-world-management.md` in a fresh session.
