# Review Log — Villager AI & Behavior

## Review — 2026-07-10 — Verdict: NEEDS REVISION
Scope signal: L
Specialists: game-designer, ai-programmer, systems-designer, qa-lead, godot-specialist, performance-analyst + creative-director (senior synthesis)
Blocking items: 8 | Recommended: ~10
Summary: First full review. A concentrated defect knot in F2/F4 + the
claim lifecycle: F2 same-command tie nondeterminism, F4's inverted
vacate objective (worked example proved it pulls the occupant TOWARD the
builder), F4's "within one tick" breaking at move_speed < 2.0, and
undefined job-claim stickiness (mid-travel oscillation). Plus: the VS
tier mismatch (~5 villagers at VS but spawning owned by Alpha-tier
Township), the "tireless machine" Pillar-2 risk (CD: NOT a
name-and-defer — it sits dead center of the MVP test hypothesis), an
unbounded F2 fallback (worst case 15,360 pathfinds/pass), and the
missing path-intersection re-path filter as a design contract.
Prior verdict resolved: First review

**Post-review revision (same session, 2026-07-10):** all 8 blockers
resolved with user decisions: F2 secondary tie-break (cell index) +
max_selection_candidates=15 cap; F4 direction flipped to
argmax-distance + normal-step semantics (no tick promise); claim
stickiness clause (Rule 4); Rule 14b starting roster
(starting_villager_count: MVP 1 / VS 5, growth stays Township);
Rules 7b/7c life texture (Breather beat after jobs_before_break=4 jobs,
breather_duration_ticks=90 + idle micro-behaviors, new Breather state);
Rule 10b path-intersection re-path filter as behavioral contract.
Recommended items applied: chained-arrival rule pinned (per-cell
step+align overhead, AC40 measures), EC3 winner determinism, EC3b
same-need no-op, EC12 softened, qa-lead package (AC5/20/37 rewritten,
AC41–47 added, AC39 re-tiered Advisory, harness notes), 4 new tuning
knobs, OQ8–10 added (bed assignment, engine-doc gaps, extreme-tuning
caveat), 30-villager synthetic stress added to the pre-VS spike scope.
**Re-review NOT yet run** — run
`/design-review design/gdd/villager-ai-behavior.md` in a FRESH session.
