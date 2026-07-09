# Build Validation & Navigability

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
> **Implements Pillar**: Pillar 4 — Clarity over complexity (visible validity, legible warnings); Pillar 1 — The building IS the game (rooms gain meaning); Pillar 3 — Cozy, but with stakes (gentle guidance, never blocking)

## Summary

Build Validation & Navigability is the game's structural analyst: it
watches what the player builds (via the Building System's
construction-completed signals) and answers two questions the builder
systems deliberately don't — *"is this a room?"* (enclosure detection:
floor, walls, roof) and *"can a villager actually get there?"*
(reachability, using Villager AI's exact walkability rules —
`villager_clearance` = 3, `max_step_height` = 1, registered constants).
It never blocks anything (Building System Core Rule 10); it recognizes,
confirms, and gently warns: a completed room earns its "shelter" status,
and a walled-in bed earns a visible, fixable warning instead of silent
villager failure.

> **Quick reference** — Layer: `Feature/Gameplay` · Priority: `MVP` · Key deps: `Building System, Villager AI & Behavior`

## Overview

**Player-facing:** this system is how the game *understands* what the
player built. Its two player-visible outputs are a confirmation and a
warning. The confirmation: when walls, floor, and roof close around a
space with a usable way in, the game recognizes "a room" — the concept's
core loop payoff ("complete a house — shell → furnish → villager moves
in") gets its formal moment. The warning: when something the villagers
need is unreachable (a bed sealed behind walls, per the no-doors MVP), a
gentle, non-modal cue appears — complementing the Building System's
orange unreachable-*blueprint* ghosts (its Edge Case 5) with the
completed-structure half the review flagged as its Open Question 7. Per
Pillar 4 the player always sees WHY something is invalid; per Pillar 3
the tone is guidance, never punishment; per Core Rule 10 of the Building
System, nothing is ever prevented — the player may build "wrong" freely.

**System-facing:** this is a pure analysis layer — it owns no world
data and mutates nothing. It consumes: the Building System's
construction-completed/removed signals and combined planned-occupancy
view, Voxel World's physical occupancy, and Villager AI's walkability
definition (consumed verbatim, never redefined — its Rule 10). It
produces: room/enclosure status, per-object reachability status, and
the signals the Villager Info UI and Needs display build on. Analysis
runs incrementally on structure-change events, not per frame.

Out of scope: pathfinding itself (Villager AI / AI ADR), blocking or
auto-correcting placements (never — Building Core Rule 10), the
NavigationServer3D/rebake implementation question (building ADR), and
whether enclosure affects need recovery values (a design decision made
in Section C, with the value table owned by Needs & Mood).

## Player Fantasy

**"The game sees what I made."**

An indirect fantasy of *recognition and gentle stewardship support*:

1. **Being understood.** I pile up walls, a floor, a roof — and the game
   says "that's a room." My creation isn't just blocks to the simulation;
   it has *meaning*. (The formal delivery of Pillar 1's promise that
   building carries function.)
2. **The completion beat.** The moment the last roof block settles and
   the room registers is a micro-payoff on the way to the concept's core
   loop peak ("complete a house... villager moves in") — recognition
   makes finishing feel *official*.
3. **A helpful eye, not a hall monitor.** When I've accidentally sealed
   the bed in, the game quietly points instead of scolding or stopping
   me. I stay the author; the game is a considerate assistant. NOT the
   fantasy: a building-code inspector (blocking), a nagging tutorial, or
   a puzzle validator with pass/fail states.

Reference feeling: Stonehearth's room detection ("this is now a
bedroom") and The Sims' room recognition — both make enclosure feel
meaningful without policing it.

> `creative-director` not consulted — Lean mode (non-high-risk section).
> Sourced from game-concept.md core loop + Pillars 1/3/4. Review manually
> before production.

## Detailed Design

### Core Rules

**Room detection (the no-doors MVP definition)**

1. A **candidate interior cell** is an air cell with a solid cell directly
   above it (roof — at any height within `max_room_height`, default 8) and
   a solid cell directly below (built floor or terrain). A **candidate
   region** is a maximal orthogonally-connected set of candidate interior
   cells.
2. A candidate region is a **valid room** iff: it has at least
   `min_room_cells` (default 2) interior cells, AND at least one
   villager-walkable connection to the outside world exists (per Villager
   AI's exact walkability rules — `villager_clearance` = 3,
   `max_step_height` = 1, consumed verbatim). The MVP's "door" is simply a
   walkable gap in the walls; Vertical Slice doors will formalize these
   openings without changing this definition.
3. A candidate region with NO walkable connection to the outside is a
   **sealed space** — never a room. If it contains furniture, it raises
   the sealed-space warning (Rule 8); if empty, it is silently ignored
   (players may build solid decorative masses freely).
4. Room detection confers no persistent identity in MVP — rooms are
   re-derived facts about the world, not named objects. (Room
   naming/assignment is a future feature, see Open Questions.)

**Shelter status and the recovery ladder**

5. A piece of furniture is **sheltered** iff its cell lies inside a valid
   room; otherwise it is **unsheltered**. This flag is this system's one
   mechanical output.
6. The sleep recovery ladder consumes the flag: **sheltered bed = 1.0 ·
   unsheltered bed = `unsheltered_bed_multiplier` (0.7) · ground =
   `ground_penalty` (0.4)**. The rate values remain owned by the Needs &
   Mood GDD's source→rate table (this GDD supplies only the
   sheltered/unsheltered classification — its table gains one row,
   patched with permission). This is Pillar 1 made literal: the *room* is
   worth +30% sleep quality over the bare bed.
