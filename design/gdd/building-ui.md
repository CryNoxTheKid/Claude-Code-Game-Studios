# Building UI

> **Status**: Approved (2026-07-10 — MAJOR REVISION NEEDED → toast model rebuilt; re-review NEEDS REVISION (narrow) → grace-clock rewrite + patches; verification pass CLEAN)
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
> **Implements Pillar**: Pillar 4 — Clarity over complexity (primary); Pillar 1 — The building IS the game (the toolset's face)

## Summary

Building UI is the MVP's entire heads-up display: the build toolbar
(six tools), the material and furniture palette (fed by the Resource &
Item Database), the wall-height stepper and roof-formation picker,
undo/redo controls, validity and validation feedback (invalid-commit
cues, Build Validation's warning/info toasts + the issues anchor — room
confirmations are celebrated in-world, not in the HUD), and — as the
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
     Validation's warning/info toasts + the issues anchor (Rules 9–9c).
   Everything else is world view. No permanent panels beyond these
   (Pillar 4).
2. The UI is a **pure mirror of simulation state**: every control
   reflects its source system's state (active tool, selected material,
   wall height, undo availability, time state) — no UI-owned
   *simulation-authoritative* state, ever. **UI-local presentation
   memory IS owned here by design and is exhaustively scoped**: the
   per-tool last-selected material (Rule 5), toast/anchor presentation
   state (shown/dismissed flags, grace/debounce timers, focus, toast
   display order/age, and the anchor's expanded/collapsed flag — Rules
   9–9c), and nothing else; none of it is serialized, none of it is
   consumed by any other system. *(Revised 2026-07-10 — the original
   "no UI-owned state, ever" claim contradicted Rules 5 and 9.)*
   Mirroring uses each source's signals — except the **time controls,
   whose display is written EXCLUSIVELY from the pause/warp API's
   returned state** (Rule 10, Edge Case 12); Time & Tick state signals
   are consumed only for changes not initiated by this HUD, and a
   signal never overwrites a newer returned state (no stale-writer
   race — re-review fix, 2026-07-10).
   The HUD runs on raw delta (fully responsive during pause, same
   pattern as Camera & Input).

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
   mousewheel over the stepper, and the `height_step_up/down` actions —
   Rule 9b); it is the only player-facing tuning knob (Building Tuning
   Knobs).
