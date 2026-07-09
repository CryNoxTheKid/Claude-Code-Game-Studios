# Building UI

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
> **Implements Pillar**: Pillar 4 — Clarity over complexity (primary); Pillar 1 — The building IS the game (the toolset's face)

## Summary

Building UI is the MVP's entire heads-up display: the build toolbar
(six tools), the material and furniture palette (fed by the Resource &
Item Database), the wall-height stepper and roof-formation picker,
undo/redo controls, validity and validation feedback (invalid-commit
cues, Build Validation's warnings and room confirmations), and — as the
MVP's one global HUD element — the time controls (pause + 1x/2x/3x,
resolving the Time & Tick GDD's open UI-trigger question). It renders
and triggers; it owns no state — every displayed value lives in the
system it mirrors (Building System, Build Validation, Time & Tick).

> **Quick reference** — Layer: `Presentation` · Priority: `MVP` · Key deps: `Building System, Build Validation & Navigability, Resource & Item Database, Time & Tick System`

## Overview

**Player-facing:** this is the hand the player builds with. Per Pillar
4, it must stay *calm and legible*: a compact toolbar, a readable
palette, feedback that appears near the action (invalid cues at the
cursor, warnings as gentle toasts), and nothing permanently cluttering
the cozy valley view. Per Pillar 1, the toolbar IS the game's verb list
— if the UI feels bureaucratic, building feels bureaucratic.

**System-facing:** a pure presentation layer. It subscribes to state
(active tool, selected material, wall height, roof formation, undo/redo
availability, time state, validation events) and sends player intents
back as the same InputMap actions and calls the source systems already
define — it never interprets world clicks itself (Camera & Input →
Building System own that pipeline) and never stores gameplay state.
MVP scope is exactly one screen context: the Valley build HUD. Menus,
settings, and additional HUDs (combat, township) are separate future
systems.

## Player Fantasy

**"My workbench is always at hand — and it never gets in the way."**

1. **Everything within reach.** Tool, material, height, roof shape —
   one glance, one click, back to building. The UI feels like a
   craftsman's belt, not an office form.
2. **The world stays the star.** The HUD frames the valley instead of
   covering it; feedback happens where I'm looking (at the cursor, at
   the building), not in a corner I must check.
3. **It speaks softly.** Invalid actions get a gentle nudge, warnings
   arrive as calm notes I can dismiss — the UI is a helpful workshop
   assistant, never an alarm panel (Pillar 3's cozy tone).

Reference feeling: Stonehearth's build toolbar (compact, iconic) and
Timberborn's bottom bar (readable at a glance). NOT the fantasy: a
dense RTS command card, nested ribbon menus, or modal dialog churn.

> `creative-director` not consulted — Lean mode (non-high-risk
> sections). Review manually before production.

## Detailed Design

### Core Rules

**Layout (bottom bar + one global element)**

1. The HUD has exactly three zones in MVP:
   - **Bottom toolbar**: left — the five modal tool buttons (Wall, Floor,
     Roof, Block, Furniture); center — the context panel (swaps per armed
     tool); right — undo/redo buttons.
   - **Top-right: time controls** — pause toggle + 1x/2x/3x speed
     (radio-style, current state always visible). This resolves the Time
     & Tick GDD's open UI-trigger question.
   - **Top-right, below time controls: notification area** — Build
     Validation's toasts (Rule 9).
   Everything else is world view. No permanent panels beyond these
   (Pillar 4).
2. The UI is a **pure mirror**: every control reflects its source
   system's state (active tool, selected material, wall height, undo
   availability, time state) via that system's signals — no UI-owned
   gameplay state, ever. The HUD runs on raw delta (fully responsive
   during pause, same pattern as Camera & Input).

**Tools and context panel**

3. Tool buttons fire the tool-select InputMap actions (also bound to
   keys **1–5**); the armed tool is visibly highlighted; cancel
   (Esc/right-click, owned by the Building System) returns to Idle and
   clears the highlight. Exactly one tool ever appears active (mirrors
   Building AC 2).
4. The **context panel** shows only what the armed tool needs: material
   palette (Wall/Floor/Roof/Block), wall-height stepper (Wall only),
   roof-formation picker (Roof only, 4 icons), furniture list (Furniture
   — MVP: `bed`). Hidden in Idle.
5. The **material palette** is built from Resource & Item Database
   queries (`building_material`, tier-0 rule; `furniture_fixture` for
   the Furniture tool) — icon from `visual_asset`, tooltip from
   `display_name`. The palette shows exactly what the database offers
   (Building AC 18); the last selection per tool is remembered within
   the session.
6. The **wall-height stepper** shows 1–8 with +/− buttons (and
   mousewheel over the stepper); it is the only player-facing tuning
   knob (Building Tuning Knobs).
7. **Undo/redo buttons** mirror stack state (disabled when empty —
   mirroring Building's stack exactly); click = one step; **Ctrl+Z /
   Ctrl+Y** bindings; a held key repeats at the OS key-repeat rate, one
   step per repeat (Building UI Requirements).

**Feedback**

8. **Invalid-commit cue**: a transient marker at the cursor (orange
   accent per the state axis + the gentle negative sound), auto-fading
   in ~1s, optionally carrying a one-line reason ("occupied", "too many
   cells"). Never modal, never blocking input.
9. **Build Validation toasts**: confirmations (room recognized)
   auto-fade; warnings (sealed space) persist until dismissed and
   re-appear when Build Validation re-emits (its AC 22 — the UI owns
   dismiss-presentation only); info hints (unsheltered bed) are
   dismissible and low-key. Each toast carries the why-string verbatim.
   At most 3 simultaneous toasts; overflow queues oldest-first.
10. **Time controls**: pause toggle bound to **Space**; speed cycling on
    **+/−** (or clicking 1x/2x/3x directly); the control always shows
    the current state (paused state visually unmistakable). Calls Time &
    Tick's pause/warp API; displays its state — never computes time
    itself.

**Input boundaries**

11. The HUD never interprets world clicks: pointer events over HUD
    elements are UI-local; while the cursor hovers the HUD, the world
    pick is suppressed (the Building System's ghost hides — no
    accidental building behind the toolbar). Everything else flows
    through the established Camera & Input → Building System pipeline
    untouched.
12. New InputMap actions introduced by this GDD (`tool_select_1..5`,
    `time_pause`, `time_speed_up/down`) are registered under Camera &
    Input's action ownership (its Core Rule 7 — it owns definitions,
    consumers own meaning).

### States and Transitions

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Idle | Boot, cancel, tool deactivated | Tool selected | Toolbar + time controls visible; context panel hidden |
| ToolArmed(tool) | Tool selected (button or key 1–5) | Cancel / other tool / Suspended | Context panel for that tool; active button highlighted |
| Suspended | Camera & Input enters Suspended (scene transition) | Reactivation | Entire HUD hidden; all input ignored (mirrors Building's tool state machine) |

**Toast lifecycle:** Queued → Shown → (auto-fade | dismissed) — warnings
re-enter Queued when their event re-emits.

### Interactions with Other Systems

- **Building System** (upstream, MVP): displays its
  tool/material/height/formation/undo state; triggers it exclusively via
  the shared InputMap actions and its existing selection calls. Mirrors,
  never owns (its UI Requirements section is this GDD's contract).
- **Build Validation & Navigability** (upstream, MVP): consumes its
  confirmation/warning/info events + why-strings (Rule 9); owns only
  presentation (dismiss state).
- **Resource & Item Database** (upstream, MVP): palette contents, icons,
  display names.
- **Time & Tick System** (upstream, MVP): pause/warp API calls + state
  display. Resolves its Core Rule 2 open trigger ("Building UI/HUD") —
  noted for a cross-reference patch.
- **Camera & Input** (upstream, MVP): action ownership for the new
  bindings (Rule 12); Suspended state propagation; HUD-hover pick
  suppression coordinates with its mouse-ray consumers.
- **Villager Info UI** (MVP sibling, undesigned): separate GDD —
  villager-related display lives there; this GDD is strictly the
  build-and-time HUD.
- **Scene/World Management** (upstream): hosting; Suspended during
  transitions.

## Formulas

*(`systems-designer` consulted — mandatory even in Lean mode. Verdict:
zero formulas.)*

**None.** This GDD renders and triggers but computes nothing — every
number the player sees (wall height, time speed, undo depth) is owned
and derived by an upstream system; the only UI-local numeric behaviors
(toast cap, fade durations, FIFO overflow) are authored constants and
ordering rules — recorded in Tuning Knobs and Edge Cases respectively,
not as formulas.

## Edge Cases

1. **Toast overflow.** More than 3 simultaneous toasts → FIFO eviction:
   the oldest visible toast yields; evicted warnings re-enter the queue
   (they persist by rule until dismissed).
2. **Rapid tool switching** (spamming keys 1–5). The context panel swaps
   cleanly with last-input-wins; no flicker of stale panels, no orphaned
   highlight (mirrors Building AC 2's exactly-one-active guarantee).
3. **Palette integrity.** The palette can never show a broken entry: the
   item database fails at boot on missing `visual_asset` (its AC 22),
   and the reserved `missing_item` is never palette-eligible (not
   tier-0, reserved id). No UI fallback path needed — by upstream design.
4. **Undo clicked as the stack empties concurrently.** The button
   mirrors state via signals; a click racing a just-disabled state is a
   silent no-op — the UI never issues an action the source system would
   reject noisily.
5. **Drag released over the HUD.** Hover suppression (Rule 11) applies
   to *starting* picks, not active drags: a drag begun in the world
   commits on release even over the HUD, using the last valid world
   preview (the preview locks when the cursor enters HUD space). No
   accidental aborts from brushing the toolbar.
6. **Suspended with live toasts.** The toast queue survives Suspended:
   hidden with the HUD, restored on reactivation; auto-fade timers pause
   while hidden. (Warnings would re-derive anyway — Build Validation
   re-emits.)
7. **Speed changed while paused.** Pressing +/− while paused updates the
   *stored* speed without unpausing (mirrors Time & Tick's independent
   pause/speed state); the control displays both facts (paused + pending
   speed).
8. **Window resize / aspect ratio.** The bottom bar anchors to the
   bottom edge (centered, max-width), time controls and toasts to the
   top-right corner — no fixed pixel positions; minimum supported layout
   must hold at 1280×720.
9. **Toast dismissal click.** The click is consumed by the toast — it
   never falls through to the world or the toolbar beneath.
10. **No text input exists in MVP** — keys 1–5/Space/+/− are always
    live. When any text field arrives (VS+: save names, villager
    renaming), shortcut suppression while typing becomes a requirement —
    flagged in Open Questions so it isn't forgotten.

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Building System | ✅ Designed (In Review) | Tool/material/height/formation/undo state + the UI Requirements contract; triggered via shared InputMap actions |
| Build Validation & Navigability | ✅ Designed | Confirmation/warning/info toast events + why-strings; re-assert rule (its AC 22) |
| Resource & Item Database | ✅ Designed | Palette contents, `visual_asset` icons, `display_name` tooltips, tier-0 rule |
| Time & Tick System | ✅ Designed | Pause/warp API + state display (resolves its Core Rule 2 UI-trigger question) |
| Camera & Input | ✅ Designed | InputMap action ownership for new bindings (Rule 12); Suspended state; raw-delta pattern |
| Scene/World Management | ✅ Designed | Hosting; Suspended during transitions |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Onboarding / Tutorial | Vertical Slice | Undesigned | The toolbar as the teachable surface *(provisional)* |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `toast_max_visible` | 3 | 1–5 | Simultaneous notifications — more = noisier (Pillar 4) |
| `toast_confirm_fade` | 4s | 2–8s | How long the room confirmation stays |
| `invalid_cue_fade` | 1s | 0.5–2s | Duration of the at-cursor invalid marker |

Layout anchors/sizes carry no gameplay effect — they belong to the UX
spec / art bible, not this GDD. All values data-driven per the coding
standard.

## Visual/Audio Requirements

Iconography follows the Visual Direction Note: palette icons derive from
`visual_asset` (material↔meaning color families); the blue–orange state
axis governs UI states (armed tool blue-accented, warnings orange —
never red-green). The paused state must be visually unmistakable (e.g.
icon + subtle vignette — treatment to the art bible). Audio: subtle UI
clicks only; commit/invalid sounds are owned by the Building System (no
duplication). **New assets required**: 5 tool icons, 4 roof-formation
icons, time-control icons, toast frames (3 severity tiers).

## Game Feel

Every UI reaction lands the same frame as its input (raw-delta path);
context-panel swaps are snappy (no slide animations in MVP — speed over
ornament); the HUD never disappears unexpectedly. **Feel acceptance
criteria** (playtest): a first-time player finds tool + material
unaided in under a minute (covers the concept's onboarding beat);
nobody calls the HUD "in the way."

## UI Requirements

This GDD *is* the UI — this section points forward instead:

> 📌 **UX Flag — Building UI**: In Phase 4 (Pre-Production), run
> `/ux-design` to create the build-HUD UX spec before writing epics.
> Stories should cite `design/ux/build-hud.md`, not this GDD directly.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| UI Requirements contract (toolbar, stepper, undo, feedback) | `design/gdd/building-system.md` | UI Requirements | This GDD's order sheet |
| Toast events + why-strings + re-assert rule | `design/gdd/build-validation-navigability.md` | Rule 8, AC 22 | Event contract |
| Pause/warp trigger ("Building UI/HUD") | `design/gdd/time-tick-system.md` | Core Rule 2 | **Resolved by this GDD** (Rules 1/10 — patch note there) |
| Action ownership, Suspended, raw-delta pattern | `design/gdd/camera-input.md` | Core Rules 7–8 | New actions under its ownership (Rule 12) |
| Palette data (`display_name`, `visual_asset`, tier-0) | `design/gdd/resource-item-database.md` | Core Rules 4–8 | Data contract |
| Blue–orange axis, material colors | `design/art/visual-direction-note.md` | State axis | Visual constraint |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review produced 5 rewrites and 6 missing criteria; all
incorporated. Split per the project's test-evidence table: headless
unit-testable mirror/event logic is BLOCKING; rendering/viewport/layout
checks are ADVISORY (interaction test or walkthrough doc).)*

**Blocking — headless unit tests (state-mirror & event logic)**
1. **GIVEN** any tool selected in the Building System (mocked signal), **WHEN** it arrives, **THEN** the matching button highlights and all others un-highlight, same frame.
2. **GIVEN** key 1–5 pressed, **WHEN** the action fires, **THEN** the corresponding tool-select action is emitted — the UI sends intents, never sets Building state directly.
3. **GIVEN** a tool armed, **WHEN** cancel fires, **THEN** the UI returns to Idle and the context panel hides.
4. **GIVEN** Wall armed → palette + stepper; Roof armed → palette + 4 formation icons; Furniture armed → furniture list (`bed` only); Idle → no panel (Rule 4).
5. **GIVEN** the mocked MVP dataset, **WHEN** the palette renders, **THEN** exactly the tier-0 materials appear for placement tools and exactly `bed` for Furniture.
6. **GIVEN** a material selected for tool A, **WHEN** switching to B and back, **THEN** A's last selection is restored (session-scoped).
7. **GIVEN** the stepper at 8, **WHEN** + fires, **THEN** it stays 8; same at 1 with − (clamped display of Building's range).
8. **GIVEN** an empty undo stack (mocked), **THEN** undo is disabled; **GIVEN** a redo branch, **THEN** redo enables — mirroring only.
9. **GIVEN** N synthetic undo action-pressed events in sequence, **THEN** exactly N undo intents are emitted — none added or dropped (no debounce, no acceleration).
10. **GIVEN** an invalid-commit event, **THEN** the at-cursor cue appears and auto-fades within `invalid_cue_fade` ±10 %, blocking no input.
11. **GIVEN** a dismissed warning toast, **WHEN** Build Validation re-emits, **THEN** it reappears (UI owns presentation only).
12. **GIVEN** a 4th simultaneous toast, **THEN** only 3 show, oldest evicted FIFO; evicted warnings re-queue.
13. **GIVEN** Space pressed, **THEN** Time & Tick's pause toggle is called and the control reflects the *returned* state — never a UI-local pause.
14. **GIVEN** paused at stored 2x, **WHEN** + fires, **THEN** the stored speed changes without unpausing; the control shows both facts (Edge Case 7).
15. **GIVEN** the cursor over any HUD element, **THEN** hover-suppression reports active and the Building ghost hides (Rule 11).
16. **GIVEN** Suspended entered, **THEN** the HUD hides, ignores input, and toast timers freeze — restoring on reactivation (Edge Case 6).
17. **GIVEN** rapid interleaved tool-select events (spam 1–5), **THEN** last-input-wins with exactly one highlight and no stale panel at every step (Edge Case 2).
18. **GIVEN** an undo click racing a same-frame disable signal, **THEN** silent no-op — no action emitted, no error (Edge Case 4).
19. **GIVEN** mousewheel over the stepper, **THEN** it steps identically to the +/− buttons within 1–8 (Rule 6).
20. **GIVEN** an info-tier hint (unsheltered bed), **THEN** it renders as dismissible low-key — distinct from warning styling — and its why-string passes through verbatim (Rule 9).
21. **GIVEN** arbitrary interleaved mocked state sequences, **THEN** at no point do two tools appear active simultaneously (invariant over AC 1).
22. **GIVEN** the InputMap at boot, **THEN** `tool_select_1..5`, `time_pause`, `time_speed_up/down` exist as registered actions (smoke check, Rule 12).

**Advisory — interaction test / manual walkthrough (UI evidence gate)**
23. **GIVEN** a drag begun in the world, **WHEN** the cursor enters HUD space, **THEN** the drag is NOT canceled (UI half); **WHEN** released over the HUD, **THEN** the commit uses the last valid world preview (integration with Camera & Input/Building — Edge Case 5).
24. **GIVEN** a toast dismissal click in a live viewport, **THEN** the click is consumed — nothing beneath receives it (Edge Case 9).
25. **GIVEN** a 1280×720 window, **THEN** the three zones' bounding rects lie fully in-viewport and do not intersect (screenshot/rect assertion — Edge Case 8).
26. **GIVEN** a first-time playtester, **THEN** tool + material found unaided in under a minute (Game Feel criterion — playtest evidence doc).

## Open Questions

1. **UX spec details** (exact layout metrics, icon design, arrangement)
   → */ux-design build-hud in Pre-Production (see the UX Flag in UI
   Requirements)*
2. **Shortcut suppression when text input arrives** (Edge Case 10)
   → *Vertical Slice, with the first text field*
3. **Gamepad menu navigation** (technical-preferences: "partial, later")
   → *Alpha, shared with the Camera & Input open question*
4. **Exact toast styling per severity tier** → *art bible*
5. **Where do future HUD elements live** (combat/wave, township)? Own
   systems slotting into these zones — → *their GDDs (VS/Alpha)*
