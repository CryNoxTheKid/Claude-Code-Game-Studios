# Review Log — Scene/World Management

## Review — 2026-07-10 — Verdict: NEEDS REVISION (re-review #1)
Scope signal: S
Specialists: game-designer, systems-designer, qa-lead, godot-specialist + creative-director (senior synthesis)
Blocking items: 2 (+4 execution defects from the prior revision) | Recommended: ~6
Summary: All 3 prior blockers verified HOLDING (warp persistence reciprocally
consistent with Time & Tick, no orphaned reset references). But two NEW
defects: (1) the undo-abort trap — Building's undo-clear fired on
transition-BEGIN while the load-failure path aborts in-place, wiping undo
with no scene change (same irreversible-trap class as the fixed warp bug,
reintroduced by the dependency added in the same pass); (2) Core Rule 2
"Valley is the single persistent root" contradicted the two-live-scenes
requirement (Godot has one current_scene — hosting container unnamed).
Plus 4 sloppy-execution defects in the prior revision itself (AC10
malformed, AC7 re-tier claimed-but-not-applied, scope tags not inline,
boot-order Edge Case without AC) — CD: "the summary asserted changes the
artifact didn't contain; verify against the file." CD adjudicated
game-designer's warp-in-dungeon/unattended-Valley blockers OUT of this
GDD's scope (→ Dungeon System GDD OQs), but the hand-waving dismissal in
the Edge Case row had to go.
Prior verdict resolved: Partially (3/3 old blockers hold; new defects found)

**Post-review revision (same session, 2026-07-10):** all 12 findings fixed
with 2 user decisions: side-effect discipline (new Core Rule 7 — begin =
reversible only, irreversible effects bind to COMPLETE; Building Rule 17 +
AC32b updated reciprocally) and return-cue split (victory amber vs.
death/retreat muted "limping home"). World Root container named in Core
Rule 2; AC10 rewritten (4 checkpoints incl. mid-visit); AC7 re-tier
actually applied; inline scope tags on all 18 ACs; AC17 boot-order (MVP,
incl. boot-halt failure behavior); AC18 abort-leaves-no-trace; formal
failure-exit in the States table; AC15 queue_free tolerance; OQ2 reframed
(SceneTree-membership + viewport/audio partitioning); 2 new OQs (warp
meaning in dungeons, unattended-Valley safety). Every fix verified against
the file this time (grep-confirmed). **Re-review #2 NOT yet run** — run
`/design-review design/gdd/scene-world-management.md` in a FRESH session.

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
