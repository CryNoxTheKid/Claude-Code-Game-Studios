# Scene/World Management

> **Status**: In Review (revised three times 2026-07-10 — re-review #2 NEEDS REVISION, all 8 blockers fixed in-session, re-review #3 pending)
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
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

1. On game launch, the engine loads and instantiates the **World Root** (Core
   Rule 2) as the active scene; World Root then attaches the Valley scene as
   its child during boot — no intermediate menu or loading screen at MVP.
   World Root's own initialization is the boot gate where the Edge-Case
   boot-order requirement (Resource & Item Database Ready before dependents)
   is enforced. *(REVISED 2026-07-10 re-review #2: the prior wording "loads
   the Valley scene directly as the active scene" was leftover pre-fix text —
   it contradicted Core Rule 2's World Root topology and left no engine-level
   gate point for the AC17 boot-halt.)*
2. A thin, persistent **World Root** container node — owned by this system,
   alive for the entire process lifetime — anchors the scene tree. The
   Valley scene attaches under it at boot and persists for the whole play
   session; *(Vertical Slice+)* Dungeon scenes attach as SIBLINGS of the
   Valley under the same World Root *(REVISED 2026-07-10 re-review: the
   old wording "the Valley scene is the single persistent root"
   contradicted Core Rule 4's two-simultaneously-live-scenes requirement —
   Godot has one `current_scene` and no native two-roots concept, so the
   hosting container must be named; its implementation detail goes to the
   scene-management ADR)*. Foundation/Core systems that need a stable
   parent (Voxel World, Camera & Input, Time & Tick, Villager AI, Building
   System, Building UI, Villager Info UI — the full hosted list, matching
   the Dependencies table) attach as children of the Valley scene and are
   expected to exist for the lifetime of a play session.
   **Engine guardrail** *(added 2026-07-10 re-review #2)*: the scene handoff
   MUST NOT be implemented via `SceneTree.change_scene_to_file()`,
   `change_scene_to_packed()`, or `reload_current_scene()` — these replace
   the engine's single `current_scene` wholesale and would destroy the
   persistent World Root this rule requires. Dungeon entry/exit is
   add/remove of child scenes under World Root, never a current-scene swap.
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
   Valley scene at the position/state it was left in. **Return-cue mapping**
   *(made explicit 2026-07-10 re-review #2 — user decision: 3 buckets)*:
   each leave-reason maps to its own return cue in Visual/Audio
   Requirements — **completion** → victory amber; **voluntary exit**
   (player chooses to leave mid-run, unforced) → neutral cue, neither
   triumph nor defeat; **death/retreat** (defeated or forced withdrawal) →
   muted "limping home". The sharp enum definition of exit-vs-retreat
   (what counts as "forced") is owned by the Dungeon System GDD.
6. Exactly one scene has "control" (receives player input, is rendered as the
   primary view) at any time; the loading transition is the only state where
   neither scene is receiving player input.
7. **Side-effect discipline — the three-signal contract** *(added 2026-07-10
   re-review; EXTENDED at re-review #2 with the transition-ABORT signal,
   closing the abort soft-lock: with only begin/complete, a failed load left
   reversible begin-effects — camera Suspended, UI hidden — with no signal
   that unwinds them, freezing all input permanently)*. A transition has two
   signals covering three outcomes; every consumer binds by effect class:
   - **transition-begin** — reserved for REVERSIBLE presentation/suspension
     effects (camera Suspended, UI hiding, overlay fade-in). Consumers MUST
     NOT bind irreversible state changes to begin.
   - **transition-complete** — fires ONLY on success. Irreversible reactions
     (Building's undo-stack clear, Save/Load's savepoint) bind here. It also
     ends the reversible begin-effects on the success path (camera resumes
     in the target scene, UI reappears).
   - **transition-abort** — fires ONLY on failure (load error). EVERY
     reversible begin-effect MUST unwind on abort: camera exits Suspended in
     the source scene, UI reappears, the overlay fades out. No irreversible
     effect ever fired (they bind to complete), so there is nothing to roll
     back — abort leaves no trace and restores full control.
   Exactly one of complete/abort fires per begin, exactly once. The
   double-trigger debounce (Edge Cases) releases on EITHER of them — never
   on complete alone.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|-----------------|-----------------|----------|
| Booting | Game launch | Valley scene finishes loading — OR the Resource & Item Database fails to reach Ready, which exits to a boot-error HALT (error screen shown, the Valley is never attached; see Edge Case "Boot ordering" and AC17 — formal failure-exit added 2026-07-10 re-review #2, mirroring Transitioning's) | World Root loads first (Core Rule 1) and attaches the Valley scene once foundation data reports Ready; at MVP this is near-instant with no visible loading UI |
| InValley | Booting completes, OR returning from a Dungeon | Player triggers dungeon entry | Valley scene has control; Villager AI, Needs, Building all simulate normally |
| Transitioning | Dungeon entry or exit triggered | Target scene finishes loading (transition-COMPLETE fires) — OR the load FAILS: transition-ABORT fires, which exits back to the source state (InValley/InDungeon) with an error shown, every reversible begin-effect unwound (camera/UI restored), and no irreversible side effect fired (Core Rule 7 three-signal contract; abort signal added 2026-07-10 re-review #2) | Short loading transition shown; neither scene receives input; the Valley keeps simulating in the background if transitioning INTO a dungeon |
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
  transition signals: it enters Suspended on transition-begin and exits
  Suspended on transition-complete OR transition-abort (whichever fires —
  Core Rule 7; abort listener added 2026-07-10 re-review #2 so a failed
  load can never strand the camera in Suspended). No camera control or
  input dispatch during a transition. Added 2026-07-09 when
  `design/gdd/camera-input.md` was authored, for bidirectional consistency.
- **Time & Tick System** (Foundation sibling): hosting relationship, PLUS a
  real data dependency in the OPPOSITE direction from Camera & Input — THIS
  system has NO direct call into Time & Tick *(REVISED 2026-07-10: the
  former time-warp-reset call was removed — warp persists across
  transitions, see Edge Cases)*. All transition effects reach consumers
  exclusively via the transition-begin/-complete signals — there are no
  direct-call side effects, so no call-vs-signal ordering exists to race.
  Time & Tick's own clock is deliberately NOT suspended by transitions (see
  `design/gdd/time-tick-system.md` Core Rule 6). Added 2026-07-09 for
  bidirectional consistency.
- **Save/Load & World Persistence** (downstream, Vertical Slice tier): needs a
  moment where world state is stable. Interface: this system emits the
  transition-begin/-complete/-abort signals (Core Rule 7); Save/Load binds
  its savepoint to transition-COMPLETE only (irreversible effect class —
  never to begin, and abort must leave no savepoint).
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
| The target scene fails to load (missing file, error) | The transition-ABORT signal fires (Core Rule 7): every reversible begin-effect unwinds (camera exits Suspended, UI reappears, overlay fades out), an error is shown, and the player remains in the currently-loaded (source) scene with FULL control restored. Because irreversible side effects bind only to transition-complete, the abort leaves NO trace: the undo stack, savepoints, and all consumer state are exactly as before the trigger *(strengthened 2026-07-10 re-review; abort-unwind added at re-review #2 — previously the suspension had no defined recovery path on failure)* | Never leave the player in a state with no active scene, never freeze input after a failed load, and never let a failed transition destroy state |
| Player triggers a transition while actively in build-placement mode | The transition begins; the transition-begin signal drives Camera & Input into Suspended, which propagates to the Building System and REACTIVELY aborts the in-progress placement — nothing is committed, no incomplete/invalid blocks left behind *(REVISED 2026-07-10 re-review #2: the prior "cancelled, THEN the transition begins" ordering contradicted building-system.md's reactive Suspended mechanism — this GDD now defers to that model; the aborted drag is a reversible begin-effect per Core Rule 7: if the transition itself aborts, the drag stays cancelled, which is recoverable — the player simply re-starts it)* | Prevents an inconsistent build state across the scene swap, with ONE owner for the cancel mechanism (Building's Suspended reaction), not two orderings |
| Time-warp is active when a transition begins | **Time-warp PERSISTS unchanged across the transition and the visit** — it is global game state this system never touches *(REVISED 2026-07-10 review: the earlier reset-to-1x created an irreversible warp trap — Building UI, the sole owner of the warp controls, does not exist in dungeon scenes, so "manually re-engage" was impossible until return; and the background Valley would have silently dropped to 1x against the player's set speed)* | Warp is a player setting, not scene state; the Valley keeps simulating at the chosen speed (Core Rule 4 coherence). What warp MEANS inside a dungeon (does combat run at 3x? is there a warp control there?) and what an unattended high-warp Valley may suffer during a long run are OPEN design questions owned by the future Dungeon System / Squad & Combat GDDs — see Open Questions *(re-review 2026-07-10: replaced an earlier hand-wave that dismissed this as "a presentation concern")* |
| No valid dungeon scene currently exists for an entry trigger (e.g., content not yet available) | No transition begins; the player gets feedback that entry isn't currently possible | Prevents loading a non-existent scene |
| Simulation during the loading transition itself (the brief loading-screen moment) | The Valley simulation does NOT pause — it runs continuously through the transition overlay; only camera/input hand off | Simplest rule: continuous simulation from boot through return, no special "paused while loading" case |
| A transition is triggered while the game is PAUSED (Time & Tick pause active) | Allowed — the transition overlay animates on raw delta (UI-level, like the camera); the pause state persists unchanged through the transition, exactly like warp *(added 2026-07-10 review)* | Pause is a player setting, not scene state; transitions are presentation, not simulation |
| Boot ordering (MVP) | The Booting state completes only after foundation data systems report ready — concretely, the Resource & Item Database must reach its Ready state before the Valley scene's dependent systems (Building, Villager AI) initialize *(added 2026-07-10 review; the DB's GDD defers the full boot-order mechanism to a boot-order ADR — this row records the design requirement that ADR must satisfy)*. **Failure behavior** *(added at re-review)*: if the DB fails to reach Ready (load error/timeout), boot HALTS on an error screen — the game never opens a Valley with an empty palette | A scene whose systems boot before their data layer is ready would read an empty palette; failing loudly at boot beats failing confusingly in-game |

*(Save/Load does not exist until Vertical Slice — so there is no edge case here for
"game closed while InDungeon"; that belongs in the Save/Load & World Persistence GDD
once it is designed.)*

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|----------------------|
| Time & Tick System | (no direct dependency — REVISED 2026-07-10) | The former time-warp-reset call was removed; warp persists across transitions as global game state. Rows retained for history/bidirectional consistency with `design/gdd/time-tick-system.md` |
| Building System | Depended on by | Clears its undo stack on the transition-COMPLETE signal (its Core Rule 17 — REVISED at the 2026-07-10 re-review from transition-begin: clearing on begin wiped undo even when a failed load aborted the transition; see Core Rule 7 side-effect discipline) |
| Save/Load & World Persistence | Depended on by | Listens for the transition-COMPLETE signal as a savepoint (per Core Rule 7, irreversible effects never bind to begin; exact savepoint policy is that GDD's decision when authored) |
| Camera & Input | Depended on by | Hosting relationship PLUS listens for the transition signals: Suspended entered on begin, exited on complete OR abort (Core Rule 7 three-signal contract; abort listener added 2026-07-10 re-review #2 — data/event dependency, 2026-07-09, bidirectional with `design/gdd/camera-input.md`) |
| Voxel World / Grid Data System | Depended on by (structural) | Attaches as a child under the scene this system loads (hosting, not data — intentionally not a formal index edge) |
| Time & Tick System | Depended on by (structural) | Same hosting relationship |
| Villager AI & Behavior | Depended on by (structural) | Same hosting relationship |
| Building System | Depended on by (structural) | Same hosting relationship |
| Dungeon System | Depended on by (Vertical Slice+) | Defines dungeon scene content; this system only handles load/unload lifecycle |
| Building UI | Depended on by (structural) | Hosting; hides/suspends via the Suspended propagation (added 2026-07-10, cross-review bidirectional fix) |
| Villager Info UI | Depended on by (structural) | Hosting; same Suspended propagation (added 2026-07-10, cross-review bidirectional fix) |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------------|------------|---------------------|---------------------|
| `loading_transition_duration` | 1.2s | 0.5s – 3.0s | Builds more anticipation (the "step into the unknown" feel from Player Fantasy), but risks feeling sluggish since there's no other loading in the game | Feels snappier, but risks an abrupt cut that undermines the tension beat |

*(Only one knob — this system is deliberately thin; the actual decay/balance
values belong to the systems that own them, not here. VS tuning note, added
at re-review #2: one shared duration currently paces three emotionally
distinct return beats (amber/neutral/muted — Core Rule 5); whether "limping
home" wants different pacing than triumph is a VS tuning question — split
the knob per-beat only if playtests demand it. The AC12 thresholds are
test-harness tolerances, not tuning knobs, and intentionally do not appear
here.)*

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|------------------|-----------------|----------|
| Transition begins — entering dungeon | Overlay fades in with a cool rim-light/fog tint (Visual Direction Note §2c "stakes as weather") | Short tension stinger, distinct from Valley ambience | Must Have (Vertical Slice) |
| Transition begins — returning to Valley after COMPLETION | Overlay fades in with a warm amber tint (Visual Direction Note §2a "warm-light-as-reward") — reserved for completion only *(narrowed 2026-07-10 re-review #2, user decision: 3 buckets)* | Short warm/relief cue | Must Have (Vertical Slice) |
| Transition begins — returning to Valley after VOLUNTARY EXIT (unforced mid-run leave) | Neutral tint — neither the reward amber nor the defeat mute; a plain "coming home" *(added 2026-07-10 re-review #2: a mid-run bail-out is neither triumph nor defeat — mapping per Core Rule 5)* | Plain, unadorned return cue | Must Have (Vertical Slice) |
| Transition begins — returning to Valley after death/retreat | Muted, desaturated-neutral tint — "limping home," NOT the reward amber *(split 2026-07-10 re-review: a defeated return getting the victory cue is ludonarrative dissonance; tint spec → `/asset-spec`, consistent with §2 of the Visual Direction Note's state axis)* | Quiet, somber cue; no relief sting | Must Have (Vertical Slice) |
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
   loading screen shown. *[Integration, MVP]*
2. **GIVEN** the Valley scene has loaded, **WHEN** inspected, **THEN** Voxel
   World, Camera & Input, Time & Tick System, and Villager AI & Behavior are
   children of the Valley root (itself under the persistent World Root, Core
   Rule 2) and remain valid for the entire play session.
   *[Integration, MVP]*
3. **GIVEN** the player is in the Valley scene, **WHEN** they trigger dungeon
   entry, **THEN** a loading transition begins, the Dungeon scene becomes
   active on completion, and Valley input is suspended for the duration —
   timing tolerance is tested only in AC12a *(split per the 2026-07-10
   review)*. *[Integration, VS+]*
4. **GIVEN** the player is fully inside a Dungeon scene, **WHEN** input is
   checked, **THEN** the Valley scene receives zero player input while the
   Dungeon scene has full control. *[Integration, VS+]*
5. **GIVEN** the player is inside a Dungeon scene, **WHEN** time passes,
   **THEN** the Valley scene's simulation (villager schedules, needs decay,
   build timers) continues advancing in real time, verifiable by comparing
   Valley state immediately before entry and immediately after return.
   *[Integration, VS+]*
6. **GIVEN** the player exits/dies/completes the dungeon, **WHEN** that
   happens, **THEN** a loading transition plays, the Dungeon scene is freed
   from memory, and control returns to the Valley with player position and
   camera state restored to pre-entry values, while simulation state
   (needs, schedules, timers) reflects elapsed real time per AC5 — NOT a
   snapshot restore *(reworded 2026-07-10: "exact state" contradicted Core
   Rule 4's continuous simulation)*. *[Integration, VS+]*
7. **GIVEN** a scene transition is in progress, **WHEN** a second is
   triggered, **THEN** the second trigger is ignored until the first
   completes. *[Logic, VS+]* *(re-tiered from Integration at the
   2026-07-10 review — pure state-machine debounce, unit-testable; the
   re-tier was claimed then but only actually applied at the re-review)*
8. **GIVEN** the target scene fails to load, **WHEN** a transition is
   attempted, **THEN** the transition-ABORT signal fires exactly once (and
   transition-complete does not fire), an error is shown, and the player
   remains in the source scene with full control — specifically, Camera &
   Input has exited Suspended and the UI is visible again (the reversible
   begin-effects unwound per Core Rule 7; abort-unwind assertion added
   2026-07-10 re-review #2). *[Integration, VS+]*
9. **GIVEN** the player is in active build-placement mode, **WHEN** a
   transition is triggered, **THEN** the in-progress placement is cleanly
   cancelled with no invalid blocks left behind. *[Integration, VS+]*
10. **GIVEN** time-warp is set to Nx (for each N in {1, 2, 3}) before dungeon
    entry, **WHEN** the warp value is sampled at (a) transition-begin,
    (b) entry-transition-complete, (c) after the test harness has
    deterministically advanced the Time & Tick System by at least 10
    in-game seconds' worth of ticks (20 ticks at `ticks_per_second`=2.0 —
    driven tick advancement, NOT a wall-clock sleep; determinism fix at
    re-review #2), and (d) return-transition-complete, **THEN** all four
    samples equal N — this system never touches the warp value.
    *[Integration, VS+]* *(Rewritten at the 2026-07-10 re-review:
    the prior text was grammatically malformed and sampled only transition
    boundaries; checkpoint (c) proves persistence through the stay.)*
11. **GIVEN** no dungeon scene is available for the target, **WHEN** entry is
    triggered, **THEN** no transition begins and the player receives feedback
    that entry isn't possible. *[Integration, VS+]*
12. **Performance** *(two separate, measurable criteria; [Performance,
    Advisory, milestone-gated] — DEFERRED, require a full build +
    profiling. "Performance" is an advisory evidence class, not one of the
    5 canonical blocking test types; the numeric thresholds below are
    TEST-HARNESS CONSTANTS — tolerances, not gameplay tuning knobs, hence
    deliberately absent from Tuning Knobs — noted at re-review #2)*:
    a. A scene load completes within `loading_transition_duration` + 0.1s
       tolerance. *[VS+]*
    b. After the transition overlay is dismissed, none of the first 30
       frames exceeds the NEW scene's own settled steady-state baseline by
       more than 50% — baseline = the average frame time over frames 60–90
       after transition-complete in the same target scene, measured on
       min-spec target hardware *(baseline methodology REVISED at
       re-review #2: the prior pre-transition baseline compared different
       scene content — a legitimately heavier Dungeon would have failed as
       a false-positive hitch)*. *[VS+]*
13. No hardcoded values in implementation — transition duration and other
    tunables are read from data/config, not literals in code.
    *[Config/Data, Advisory, VS+]* *(scope tag added at re-review #2 — the
    sole tunable this AC governs, `loading_transition_duration`, only
    applies to VS+ transitions; this was the missed tag that falsified the
    prior "all 18 tagged" claim)*

*(Scope-tag note: every AC above and below carries its tag INLINE — [MVP]
gates MVP Done, [VS+] never does. Fixed at the 2026-07-10 re-review; the
prior revision stated the tags only in this paragraph while the inline
markers were missing, which qa-lead correctly flagged as unusable.)*

14. **GIVEN** the Transitioning state is active (overlay visible), **WHEN** Valley simulation is inspected mid-transition, **THEN** villager schedules/needs/build timers are advancing unpaused (Core Rule 4 during the overlay itself, distinct from AC5's before/after check). *[Integration, VS+]*
15. **GIVEN** a return-to-Valley transition completes, **WHEN** input and the scene tree are checked ONE FRAME after the transition-complete signal (allowing Godot's deferred `queue_free()` to settle — tolerance added at the 2026-07-10 re-review), **THEN** the Dungeon scene no longer exists and the Valley receives full input — the symmetric counterpart to AC4. *[Integration, VS+]* *(PROVISIONAL pending the open "scene-teardown signal ordering" question (Open Questions) — the one-frame tolerance bakes in an assumed answer; revisit when the scene-management ADR resolves that OQ — flagged at re-review #2)*
16. **GIVEN** the game is paused (Time & Tick), **WHEN** a transition is triggered, **THEN** the overlay animates on raw delta, the transition completes normally, and the pause state is unchanged afterward (Edge Case: transition-while-paused). *[Integration, VS+]*

**Added by the 2026-07-10 re-review (split/reworked at re-review #2):**
17. Boot order *(split into a/b at re-review #2 — the two behaviors need different test setups)*:
    a. **GIVEN** the Resource & Item Database reaches Ready during boot, **WHEN** the Building System and Villager AI initialize, **THEN** both initialize only after DB-Ready is observed (boot-order Edge Case). *[Integration, MVP]*
    b. **GIVEN** the Resource & Item Database fails to reach Ready, **WHEN** boot runs, **THEN** boot halts on an error screen and the Valley scene is never attached/made active — no empty-palette Valley (Booting failure-exit, States table). *[Integration, MVP]*
18. Abort leaves no trace *(split into a/b at re-review #2: "bit-identical" was not operationally testable, and Save/Load does not exist yet)*:
    a. **GIVEN** the Building System's undo stack holds ≥1 command, **WHEN** a transition is triggered and ABORTS on load failure, **THEN** the undo stack is unchanged by deep-equality of its serializable state — same command count, same order, same per-command parameter data (NOT a literal memory/bit comparison) — no irreversible side effect fired on transition-begin (Core Rule 7). *[Integration, VS+]*
    b. **GIVEN** Save/Load savepoints exist, **WHEN** a transition aborts, **THEN** no savepoint was created by the aborted transition. *[Integration, VS+ — DEFERRED pending the Save/Load & World Persistence GDD; cannot be a live gate against an undesigned system]*
19. **GIVEN** the player enters a dungeon, **WHEN** the scene tree is inspected while InDungeon, **THEN** the Dungeon scene is attached as a SIBLING of the Valley scene under the persistent World Root — NOT as a child of Valley — and the World Root node is the same instance that existed at boot (Core Rule 2 topology; regression guard added at re-review #2 — this exact structure was re-review #1's blocker). *[Integration, VS+]*
20. **GIVEN** each of the three return reasons (completion / voluntary exit / death-retreat), **WHEN** the return transition begins, **THEN** the overlay uses that reason's cue from Visual/Audio Requirements (amber / neutral / muted respectively — Core Rule 5 mapping); evidence: screenshot per reason + lead sign-off. *[Visual/Feel, Advisory, VS+ — advisory per project testing standards; added at re-review #2 as the regression guard for the return-cue split]*

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Is there a hard performance ceiling on running two full scenes (Valley + Dungeon) simultaneously that requires design mitigation (e.g., LOD/pausing off-screen systems)? | technical-director | Before Vertical Slice implementation begins | — |
| What is the exact visual treatment of the loading transition (fade, iris, narrative text, etc.)? | art-director | During art bible / `/asset-spec` | — |
| Once Save/Load exists, does boot always go to a fixed Valley scene, or to a saved game state? | systems-designer (Save/Load GDD) | When Save/Load & World Persistence GDD is authored | — |
| Scene-teardown signal ordering: must the transition-complete signal fire strictly AFTER the old scene's `queue_free()` settles (teardown-emitted signals vs listeners)? *(2026-07-10 review)* | technical-director | Scene-management section of `/create-architecture` | — |
| Backgrounded-Valley integrity: the Valley must NEVER leave the SceneTree while backgrounded (orphaned nodes do not process — the real Godot risk; visibility does not gate processing, and SceneTree.paused is already forbidden project-wide). What partitioning does the two-live-scenes structure need for WorldEnvironment, Camera3D.current, audio listeners, Valley 3D-ambience bleed-through, **NavigationServer3D maps** (shared World3D = shared nav map: RVO avoidance crosstalk between backgrounded Valley villagers and active dungeon squad), **input routing** (Godot delivers `_input`/`_unhandled_input` tree-wide — Core Rule 6's "one scene has control" is manual code discipline under a shared World3D; SubViewports would isolate input for free), and GI probe/lighting bleed — shared World3D (Jolt physics/audio crosstalk) vs. separate SubViewports (compositing cost)? *(Reframed at the 2026-07-10 re-review; nav-map, input-routing, and GI facets added at re-review #2)* | technical-director | Scene-management ADR + the pre-VS performance spike | — |
| Does time-warp apply INSIDE dungeon-scene content (does combat run at 3x?), and if dungeons run at fixed 1x, how is that gated without a warp control existing there? This GDD only guarantees the warp VALUE persists untouched; its meaning per scene is undecided. *(2026-07-10 re-review, from the warp-persistence fix)* | game-designer | Dungeon System / Squad & Combat GDD authoring | — |
| Unattended-Valley safety: during a long dungeon run at high warp, the Valley simulates for potentially hours of game time with zero player visibility or agency — is a needs floor, alert system, or return summary required to protect the Pillar-2 stewardship fantasy? *(2026-07-10 re-review)* | game-designer | Dungeon System GDD authoring, before Vertical Slice | — |
| Boot-order mechanism (Resource & Item Database Ready before dependents — see the new Edge Case row) | technical-director | Boot-order ADR via `/create-architecture` | — |
| Repeat-visit transition fatigue: dungeons are repeatable, but every entry/exit pays the full fixed-duration ceremony — does the Nth re-run need a shortened/skippable transition to protect the "never a hiccup" Player Fantasy? *(2026-07-10 re-review #2)* | game-designer | Dungeon System GDD authoring | — |
| Boot performance budget: Core Rule 1's "near-instant" boot is an assumption, not a budget — if DB load ever exceeds a threshold (slow disk, grown data), is a minimal loading affordance required instead of an unexplained frozen window? *(2026-07-10 re-review #2)* | technical-director | Boot-order ADR / pre-VS performance spike | — |
