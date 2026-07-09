# Villager AI & Behavior

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: Pillar 2 — A settlement that feels alive (primary); Pillar 1 — The building IS the game (villagers construct and inhabit what the player builds)

## Summary

Villager AI & Behavior owns everything a villager *does*: perceiving the
world, choosing an activity (build, sleep, eat, wander), pathing to it, and
performing it. It is the labor half of the game's two central loops — it
consumes the Building System's construction-job queue to physically build
what the player plans, and it consumes needs (from the Needs & Mood System)
to make villagers live in what gets built. It runs on Time & Tick's game
time, reads Voxel World for physical occupancy, and is bounded by a
deliberate population ceiling of 20–30 concurrent villagers so every
villager can stay an individual with a name, a routine, and (later) a
story — never an anonymous crowd.

> **Quick reference** — Layer: `Core/Gameplay` · Priority: `MVP` · Key deps: `Voxel World, Time & Tick System` · Population ceiling: 20–30 (Full Vision)

## Overview

**Player-facing:** villagers are the game's proof of life (Pillar 2) and
the payoff of Pillar 1: the player never controls them directly — they are
the "unseen steward's" wards. The player builds; villagers claim the work,
walk to the site, hammer blocks into existence, then move into the finished
home, sleep in the bed, and visibly live a daily rhythm. Every emotion the
concept promises — pride, care, emergent stories — is delivered through
watching these agents behave believably. The 20–30 ceiling is a design
choice, not (only) a technical one: it keeps each villager legible as a
person, matching the concept's named-villager/diaries/bonds vision.

**System-facing:** this system is an agent runtime. Each villager is an
autonomous agent that repeatedly: evaluates available activities (a
construction job from the Building System's queue, a need to satisfy, an
idle behavior), commits to one, paths to its target through Voxel World's
physical occupancy, performs it over game ticks, and re-evaluates on
completion or interruption. This GDD owns activity selection, movement,
job-claim mechanics (confirming the Building System's provisional
contract), interruption/abandon semantics, and the villager's observable
day rhythm. It does NOT own: what needs exist and how they decay (Needs &
Mood System), whether a structure is livable (Build Validation &
Navigability), what jobs exist (Building System owns its queue), or combat
behavior (Squad & Combat, Vertical Slice+).

The MVP slice is deliberately tiny: ONE villager, ONE need (sleep), the
construction-job loop, and the move-into-home moment — exactly the
concept's MVP hypothesis ("watch a villager move in and live there").

## Player Fantasy

**"They live because of what I built — and they'd be lost without me."**

An indirect but central fantasy: the player never issues a command to a
villager, yet everything a villager does reflects the player's stewardship.
Three beats:

1. **Watching them work.** The wall I planned is being *built by someone* —
   a small figure walks over, hammers, and the block turns real. My intent
   passes through their hands (delivers the construction half of Pillar 1;
   the Building System's "construction has weight" feel claim is fulfilled
   HERE, by visible labor).
2. **Watching them live.** At dusk the villager stops working, walks home,
   and sleeps in the bed I placed. The settlement has a pulse that keeps
   beating when I'm not steering — the concept's core fantasy of
   "stewardship of a place that feels alive."
3. **Being needed.** When something is wrong — no bed, an unreachable
   build spot — the villager's visible state (wandering at night, orange
   pulsing ghost) tells me *I* am the one who can fix their world. Care,
   not control.

Reference feeling: Stonehearth's hearthlings and RimWorld's colonists —
autonomous wards whose visible routines create attachment. NOT the fantasy:
an RTS unit (no direct orders), a Sims puppet (no possession), or an
anonymous crowd sim (the 20–30 ceiling exists precisely so no villager is
ever "one of thousands").

> `creative-director` not consulted — Lean mode (non-high-risk section).
> Sourced from game-concept.md Core Fantasy ("unseen steward") + MDA table
> (Fellowship = between villagers, vicarious). Review manually before
> production.

## Detailed Design

### Core Rules

**Agent loop**

