# Scene/World Management

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: None directly — Foundation infrastructure that enables all pillars

## Summary

Scene/World Management owns loading, unloading, and switching between the game's
distinct play areas — starting with the single always-loaded valley scene at MVP,
and later including separate seal-dungeon scenes reached via a short loading
transition. It exists so every other system (Voxel World, Villager AI, Camera,
Building) has one consistent root to run inside, and so area transitions are
handled in one place instead of ad-hoc per-system.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `None`

## Overview

Scene/World Management is the system that loads the game world onto the screen
and manages transitions between distinct play areas. At MVP, this is minimal:
the game boots directly into the single valley/settlement scene — no menu, no
loading screen, nothing to manage yet beyond having a stable scene root that
Voxel World, Camera, and Villager AI can all attach under. From Vertical Slice
onward, this system also handles entering and leaving seal dungeons: each
dungeon is a separate scene, reached via a short loading transition, with the
valley preserved (villagers keep living, needs keep decaying) while the player
is away. This system does not decide WHAT is in a scene — it decides WHEN
scenes load, unload, and hand off control between each other.

## Player Fantasy

The player does not directly interact with, or notice, this system — and should
not. What they feel instead is the *seamlessness* it enables: the game begins
with no barrier directly in the valley, no menu standing between the player and
their first build action. Later, entering a seal dungeon should feel like a
deliberate step into the unknown (the short loading transition as a tension
beat), not a technical hiccup. Success for this system means the player never
thinks about the fact that it exists.

*(`creative-director` not consulted — Lean mode skips non-high-risk sections.)*

## Detailed Design

*(`systems-designer` / `engine-programmer` not consulted — Lean mode skips
non-high-risk sections. Review manually before production.)*

### Core Rules

1. On game launch, the engine loads and instantiates the Valley scene directly
   as the active scene — no intermediate menu or loading screen at MVP.
2. The Valley scene is the single persistent root; Foundation/Core systems that
   need a stable parent (Voxel World, Camera & Input, Time & Tick, Villager AI)
   attach as children of it and are expected to exist for the lifetime of a
   play session.
3. *(Vertical Slice+)* Entering a seal dungeon triggers a scene transition: a
   short loading transition is shown, the Dungeon scene is loaded and
   instantiated, and control (camera, input) hands off to it.
4. *(Vertical Slice+)* While the player is inside a Dungeon scene, the Valley
   scene is NOT unloaded — it continues simulating in the background (villager
   schedules, needs decay, build-over-time timers keep advancing), so time
   passes realistically in the settlement while the player is away.
5. *(Vertical Slice+)* Leaving a dungeon (exit, death/retreat, or completion)
   triggers the reverse transition: a short loading transition, the Dungeon
   scene is unloaded/freed, and control hands back to the already-running
   Valley scene at the position/state it was left in.
6. Exactly one scene has "control" (receives player input, is rendered as the
   primary view) at any time; the loading transition is the only state where
   neither scene is receiving player input.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|-----------------|-----------------|----------|
| Booting | Game launch | Valley scene finishes loading | Engine loads the Valley scene; at MVP this is near-instant with no visible loading UI |
| InValley | Booting completes, OR returning from a Dungeon | Player triggers dungeon entry | Valley scene has control; Villager AI, Needs, Building all simulate normally |
| Transitioning | Dungeon entry or exit triggered | Target scene finishes loading | Short loading transition shown; neither scene receives input; the Valley keeps simulating in the background if transitioning INTO a dungeon |
| InDungeon | Transitioning (entry) completes | Player exits/dies/completes the dungeon | Dungeon scene has control; the Valley scene keeps simulating in the background (Core Rule 4) |

### Interactions with Other Systems

- **Voxel World, Villager AI & Behavior, Building System** (Foundation/Core
  siblings): This is NOT a data dependency — it is a **hosting
  relationship**. These systems' root nodes attach structurally under the
  Valley scene this system loads. This system does not own their behavior,
  only their lifetime (when they are instantiated/destroyed as scenes
  load/unload). This is why the relationship does not appear as a
  "Depends On" edge in the systems index.
