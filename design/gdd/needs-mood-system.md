# Needs & Mood System

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-10
> **Last Verified**: 2026-07-10
> **Implements Pillar**: Pillar 2 — A settlement that feels alive (primary); Pillar 1 — The building IS the game (furniture satisfies needs: the Building→Needs seam); Pillar 4 — Clarity over complexity (needs/mood shown up front)

## Summary

The Needs & Mood System owns the values that make villagers feel alive:
which needs exist (MVP: sleep), how fast they decay per game tick, when
they become urgent, how activities and furniture restore them, and how
overall need satisfaction rolls up into a single visible **mood**. It is
the scoreboard of the concept's unique hook — furniture carries function —
because a bed's mechanical meaning ("this room is shelter") is defined
here as need-recovery data. Villager AI consumes its urgency signals and
performs the recovery activities; this system never moves a villager.

> **Quick reference** — Layer: `Gameplay` · Priority: `MVP` · Key deps: `Villager AI & Behavior, Time & Tick System`

## Overview

**Player-facing:** needs and mood close the game's core loop: build →
furnish → *watch it matter*. The player never manages needs directly —
they read a villager's visible mood and need levels (Villager Info UI)
and respond by building: a bed turns exhausted ground-sleeping into
restful nights, and the villager's mood visibly lifts. Per Pillar 4, the
causality must be legible up front: WHY a villager is unhappy (no bed,
poor sleep) is always readable, so the fix is always buildable. This is
the concept's MVP hypothesis made measurable — "a villager with needs
(sleep) that the home satisfies + visible mood."