7. Analysis is **event-driven, never per-frame**: re-evaluation of the
   affected region runs when the Building System signals a construction
   completed or a built cell removed (its batched signals bound the event
   rate). Between events, all statuses are stable. MVP analyzes **built
   structures only** — blueprint-stage unreachability is already covered
   by the Building System's orange ghosts (its Edge Case 5).

**Warnings and confirmations (never blocking)**

8. Three player-facing outputs, all non-modal, severity-tiered:
   - **Confirmation** (positive): a candidate region becomes a valid room
     → the "room recognized" moment (one-shot celebration cue +
     persistent subtle status).
   - **Warning — sealed space with furniture**: furniture exists in a
     sealed space → persistent gentle warning naming the problem ("the
     bed can't be reached — the room has no opening").
   - **Info — unsheltered bed**: a claimed/placed bed outside any valid
     room → low-key hint ("a roof would make this a proper home"),
     because it works, just sub-optimally.
9. This system never blocks, reverts, or auto-fixes a placement (Building
   System Core Rule 10). It also never moves villagers or triggers
   behavior — Villager AI does its own reach checks at claim time (its
   F2/Rule 11); this system's outputs are for the *player's*
   understanding.

### States and Transitions

**Per candidate region:**

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Open | Region fails enclosure (no roof/floor coverage or below `min_room_cells`) | Structure change re-evaluation | No status shown — just ordinary outdoors/incomplete construction |
| Room (valid) | Enclosure met + walkable outside connection | Structure change breaks a condition | "Room recognized" one-shot on entry; furniture inside is sheltered |
| Sealed | Enclosure met, NO walkable outside connection | An opening is created / region dissolves | Sealed-space warning iff furniture inside; furniture inside is unsheltered (a sealed "room" shelters no one) |

**Per furniture item:** Sheltered ↔ Unsheltered (derived purely from its
cell's region state; changes emit a status event for the Needs recovery
ladder and the UI).

### Interactions with Other Systems

- **Building System** (upstream, MVP): construction-completed/removed
  signals trigger re-analysis (batched per its Interactions rule); the
  combined planned-occupancy view is available but unused in MVP
  (built-only analysis, Rule 7). Resolves its Open Question 7
  (completed-structure warnings live here).
- **Villager AI & Behavior** (upstream, MVP): walkability definition
  consumed verbatim (its Rules 8–10; registry constants). No runtime
  calls in either direction — this system runs its own region/reach
  analysis using the same rules; villager pathing stays the AI's own job.
- **Voxel World** (upstream, MVP): physical occupancy reads for the
  region analysis. Read-only.
- **Needs & Mood System** (MVP, downstream): consumes the
  sheltered/unsheltered flag per bed for its source→rate table (extended
  to the 3-tier ladder — patch). Values stay owned there.
- **Villager Info UI / Building UI** (MVP, downstream, provisional):
  display the warnings, info hints, and room confirmations; the
  why-string ("no opening") comes from this system.
- **Township Progression** (Alpha, downstream, provisional): "housed
  villagers" (owned bed, sheltered) is an obvious prosperity input —
  flagged as a seam, not designed here.
- **Save/Load** (Vertical Slice, downstream, provisional): nothing to
  serialize — all statuses are re-derivable from the world on load (a
  deliberate property of Rule 4).

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section
even in Lean mode. Verdict: this system owns no formulas; one hidden
tuning invariant found and recorded in Tuning Knobs.)*