- **Camera & Input** (Foundation sibling): hosting relationship like the
  others above, PLUS a real data dependency — Camera & Input listens to the
  same transition-begin/-complete signal below to enter/exit its own
  Suspended state (no camera control or input dispatch during a transition).
  Added 2026-07-09 when `design/gdd/camera-input.md` was authored, for
  bidirectional consistency.
- **Time & Tick System** (Foundation sibling): hosting relationship, PLUS a
  real data dependency in the OPPOSITE direction from Camera & Input — THIS
  system calls Time & Tick's time-warp-reset function when a transition
  begins (see Edge Cases: "Time-warp resets to 1x for the transition").
  Time & Tick's own clock is deliberately NOT suspended by transitions (see
  `design/gdd/time-tick-system.md` Core Rule 6). Added 2026-07-09 for
  bidirectional consistency.
- **Save/Load & World Persistence** (downstream, Vertical Slice tier): needs a
  moment where world state is stable. Interface: this system emits a signal
  when a transition begins and when it completes; Save/Load listens to it as a
  natural savepoint (e.g., autosave before dungeon entry).
- **Dungeon System** (Vertical Slice+, Feature layer): the Dungeon System
  defines WHAT is inside a dungeon; this system only handles loading/unloading
  the dungeon scene and the transition. Ownership boundary: Dungeon System =
  content, Scene/World Management = scene lifecycle.

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section even in
Lean mode.)*

This system owns no calculations. It governs scene lifecycle and timing, not
simulation math — needs decay belongs to Needs & Mood, the tick itself belongs
to Time & Tick System. The loading transition is a fixed config value (see
Tuning Knobs), not a formula. The background-simulation decision (real-time,
not catch-up) specifically means the Valley runs at the same cost profile
whether the player is looking at it or not — there is no dual-scene budget to
compute. If a hard performance ceiling on running two scenes simultaneously
turns out to be a real constraint, that is a `technical-director` profiling
question, not a design formula (see Open Questions).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| A transition is triggered while one is already in progress (double-trigger) | The second trigger is ignored until the first completes | Prevents overlapping/broken transitions |
| The target scene fails to load (missing file, error) | Transition aborts, an error is shown, player remains in the currently-loaded (source) scene | Never leave the player in a state with no active scene |
| Player triggers a transition while actively in build-placement mode | The in-progress placement is cleanly cancelled (no incomplete/invalid blocks left behind), then the transition begins | Prevents an inconsistent build state across the scene swap |
| Time-warp is active when a transition begins | Time-warp resets to 1x for the transition and the opening moment of the target scene; must be manually re-engaged in the new scene | Prevents disorientation on entry (e.g., a dungeon entrance rushing by at high warp speed) |
| No valid dungeon scene currently exists for an entry trigger (e.g., content not yet available) | No transition begins; the player gets feedback that entry isn't currently possible | Prevents loading a non-existent scene |
| Simulation during the loading transition itself (the brief loading-screen moment) | The Valley simulation does NOT pause — it runs continuously through the transition overlay; only camera/input hand off | Simplest rule: continuous simulation from boot through return, no special "paused while loading" case |

