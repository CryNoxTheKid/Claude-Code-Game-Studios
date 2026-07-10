# Villager Info UI

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
> **Implements Pillar**: Pillar 2 — A settlement that feels alive (reading villagers); Pillar 4 — Clarity over complexity (the why is always one click away)

## Summary

Villager Info UI is how the player reads a villager: click a villager
(while no build tool is armed) and a compact side panel shows their
name, current activity, need levels, mood band, and — most importantly
— the *why* ("tired — no bed", verbatim from the Needs system). Its
only always-on element is the distress indicator: a subtle overhead
icon on villagers in trouble (trapped, ground-sleeping), so problems
are visible without clicking. Like all UI in this project it is a pure
mirror — it owns nothing but the current selection.

> **Quick reference** — Layer: `Presentation` · Priority: `MVP` · Key deps: `Villager AI & Behavior, Needs & Mood System`

## Overview

**Player-facing:** this is the window into Pillar 2. The villager
panel turns simulation state into a person: a name, what they're
doing, how they feel, and what they need from you. Per Pillar 4, the
"why" is always one click away — mood is never a mystery. Per the
quiet-HUD principle (Building UI), nothing villager-related clutters
the screen permanently; only genuine distress earns an overhead icon.

**System-facing:** a presentation layer beside Building UI. It claims
exactly one input niche: in Idle (no build tool armed), a click that
hits a villager selects them; everything else remains untouched
(Building owns armed-tool clicks; empty Idle clicks deselect). It
mirrors Villager AI (activity, distress) and Needs & Mood (values,
band, why-string) via their signals, updating live on raw delta.
Out of scope: villager rosters/lists, camera-focus-on-villager,
portraits, renaming — all VS+ (Open Questions).

## Player Fantasy

**"I know my villagers."**

1. **Meeting them.** Click — and the blocks-person becomes *someone*:
   a name, a task, a feeling. The moment attachment starts.
2. **Understanding at a glance.** One panel answers "how are they
   doing and why" without menus or math — care without homework.
