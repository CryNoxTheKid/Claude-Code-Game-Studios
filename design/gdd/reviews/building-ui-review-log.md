# Review Log: Building UI

Target: `design/gdd/building-ui.md`

## Review — 2026-07-10 — Verdict: MAJOR REVISION NEEDED
Scope signal: L
Specialists: game-designer, ux-designer, ui-programmer, systems-designer, godot-specialist, qa-lead + creative-director (synthesis)
Blocking items: 4 (merged clusters) | Recommended: 6
Summary: The toolbar/palette/stepper/undo/time-controls ~70% of the doc is
strong (minor findings only). But the toast/notification subsystem was
internally incoherent (Rule 9 vs Edge Case 1 contradicted on eviction —
append-starvation vs bump-livelock; no identity/dedup key → Shown→Queued
flicker on level-triggered re-emits; no severity priority — Info could
evict an undismissed Warning; stale warnings had NO retirement path),
failed Build Validation's four-item UI seam contract IN FULL (0/4 — item
2 was the named, pre-flagged Rule 9 contradiction), and AC11/12 actively
VALIDATED the prohibited behavior. All six specialists converged on the
toast subsystem. CD: cannot be patched, only redesigned → MAJOR (focused
— one subsystem rebuilt, the rest stands).
Prior verdict resolved: First review

### Blockers (all fixed in-session, grep-verified)
1. **Toast subsystem rebuild** [ALL SIX specialists]: Rule 9 rebuilt as
   identity → severity → lifecycle model: (signal, subject) dedup key
   (re-emits idempotent); `warning_grace_delay` first-appearance grace
   (seam 3); `min_reshow_interval` dismissal debounce (seam 2 — the
   named contradiction retired); auto-retire on cause cessation +
   Warning→Info tier-swap reconcile (seam 4); severity-tiered eviction
   with **USER RULING: warnings never evicted**, anchor = overflow home,
   hidden FIFO queue deleted (no starvation/livelock). New Rule 9c
   **issues anchor** (**USER RULING: toast-area anchor + expandable live
   list** from queryable state, hidden at zero) = seam item 1. Per-key
   lifecycle table rewritten. AC11/12 rewritten + AC27-32 added.
2. **Rule 2 self-contradiction** [ui-programmer + qa-lead]: rewritten to
   "no simulation-authoritative state" + exhaustive presentation-memory
   carve-out (material memory / toast state / timers — verified to have
   no upstream home).
3. **Celebration double-presentation** [game-designer]: **USER RULING:
   in-world only** — new Rule 9d: `room_recognized` not consumed, no
   confirmation toast, `toast_confirm_fade` deleted, AC35; reciprocal
   note in build-validation-navigability.md (its seam flag marked
   RESOLVED).
4. **Accessibility** [ux-designer]: **USER RULING: minimal keyboard
   set** — Rule 9b actions (toast_focus_cycle/toast_dismiss/
   toggle_issues/palette_next/prev; bindings [assumption] → /ux-design),
   Rule 12 registration, AC33/34/36; toast tiers differentiated by icon
   SHAPE + label (hue-alone retired, Visual Direction Note §4).

### Recommended items applied
R1 Rule 11 event-routing requirement (suppression = queryable flag on
pick starts; HUD never consumes a drag's release — godot) · R2 Edge Case
6 explicit Suspended-tied timer pause, resume-with-remaining, Godot
Tween/Timer note · R3 Rule 7 key-repeat scoping (rate untested by
design) + OQ6 velocity cap · R4 OQ7 post-4.3 verification (mouse_filter,
4.6 dual-focus, 4.5 AccessKit) · R5 pause-mirror reconciled (signals +
returned state, Rule 2) + Edge Case 12 double-tap race · R6 stale
upstream rows → Approved. Minors: AC3 un-highlight, Summary/Cross-Refs
updated, toast_max_visible min 2.

### CD notes
- Inspection surface ruled a SCOPE-decision blocker (new HUD surface),
  resolved by user choice, not silent authoring.
- Celebration fix ruled "likely deletion" — confirmed by user.
- Cluster F (engine mechanisms) explicitly non-blocking/authorable.

### State after revision
ACs 26 → 36 (22+10 blocking / 4 advisory). Core Rules 12 → 12+9b/9c/9d.
Edge Cases 10 → 12. Knobs: +min_reshow_interval(30s), +warning_grace_delay(3s),
−toast_confirm_fade; toast_max_visible range 2–5. New OQ6/OQ7. Files:
building-ui.md + build-validation-navigability.md (seam-resolution note).
**Re-review pending in a fresh session** (rebuilt Rules 9–9d are new
design — needs fresh adversarial eyes).