7. **Undo/redo buttons** mirror stack state (disabled when empty —
   mirroring Building's stack exactly); click = one step; **Ctrl+Z /
   Ctrl+Y** bindings; a held key repeats at the OS key-repeat rate, one
   step per repeat (Building UI Requirements). *(Scoping note,
   2026-07-10: the repeat RATE is OS-configured — `InputEventKey.echo`
   — and deliberately neither asserted nor tested; AC 9 tests
   count-fidelity with synthetic events only. A repeat-velocity cap is
   an Open Question.)*

**Feedback**

8. **Invalid-commit cue**: a transient marker at the cursor (orange
   accent per the state axis + the gentle negative sound), auto-fading
   in ~1s, optionally carrying a one-line reason ("occupied", "too many
   cells"). Never modal, never blocking input.
9. **Build Validation toasts — identity, severity, lifecycle**
   *(REBUILT 2026-07-10 — the original rule contradicted Build
   Validation's four-item seam contract and itself; this model
   implements all four seam items)*. The toast area shows **warnings
   and info hints only** (`sealed_space_warning`,
   `unsheltered_furniture_info`) — room confirmations are not toasts
   (Rule 9d). Each toast carries the why-string verbatim.
   - **Identity/dedup**: every toast is keyed by (signal type, subject)
     — the region for sealed-space warnings, the item for info hints.
     A re-emission matching a live key **refreshes that toast in
     place**: no new entry, no re-queue, no visual change. Build
     Validation's level-triggered per-pass re-emits are idempotent for
     presentation.
   - **First-appearance grace** (seam item 3): the grace timer is a
     **UI-local wall-clock timer per SUBJECT, started on the subject's
     first qualifying emission — NOT a count of re-emissions** (Build
     Validation is event-driven, its Rule 7: a persisting cause may
     emit exactly once; rewritten 2026-07-10 — the original re-emission
     wording was unsatisfiable). When `warning_grace_delay` expires,
     the UI checks Build Validation's queryable state: cause still
     holds → the toast (or anchor entry) appears; cause resolved
     meanwhile → nothing ever surfaces (a transient seal fixed within
     the same build gesture never appears at all). These timers (grace
     AND the debounce below) freeze only during Suspended (Edge Case
     6), never during ordinary game pause — the expiry check reads
     current queryable state, which stays correct while paused
     (removal/undo still fire analysis in pause).
   - **Severity**: Warning outranks Info. A visible Warning is NEVER
     evicted by a lower-severity arrival; it leaves the screen only via
     player dismissal, tier-swap, cause resolution, or the overflow
     rule below.
   - **Cap and overflow — the anchor is the overflow home; there is no
     hidden queue**: at most `toast_max_visible` toasts show. When
     full: a new Warning evicts the oldest visible Info (which
     collapses into the anchor); if every visible slot holds a Warning,
     the NEW warning goes directly to the anchor (badge increments — it
     is never invisible, so nothing starves). A new Info arriving when
     full goes directly to the anchor.
   - **Dismissal + re-show debounce** (seam item 2): dismissing a toast
     hides it and starts `min_reshow_interval` for its key (same
     wall-clock timer class as grace); re-emissions inside the window
     do NOT re-show it (the issue stays in the anchor list — dismissal
     hides a toast, never the record). At window expiry the queryable
     state decides: cause still holds → the toast re-shows (no
     re-emission required); cause gone → the entry was already retired
     by reconciliation.
   - **Promotion** *(2026-07-10 re-review ruling)*: when a visible slot
     frees (dismissal, retirement, or tier-swap), the longest-waiting
     anchor-only Warning is promoted into it as a toast — grace was
     already served, so it surfaces immediately; a previously-dismissed
     key still respects its remaining `min_reshow_interval` (the
     next-longest-waiting eligible key promotes instead). Info promotes
     only when no anchor-only Warning waits. The anchor is a true
     overflow buffer, never a graveyard.
   - **Reconciliation — resolution and tier-swap** (seam item 4): the
     toast/anchor set reconciles against each analysis pass's emissions
     plus Build Validation's queryable state (its no-cleared-signal
     model, its Rule 10; all emissions of one pass arrive synchronously
     in one frame — same-frame delivery IS the reconciliation unit, per
     the reciprocal note in its Rule 10). A key whose emissions cease
     is **auto-retired** — toast and anchor entry removed within one
     reconcile; solved problems never require a manual dismiss. A
     subject whose Warning ceases while an Info begins in the same pass
     swaps tiers: the Warning retires, the Info appears — never both
     for one subject. **Tier-swap bookkeeping is per SUBJECT across
     keys** *(added 2026-07-10 re-review)*: a swap of an already-Shown
     Warning shows the Info immediately (grace was served by the
     Warning); a swap during Grace transfers the elapsed grace credit
     to the Info key — no restart, so a flickering cause can never
     indefinitely suppress surfacing; an active dismissal-debounce
     window on the retiring Warning does NOT carry to the Info (a tier
     change is new information the player has not dismissed).
9b. **Keyboard access** *(2026-07-10 decision — no persistent element
   is mouse-only; completed at the re-review, which found the stepper
   and roof picker still keyboard-less)*: `toast_focus_cycle` steps
   focus through visible toasts; `toast_dismiss` dismisses the focused
   toast with semantics identical to a click; `toggle_issues`
   opens/closes the anchor list (Rule 9c); `palette_next`/`palette_prev`
   cycle the armed tool's material/furniture palette selection;
   `formation_next`/`formation_prev` cycle the roof-formation picker
   (Roof armed); `height_step_up`/`height_step_down` drive the
   wall-height stepper (Wall armed — +/− keys are time-owned and
   unavailable). Default bindings are `[assumption]` until the
   /ux-design pass — the ACTIONS are the commitment, not the keys
   (Q/E are camera-owned and avoided; Tab collides with Godot's
   built-in `ui_focus_next` and needs explicit resolution there).
   **Esc releases HUD keyboard focus WITHOUT dismissing** (distinct
   from `toast_dismiss`): a focused toast or expanded anchor loses
   focus on Esc, and only an Esc pressed with NO HUD focus falls
   through to world-level handlers — e.g., Villager Info UI's deselect
   (its Rule 1 Esc routing; reciprocal clause added 2026-07-11).
9c. **The issues anchor** *(seam item 1 — the on-demand inspection
   surface)*: a compact counter at the top of the notification zone
   ("N ⚠"), visible iff at least one active warning/info exists
   anywhere (shown, dismissed-within-window, or overflowed); hidden
   entirely at zero issues (Pillar 4 calm — no dead chrome). Activating
   it (click or `toggle_issues`) expands a compact list of ALL active
   issues with verbatim why-strings, built live from Build Validation's
   queryable state (its Rule 10 state+events contract) — never a
   UI-cached copy. The anchor stores nothing but its expanded/collapsed
   flag.
9d. **Room confirmations have no HUD surface**: the room-recognized
   celebration is entirely in-world (Build Validation's Visual/Audio —
   highlight tracing the room + chime, honoring its
   one-celebration/anti-stacking rule). This HUD does not consume
   `room_recognized` and renders no confirmation toast *(2026-07-10
   decision — deletes the original auto-fading confirmation toast and
   the `toast_confirm_fade` knob)*. **Accepted asymmetry** *(re-review
   acknowledgment)*: warnings are durable (the anchor); a missed
   in-world celebration is unrecoverable — deliberate,
   cozy-over-completionist; revisit only if the MVP playtest shows
   players missing their move-in moments.
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
    untouched. **Event-routing requirement** *(added 2026-07-10;
    generalized 2026-07-11)*: hover suppression gates pick *starts*
    via a queryable flag consumed by the world-pick pipeline — **the
    flag is the SHARED gate for EVERY world-pick consumer**: the
    Building System's ghost/placement pick AND Villager Info UI's
    villager-selection query (its Rule 1 HUD-hover gate) both honor
    it; the ghost hiding is one consequence, not the flag's scope. The
    HUD must NOT consume the pointer-release event of an in-progress
    world drag (Edge Case 5 depends on the drag owner still observing
    the release; a naive whole-zone mouse-filter=STOP would swallow
    it) — **RESOLVED 2026-07-11 via ADR-0010**: Building System tracks
    an in-progress drag's release via `_input()` (fires before Control
    consumption) rather than `_unhandled_input()`, immune to HUD hover
    regardless of the HUD's own mouse_filter configuration.