**None.** This system evaluates boolean predicates over an
algorithmically-detected region (flood-fill class, deferred to the
building/AI ADR) and passes through a classification flag consumed by
the Needs & Mood GDD's rate table — there is no original numeric
computation here to formalize.

Deliberately NOT formulas (and why):
- **Room validity** — a boolean predicate over Core Rules 1–3 (threshold
  comparisons and reachability), not a value computation.
- **Region detection / outside-connection test** — flood-fill/BFS-class
  algorithms; same treatment as Voxel World's raycast: deferred to the
  ADR. Analysis scope is bounded by connectivity itself, not by an
  arbitrary radius.
- **Recovery ladder values** (1.0 / 0.7 / 0.4) — owned by the Needs &
  Mood source→rate table; this system supplies only the sheltered flag.
- **Warning debounce** — inherited from the Building System's batched
  signals (a dependency, not a timing formula).

**Tuning invariant** (recorded in Tuning Knobs): `max_room_height ≥`
the Building System's maximum `wall_height` (currently 8 = 8) — these
must be retuned in lockstep, or tall single-story builds silently stop
registering as rooms.

## Edge Cases

1. **Connected interiors form ONE region.** Two "rooms" joined by a gap
   are one region in MVP (no interior doors exist to separate them).
   Correct and accepted — per-room subdivision arrives with doors at
   Vertical Slice.
2. **A room is sealed by its last gap being built shut.** Room → Sealed
   on the construction-completed signal; all furniture inside flips to
   unsheltered; the sealed-space warning appears iff furniture is inside.
   If a villager is inside, Villager AI's trapped handling (its Edge Case
   2) shows distress — two independent, complementary signals.
3. **Villager sealed in WITH its bed.** The villager can still physically
   use the bed (its own reach check runs from *its* position), but
   recovery drops to unsheltered rate (a sealed space shelters no one,
   States table) and both warnings stand (sealed-space + AI distress).
   Deliberate: mechanically survivable, clearly signaled, player-fixable.
4. **An opening exists but isn't walkable from outside** (hole onto a
   2-cell drop). Not a valid connection — openings must satisfy the
   walkability rules (step ≤ 1, clearance 3), not merely be holes. The
   region is Sealed.
5. **Terrain as structure.** Terrain counts as floor and as wall (solid
   is solid) — a house built against a hillside or into a natural
   overhang can form valid rooms. No distinction between built and
   natural enclosure in MVP.
6. **Roof-on-pillars (no walls).** Valid room by Rule 2 — the definition
   requires roof, floor, size, and reachability, not wall coverage.
   **Accepted for MVP as a KNOWN design gap** (2026-07-10 cross-review,
   user decision): with zero material cost, the minimal carport reaches
   full shelter (1.0) — walls contribute no mechanical value at MVP,
   which the cross-review flagged as failing Pillar 1's own design test
   for walls specifically. This is a deliberate MVP scope-narrowing, NOT
   an oversight: the wall-coverage requirement (Open Question 1) is
   **priority #1 for this GDD's Vertical Slice revision**, and MVP
   playtest feedback about "why bother with walls" should be read as
   confirming this known gap, not as a new finding.
7. **A hole appears in the roof** (block removed). Cells under the hole
   lose candidate status; the region shrinks or splits; if what remains
   meets Rule 2 it stays a room. A bed now under open sky flips to
   unsheltered. Partial roof damage de-shelters only the affected cells'
   furniture.