1. Every villager is an autonomous agent running one loop: **decide →
   travel → perform → re-evaluate**. Decisions and work progress happen on
   game tick events; visible movement interpolates continuously using game
   delta (so motion is smooth but stops dead while paused — consistent
   with Time & Tick's rules).
2. **Activity selection is a strict priority list** (MVP):
   1. Urgent need — a need below its urgency threshold (threshold values
      owned by the Needs & Mood GDD; MVP: sleep only)
   2. Work — an available construction job (Building System queue)
   3. Idle — wander near the settlement (never leaves the world bounds)
   The list is re-evaluated when an activity completes, when interrupted,
   and periodically every `decision_interval` ticks so an urgent need can
   preempt long work.
3. **Preemption is graceful, never abrupt**: when an urgent need preempts
   work, the villager finishes the current cell's in-progress tick, then
   releases its job claim back to the queue and pursues the need. This
   defines the "graceful abandon" the Building System's Edge Case 7
   references — from this side of the contract.

**Job claiming (confirms the Building System's Core Rule 12 contract)**

4. One job (one blueprint cell) per villager at a time. A villager
   selects the **nearest reachable available job** by path distance (the
   Building System's queue order is availability/tie-breaking only —
   proximity choice is explicitly allowed by that contract). Claiming
   locks the job; no other villager may claim it until released.
5. **On site** = the villager occupies the job's target cell or an
   orthogonally adjacent cell (including directly above/below), exactly as
   the Building System defines. Work progress accrues only while on site.
6. **Unreachable jobs**: if pathing to a job fails, the villager reports
   the failure to the Building System (which turns the ghost orange, its
   Edge Case 5), releases the claim, and tries the next-nearest job. All
   villagers retry unreachable jobs every `unreachable_retry_ticks` (this
   GDD owns the cadence the Building System listed as provisional).
7. **Nudge-aside** (Building System Edge Case 6): when a builder's target
   cell is occupied by another character, the builder requests a vacate.
   An idle or wandering occupant steps to the nearest walkable adjacent
   cell within one tick; an occupant mid-activity (working, sleeping) is
   NOT interrupted — the builder's cell stays deferred until free. A
   villager never nudges another builder off a claimed job.

**Movement and walkability**

8. Villagers move cell-to-cell on walkable surfaces. A cell is
   **standable** iff: the cell below is solid (terrain or Built block —
   blueprints are non-solid per the Building System's Core Rule 14b), and
   the cell itself plus the two cells above are empty
   (`villager_clearance` = 3 cells, registered constant). *Consequence:
   the Building System's default `wall_height` of 3 yields exactly the
   minimum walkable interior height — a standard room is walkable with no
   headroom to spare; lowering wall height below 3 makes the interior
   unwalkable.*
9. A step between adjacent standable cells is legal if the height
   difference is at most 1 cell (natural block staircases work; 2+ cliffs
   don't). Orthogonal steps only; a diagonal is legal only when both
   flanking orthogonal cells are also passable (no corner-cutting through
   walls). No jumping, swimming, or climbing in MVP.
10. These walkability rules are THE definition Build Validation &
    Navigability later checks against — that system asks "can a villager
    (per these rules) reach X?", it does not define its own movement.

**Home and sleep (MVP's move-in moment)**

11. Beds have owners: the first villager to need sleep claims an unowned,
    reachable bed permanently (one bed = one owner). Claiming a bed IS the
    "move-in" moment — the MVP hypothesis's payoff.
12. A villager whose sleep need is urgent goes to its owned bed (or claims
    one, Rule 11). If no reachable bed exists, the villager sleeps on the
    ground where it stands at reduced recovery (values owned by the Needs
    GDD) — visibly worse off, telling the player exactly what's missing
    (Player Fantasy Beat 3: being needed).
13. Sleeping ends when the need is restored above its wake threshold
    (Needs GDD's value); the villager then re-enters the decision loop.

**Population**

14. The population ceiling is 20–30 concurrent villagers at Full Vision
    (MVP: exactly 1; Vertical Slice: ~5 per the concept). This ceiling is
    a design commitment (individual legibility, Pillar 2), and the
    performance budget assumes it. *Spawning/recruiting new villagers is
    owned by Township Progression (Alpha) — not this system.*

### States and Transitions

**Agent state machine** (per villager):

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Deciding | Loop start, activity end, interruption, preemption | Activity chosen (same tick) | Runs the priority list (Rule 2); instantaneous — never a visible "stand and think" pause |
| Traveling | Activity chosen with a distant target | Arrival on site / target invalidated / preemption | Follows the computed path cell-by-cell; re-paths if a Voxel World write blocks the path |
| Working | Arrived at claimed job, on site | Cell Built / job revoked / preemption | Applies tick progress to the claimed cell (Building System F3); plays work animation/sound |
| Sleeping | Arrived at owned bed (or ground fallback) with urgent sleep need | Wake threshold reached / bed removed under them | Restores sleep need per tick (rates owned by Needs GDD) |
| Wandering | Decided Idle | Any higher-priority activity appears (checked every `decision_interval` ticks) | Ambles between nearby standable cells; pure flavor, no gameplay effect |

*(No "Suspended" state: villagers live in the Valley and keep simulating
during scene transitions and dungeon excursions — Scene/World Management's
Core Rule 4. Villagers pause only when game time pauses.)*

### Interactions with Other Systems

- **Building System** (MVP, mutual — THE central seam): consumes its
  construction-job queue under the contract its Core Rule 12 defines;
  this GDD CONFIRMS that contract (Rules 4–7 above) and supplies the
  provisional halves it listed: claim mechanics, on-site presence,
  unreachable reporting + retry cadence, graceful abandon, nudge-aside.
  Its GDD's "PROVISIONAL" markers on the job contract can be considered
  resolved once this GDD is approved.
- **Time & Tick System** (upstream, MVP): decisions/work/need-recovery on
  tick events; movement interpolation on game delta; everything halts in
  pause and accelerates under warp. Never touches raw delta.
- **Voxel World** (upstream, MVP): reads physical occupancy for
  walkability (Rules 8–9) and listens to write signals to re-path when
  the world changes mid-travel. Never mutates the grid (construction
  writes go through the Building System).
- **Needs & Mood System** (MVP sibling, undesigned — PROVISIONAL): defines
  which needs exist, decay rates, urgency/wake thresholds, and recovery
  rates. This GDD only consumes "need X is urgent" signals and reports
  recovery activity. Its GDD must confirm this interface.
- **Build Validation & Navigability** (MVP, downstream): consumes the
  walkability definition (Rules 8–10) as its ground truth for
  reachability/livability checks.
- **Villager Info UI** (MVP, downstream): displays villager name, current
  activity, and need levels — all state it shows lives here or in Needs.
- **Scene/World Management** (Foundation, upstream): villagers simulate
  continuously through transitions (no Suspended state); hosted in the
  Valley scene.
- **Save/Load & World Persistence** (Vertical Slice, downstream,
  provisional): serializes per-villager state (position, current activity,
  claimed job id, owned bed, need levels via Needs GDD).
- **Squad & Combat / Wave Defense** (Vertical Slice, downstream,
  provisional): recruits able villagers into squads — out of scope here;
  flagged so the seam isn't forgotten.

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section even
in Lean mode. Review produced 3 revisions and 1 added formula; all
incorporated.)*

### F1 — Travel time

`travel_time_game_seconds = path_length_cells / move_speed`

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `path_length_cells` | float | ≥ 0 | Steps in the computed cell path; orthogonal step = 1.0, diagonal = 1.4. `0` is valid (target is the current/adjacent cell, Rule 5) → immediate arrival |
| `move_speed` | float | 1.5–6.0, default 3.0 | Cells per game-second. Game-time invariant: warp accelerates wall-clock travel proportionally, never the game-time cost |

Example: a 12-step path at 3.0 → 4.0 game-seconds; at 2x warp = 2.0
wall-clock seconds.

**Arrival/tick-boundary rule**: movement interpolates on game delta, so
arrival routinely happens between ticks. Working state is entered
immediately on arrival (visually), but the first work-progress increment
is credited at the NEXT tick boundary — no partial-tick credit, ever.
(Cross-reference: Building System F3 consumes this rule; without it,
effective build times would drift by up to one tick per job.)

### F2 — Job selection

`chosen_job = argmin(path_length_cells)` over available reachable jobs;
tie-break by queue order (older commit first).

**Approximation contract** (required for implementations to converge):
candidates are pre-filtered to the nearest `job_candidate_count` (default
5) by straight-line (Chebyshev) distance; only those are true-path
checked; if all fail reachability, the next `job_candidate_count` are
tried, and so on. "Nearest" therefore formally means: *nearest true-path
job among the straight-line-nearest candidates* — deterministic and
bounded, never a full-queue pathfind.

### F3 — Wander target selection

`wander_target = ` a uniformly chosen cell from the set produced by a
**bounded flood-fill** of standable, reachable cells within
`wander_radius` (default 8) of the current position; re-picked every
`wander_interval` ticks (default 6). Flood-fill guarantees reachability
by construction (no island targets, no post-hoc path validation).

**Determinism contract**: the random source is injected (dependency
injection per coding standards) — production uses the live RNG;
tests inject a fixed-sequence instance through the same interface, so
wander tests are deterministic without seeding globals.

### F4 — Nudge-aside target selection

`vacate_target = argmin(height_difference, then Chebyshev distance to
requester)` over standable cells orthogonally adjacent to the occupant;
tie-break by a fixed scan order (N, E, S, W). Deterministic — the same
situation always produces the same step. If no adjacent standable cell
exists, the vacate request fails and the builder's cell stays deferred
(Building System Edge Case 6).

### Deliberately NOT formulas (and why)

- **The pathfinding algorithm** (A*, flow fields, hierarchical) —
  architecture, deferred to the AI ADR; this GDD only defines the
  walkability rules (Core Rules 8–9) any algorithm must respect.
- **Need decay/recovery rates, thresholds, ground-sleep penalty** — owned
  by the Needs & Mood GDD (Core Rules 12–13 reference, never define).
- **Construction progress per tick** — Building System F3.
- **`decision_interval`, `unreachable_retry_ticks`** — authored config
  values (Tuning Knobs), no computation.

## Edge Cases

1. **Path blocked mid-travel** (world changed while walking). The villager
   re-paths from its current cell. If the target is now unreachable: for a
   job — report to the Building System (orange ghost), release the claim,
   pick the next job (F2); for a bed — fall back to ground sleep (Rule 12);
   for a wander target — pick a new one (F3).
2. **Villager completely walled in** (no legal step from its cell). The
   villager stays put — **villagers never teleport, clip, or despawn to
   escape**. It idles in place with a visible distress cue (treatment via
   Villager Info UI / art bible); urgent sleep falls back to ground sleep
   in place. The player resolves it by removing blocks. *(A trapped
   villager is always the player's own construction — consistent with the
   unreachable-blueprint philosophy: visible, patient, player-fixable.)*
3. **Two villagers race for the same job.** Claims are atomic: exactly one
   succeeds; the loser's F2 selection simply proceeds to its next
   candidate. No error state, no double-work.
4. **Job revoked mid-work** (player undo/removal — Building Edge Case 7).
   The villager stops at the current tick boundary, plays no failure
   reaction (the world simply changed), and re-enters Deciding. Its claim
   bookkeeping is cleared by the revocation itself.
5. **Bed removed while the villager sleeps in it** (Building Edge Case
   11). The villager wakes immediately, its bed ownership dissolves, and
   it re-enters Deciding — typically resuming sleep on the ground (reduced
   recovery) or claiming another free bed if one is reachable.
6. **Bed removed while owned but unoccupied.** Ownership dissolves
   silently; the villager claims a new bed the next time sleep becomes
   urgent (Rule 11).
7. **All available jobs unreachable.** Every job gets reported (Building
   System shows orange on each); the villager falls through the priority
   list to Wandering. Retries continue every `unreachable_retry_ticks`.
8. **No standable wander cell in radius** (flood-fill returns only the
   current cell). The villager stays in place until the next
   `wander_interval` re-pick — visually a calm pause, not an error.
9. **Tick burst (up to `max_ticks_per_frame = 10`).** Per villager: at
   most one decision re-evaluation per processed tick, work progress per
   the Building System's per-villager burst rule, need recovery per tick.
   A burst never lets a villager make 10 contradictory decisions in one
   frame — decisions consider state as of each processed tick in order.
10. **Player is in a dungeon (scene transition).** Villagers keep
    simulating in the Valley in real time — building, sleeping, wandering
    (Scene/World Management Core Rule 4). The player returns to visible
    progress, not a freeze-frame.
11. **Save/Load mid-activity** (Vertical Slice, provisional). Serialized
    claimed-job ids and bed ownership are re-validated on load; a claim
    whose job no longer exists dissolves and the villager re-enters
    Deciding. Never crash on a stale reference.
12. **MVP degenerate case: zero jobs, zero urgent needs.** The single
    villager wanders indefinitely — this is the correct, calm baseline
    state of an idle settlement, not a bug. (It is also the first thing a
    player sees before building anything: a villager waiting for a home.)

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Voxel World | ✅ Designed | Physical occupancy reads for walkability (Rules 8–9); write signals for mid-travel re-pathing. Never mutates the grid |
| Time & Tick System | ✅ Designed | Tick events (decisions, work, need recovery) + game delta (movement interpolation); pause/warp semantics |
| Building System | ✅ Designed (In Review) | The construction-job queue and its Core Rule 12 contract — this GDD confirms it and supplies the AI halves (Rules 3–7) |
| Needs & Mood System | ✅ Designed (2026-07-10) | Which needs exist, urgency/wake thresholds, decay and recovery rates (incl. the ground-sleep penalty) — **interface CONFIRMED** by needs-mood-system.md (urgency=25, satisfied=95, ground_penalty=0.4 — registered constants) |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Build Validation & Navigability | MVP | Undesigned | The walkability definition (Rules 8–10) as ground truth for reachability *(provisional)* |
| Needs & Mood System | MVP | Undesigned | Activity state (what the villager is doing) to apply recovery; mutual seam with the upstream row *(provisional)* |
| Villager Info UI | MVP | Undesigned | Villager name, current activity/state, distress cues *(provisional)* |
| Professions & Ranks | Alpha | Undesigned | The activity-selection layer professions plug into *(provisional)* |
| Relationships & Bonds | Alpha | Undesigned | Villager identity + proximity/interaction events *(provisional)* |
| Township Progression | Alpha | Undesigned | Population (spawning/recruiting is ITS job, bounded by the 20–30 ceiling) *(provisional)* |
| Squad & Combat / Wave Defense | Vertical Slice | Undesigned | Recruits able villagers into squads *(provisional)* |
| Save/Load & World Persistence | Vertical Slice | Undesigned | Per-villager state serialization (position, activity, claimed job id, owned bed) *(provisional)* |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `move_speed` | 3.0 cells/game-second | 1.5–6.0 | Travel pacing (F1). Too fast: villagers feel skittish/insect-like; too slow: construction stalls on travel time and the settlement feels sluggish |
| `decision_interval` | 2 ticks (= 1.0s at 1x) | 1–10 | How often urgent needs can preempt long activities (Rule 2). Lower = more responsive, more re-evaluation cost |
| `unreachable_retry_ticks` | 20 (= 10s at 1x) | 10–120 | Retry cadence for unreachable jobs (Rule 6 — the value the Building System's Tuning Knobs listed as provisional; owned here) |
| `wander_radius` | 8 cells | 3–16 | How far idle villagers roam (F3). Larger = livelier settlement but villagers drift farther from future jobs |
| `wander_interval` | 6 ticks (= 3s at 1x) | 2–20 | How often a wander target is re-picked (F3) |
| `job_candidate_count` | 5 | 3–10 | F2's pre-filter width. Larger = closer to a true global "nearest" at more pathfinding cost |
| Population ceiling | 20–30 (Full Vision) | design commitment, not a slider | MVP: 1, Vertical Slice: ~5. Raising it beyond 30 invalidates the per-agent AI assumption AND the Pillar-2 individual-legibility promise — treat as a design change, not a tune |

All values data-driven per the coding standard; none are player-facing.

## Visual/Audio Requirements

**Visual** (specs to the art bible; requirements set here):
- **Activity legibility** (Pillar 4): a viewer must be able to read a
  villager's current state at a glance — distinct silhouettes/animations
  for walking, working (hammering toward the target cell), sleeping
  (lying down; simple zzz-cue acceptable), and wandering (relaxed gait).
- **Distress cue** for trapped/ground-sleeping villagers (Edge Case 2,
  and Rule 12's ground sleep) — visible but gentle, cozy-not-alarming
  (Pillar 3); exact treatment to the art bible.
- **Movement smoothness**: continuous interpolation between cells (F1) —
  a villager must never visibly teleport or snap cell-to-cell.
- **New assets required** (MVP): one villager model + walk, work, sleep,
  idle animation sets — the largest single asset dependency of the MVP.

**Audio** (MVP-light):
- Work loop (rhythmic hammering while Working — pairs with the Building
  System's per-cell completion tick), soft footsteps, an optional gentle
  sleep cue. Ambient village bed is the Audio System's job (Alpha).

## Game Feel

**Feel reference**: Stonehearth hearthlings — unhurried, purposeful,
watchable. The test: a player who zooms in on a villager for 30 seconds
should feel calm and informed, never confused about what it's doing.

- **No visible hesitation**: Deciding is instantaneous (state table) — a
  villager finishes hammering and *walks off with purpose*. Dead frames
  between activities read as "dumb AI" and are a feel bug.
- **Movement**: smooth game-delta interpolation; pause freezes mid-stride
  (correct and expected under Time & Tick's rules); warp visibly speeds
  walking without animation glitches.
- **Work rhythm**: hammer beats align with tick progress on the claimed
  cell, so construction audibly/visibly ticks toward completion — the
  Building System's "construction has weight" claim is delivered by this
  animation-to-progress lockstep.
- **Feel acceptance criteria** (subjective, playtest-verified): a
  first-time observer can narrate what the villager is doing without UI
  help; nobody describes villager motion as "teleporting" or "jittery";
  the move-in moment (first bed claim + sleep) reads as a small story
  beat, not a state change.

## UI Requirements

None owned — this system renders no UI. It supplies to the Villager Info
UI (MVP, downstream): villager name, current state (Deciding/Traveling/
Working/Sleeping/Wandering as player-readable labels), current need levels
(values via Needs GDD), and distress flags (trapped, ground-sleeping,
no-bed). The UI renders and never owns.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| Construction-job contract (per-cell jobs, on-site, parallel claims) | `design/gdd/building-system.md` | Core Rule 12, Edge Cases 5–7, F3 burst rule | Mutual contract — this GDD CONFIRMS it and fills the AI halves |
| Blueprints non-solid until Built; occupancy authority split | `design/gdd/building-system.md` | Core Rule 14b | Walkability input (Rules 8–9) |
| Tick events, game delta, pause/warp, max_ticks_per_frame | `design/gdd/time-tick-system.md` | Core Rules, Formulas | Time base for the whole agent loop |
| Physical occupancy reads, write signals | `design/gdd/voxel-world.md` | Core Rules 5–6 | Walkability + re-path triggers |
| Valley never pauses during transitions | `design/gdd/scene-world-management.md` | Core Rule 4 | Why there is no Suspended state here |
| Need definitions, thresholds, recovery rates | `design/gdd/needs-mood-system.md` (not yet authored) | Needs interface | PROVISIONAL |
| Walkability as validation ground truth | `design/gdd/build-validation-navigability.md` (not yet authored) | Rules 8–10 | PROVISIONAL |
| Population ceiling resolution (20–30) | `design/gdd/game-concept.md` + `design/gdd/systems-index.md` | Open Question / high-risk flag | Resolved BY this GDD (patches in Phase 5) |
| `bed` item, `ticks_per_second`, `max_ticks_per_frame`, `cell_size` | `design/registry/entities.yaml` | Registry facts | Data dependency |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review produced 3 rewrites and 6 missing criteria; all incorporated.
Needs & Mood values are mocked at the "need is urgent" boundary per the
testing standards — those ACs do NOT wait for that GDD.)*

**Decision loop**
1. **GIVEN** an urgent need and an available job, **WHEN** deciding, **THEN** the need is chosen (Rule 2 priority).
2. **GIVEN** an available job and no urgent need, **WHEN** deciding, **THEN** the job is chosen over wandering.
3. **GIVEN** no jobs and no urgent needs, **WHEN** deciding, **THEN** the villager wanders — indefinitely and without error (Rule 2, Edge Case 12).
4. **GIVEN** a Working villager whose need becomes urgent, **WHEN** the `decision_interval` re-check fires, **THEN** the current tick's work completes, the claim is released, and the need is pursued (Rule 3 graceful preemption).
5. **GIVEN** any activity ends, **WHEN** Deciding runs, **THEN** the next state is assigned within the same tick invocation — Deciding never consumes an additional tick.

**Jobs and construction**
6. **GIVEN** multiple available jobs, **WHEN** selecting, **THEN** the nearest-by-true-path among the straight-line-nearest `job_candidate_count` candidates is chosen; ties break by older commit (F2).
7. **GIVEN** all `job_candidate_count` nearest candidates fail the true-path check, **WHEN** selecting, **THEN** the next `job_candidate_count` candidates are evaluated in turn, deterministically — never a full-queue pathfind (F2 fallback).
8. **GIVEN** a claimed job, **WHEN** another villager attempts to claim it, **THEN** the claim fails atomically and the loser selects its next candidate (Edge Case 3).
9. **GIVEN** pathing to a claimed job fails, **WHEN** the failure registers, **THEN** it is reported to the Building System, the claim is released, and the next candidate is tried (Rule 6).
10. **GIVEN** an unreachable job, **WHEN** `unreachable_retry_ticks` elapse, **THEN** a retry attempt occurs (Rule 6).
11. **GIVEN** every available job reports unreachable in the same Deciding pass, **WHEN** the priority list completes, **THEN** the villager falls through to Wandering — never stuck in Deciding — and retries resume on cadence (Edge Case 7).
12. **GIVEN** a villager not in the target or an orthogonally adjacent cell, **WHEN** ticks fire, **THEN** no work progress accrues; **GIVEN** on-site, **THEN** it accrues (Rule 5).
13. **GIVEN** arrival between two ticks, **WHEN** Working begins, **THEN** the first progress increment is credited at the next tick boundary — never partially (F1 arrival rule).

**Movement and walkability**
14. **GIVEN** a cell without 3-cell vertical clearance (`villager_clearance`), **WHEN** standability is evaluated, **THEN** it is not standable (Rule 8).
15. **GIVEN** two adjacent standable cells with height difference 1, **WHEN** stepping, **THEN** the step is legal; **GIVEN** difference ≥ 2, **THEN** illegal (Rule 9).
16. **GIVEN** a diagonal step whose flanking orthogonal cells are blocked, **WHEN** pathing, **THEN** the diagonal is not used (Rule 9).
17. **GIVEN** a Planned blueprint cell in the path, **WHEN** pathing, **THEN** the cell is treated as passable (Building Core Rule 14b).
18. **GIVEN** a Voxel World write blocks the current path mid-travel, **WHEN** the write signal fires, **THEN** the villager re-paths from its current cell (Edge Case 1).
19. **GIVEN** a Traveling villager whose target becomes invalid before arrival (bed destroyed, job voided) with no re-path possible, **WHEN** detected, **THEN** it exits to Deciding and re-selects — never keeps traveling toward a dead target (state table).
20. **GIVEN** any frame during travel, **WHEN** position is sampled, **THEN** per-frame displacement never exceeds `move_speed × game_delta` (no teleporting).
21. **GIVEN** pause, **WHEN** real time passes, **THEN** position is unchanged; **GIVEN** 2x warp, **THEN** wall-clock travel halves while game-time cost is constant (F1 invariance).

**Sleep and home**
22. **GIVEN** a first urgent sleep need and an unowned reachable bed, **WHEN** deciding, **THEN** the villager claims that bed permanently (move-in, Rule 11).
23. **GIVEN** an owned reachable bed and urgent sleep, **WHEN** deciding, **THEN** the villager sleeps in its own bed.
24. **GIVEN** no reachable bed and urgent sleep, **WHEN** deciding, **THEN** the villager sleeps on the ground at its current cell with the reduced-recovery flag set (Rule 12; rates mocked).
25. **GIVEN** the sleep need restored above the wake threshold (mocked), **WHEN** the tick fires, **THEN** the villager wakes and re-enters Deciding (Rule 13).
26. **GIVEN** a bed removed while the villager sleeps in it, **WHEN** the removal registers, **THEN** the villager wakes immediately and ownership dissolves (Edge Case 5).
27. **GIVEN** an owned but unoccupied bed removed, **WHEN** the removal registers, **THEN** ownership dissolves and a new bed is claimed at the next urgent sleep (Edge Case 6).

**Wandering**
28. **GIVEN** any wander target selection, **WHEN** evaluated, **THEN** the target is reachable by construction — never an island cell (F3 flood-fill).
29. **GIVEN** wander targets over time, **WHEN** sampled, **THEN** all lie within `wander_radius` and world bounds (F3).
30. **GIVEN** an injected fixed-sequence random source, **WHEN** wandering runs twice from the same state, **THEN** the wander paths are identical (F3 determinism).
31. **GIVEN** a flood-fill wander search returning only the current cell, **WHEN** `wander_interval` elapses, **THEN** the villager stays in place without error and re-attempts at the next interval (Edge Case 8).

**Lifecycle and edge behavior**
32. **GIVEN** a villager with no legal step from its cell, **WHEN** any game time passes, **THEN** it remains in place with the distress flag set and never teleports (Edge Case 2).
33. **GIVEN** a job revoked mid-work, **WHEN** the revocation registers, **THEN** the villager stops at the tick boundary and re-enters Deciding without error (Edge Case 4).
34. **GIVEN** an idle occupant in a builder's target cell, **WHEN** the vacate request fires, **THEN** the occupant steps to the F4 target within one tick; **GIVEN** a Working/Sleeping occupant, **THEN** it is not interrupted (Rule 7).
35. **GIVEN** a vacate-target tie on height difference and distance, **WHEN** resolved, **THEN** the fixed N/E/S/W scan order breaks the tie identically every run (F4 determinism).
36. **GIVEN** a tick burst of `max_ticks_per_frame`, **WHEN** processed, **THEN** at most one decision re-evaluation occurs per processed tick, in order (Edge Case 9).
37. **GIVEN** a scene transition (player to dungeon), **WHEN** it completes, **THEN** villager activities continue uninterrupted in the Valley (Edge Case 10).
38. **[PROVISIONAL — Save/Load undesigned, VS tier]** **GIVEN** a deserialized claimed-job or bed-owner id that no longer exists, **WHEN** load completes, **THEN** the stale claim dissolves and the villager enters Deciding — never crashes (Edge Case 11; testable now against a mocked serializer contract).
39. **[PROVISIONAL — milestone-gated]** **GIVEN** the Vertical Slice population (~5) and the Full Vision ceiling (30), **WHEN** simulating at 1x and 3x warp, **THEN** the 16.6ms frame budget is maintained — enforced at those milestones, never a blocker for MVP Done (population ceiling).

## Open Questions

1. **Needs & Mood interface confirmation** — **RESOLVED 2026-07-10**:
   `needs-mood-system.md` confirms the interface — edge-triggered "need
   urgent"/"need satisfied" signals (urgency_threshold=25,
   satisfied_threshold=95), source-scored recovery (bed 1.0 / ground 0.4
   via ground_penalty), all three now registered constants.
2. **AI architecture** — behavior tree vs. utility layer vs. plain FSM per
   agent. The 20–30 ceiling explicitly permits deep per-agent AI; the
   choice is architectural, not design. → *AI ADR via `/create-architecture`*
3. **Pathfinding algorithm + re-path storm cost** — algorithm choice, and
   whether N villagers re-pathing on every Voxel World write signal needs
   throttling/batching at scale. → *AI ADR + the performance spike before
   Vertical Slice*
4. **Day/night rhythm** — the concept's "day schedules" (work by day,
   sleep by night) layers on top of the need-driven MVP. Requires a
   day/night clock nobody owns yet (Time & Tick extension?). → *Needs &
   Mood or Professions GDD, Alpha; flag to Time & Tick when scheduled*
5. **Villager identity generation** — names, appearance variation,
   personality seeds (feeds diaries/bonds later). Who owns it and when?
   → *narrative-director / world-builder, Vertical Slice*
6. **Distress cue treatment** — exact visual for trapped/ground-sleeping
   villagers (Edge Case 2, Rule 12). → *art bible + Villager Info UI GDD*
7. **Villager behavior during waves** — flee, hide, keep working?
   → *Wave Defense GDD, after the `/prototype wave-defense` spike*