*(Save/Load does not exist until Vertical Slice — so there is no edge case here for
"game closed while InDungeon"; that belongs in the Save/Load & World Persistence GDD
once it is designed.)*

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|----------------------|
| Time & Tick System | This system depends on | Calls the time-warp-reset function on transition begin (data/event dependency, added 2026-07-09 for bidirectional consistency with `design/gdd/time-tick-system.md`) |
| Save/Load & World Persistence | Depended on by | Listens for transition-begin/-complete signals as save points (data/event dependency) |
| Camera & Input | Depended on by | Hosting relationship PLUS listens for transition-begin/-complete signals to enter/exit its own Suspended state (data/event dependency, added 2026-07-09 for bidirectional consistency with `design/gdd/camera-input.md`) |
| Voxel World / Grid Data System | Depended on by (structural) | Attaches as a child under the scene this system loads (hosting, not data — intentionally not a formal index edge) |
| Time & Tick System | Depended on by (structural) | Same hosting relationship |
| Villager AI & Behavior | Depended on by (structural) | Same hosting relationship |
| Building System | Depended on by (structural) | Same hosting relationship |
| Dungeon System | Depended on by (Vertical Slice+) | Defines dungeon scene content; this system only handles load/unload lifecycle |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------------|------------|---------------------|---------------------|
| `loading_transition_duration` | 1.2s | 0.5s – 3.0s | Builds more anticipation (the "step into the unknown" feel from Player Fantasy), but risks feeling sluggish since there's no other loading in the game | Feels snappier, but risks an abrupt cut that undermines the tension beat |

*(Only one knob — this system is deliberately thin; the actual decay/balance
values belong to the systems that own them, not here.)*

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|------------------|-----------------|----------|
| Transition begins — entering dungeon | Overlay fades in with a cool rim-light/fog tint (Visual Direction Note §2c "stakes as weather") | Short tension stinger, distinct from Valley ambience | Must Have (Vertical Slice) |
| Transition begins — returning to Valley | Overlay fades in with a warm amber tint (Visual Direction Note §2a "warm-light-as-reward") | Short warm/relief cue | Must Have (Vertical Slice) |
| Transition completes | Overlay fades out over ~0.2–0.3s, revealing the target scene | Target scene's ambient audio bed fades in | Must Have (MVP for the boot moment; Vertical Slice for dungeons) |
| Game boot (MVP) | No overlay — direct cut/fade into the Valley (Core Rule 1) | Valley ambient bed starts | Must Have (MVP) |

📌 **Asset Spec** — Once the art bible is approved, run
`/asset-spec system:scene-world-management` to derive overlay/transition
assets from this section.

## Game Feel

### Feel Reference

Should feel like a deliberate, brief curtain-draw — present enough to register
as a meaningful boundary between "home" and "danger," but never long enough
to feel like waiting. NOT a jarring instant cut (would undercut the tension
beat from Player Fantasy). NOT a slow multi-second load screen (breaks the
game's cozy, unhurried pacing in the wrong direction — this should read as
anticipation, not friction).

### Input Responsiveness / Animation Feel Targets / Impact Moments

N/A — no player input occurs during a transition (see Core Rule 6). These
tables apply to systems with active player input during the moment being
described; this system has none during its own transition state.

### Weight and Responsiveness Profile

Unhurried but purposeful (matches the 1.2s default tuning value); always
resolves predictably — the player should never suspect the game has frozen
(the overlay shows visible progress throughout).

### Feel Acceptance Criteria

- [ ] Playtesters do not describe the transition as "jarring" or "too slow"
      unprompted (in addition to Acceptance Criterion 12, which sets the
      measurable performance bound).

## UI Requirements

| Information | Display Location | Update Frequency | Condition |
|--------------|-------------------|-------------------|-----------|
| Loading transition overlay | Full-screen overlay | Once per transition | During the Transitioning state |
| Load-failure error message | Full-screen or toast overlay | On failure only | Edge Case: target scene fails to load |

> **📌 UX Flag — Scene/World Management**: This system has UI requirements
> (the transition overlay and error message). In Phase 4 (Pre-Production),
> run `/ux-design` to create a UX spec for this before writing epics. Stories
> referencing this UI should cite `design/ux/[screen].md`, not this GDD directly.

## Cross-References