8. **Furniture in an opening/edge cell.** Its shelter status follows its
   own cell's candidate status (deterministic per Rule 1) — a bed exactly
   under the roof edge is sheltered; one cell further out is not.
9. **Minimal bedroom.** `min_room_cells` = 2 → a bed cell plus one free
   interior cell is the smallest valid room. A 1-cell roofed niche
   holding a bed is NOT a room — the bed is unsheltered (info hint, not
   warning).
10. **Batched construction bursts.** One re-analysis per batched Building
    System signal, never per cell — a 512-cell command completion
    triggers one pass over the affected region.
11. **World load.** A full analysis pass runs once on load; all statuses
    are re-derived from the world (nothing was serialized —
    Interactions). Load-time statuses must equal pre-save statuses
    (AC-tested).
12. **Region at world edge.** The world boundary acts as neither wall nor
    opening — candidate cells simply end there; reachability uses
    in-bounds cells only. A "room" built against the world edge behaves
    exactly like one built against a cliff (case 5).

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Building System | ✅ Designed (In Review) | Construction-completed/removed signals (batched) as the analysis trigger; combined planned-occupancy view (unused in MVP, reserved) |
| Villager AI & Behavior | ✅ Designed | The walkability definition, consumed verbatim (`villager_clearance`=3, `max_step_height`=1, corner-cutting rule) — never redefined |
| Voxel World | ✅ Designed | Physical occupancy reads for region analysis (read-only) |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Needs & Mood System | MVP | ✅ Designed | The sheltered/unsheltered flag per bed — extends its source→rate table to the 3-tier ladder *(patch pending)* |
| Villager Info UI / Building UI | MVP | Undesigned | Warnings, info hints, room confirmations + why-strings *(provisional)* |
| Township Progression | Alpha | Undesigned | "Housed villagers" (owned + sheltered bed) as a prosperity input *(provisional)* |
| Save/Load & World Persistence | Vertical Slice | Undesigned | Nothing — all statuses re-derive on load (deliberate; Edge Case 11) |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `min_room_cells` | 2 | 1–9 | Smallest valid room (Edge Case 9). 1 would make roofed niches count; large values punish cozy starter huts |
| `max_room_height` | 8 | 3–16 | How high above an interior cell the roof may sit (Rule 1). **Invariant: must stay ≥ the Building System's max `wall_height` (currently 8 = 8) — retune in lockstep**, or tall single-story builds silently stop registering as rooms |
| `unsheltered_bed_multiplier` | 0.7 | 0.5–0.9 | The middle rung of the recovery ladder. **Invariant: `ground_penalty` (0.4) < this < 1.0** — outside that order the ladder collapses and either beds or rooms stop mattering |

All values data-driven per the coding standard; none are player-facing.

## Visual/Audio Requirements

