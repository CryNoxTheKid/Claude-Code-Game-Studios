# Review Log: Build Validation & Navigability

Target: `design/gdd/build-validation-navigability.md`

## Review — 2026-07-10 — Verdict: NEEDS REVISION
Scope signal: M
Specialists: game-designer, systems-designer, ai-programmer, godot-specialist, performance-analyst, ux-designer, qa-lead + creative-director (synthesis)
Blocking items: 6 | Recommended: 10
Summary: Design spine sound (clean analysis-only boundary, genuine Pillar 1/3/4
delivery, carport gap correctly quarantined), but the core predicate (candidate
cell / reachable / outside) and the eventing model (signal contract, tier
exclusivity, statelessness vs. one-shot) were under-specified as design rulings
a programmer could not safely guess. Three of six blockers found independently
by two reviewers each. CD: focused pass over Rule 1, Rule 8, and the
signal/state model — not a redesign.
Prior verdict resolved: First review

### Blockers (all fixed in-session, grep-VERIFIED)
1. **B1 clearance gate** [ai-programmer + systems-designer, convergent]: Rule 1
   lacked `villager_clearance` — crawlspace bed read "sheltered (1.0)" while
   unreachable. → Rule 1 rewritten: candidate interior cell = standable per
   Villager AI Rule 8 + roofed (nearest-solid scan ≤ max_room_height);
   furniture-transparency clause (latent defect: furniture's own occupied cell
   was never an "air cell"); Edge Case 13; AC28. **User decision: standable
   interiors** (over geometric-interior + reachable-shelter).
2. **B2 outside/scan semantics** [systems-designer + ai-programmer]: → Rule 2
   outside = open-sky standable cell; trace runs movement graph until open sky;
   enclosed-chain case pinned; AC5 third clause.
3. **B3 reach graph** [ai-programmer]: → Rule 2 reach graph = villager movement
   graph verbatim (flanked diagonals); region membership stays orthogonal;
   AC29/30.
4. **B4 tier exclusivity** [game-designer + qa-lead, convergent]: → Rule 8
   Warning-supersedes-Info per item; AC17/18 assert Info-count = 0.
5. **B5 signal contract** [qa-lead]: → new Core Rule 10 (exactly 4 signals:
   shelter_status_changed / room_recognized / sealed_space_warning /
   unsheltered_furniture_info; state+events model).
6. **B6 statelessness vs one-shot** [qa-lead + systems-designer, convergent]:
   → new Core Rule 11 (transient never-serialized snapshot; continuity = no
   interior cell in a prior valid room; silent load seeding, AC31; Rule 4
   scoped).

### Recommended items applied
R1 batch≠command (EC10 + AC19 rewritten; reciprocal per-frame batching contract
in building-system.md Interactions) · R2 OQ5 reframed into two axes — region-
size cost is villager-count-INDEPENDENT and MVP-reachable (reciprocal spike
axis (d) in villager-ai-behavior.md OQ3) · R3 max_room_height range 3–16 → 8–16
· R4 navmesh Cross-Ref contradiction fixed + O(affected-region) backing-store +
chunk-boundary reqs in OQ5 · R5 AC36 divergence property test · R6 celebration
pacing knob `room_cue_cooldown_ticks` = 20 (**user decision: cooldown** over
size threshold / none) · R7 Warning scoped to need-functional furniture
(**user decision**) + AC35 · R8 invariant (a) escalated to BLOCKING config-load
failure (**user decision**), AC27 · R9 warning/info differentiated by icon
SHAPE + label, never intensity · R10 UI seam flag (on-demand status surface
unimplemented in both UI GDDs) + dismissal-debounce ownership + Game Feel grace
note.

### Nice-to-haves applied
AC33 (never-moves-villagers call-count), AC34 (EC2 standalone), EC9
knob-scoping, Open→Sealed direct edge in States table, cross-doc range trap
(ground_penalty 0.1–0.8 vs multiplier 0.5–0.9) documented in AC footnote.

### CD disagreements with specialists (recorded)
- ux-designer's "on-demand contract" BLOCKING downgraded to a seam flag (UI
  GDDs are unreviewed; surface is their design task) — but Building UI /
  Villager Info UI reviews MUST cover the room-status/active-warnings surface.
- godot-specialist's "event contract incompatible with NavigationServer3D"
  softened: event-scoped rebake is possible; the real defect was the
  settled-vs-open contradiction (fixed, R4).
- performance-analyst's "borderline blocking" flood-fill: substance accepted
  (OQ5 reframe), solution stays with the pre-VS spike.

### State after revision
ACs 26 → 36 (+ AC5/16/17/18/19/21 rewritten). Core Rules 9 → 11. Edge Cases
12 → 13. New tuning knob: room_cue_cooldown_ticks (internal-only, not
registered). Files touched: build-validation-navigability.md,
building-system.md (1 reciprocal bullet), villager-ai-behavior.md (1 reciprocal
OQ3 axis). **Re-review pending in a fresh session.**