| This Document References | Target GDD | Specific Element Referenced | Nature |
|---------------------------|-----------|-------------------------------|--------|
| "transition-begin/-complete signals used as save points" | `design/gdd/save-load-world-persistence.md` (not yet authored) | Transition signal timing | Ownership handoff |
| "dungeon scene content is owned by Dungeon System" | `design/gdd/dungeon-system.md` (not yet authored) | Scene content vs. lifecycle boundary | Rule dependency |

*(Both target GDDs do not exist yet — marked as provisional assumptions, to be
cross-checked when each is authored.)*

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean mode.
Verdict: GAPS on first draft → 2 missing criteria added, Core Rule 6 coverage
tightened, performance criterion split and given measurable thresholds.)*

1. **GIVEN** the game is launched, **WHEN** the boot sequence completes, **THEN**
   the Valley scene is active and receiving player input with no menu or
   loading screen shown (MVP). *[Integration]*
2. **GIVEN** the Valley scene has loaded, **WHEN** inspected, **THEN** Voxel
   World, Camera & Input, Time & Tick System, and Villager AI & Behavior are
   children of the Valley root and remain valid for the entire play session.
   *[Integration]*
3. **GIVEN** the player is in the Valley scene, **WHEN** they trigger dungeon
   entry (Vertical Slice+), **THEN** a loading transition plays for
   `loading_transition_duration` ± 0.1s, the Dungeon scene becomes active, and
   Valley input is suspended. *[Integration]*
4. **GIVEN** the player is fully inside a Dungeon scene, **WHEN** input is
   checked, **THEN** the Valley scene receives zero player input while the
   Dungeon scene has full control. *[Integration]*
5. **GIVEN** the player is inside a Dungeon scene, **WHEN** time passes,
   **THEN** the Valley scene's simulation (villager schedules, needs decay,
   build timers) continues advancing in real time, verifiable by comparing
   Valley state immediately before entry and immediately after return.
   *[Integration]*
6. **GIVEN** the player exits/dies/completes the dungeon, **WHEN** that
   happens, **THEN** a loading transition plays, the Dungeon scene is freed
   from memory, and control returns to the Valley scene in the exact state
   (position, simulation state) it was left in. *[Integration]*
7. **GIVEN** a scene transition is in progress, **WHEN** a second is
   triggered, **THEN** the second trigger is ignored until the first
   completes. *[Integration]*
8. **GIVEN** the target scene fails to load, **WHEN** a transition is
   attempted, **THEN** it aborts, an error is shown, and the player remains in
   the source scene with full control. *[Integration]*
9. **GIVEN** the player is in active build-placement mode, **WHEN** a
   transition is triggered, **THEN** the in-progress placement is cleanly
   cancelled with no invalid blocks left behind. *[Integration]*
10. **GIVEN** time-warp is active, **WHEN** a transition begins, **THEN**
    time-warp resets to 1x for the transition and the opening moment of the
    target scene. *[Integration]*
11. **GIVEN** no dungeon scene is available for the target, **WHEN** entry is
    triggered, **THEN** no transition begins and the player receives feedback
    that entry isn't possible. *[Integration]*
12. **Performance** *(two separate, measurable criteria, DEFERRED — require a
    full build + profiling)*:
    a. A scene load completes within `loading_transition_duration` + 0.1s
       tolerance.
    b. After the transition overlay is dismissed, none of the next 30 frames
       exceeds baseline frame time by more than 50%.
13. No hardcoded values in implementation — transition duration and other
    tunables are read from data/config, not literals in code.
    *[Config/Data, Advisory]*

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Is there a hard performance ceiling on running two full scenes (Valley + Dungeon) simultaneously that requires design mitigation (e.g., LOD/pausing off-screen systems)? | technical-director | Before Vertical Slice implementation begins | — |
| What is the exact visual treatment of the loading transition (fade, iris, narrative text, etc.)? | art-director | During art bible / `/asset-spec` | — |
| Once Save/Load exists, does boot always go to a fixed Valley scene, or to a saved game state? | systems-designer (Save/Load GDD) | When Save/Load & World Persistence GDD is authored | — |