Room-recognized moment: a subtle one-shot (brief warm highlight tracing
the room's bounds + a soft chime — cozy, not fanfare; exact treatment to
the art bible). Warnings/info use the Visual Direction Note's orange
state family (consistent with the Building System's unreachable ghosts)
— warning ≠ info in intensity, never red-green. **New assets required**:
room-highlight effect, sealed-space warning icon, unsheltered info icon.

## Game Feel

Recognition must feel *earned and immediate* — the room registers on the
same beat the last cell completes. If a Building System
command-completion flourish fires simultaneously (finishing the roof
often completes both), the room cue follows it by a breath rather than
stacking (one celebration, two layers). Warnings appear calmly after the
fact — never mid-drag, never interrupting the build flow.

**Feel acceptance criteria** (subjective, playtest-verified): the first
room recognition elicits visible delight ("it noticed!"); no tester
reads the sealed-space warning as punishment; nobody asks "what does
this warning mean."

## UI Requirements

None owned — supplies to Building UI / Villager Info UI: room status
(on-demand, not a permanent overlay — clutter violates Pillar 4's calm),
warnings with why-strings ("the bed can't be reached — the room has no
opening"), and the one-shot recognition event. Warnings must be
dismissable but re-assert if the cause persists after further building.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| Construction signals, never-block rule, planned-occupancy view, Open Question 7 | `design/gdd/building-system.md` | Interactions, Core Rules 10/14b, OQ7 | Trigger source; **this GDD resolves its OQ7** (completed-structure warnings) |
| Walkability rules + constants | `design/gdd/villager-ai-behavior.md` | Rules 8–10 | Consumed verbatim (its Rule 10 mandate) |
| Source→rate table (3-tier ladder extension) | `design/gdd/needs-mood-system.md` | Core Rule 4 | Value ownership stays there; patch adds the unsheltered rung |
| "Does a room need a validated path before it's livable?" | `design/gdd/game-concept.md` | Open Questions | **Resolved by this GDD**: yes — reachability is a room condition (Rule 2) |
| Orange state family, colorblind-safe | `design/art/visual-direction-note.md` | State axis | Warning/info visual constraint |
| `villager_clearance`, `max_step_height`, `ground_penalty`, `bed` | `design/registry/entities.yaml` | Registry facts | Locked inputs; `unsheltered_bed_multiplier` + room knobs registered at Phase 5 |
| NavigationServer3D rebake cost | `docs/engine-reference/godot/` + future building ADR | High-risk flag | Implementation question, NOT resolved here (this design is cell-rule-based and needs no navmesh) |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review produced 5 rewrites and 6 missing criteria; all
incorporated. Building System signals and Villager AI's distress signal
are mocked at the boundary per testing standards.)*

**Room detection**
1. **GIVEN** a 3×3 interior with full roof, floor, walls, and one 1-wide × 3-high walkable gap (step 0), **WHEN** analyzed, **THEN** it is a valid room (Rule 2).
2. **GIVEN** the same structure fully sealed, **WHEN** the completion signal fires, **THEN** the region becomes Sealed and is not a room (Rule 3, Edge Case 2).
3. **GIVEN** a sealed region containing a bed, **WHEN** analyzed, **THEN** the sealed-space warning is raised; **GIVEN** the same region empty, **THEN** no warning (Rule 3).
4. **GIVEN** a candidate region of exactly `min_room_cells` with a walkable connection, **WHEN** analyzed, **THEN** it is a valid room; **GIVEN** one cell fewer, **THEN** it is not (Edge Case 9).
5. **GIVEN** a room whose only opening leads onto a 2-cell drop, **WHEN** analyzed, **THEN** the region is Sealed (step-height violation); **GIVEN** an opening with less than 3 cells of vertical clearance, **THEN** likewise Sealed (clearance violation) — both walkability failure modes (Edge Case 4).
6. **GIVEN** an interior cell with roof exactly `max_room_height` above, **WHEN** analyzed, **THEN** it is a candidate cell; **GIVEN** one cell higher, **THEN** it is not (Rule 1 boundary).
7. **GIVEN** two interiors connected by a gap, **WHEN** analyzed, **THEN** they form ONE region with one status (Edge Case 1).
8. **GIVEN** a valid room split in two by removing a connecting roof/floor segment, **WHEN** analyzed, **THEN** two independent regions result, each independently evaluated against Rule 2 (Edge Case 7).
9. **GIVEN** terrain forming the floor and one wall, **WHEN** analyzed, **THEN** the enclosure can be a valid room (Edge Case 5).
10. **GIVEN** a roof on pillars with no walls (floored, reachable, ≥ min cells), **WHEN** analyzed, **THEN** it IS a valid room (Edge Case 6 — accepted MVP behavior).
11. **GIVEN** a region at the world edge, **WHEN** analyzed, **THEN** the boundary is neither wall nor opening; reachability uses in-bounds cells only (Edge Case 12).

**Shelter status and events**
12. **GIVEN** a bed inside a valid room, **WHEN** classified, **THEN** it is sheltered (Rule 5).
13. **GIVEN** a roof hole opening above that bed's cell, **WHEN** re-analyzed, **THEN** the bed flips to unsheltered (Edge Case 7).
14. **GIVEN** a bed in a sealed region, **WHEN** classified, **THEN** it is unsheltered (States table).
15. **GIVEN** a bed exactly under the roof edge vs. one cell outside it, **WHEN** analyzed, **THEN** the former is sheltered and the latter is not — purely a function of its own cell's candidate status (Edge Case 8).
16. **GIVEN** a shelter-status change, **WHEN** it occurs, **THEN** exactly one `shelter_status_changed` signal is emitted per transition — Needs and UI subscribe to the same emission (assert emission count = 1, not consumer count).
17. **GIVEN** an unsheltered bed in the open vs. a bed in a sealed space, **WHEN** classified, **THEN** the former emits an Info-tier event and the latter a Warning-tier event — distinct signal types (Rule 8 severity tiers).
18. **GIVEN** a region seals with both a villager and a bed inside, **WHEN** analyzed, **THEN** the sealed-space warning fires and the bed flips to unsheltered, independently of Villager AI's distress signal — no suppression or coupling between the two (Edge Case 3; AI signal mocked separately).

**Lifecycle, triggers, and contracts**
19. **GIVEN** a batched construction signal covering N cells, **WHEN** received, **THEN** exactly one re-analysis pass runs over the affected region (assert analysis call-count = 1) (Rule 7, Edge Case 10).
20. **GIVEN** no structure-change signals, **WHEN** N frames pass, **THEN** the instrumented analysis call-count stays 0 — event-driven, never per-frame (Rule 7).
21. **GIVEN** a candidate region becomes a valid room, **WHEN** the transition occurs, **THEN** exactly one "room recognized" one-shot fires — and does NOT re-fire on later re-analyses that keep the room valid (Rule 8).
22. **GIVEN** a warning's cause persists, **WHEN** any later re-analysis runs, **THEN** the warning event re-emits every qualifying pass regardless of prior UI dismissal — dismiss/re-show presentation is the UI's own (advisory-tier) behavior (UI Requirements).
23. **GIVEN** blueprint (unbuilt) cells forming a would-be roof, **WHEN** analyzed, **THEN** they do NOT count as solid — analysis is built-only in MVP (Rule 7).
24. **GIVEN** mocked changed walkability constants in the registry, **WHEN** reachability is evaluated, **THEN** the updated values are used — no independent copies (Rule 2 verbatim-consumption).
25. **GIVEN** any invalid/sealed configuration, **WHEN** the player completes the placement, **THEN** the Building System's completion signal and world state are unmodified — no block/revert call is ever observed (Rule 9 never-blocks, verified via mock call-count).
26. **[PROVISIONAL — Save/Load]** **GIVEN** a world state, **WHEN** saved and reloaded (mocked), **THEN** all region and shelter statuses re-derive identically to pre-save (Edge Case 11).

*Config-validation (advisory CI smoke checks, not gameplay ACs):
(a) `max_room_height ≥` Building's max `wall_height` at load;
(b) `ground_penalty < unsheltered_bed_multiplier < 1.0` (the two Tuning
Knob invariants).*

## Open Questions

1. **Wall coverage at Vertical Slice** — should a valid room eventually
   require some wall enclosure (retiring the "cozy carport", Edge Case
   6)? Decide together with doors. **Elevated to VS priority #1 by the
   2026-07-10 cross-review** (walls are mechanically inert at MVP — a
   known, accepted gap that VS must close). → *this GDD's VS revision*
2. **Doors** — when VS adds them, an opening becomes a formal object
   (walkable when open). The room definition (Rule 2) should survive
   unchanged; verify. → *VS revision + Building System OQ 6*
3. **Room identity and function** — persistent named rooms ("bedroom",
   "dining hall") once furniture functions multiply. → *VS+ with the
   furniture set*
4. **Wave damage interplay** — do breached walls (destroyed by waves)
   trigger re-analysis and warnings mid-combat, or after? → *Wave
   Defense GDD, after the `/prototype wave-defense` spike*
5. **Analysis performance at township scale** — region re-analysis cost
   with large worlds and 20–30 villagers' worth of construction;
   cell-rule approach vs. NavigationServer3D remains open. →
   *building/AI ADR + the pre-VS performance spike*
6. **"Housed" as a prosperity input** — formalize the owned-sheltered-bed
   status for Township Progression. → *Township Progression GDD, Alpha*