**System-facing:** this system is a per-villager value model on game
time. Each need is a 0–100 value decaying per tick; thresholds trigger
urgency (consumed by Villager AI's priority list) and wake/satisfaction;
recovery rates depend on HOW the need is satisfied — the Building→Needs
seam: furniture defines recovery quality (bed = full-rate sleep; ground =
penalized sleep), which is exactly how "the building IS the stats"
(Pillar 1) enters the simulation. Mood is a derived read-only aggregate
of need satisfaction (MVP: one need → simple mapping; the schema
anticipates more needs and, later, mood modifiers from Relationships/
events). This GDD owns all values and formulas; it owns NO behavior —
Villager AI decides and acts, this system scores.

Out of scope here: which activities exist and how villagers perform them
(Villager AI), what furniture exists (Resource & Item Database / Building
System), mood consequences beyond display (work-speed modifiers, breaks —
Alpha, flagged as an Open Question), and social/relationship needs
(Relationships & Bonds, Alpha).

## Player Fantasy

**"When they're doing well, it's because of me."**

The indirect care-taker fantasy, sharpened to cause and effect:

1. **Reading them.** A glance tells me how my villagers are doing — a
   mood face, a need bar. No spreadsheets, no digging (Pillar 4). Concern
   is legible before it becomes crisis.
2. **Fixing it by building.** Every unhappiness has a buildable answer —
   tired villager, no bed → I build a bed. The emotional loop IS the
   gameplay loop: worry → build → relief. (This is the furniture-carries-
   function hook felt from the caretaker's side.)
3. **Quiet satisfaction.** A settlement of well-rested, content villagers
   is the visible scoreboard of my stewardship — cozy, not min-maxed.
   Mood is a warm signal, not a punishment meter (Pillar 3: threats come
   from waves, not from villagers spiraling into misery).

Reference feeling: RimWorld's need bars for legibility — but explicitly
NOT its mental-break spiral (our mood informs, it does not punish in
MVP); Stonehearth's happiness as ambient warmth. NOT the fantasy: a
tamagotchi (constant urgent maintenance), or an opaque sim where
unhappiness is a puzzle to decode.

> `creative-director` not consulted — Lean mode (non-high-risk section).
> Sourced from game-concept.md (MVP hypothesis, Pillar 3/4) + the
> Building→Needs seam carry-forward. Review manually before production.

## Detailed Design

### Core Rules

**The need model**

1. A need is a per-villager float from 0 (desperate) to 100 (fully
   satisfied). Every need decays by its `decay_per_tick` on each game tick
   except while that need is being recovered.
2. **Fixed need schema** (same pattern as the item database's category
   set): the schema knows three needs from day one — `sleep` (MVP),
   `food` (Vertical Slice), `company` (Alpha). MVP fills only `sleep`
   with values. Adding a need type is a design change, not a data edit.
3. **Thresholds** (per need, edge-triggered signals):
   - `urgency_threshold` (default 25): crossing downward emits "need is
     urgent" — the signal Villager AI's priority list consumes (its Rule 2).
   - `satisfied_threshold` (default 95): crossing upward during recovery
     emits "need satisfied" — Villager AI's wake/stop trigger (its Rule 13).
4. **Recovery happens only through activities** (Villager AI performs
   them; this system scores them). Recovery rate depends on the
   **recovery source** — THE Building→Needs seam:

   | Source | Rate | Meaning |
   |--------|------|---------|
   | Owned bed, **sheltered** (inside a valid room) | `bed_recovery_per_tick` (full rate, ×1.0) | The full furniture-carries-function hook: bed + room = proper shelter |
   | Owned bed, **unsheltered** (no valid room) | full rate × `unsheltered_bed_multiplier` (default 0.7) | The bed works, the missing room visibly costs — makes building the room mechanically worthwhile (Pillar 1) |
   | Ground (no bed) | full rate × `ground_penalty` (default 0.4) | Survivable but visibly worse — the buildable-fix signal |

   The source→rate table is owned HERE, keyed by item id + shelter flag;
   the sheltered/unsheltered classification is supplied by Build
   Validation & Navigability (its Rule 5 — extended 2026-07-10 from the
   original two-tier table when that GDD introduced room detection).
   Future furniture (VS+) extends the table, and quality tiers can
   multiply it later.
5. **No death spiral** (Pillar 3): a need at 0 harms nothing in MVP — a
   villager with sleep at 0 simply ground-sleeps wherever it stands
   (Villager AI's urgent priority already guarantees this). Needs create
   care, never fail-states; threats come from waves, not neglect.

**Mood**

6. Mood is a derived, read-only 0–100 value: the mean of all active need
   values, **smoothed** over `mood_smoothing_ticks` so it drifts rather
   than flickers (a bad night lingers briefly; a good night's glow lasts).
   MVP: one need → mood ≈ smoothed sleep value.
7. Mood is displayed in three bands (colorblind-safe per the Visual
   Direction Note's state axis): **Happy** (≥ 70), **Content** (40–69),
   **Low** (< 40). Bands, not raw numbers, are the player-facing signal.
8. **MVP mood is display-only.** No gameplay consequences (work speed,
   breaks) until Alpha — that seam is Open Question 2.
9. All values are data-driven config (coding standard); nothing here is
   hardcoded.

### States and Transitions

**Per-need state** (per villager, per need):

| State | Entry | Exit | Behavior |
|-------|-------|------|----------|
| Satisfied | Value > `urgency_threshold` | Value crosses ≤ threshold | Decays per tick; no signals |
| Urgent | Downward cross of `urgency_threshold` | Recovery raises value above it | "Need urgent" signal emitted ONCE on entry; keeps decaying until recovery starts |
| Recovering | Villager AI reports a recovery activity for this need | Upward cross of `satisfied_threshold`, or activity interrupted | Value rises by the source's rate per tick; no decay; on satisfied-cross, "need satisfied" emitted ONCE |

**Mood bands**: Happy ↔ Content ↔ Low — transitions purely derived from
the smoothed value crossing 70/40; band changes emit a display event for
the Villager Info UI (and nothing else in MVP).

### Interactions with Other Systems

- **Villager AI & Behavior** (MVP, mutual — the primary seam): this
  system emits "need urgent"/"need satisfied" signals (consumed by its
  Rules 2 and 13); Villager AI reports the active recovery activity and
  its source (owned bed vs. ground — its Rules 11–12), which this system
  scores per Rule 4. Confirms that GDD's provisional Needs interface —
  its Open Question 1 is resolved by this GDD.
- **Time & Tick System** (upstream, MVP): all decay/recovery on tick
  events; pause halts everything; warp accelerates (a 3x day drains
  needs 3x faster in wall-clock — by design).
- **Building System / Resource & Item Database** (indirect): the
  recovery-source table (Rule 4) is keyed by item ids defined in the
  database and placed by the Building System — but neither system is
  called at runtime; Villager AI reports which source it is using.
- **Build Validation & Navigability** (MVP, upstream for the shelter
  flag): supplies the per-bed sheltered/unsheltered classification (its
  Rule 5) that selects between the table's top two rungs. Added
  2026-07-10 with the 3-tier ladder.
- **Villager Info UI** (MVP, downstream): displays need values, mood
  band, and the WHY (current strongest need drain + missing source, e.g.
  "tired — no bed"), per Pillar 4's legibility rule.
- **Relationships & Bonds** (Alpha, downstream, provisional): will add
  the `company` need's sources and mood modifiers beyond need means.
- **Save/Load** (Vertical Slice, downstream, provisional): serializes
  per-villager need values and mood smoothing state.

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section even
in Lean mode. Review produced 2 revisions (EMA snap rule, F2 stopping
point) and 2 additions (mean definition, spawn initialization); all
incorporated.)*

### F1 — Need decay (per tick, while not Recovering)

`value ← max(0, value − decay_per_tick[need])`

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `value` | float | 0–100 | Current need value; comparisons are `<=`/`>=` crosses, never equality checks |
| `decay_per_tick[sleep]` | float | > 0, default 0.07 | Full drain 100→0 in ~1429 ticks ≈ 11.9 min game time at 1x |

Time-to-urgent from full: ceil((100 − 25) / 0.07) = 1072 ticks ≈ **8.9
min at 1x** (the chosen pacing; ceil because the signal fires on the
downward cross, per the qa-lead's boundary check).

### F2 — Need recovery (per tick, while Recovering)

`value ← value + base_recovery_per_tick[need] × source_multiplier`

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `base_recovery_per_tick[sleep]` | float | > 0, default 0.5 | Full-rate recovery (owned bed) |
| `source_multiplier` | float | 0–1 | Bed = 1.0; ground = `ground_penalty` = 0.4 |

**Stopping point**: the `satisfied_threshold` (95) cross is the true and
only exit (state table) — the final tick may overshoot 95 by up to one
increment; that slack is intentional and the value is simply left where
it lands. There is no separate clamp at 100 during recovery.

Worked: urgent (25) → satisfied (95) = 70 points: **bed 140 ticks =
70s**; **ground 350 ticks ≈ 2.9 min** game time at 1x.

### F3 — Mood smoothing (per tick)

`mood ← mood + (mean_active − mood) / mood_smoothing_ticks` — with
explicit float division (`/ 40.0`), and a **snap rule**: if
`abs(mean_active − mood) < 0.05`, then `mood = mean_active` (prevents the
EMA asymptote from permanently stalling just below a band boundary, e.g.
69.97 vs Happy ≥ 70).

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `mean_active` | float | 0–100 | Unweighted arithmetic mean over **active (schema-filled) needs only** — inactive needs (food/company before their tiers) are excluded, never defaulted |
| `mood_smoothing_ticks` | float | 10–120, default 40 | = 20s at 1x; ~63% caught up after 40 ticks, ~95% after 2 min |

### F4 — Spawn initialization

`needs ← 100 (each active need); mood ← mean_active` — mood initializes
**equal to** the spawn mean, never 0 (a cold-start at 0 would falsely
display "Low" for ~20s while F3 catches up).

### Burst rule (signal ordering)

Within a tick burst (up to `max_ticks_per_frame` = 10), F1–F3 apply per
tick **in order**, and threshold signals are emitted per-tick in-order —
never coalesced or deduplicated across the burst. (Today sleep's rates
cannot cross both thresholds in one burst — that is numeric coincidence,
not a guarantee; faster future needs rely on this rule.)

### Deliberately NOT formulas (and why)

- **Which activity recovers which need** — Villager AI behavior.
- **Band mapping** (70/40 comparisons) — a display rule, not math.
- **Mood consequences** — Alpha, Open Question 2.

## Edge Cases

1. **Recovery interrupted mid-way** (bed removed, job preemption — value
   lands between thresholds, e.g. 60). Not a limbo: any value above
   `urgency_threshold` that isn't mid-recovery is simply Satisfied —
   decay resumes silently and Urgent re-triggers only on the next
   downward 25-cross. *(Made explicit per the systems-designer consult.)*
2. **Need reaches 0.** Value clamps and stays at 0; the Urgent signal
   fired once at the 25-cross and does NOT re-fire at 0 (edge-triggered,
   cross-not-equality). No harm occurs (Core Rule 5) — the villager
   ground-sleeps per Villager AI's urgent priority.
3. **Recovery source removed mid-recovery** (bed removed while sleeping —
   Building Edge Case 11 / Villager AI Edge Case 5). Recovery stops that
   tick; the need re-enters Satisfied or Urgent purely by its current
   value. Villager AI owns the wake behavior; this system just stops
   scoring.
4. **Value sits exactly on a threshold across many ticks.** Signals fire
   only on *crossing* (`<=`/`>=` transitions between ticks), never on
   equality re-checks — a value parked at 25.0 emits nothing new.
5. **A new need activates at a tier boundary** (Vertical Slice adds
   `food`). Existing villagers initialize the new need at 100 on first
   load of the new version — nobody starts the patch day starving.
   `mean_active` simply gains a term (F3 definition).
6. **A future fast need crosses both thresholds inside one tick burst.**
   The burst rule guarantees per-tick, in-order signal emission —
   Villager AI receives urgent-then-satisfied in order, never a
   deduplicated nothing.
7. **Pause.** No decay, no recovery, no mood drift (everything is
   tick-driven); the UI keeps displaying the frozen values.
8. **Save/Load** *(Vertical Slice, provisional)*. Need values AND the
   smoothed mood are serialized; on load, mood is restored — never
   re-initialized via F4 (that would erase the smoothing state). A saved
   need type no longer in the schema is dropped with a log line, never a
   crash.
9. **Time-warp 3x.** All rates are tick-based, so game-time pacing is
   invariant; wall-clock everything runs 3x — a deliberately
   faster-breathing settlement.
10. **Mood band flapping at a boundary** (69.9 ↔ 70.1). The EMA smoothing
    is the primary anti-flicker mechanism and the snap rule settles
    stable states. If playtests still show band flapping, add a ±1
    display hysteresis as a UI-side tuning — noted in Tuning Knobs, not
    pre-built.
11. **Recovery source UPGRADED mid-recovery** (the roof completes while
    the villager is already asleep in the until-now unsheltered bed —
    Build Validation emits `shelter_status_changed` during Recovering).
    The source→rate table is re-evaluated per tick: the new (higher) rate
    applies from the next tick onward; no restart, no signal, no lost
    progress. The mirror case (downgrade — roof removed mid-sleep)
    behaves identically with the lower rate. *(Added 2026-07-10 — the
    cross-review scenario walkthrough found this transition only
    implicitly defined.)*

## Dependencies

### Upstream (systems this one depends on)

| System | GDD Status | What this system consumes |
|--------|-----------|---------------------------|
| Time & Tick System | ✅ Designed | Tick events for all decay/recovery/mood math; pause/warp semantics |
| Villager AI & Behavior | ✅ Designed (mutual) | Reports of the active recovery activity and its source (owned bed vs. ground, its Rules 11–12) |

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Villager AI & Behavior | MVP | ✅ Designed (mutual) | "Need urgent"/"need satisfied" signals (its Rules 2, 13) — its provisional Needs interface is CONFIRMED by this GDD |
| Villager Info UI | MVP | Undesigned | Need values, mood band, the "why" explanation *(provisional)* |
| Relationships & Bonds | Alpha | Undesigned | The `company` need slot + mood modifier seam *(provisional)* |
| Professions & Ranks / work systems | Alpha | Undesigned | Mood consequences (work speed etc.) once Open Question 2 resolves *(provisional)* |
| Save/Load & World Persistence | Vertical Slice | Undesigned | Need values + smoothed mood serialization (Edge Case 8) *(provisional)* |

## Tuning Knobs

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `decay_per_tick[sleep]` | 0.07 | 0.03–0.2 | The session rhythm: ~9 min to urgent at default; 0.2 ≈ tamagotchi territory (avoid) |
| `base_recovery_per_tick[sleep]` | 0.5 | 0.2–2.0 | Sleep duration (~70s in bed at default) |
| `ground_penalty` | 0.4 | 0.1–0.8 | How much worse bed-less sleep is — the strength of the "build a bed" signal. Too close to 1.0 kills the furniture hook |
| `unsheltered_bed_multiplier` | 0.7 | 0.5–0.9 | The middle rung of the recovery ladder (bed outside a valid room). **Invariant: `ground_penalty` < this < 1.0** — outside that order the ladder collapses. Owned HERE (this table is the source of truth); Build Validation supplies only the sheltered flag (added 2026-07-10, cross-review ownership fix) |
| `urgency_threshold` | 25 | 10–40 | When villagers drop work to satisfy a need |
| `satisfied_threshold` | 95 | 80–100 | When recovery ends (wake) |
| `mood_smoothing_ticks` | 40 | 10–120 | Mood inertia — how long a bad night lingers |
| Mood band boundaries | 70 / 40 | display contract | Shared verbatim with Villager Info UI — changing them is a UI-coupled design change |
| Band display hysteresis | 0 (off) | 0–3 | Anti-flapping reserve (Edge Case 10) — enable only if playtests show flicker |

All values data-driven per the coding standard; none are player-facing.

## Visual/Audio Requirements

This system renders nothing. It requires the Villager Info UI / art bible
to provide: three mood-band icons (readable at a glance, colorblind-safe
per the Visual Direction Note — never red-green), and a need-bar
treatment. Audio: none in MVP (an optional gentle band-up chime is a
Polish candidate, not a requirement).

## Game Feel

The feel target is a *breathing* settlement: needs create a ~10-minute
heartbeat (work → tire → sleep → refreshed) that the player senses
without watching numbers. Mood drifts rather than snaps (smoothing =
emotional inertia — villagers aren't light switches). Tone per Pillar 3:
a Low villager looks tired-cozy, never suffering-grimdark.

**Feel acceptance criteria** (subjective, playtest-verified): a
first-time player, asked "why is the villager unhappy?", answers
correctly within one need cycle without a tutorial; nobody describes the
needs as "nagging."

## UI Requirements

None owned — supplies to Villager Info UI: per-need values (0–100), mood
band (3 states + display events on change), and the **why-string** — the
strongest current drain plus its missing source (e.g. "tired — no bed").
Pillar 4 contract: the UI must never show a mood without the reason being
one interaction away.

## Cross-References

| Reference | Document | What | Nature |
|-----------|----------|------|--------|
| Urgency/wake signal consumption, recovery activities, bed ownership | `design/gdd/villager-ai-behavior.md` | Rules 2, 11–13; Open Question 1 | Mutual contract — CONFIRMED by this GDD (patch its provisional markers) |
| Tick events, pause/warp | `design/gdd/time-tick-system.md` | Core Rules | Time base |
| `bed` definition; furniture placement | `design/gdd/resource-item-database.md`, `design/gdd/building-system.md` | bed id, furniture tool | Recovery-source table keys (Rule 4) |
| MVP hypothesis, Pillars 1/3/4 | `design/gdd/game-concept.md` | MVP Definition, Pillars | Scope authority; "visible mood" mandate |
| Colorblind-safe state colors | `design/art/visual-direction-note.md` | State axis | Band display constraint |
| `bed`, `ticks_per_second`, `max_ticks_per_frame` | `design/registry/entities.yaml` | Registry facts | Data dependency; new constants registered at Phase 5 (thresholds, ground_penalty — consumed by Villager AI) |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review produced 1 rewrite, 1 doc off-by-one fix (F1: 1072 ticks),
and 5 missing criteria; all incorporated. Villager AI activity reports
are mocked at the boundary per testing standards.)*

**Signals & decay**
1. **GIVEN** a need at 100 and no recovery, **WHEN** 1 tick fires, **THEN** the value decreases by exactly `decay_per_tick` (F1).
2. **GIVEN** a need below `decay_per_tick`, **WHEN** a tick fires, **THEN** the value clamps to exactly 0 and stays (F1).
3. **GIVEN** a need decaying across `urgency_threshold`, **WHEN** the cross occurs, **THEN** exactly one "need urgent" signal is emitted (edge-triggered).
4. **GIVEN** a need parked exactly at the threshold for many ticks, **WHEN** ticks fire, **THEN** no additional signals are emitted (Edge Case 4).
5. **GIVEN** a need at 0 for many ticks, **WHEN** ticks fire, **THEN** no repeated urgent signals are emitted (Edge Case 2).
6. **GIVEN** a need at 0 for many ticks, **WHEN** ticks fire, **THEN** no signal, event, or state change beyond the sustained clamp occurs — "harms nothing" is literal (Rule 5).
7. **GIVEN** no recovery, **WHEN** decaying from 100 at defaults, **THEN** the urgent signal fires after exactly ceil(75/0.07) = **1072 ticks** (F1 boundary test).

**Recovery**
8. **GIVEN** a Recovering need with a mocked bed source, **WHEN** 1 tick fires, **THEN** the value increases by exactly `base_recovery_per_tick` × 1.0 (F2).
9. **GIVEN** a mocked ground source, **WHEN** 1 tick fires, **THEN** the increase is × `ground_penalty` (F2).
10. **GIVEN** a mocked NEW source id with its own multiplier, **WHEN** Recovering, **THEN** F2 applies via table lookup — no hardcoded two-source branch (Rule 4 extensibility).
11. **GIVEN** a Recovering need crossing `satisfied_threshold`, **WHEN** the cross occurs, **THEN** exactly one "need satisfied" signal is emitted, recovery stops, and overshoot of at most one increment is retained (F2).
12. **GIVEN** no recovery-activity report from Villager AI, **WHEN** a need sits below the urgency threshold for many ticks, **THEN** it never enters Recovering — recovery cannot self-trigger from value alone (state table).
13. **GIVEN** a recovery interrupted between thresholds (e.g. 60), **WHEN** the interruption registers, **THEN** the need re-enters Satisfied, decays normally, and re-triggers Urgent only at the next 25-cross (Edge Case 1).

**Mood**
14. **GIVEN** a mocked `mean_active` differing from mood, **WHEN** 1 tick fires, **THEN** mood moves by exactly (mean − mood) / `mood_smoothing_ticks` in float math (F3).
15. **GIVEN** abs(mean − mood) < 0.05, **WHEN** a tick fires, **THEN** mood snaps exactly to mean (F3 snap).
16. **GIVEN** `mean_active` stable at 70 for enough ticks that the snap condition is met, **WHEN** it fires, **THEN** mood == 70.0 exactly and Happy activates (F3 anti-asymptote, bounded claim).
17. **GIVEN** a new villager spawns, **WHEN** initialized, **THEN** every active need is 100 and mood equals `mean_active` — never 0 (F4).
18. **GIVEN** mood crossing a band boundary, **WHEN** the cross occurs, **THEN** exactly one band-change display event is emitted.
19. **GIVEN** default hysteresis = 0, **WHEN** mood crosses 70.00 or 40.00 exactly, **THEN** the band event fires at the boundary tick — no implicit dead zone (Edge Case 10).
20. **GIVEN** inactive schema needs (food/company pre-tier), **WHEN** `mean_active` is computed, **THEN** they are excluded — a lone sleep of 60 yields mean 60, not 86.7 (F3 definition).

**Time, lifecycle, persistence**
21. **GIVEN** a tick burst of `max_ticks_per_frame`, **WHEN** processed, **THEN** F1–F3 apply per tick in order and threshold signals are emitted in order, never coalesced (burst rule).
22. **GIVEN** identical tick counts dispatched at 1x vs 3x warp, **WHEN** F1/F2 apply, **THEN** the resulting values are identical — rates are functions of tick count, never wall-clock (Edge Case 9).
23. **GIVEN** pause (zero ticks), **WHEN** real time passes, **THEN** values and mood are unchanged (Edge Case 7).
24. **[PROVISIONAL — Save/Load]** **GIVEN** a save with need values and mood, **WHEN** loaded, **THEN** mood is restored as-saved, never re-initialized via F4 (Edge Case 8; mocked serializer now).
25. **[PROVISIONAL — Save/Load]** **GIVEN** a saved need type no longer in the schema, **WHEN** loaded, **THEN** it is dropped with a log line, never a crash (Edge Case 8).
26. **GIVEN** a version adds a new active need (mocked schema change), **WHEN** an existing villager loads, **THEN** the new need initializes at 100 (Edge Case 5).
27. **GIVEN** default values, **WHEN** a full sleep cycle runs (100 → urgent → bed recovery → satisfied), **THEN** total game time is ~9 min decay + ~70s recovery within ±5% (integration pacing test).

*Advisory (not a Logic AC): Rule 8's "mood is display-only" is an absence
claim — verified via an architectural contract check (no mood-consuming
API in work/scheduling code), owned alongside code review, not the
blocking test gate.*

## Open Questions

1. **Mood consequences** — work speed, breaks, celebration behaviors once
   mood stops being display-only. → *Professions & Ranks / economy GDDs,
   Alpha (the seam Rule 8 reserves)*
2. **`food` need design** — sources, hunger pacing, the eating activity,
   interplay with Gathering & Production. → *this GDD's Vertical Slice
   revision + Gathering & Production Chains GDD*
3. **`company` need + mood modifiers beyond need means** —
   → *Relationships & Bonds GDD, Alpha*
4. **Day/night rhythm** — shared open question with Villager AI (its OQ
   4): a clock would let sleep anticipate night instead of pure decay.
   → *Alpha, owner TBD (Time & Tick extension)*
5. **Furniture quality multiplying recovery** — the concept's
   crafting-quality tiers (a masterwork bed heals faster?) extend the
   source→rate table. → *crafting/quality GDDs, Alpha*
6. **Band hysteresis** — enable only if playtests show flapping (Edge
   Case 10, Tuning Knobs). → *MVP playtest*