3. **Never missing a cry for help.** The distress icon means I don't
   have to patrol my villagers; trouble finds my eyes. (The UI half of
   the Villager AI's never-teleport/visible-distress philosophy.)

Reference feeling: RimWorld's colonist readout stripped to Stonehearth
warmth — informative, never clinical. NOT the fantasy: a stat sheet,
a manage-everything dashboard, or Sims needs-micromanagement.

> `creative-director` not consulted — Lean mode (non-high-risk
> sections). Review manually before production.

## Detailed Design

### Core Rules

1. **Selection** exists only in Idle (no build tool armed): a click
   whose pick hits a villager selects them; a click hitting nothing
   deselects; Esc deselects; clicking another villager switches. While
   any build tool is armed, all clicks belong to the Building pipeline
   — selection is untouchable (no accidental villager-clicks
   mid-build).
2. **The panel** (right side, compact) shows: name, current activity
   as a player-readable label (the five AI states → "Working",
   "Sleeping", …), one bar per active need (MVP: sleep), the mood-band
   icon (3 states), the why-string whenever a need is urgent or mood
   is not Happy (verbatim from Needs), and any distress flags.
3. **Live mirror**: while selected, the panel updates continuously
   (raw delta — readable during pause); it holds selection when the
   villager walks off-screen (no camera follow in MVP — Open
   Question). Selection is the only state this system owns.
4. **Overhead distress icon**: villagers with an active distress flag
   (trapped, ground-sleeping — Villager AI Edge Case 2 / Rule 12) show
   a subtle icon above their head, visible unselected, disappearing
   when the cause resolves. No permanent mood icons over heads
   (Pillar 4 calm; the panel is where mood lives).
5. **Why-strings pass through verbatim** from Needs & Mood (its UI
   contract) — this UI never composes its own explanations.
6. The panel design assumes N villagers (VS ~5, ceiling 20–30) from
   day one — selection is per-villager; only the roster/list view is
   deferred (Open Questions).

### States and Transitions

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Unselected | Boot, deselect, villager despawn | Villager clicked (Idle mode) | No panel; overhead distress icons still visible |
| Selected(v) | Click hit villager v | Deselect / other villager / Suspended | Panel live-mirrors v; overhead icons unchanged |
| Suspended | Camera & Input Suspended | Reactivation | Panel + icons hidden; selection retained through the transition |

### Interactions with Other Systems

- **Villager AI & Behavior** (upstream, MVP): activity state, name,
  distress flags (its Rule 12/Edge Case 2 + Info UI contract); a
  villager-hit query for selection picking.
- **Needs & Mood System** (upstream, MVP): need values, mood band +
  band-change events, why-strings (its UI Requirements contract).
- **Camera & Input** (upstream, MVP): mouse-ray + click actions in
  Idle; Suspended propagation. Selection introduces no new InputMap
  actions (reuses the existing click action in the unclaimed Idle
  niche).
- **Building UI** (MVP sibling): mode coordination — armed tool ⇒
  Building pipeline owns clicks; Idle ⇒ this system may claim
  villager hits. One rule, no overlap.
- **Scene/World Management** (upstream): hosting; Suspended.

## Formulas

*(`systems-designer` consulted — mandatory even in Lean mode. Verdict:
zero formulas.)*

**None** — pure mirror; selection is a consumed hit-result, need bars
are raw upstream values on the pre-contracted 0–100 scale, and icon
placement is engine projection, not designed math. See Interactions for
the upstream contracts this UI reads but never computes.

## Edge Cases

1. **Selected villager despawns** (none in MVP; waves later) → graceful
   deselect, panel closes — never a stale panel.
2. **Ray hits villager and block** → nearest hit wins; on overlap/tie
   the villager wins (the interactive entity).
3. **Several villagers along the ray** → nearest wins, deterministic.
4. **Selection during pause** → fully functional (raw delta); the
   frozen villager's panel reads normally.
5. **Distress while selected** → overhead icon and panel flag derive
   from the same signal — they can never disagree.
6. **Suspended during selection** → selection retained through the
   transition (the villager kept simulating); panel restores on return.
7. **Build tool armed while a villager is selected** (key 1–5) → the
   panel closes and selection clears — clean mode switch, mirroring
   Rule 1's exclusivity.
8. **Why-string exceeds panel width** → wraps, never silently truncates
   (Pillar 4).
9. **Many distressed villagers far away** → overhead icons may overlap
   at distance; accepted in MVP (clustering → VS+, Open Questions).
10. **Villager behind the bottom toolbar** → overhead icon may be
    occluded by HUD; accepted in MVP (the panel and warnings still
    surface the problem).

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Villager AI & Behavior | ✅ Designed | Activity state, name, distress flags (its Info-UI contract); villager-hit query for selection |
| Needs & Mood System | ✅ Designed | Need values (0–100), mood band + change events, why-strings verbatim (its UI contract) |
| Camera & Input | ✅ Designed | Mouse-ray + click action in Idle; Suspended propagation. No new InputMap actions |
| Scene/World Management | ✅ Designed | Hosting; Suspended during transitions |
| Building UI | ✅ Designed (sibling) | Click-ownership rule: armed tool ⇒ Building pipeline; Idle ⇒ villager hits may select |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Onboarding / Tutorial | Vertical Slice | Undesigned | The "meet your villager" teachable beat *(provisional)* |

## Tuning Knobs

**None** — every value here is presentation (panel metrics, icon sizes,
timings → UX spec / art bible). Honestly empty, as a pure mirror should
be.

## Visual/Audio Requirements

Mood-band icons (3, colorblind-safe — the concrete delivery of the
Needs & Mood visual requirement), the overhead distress icon (the
delivery of Villager AI's distress-cue requirement — gentle,
cozy-not-alarming per Pillar 3), a subtle selection outline on the
villager, and the panel in the warm UI style. Audio: a soft select
sound only. **New assets required**: 3 mood icons, distress icon,
selection-outline treatment.

## Game Feel

Click → panel the same frame; selecting feels like *touching* a
villager, not opening a menu. Deselection is equally instant. **Feel
acceptance criterion** (playtest): players click a villager unprompted
within their first minutes (curiosity test), and can afterwards say how
the villager is doing and why.

## UI Requirements

This GDD *is* the UI — pointer forward:

> 📌 **UX Flag — Villager Info UI**: In Phase 4 (Pre-Production), run
> `/ux-design villager-panel` before writing epics. Stories should cite
> `design/ux/villager-panel.md`, not this GDD directly.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| Info-UI contract: state labels, distress flags; hit query | `design/gdd/villager-ai-behavior.md` | UI Requirements, Rule 12, Edge Case 2 | Order sheet (villager half) |
| UI contract: values, band, why-string verbatim | `design/gdd/needs-mood-system.md` | UI Requirements | Order sheet (needs half) |
| Click ownership, quiet-HUD principle, zones | `design/gdd/building-ui.md` | Rules 1/11 | Sibling coordination |
| Mouse-ray, click actions, Suspended, raw-delta/pause contract | `design/gdd/camera-input.md` | Core Rules 7–10 (Rules 9–10 authored 2026-07-10) | Input contract |
| Blue–orange axis, cozy tone | `design/art/visual-direction-note.md` | State axis | Visual constraint |
| Pillar 2/4, onboarding beat | `design/gdd/game-concept.md` | Pillars, Flow | Scope authority |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in
Lean mode. Review produced 4 rewrites and 3 missing criteria; all
incorporated. Split per the project's test-evidence table.)*

**Blocking — headless unit tests**
1. **GIVEN** Idle mode and a mocked villager hit, **WHEN** click fires, **THEN** that villager is selected and the panel opens.
2. **GIVEN** Idle and a mocked empty hit, **WHEN** click fires, **THEN** selection clears; **GIVEN** Esc, **THEN** likewise.
3. **GIVEN** villager A selected and a hit on B, **WHEN** click fires, **THEN** selection switches to B in one step.
4. **GIVEN** any build tool armed (mocked), **WHEN** a click fires, **THEN** no selection change — clicks belong to Building (Rule 1).
5. **GIVEN** a selected villager and a mocked tool-arm event, **THEN** the panel closes and selection clears (Edge Case 7).
6. **GIVEN** each of the five AI activity states (mocked) in turn, **WHEN** selected, **THEN** the panel shows the correct distinct player-readable label for each; **WHEN** the state changes while selected, **THEN** the label updates the same frame (Rule 2, full mapping).
7. **GIVEN** mocked need values, **WHEN** rendered, **THEN** each active need bar shows the raw 0–100 value — no UI-side scaling or smoothing.
8. **GIVEN** a mood band change event, **WHEN** received, **THEN** the band icon updates (band signal only).
9. **GIVEN** mood not Happy or a need urgent, **THEN** the why-string renders verbatim from the Needs payload; **GIVEN** mood Happy AND no urgent need, **THEN** the why-string area is empty/hidden (Rule 2 both directions).
10. **GIVEN** a mocked distress flag set on any villager (selected or not), **THEN** its overhead icon activates; **WHEN** cleared, **THEN** it deactivates (Rule 4).
11. **GIVEN** a distressed villager selected, **THEN** panel flag and overhead icon reflect the same source state — single source, no divergence (Edge Case 5).
12. **GIVEN** pause (mocked), **THEN** click-to-select, panel value updates, and Esc-deselect all still fire on the paused frame — raw delta (Edge Case 4).
13. **GIVEN** Suspended active with a selection, **THEN** panel and overhead icons are hidden while the selection value persists unchanged; **WHEN** reactivated, **THEN** the same villager is selected and the panel restores (Edge Case 6 + state table).
14. **GIVEN** a selected villager despawn event, **THEN** selection clears gracefully — no stale panel, no error (Edge Case 1).
15. **GIVEN** a mocked ray with a villager and a nearer block, **THEN** the block wins; **GIVEN** overlap/tie, **THEN** the villager wins (Edge Case 2).
16. **GIVEN** a mocked ray hitting villagers A/B/C at different distances, **THEN** the nearest is selected — deterministic and repeatable (Edge Case 3).
17. **GIVEN** 20+ mocked villagers, **WHEN** selecting #1 then #17, **THEN** exactly one villager is ever selected and every panel value reflects live upstream state — mutating the upstream mock directly (bypassing signals) never leaves a stale local copy on reselect (Rules 3/6: selection is the ONLY owned state).

**Advisory — interaction test / manual walkthrough**
18. **GIVEN** a live viewport, **WHEN** a villager walks behind the toolbar, **THEN** the accepted occlusion is documented (walkthrough, Edge Case 10).
19. **GIVEN** a long why-string, **THEN** it wraps with no silent truncation (visual check, Edge Case 8).
20. **GIVEN** a first-time playtester, **THEN** they click a villager unprompted within the first minutes and can afterwards state how it's doing and why (Game Feel — playtest doc).

## Open Questions

1. **Roster/list view** of all villagers → *Vertical Slice, once ~5
   villagers exist*
2. **Camera focus on selected villager** (requires a new "focus on
   point" API from Camera & Input) → *Vertical Slice, with camera-input*
3. **Distress icon clustering** at distance (Edge Case 9) → *VS+*
4. **Portraits, renaming, identity display** → *with villager identity
   generation (Villager AI OQ 5), Vertical Slice*
5. **UX spec** → */ux-design villager-panel in Pre-Production (see the
   UX Flag)*