12. New InputMap actions introduced by this GDD (`tool_select_1..5`,
    `time_pause`, `time_speed_up/down`, and — added 2026-07-10 —
    `toast_focus_cycle`, `toast_dismiss`, `toggle_issues`,
    `palette_next`, `palette_prev`, `formation_next`, `formation_prev`,
    `height_step_up`, `height_step_down` per Rule 9b) are registered
    under Camera & Input's action ownership (its Core Rule 7 — it owns
    definitions, consumers own meaning).

### States and Transitions

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Idle | Boot, cancel, tool deactivated | Tool selected | Toolbar + time controls visible; context panel hidden |
| ToolArmed(tool) | Tool selected (button or key 1–5) | Cancel / other tool / Suspended | Context panel for that tool; active button highlighted |
| Suspended | Camera & Input enters Suspended (scene transition) | Reactivation | Entire HUD hidden; all input ignored (mirrors Building's tool state machine) |

**Per-key toast lifecycle (Rule 9):** Grace(new key, hidden — wall-clock
timer) → Shown | AnchorOnly(overflow) → Dismissed(debounce window —
anchor entry stays) → re-Shown(window elapsed + cause persists in
queryable state) — plus **AnchorOnly → Shown via promotion** (a visible
slot frees, Rule 9) — with two universal exits from any state:
**Retired** (cause gone → auto-removed within one reconcile) and
**Tier-swapped** (Warning→Info for the same subject; per-subject grace
credit transfers, debounce does not). Same-key re-emissions never
create a second instance (Rule 9 identity).
**Anchor:** Hidden(0 issues) ↔ Badge(N) ↔ Expanded — pure derivation
from the live issue set plus one expanded/collapsed flag.

### Interactions with Other Systems

- **Building System** (upstream, MVP): displays its
  tool/material/height/formation/undo state; triggers it exclusively via
  the shared InputMap actions and its existing selection calls. Mirrors,
  never owns (its UI Requirements section is this GDD's contract).
- **Build Validation & Navigability** (upstream, MVP): consumes its
  warning/info events + why-strings (Rule 9) and its queryable state
  for the issues anchor (Rule 9c); implements all four items of its UI
  seam contract (its UI Requirements — resolved 2026-07-10 by this
  review). Does NOT consume `room_recognized` (Rule 9d — the
  celebration is in-world per its Visual/Audio anti-stacking rule).
  Owns only presentation state (Rule 2's scoped carve-out).
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

1. **Toast overflow.** More than `toast_max_visible` simultaneous
   issues → the anchor absorbs the excess (Rule 9): a new Warning
   evicts the oldest visible Info into the anchor; when every visible
   slot holds a Warning, new arrivals go straight to the anchor (the
   badge counts them — nothing is ever invisible, nothing starves; the
   original hidden FIFO queue is deleted).
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
5. **Drag released over the HUD.** *(mechanism RESOLVED 2026-07-11 via
   ADR-0010)* Hover suppression (Rule 11) applies to *starting* picks,
   not active drags: a drag begun in the world commits on release even
   over the HUD, using the last valid world preview (the preview locks
   when the cursor enters HUD space). No accidental aborts from brushing
   the toolbar. Mechanism: once dragging, Building System listens for the
   release via Godot's `_input()` (fires before any Control's `_gui_input`
   consumption, regardless of cursor position) instead of
   `_unhandled_input()`, and claims the event via
   `set_input_as_handled()` — so the release is never swallowed by the
   HUD's own click-consumption, and the commit uses the locked preview
   position rather than re-deriving one from the (HUD-positioned) release
   point.
6. **Suspended with live toasts.** The toast/anchor set survives
   Suspended: hidden with the HUD, restored on reactivation; all UI
   timers (grace, debounce windows, the invalid-cue fade) pause while
   Suspended and resume with REMAINING time — never restart.
   *Implementation note: hiding a Control does not pause Godot
   Tweens/Timers — the pause is an explicit call tied to the Suspended
   transition, not a visibility side effect; the SAME Suspended-entry
   signal from Camera & Input drives both the HUD-hide and the
   timer-pause, one trigger, no drift.* Ordinary game PAUSE never
   freezes these timers (Rule 9's wall-clock semantics — analysis can
   still run while paused, since removal/undo fire signals in pause).
   (Issue records would re-derive anyway — Build Validation re-emits.)
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
11. **Warning resolves while its toast is shown.** The cause is fixed
    (emissions cease) → the toast and its anchor entry auto-retire
    within one reconcile pass — the player never has to dismiss a
    solved problem (Rule 9 reconciliation).
12. **Rapid pause double-tap.** Two Space presses faster than one
    mirrored update: each press is a synchronous API call whose
    returned state updates the display (Rules 2/10) — the control shows
    Time & Tick's authoritative state after the second call; no
    UI-local toggle exists to diverge, and per Rule 2 a queued state
    SIGNAL from press 1 can never overwrite press 2's newer returned
    state (returned-state-only writer for time controls).
13. **Focused toast retires mid-interaction.** When the toast holding
    keyboard focus auto-retires, is promoted away, or tier-swaps, focus
    moves to the next visible toast (or the anchor if none remains) —
    never a dangling null focus. *(Godot does not auto-transfer focus
    from a freed Control; the handoff is explicit. This is the first
    feature requiring focus to survive dynamic Control add/remove —
    OQ7's 4.6 dual-focus verification is BLOCKING for Rule 9b's
    implementation specifically.)*

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Building System | ✅ Approved | Tool/material/height/formation/undo state + the UI Requirements contract; triggered via shared InputMap actions |
| Build Validation & Navigability | ✅ Approved | Warning/info events + why-strings + queryable state (its Rule 10); the four-item UI seam contract (its UI Requirements) — implemented by Rules 9–9c |
| Resource & Item Database | ✅ Approved | Palette contents, `visual_asset` icons, `display_name` tooltips, tier-0 rule |
| Time & Tick System | ✅ Approved | Pause/warp API + state display (resolves its Core Rule 2 UI-trigger question) |
| Camera & Input | ✅ Approved | InputMap action ownership for new bindings (Rule 12); Suspended state; raw-delta pattern |
| Scene/World Management | ✅ Approved | Hosting; Suspended during transitions |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Villager Info UI | MVP | ✅ Designed | The click-ownership rule (armed tool ⇒ Building pipeline; Idle ⇒ villager selection may claim hits — its Rule 1) (added 2026-07-10, cross-review bidirectional fix) |
| Onboarding / Tutorial | Vertical Slice | Undesigned | The toolbar as the teachable surface *(provisional)* |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `toast_max_visible` | 3 | 2–5 | Simultaneous toasts — more = noisier (Pillar 4). **Minimum 2**: keeps one slot rotating for Info in the common case; when every slot holds a Warning, Info is anchor-only until promotion frees a slot (Rule 9 — the rotating-Info slot is best-effort, not guaranteed; rationale corrected at the re-review) |
| `min_reshow_interval` | 30s | 10–120s | Dismissal debounce (Rule 9, seam item 2): how long a dismissed toast stays hidden through re-emissions. `[assumption]` until playtest |
| `warning_grace_delay` | 3s | 1–8s | First-appearance grace (Rule 9, seam item 3): how long a new issue must persist before surfacing at all. `[assumption]` until playtest |
| `invalid_cue_fade` | 1s | 0.5–2s | Duration of the at-cursor invalid marker |

*(`toast_confirm_fade` deleted 2026-07-10 — room confirmations are no
longer toasts, Rule 9d.)*

Layout anchors/sizes carry no gameplay effect — they belong to the UX
spec / art bible, not this GDD. All values data-driven per the coding
standard.

## Visual/Audio Requirements

Iconography follows the Visual Direction Note: palette icons derive from
`visual_asset` (material↔meaning color families); the blue–orange state
axis governs UI states (armed tool blue-accented, warnings orange —
never red-green). **Warning and Info toasts are differentiated by icon
SHAPE + label, never by hue or intensity alone** (the Note's §4 day-one
pairing rule — the two silhouettes are the same warning/info icon
assets Build Validation's Visual/Audio already mandates); the armed
tool pairs its blue accent with a pressed/highlight state, not hue
alone. The paused state must be visually unmistakable (e.g. icon +
subtle vignette — treatment to the art bible). Audio: subtle UI clicks
only; commit/invalid sounds are owned by the Building System, the
room-recognized chime by Build Validation (no duplication — Rule 9d).
**New assets required**: 5 tool icons, 4 roof-formation icons,
time-control icons, toast frames (2 severity tiers — warning / info),
issues-anchor icon + badge.

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
| Warning/info events, why-strings, queryable state, no-cleared-signal model, four-item seam contract | `design/gdd/build-validation-navigability.md` | Rules 8/10/11, AC 22, UI Requirements | Event contract — seam items 1–4 implemented here (Rules 9–9c); `room_recognized` deliberately NOT consumed (Rule 9d) |
| Pause/warp trigger ("Building UI/HUD") | `design/gdd/time-tick-system.md` | Core Rule 2 | **Resolved by this GDD** (Rules 1/10 — patch note there) |
| Action ownership, Suspended, raw-delta pattern | `design/gdd/camera-input.md` | Core Rules 7–10 (Rules 9–10 authored 2026-07-10) | New actions under its ownership (Rule 12) |
| Palette data (`display_name`, `visual_asset`, tier-0) | `design/gdd/resource-item-database.md` | Core Rules 4–8 | Data contract |
| Blue–orange axis, material colors | `design/art/visual-direction-note.md` | State axis | Visual constraint |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review produced 5 rewrites and 6 missing criteria; all
incorporated. The 2026-07-10 full design review rebuilt the toast model:
AC11/12 rewritten (the originals validated the seam-contract violation)
and AC27–36 added. The same-day re-review rewrote AC27 (wall-clock grace
— the re-emission wording was unsatisfiable), extended AC31/36, and
added AC37–41. Split per the project's test-evidence table: headless
unit-testable mirror/event logic is BLOCKING; rendering/viewport/layout
checks are ADVISORY (interaction test or walkthrough doc).)*

**Blocking — headless unit tests (state-mirror & event logic)**
1. **GIVEN** any tool selected in the Building System (mocked signal), **WHEN** it arrives, **THEN** the matching button highlights and all others un-highlight, same frame.
2. **GIVEN** key 1–5 pressed, **WHEN** the action fires, **THEN** the corresponding tool-select action is emitted — the UI sends intents, never sets Building state directly.
3. **GIVEN** a tool armed, **WHEN** cancel fires, **THEN** the UI returns to Idle, the context panel hides, and the previously-armed button un-highlights.
4. **GIVEN** Wall armed → palette + stepper; Roof armed → palette + 4 formation icons; Furniture armed → furniture list (`bed` only); Idle → no panel (Rule 4).
5. **GIVEN** the mocked MVP dataset, **WHEN** the palette renders, **THEN** exactly the tier-0 materials appear for placement tools and exactly `bed` for Furniture.
6. **GIVEN** a material selected for tool A, **WHEN** switching to B and back, **THEN** A's last selection is restored (session-scoped).
7. **GIVEN** the stepper at 8, **WHEN** + fires, **THEN** it stays 8; same at 1 with − (clamped display of Building's range).
8. **GIVEN** an empty undo stack (mocked), **THEN** undo is disabled; **GIVEN** a redo branch, **THEN** redo enables — mirroring only.
9. **GIVEN** N synthetic undo action-pressed events in sequence, **THEN** exactly N undo intents are emitted — none added or dropped (no debounce, no acceleration).
10. **GIVEN** an invalid-commit event, **THEN** the at-cursor cue appears and auto-fades within `invalid_cue_fade` ±10 %, blocking no input.
11. **GIVEN** a dismissed warning toast, **WHEN** its key re-emits within `min_reshow_interval`, **THEN** the toast stays hidden while its anchor entry persists; **WHEN** a qualifying re-emission arrives after the window and the cause still holds, **THEN** the toast re-shows (Rule 9 debounce — *rewritten 2026-07-10: the original AC validated the seam-contract violation*).
12. **GIVEN** `toast_max_visible` visible toasts including at least one Info, **WHEN** a new Warning arrives, **THEN** the oldest visible Info collapses into the anchor and the Warning shows; **GIVEN** every visible slot holding a Warning, **WHEN** a new Warning arrives, **THEN** no visible toast is evicted and the new Warning appears in the anchor with the badge incremented (Rule 9 overflow — warnings never evicted by severity, nothing starves).
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

**Added by design review (2026-07-10) — blocking headless (toast model rebuild + keyboard parity)**
27. **GIVEN** exactly ONE qualifying emission for a new subject (no further emissions — Build Validation is event-driven), **WHEN** `warning_grace_delay` elapses and the mocked queryable state still holds the cause, **THEN** the toast appears (wall-clock grace + state check, no re-emission required); **GIVEN** the queryable state shows the cause resolved before expiry, **THEN** no toast and no anchor entry ever appeared (Rule 9 grace — rewritten at the re-review: the original re-emission-count wording was unsatisfiable).
28. **GIVEN** a shown toast, **WHEN** its key re-emits on N successive passes, **THEN** exactly one toast instance exists throughout — no duplicate entries, no Shown→Queued cycling (Rule 9 identity/dedup).
29. **GIVEN** a shown warning whose emissions cease (cause fixed), **WHEN** the next reconcile runs, **THEN** the toast and its anchor entry are removed with no player dismissal (Edge Case 11).
30. **GIVEN** a subject whose Warning ceases while an Info begins in the same pass, **THEN** the Warning toast retires and the Info toast appears — at no point are both visible for that subject (Rule 9 tier-swap).
31. **GIVEN** any set of active issues (shown, dismissed-in-window, and overflowed), **THEN** the anchor badge equals the live issue count and the expanded list matches Build Validation's queryable state exactly — mutating upstream state directly (bypassing signals) never leaves a stale list entry (Rule 9c — no cached copy; the queryable-state schema itself is `[assumption]` until the technical spec pass).
32. **GIVEN** zero active issues, **THEN** the anchor is fully hidden — no badge, no dead chrome (Rule 9c).
33. **GIVEN** visible toasts, **WHEN** `toast_focus_cycle` then `toast_dismiss` fire, **THEN** the focused toast is dismissed with semantics identical to a click dismissal, including the debounce window (Rule 9b keyboard parity).
34. **GIVEN** a placement tool armed, **WHEN** `palette_next`/`palette_prev` fire, **THEN** the selection cycles through exactly the palette's entries, identically to clicking them (Rule 9b).
35. **GIVEN** a `room_recognized` event (mocked), **THEN** zero toast entries and zero anchor entries are created — confirmations have no HUD surface (Rule 9d).
36. **GIVEN** the InputMap at boot, **THEN** `toast_focus_cycle`, `toast_dismiss`, `toggle_issues`, `palette_next`, `palette_prev`, `formation_next`, `formation_prev`, `height_step_up`, `height_step_down` exist as registered actions (extends AC 22; Rules 9b/12).

**Added by re-review (2026-07-10) — blocking headless**
37. **GIVEN** `toast_max_visible` Warnings shown and one anchor-only Warning, **WHEN** a visible Warning retires or is dismissed, **THEN** the longest-waiting anchor-only Warning is promoted into the freed slot immediately (Rule 9 promotion); **GIVEN** the promoted candidate was previously dismissed with `min_reshow_interval` remaining, **THEN** it is skipped and the next-longest eligible key promotes instead.
38. **GIVEN** a Warning in Grace with 2s elapsed of a 3s `warning_grace_delay`, **WHEN** it tier-swaps to Info, **THEN** the Info key inherits the elapsed credit and surfaces after 1s more if the cause holds — no grace restart (Rule 9 per-subject bookkeeping; a flickering cause cannot indefinitely suppress surfacing).
39. **GIVEN** Wall armed, **WHEN** `height_step_up`/`height_step_down` fire, **THEN** the stepper changes identically to +/− button clicks within 1–8; **GIVEN** Roof armed, **WHEN** `formation_next`/`formation_prev` fire, **THEN** the formation selection cycles identically to clicking the icons (Rule 9b keyboard completion).
40. **GIVEN** a subject in Grace, **WHEN** the game is PAUSED past the remaining delay, **THEN** the expiry still fires and the queryable-state check decides surfacing — grace/debounce timers are wall-clock, frozen only by Suspended (Rule 9, Edge Case 6).
41. **GIVEN** the focused toast auto-retires or is promoted away, **THEN** keyboard focus transfers to the next visible toast, or the anchor if none — never null while any focusable notification element exists (Edge Case 13).

**Advisory — interaction test / manual walkthrough (UI evidence gate)**
23. **GIVEN** a drag begun in the world, **WHEN** the cursor enters HUD space, **THEN** the drag is NOT canceled (UI half); **WHEN** released over the HUD, **THEN** the commit uses the last valid world preview (integration with Camera & Input/Building — Edge Case 5, Rule 11's event-routing requirement).
24. **GIVEN** a toast dismissal click in a live viewport, **THEN** the click is consumed — nothing beneath receives it (Edge Case 9).
25. **GIVEN** a 1280×720 window, **THEN** the three zones' bounding rects lie fully in-viewport and do not intersect (screenshot/rect assertion — Edge Case 8).
26. **GIVEN** a first-time playtester, **THEN** tool + material found unaided in under a minute (Game Feel criterion — playtest evidence doc).

## Open Questions

1. **UX spec details** (exact layout metrics, icon design, arrangement,
   the default key bindings for the Rule 9b actions — currently
   `[assumption]`, including the Tab/`ui_focus_next` collision — and
   two onboarding beats the re-review flagged: first-time issues-anchor
   discoverability and badge-only-warning comprehension) →
   */ux-design build-hud in Pre-Production (see the UX Flag in UI
   Requirements)*
2. **Shortcut suppression when text input arrives** (Edge Case 10)
   → *Vertical Slice, with the first text field*
3. **Gamepad menu navigation** (technical-preferences: "partial, later")
   → *Alpha, shared with the Camera & Input open question*
4. **Exact toast styling per severity tier** (shape pairing committed
   in Visual/Audio; exact treatment) → *art bible*
5. **Where do future HUD elements live** (combat/wave, township)? Own
   systems slotting into these zones — → *their GDDs (VS/Alpha)*
6. **Undo repeat-velocity cap** — held-key repeat rides the OS rate
   (Rule 7); whether a max-undos-per-second cap is needed to prevent
   runaway repeat on aggressive OS settings → *MVP playtest*
7. **Godot 4.5–4.7 Control/input verification** — `mouse_filter`
   consumption semantics (Rule 11's event-routing requirement), the 4.6
   dual-focus system (**BLOCKING for Rule 9b's focus-cycling
   implementation** — Edge Case 13's explicit focus handoff depends on
   it), `InputEventKey.echo` key-repeat semantics (Rule 7/AC9), and
   4.5's AccessKit accessibility APIs postdate the model's training
   data; verify against the pinned 4.7 docs before implementing the
   HUD input layer → *Technical Setup / building ADR*
8. **Timer architecture** — **RESOLVED 2026-07-11 via ADR-0011**: a
   single centralized expiry-timestamp manager (`Dictionary[key,
   TimerRecord]` + one shared `_process` loop), not N Godot `Timer`
   nodes — chosen for zero per-timer Node-lifecycle overhead at
   potentially-dozens-of-simultaneous-subjects scale, and for direct
   consistency with Time & Tick System's own "no per-consumer timers
   anywhere" precedent. Correction to this GDD's original rationale:
   Godot's `Timer.paused` property actually DOES preserve and
   auto-resume `time_left` natively (confirmed via ADR-0011's engine
   validation) — N Timer nodes would NOT have required "fragile
   time_left reconstruction" as originally assumed here; the real
   reasons for the centralized choice are Node-overhead and
   project-precedent-consistency, not pause-fidelity (both approaches
   achieve exact pause fidelity equally well).
