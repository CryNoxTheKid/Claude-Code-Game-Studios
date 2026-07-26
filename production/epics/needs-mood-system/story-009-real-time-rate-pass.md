# Story 009: Real-time-rate pass at `ticks_per_second = 4.0` (milestone criterion #4)

> **Epic**: Needs & Mood System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Config/Data
> **Estimate**: ~1 agent-day
> **Manifest Version**: 2026-07-23
> **Last Updated**: —

## Context

**GDD**: `design/gdd/needs-mood-system.md` (Tuning Knobs + F1/F2/F3 pacing prose); `design/gdd/time-tick-system.md` (the Open Question this closes)
**Requirement**: `TR-needs-mood-system-041`, `TR-needs-mood-system-030`, `TR-needs-mood-system-053`, `TR-needs-mood-system-038`, `TR-needs-mood-system-066`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Tuning/Config Data Strategy) — primary
**ADR Decision Summary**: All tunables live in the typed `.tres` config at GDD-stated defaults, and a value change is a recorded config change with rationale — not an inline edit. Safe ranges are declared per knob and enforced by `validate()`; any retune must land inside the declared range or the range itself must be re-declared in the GDD.

**Engine**: Godot 4.7-stable | **Risk**: LOW
**Engine Notes**: `TimeTickConfig.ticks_per_second` landed at **4.0** (raised from 2.0, Slice revision 2026-07-23) and `max_ticks_per_frame` at **12** (Sprint 8 re-tune). Every real-time figure written in the Needs & Mood GDD was computed at 2.0 and is therefore **2× off as written**. Tick *counts* are unaffected by the rate; only their wall-clock meaning changed.

**Control Manifest Rules (this layer)**:
- Required (Foundation): config values are data; a change is recorded with rationale (quick-spec), never a silent edit.
- Required (Feature): rates are functions of tick count, never wall-clock — this pass changes what the numbers *mean in seconds*, never how the math is expressed.
- Forbidden: changing a shipped knob without updating the GDD's stated arithmetic and every AC that pins a tick count in the same change.
- Guardrail: any retuned value must sit inside its GDD safe range, or the range is re-declared explicitly with rationale.

---

## Open Decision — REQUIRED INPUT BEFORE THIS STORY CLOSES

The `ticks_per_second` 2.0 → 4.0 change doubled the real-time meaning of every
per-tick rate this system owns. There are two coherent resolutions and they are
mutually exclusive. **This is a taste/scope call for the user, not a mechanical
edit** — the story documents both, implements the chosen one, and records it.

| | **Option A — preserve real-time pacing** | **Option B — preserve the tick anchors (recommended)** |
|---|---|---|
| What changes | `decay_per_tick[sleep]` 0.07 → **0.035**; `base_recovery_per_tick[sleep]` 0.5 → **0.25**; `mood_smoothing_ticks` 40 → **80** | Nothing. Ship the GDD defaults; restate their real-time meaning at 4.0 |
| Time to urgent (from 100) | ~8.9 min (unchanged in seconds; **2143** ticks) | ~4.5 min (**1072** ticks — unchanged) |
| Sheltered sleep duration | ~70 s (**280** ticks) | ~35 s (**140** ticks) |
| Mood inertia | ~20 s | ~10 s |
| Cascade | **AC7 (1072) and AC27 (1072/1212) both change**; GDD F1/F2 worked examples change; stories 002 + 008 tests must be updated in lockstep; all three retuned values stay inside their safe ranges | Zero code/test cascade. GDD prose (real-time figures + the "~6–7 min gap" claim) is corrected, not the numbers |
| Risk | A rate edit that misses one AC leaves a green test asserting a stale anchor | The MVP test window now contains ~2 full need cycles instead of ~1; the "deliberate wait" reads shorter |

**Producer recommendation: Option B.** Three reasons. (1) The GDD itself says the
pacing gap is a **hypothesis** "tested by the MVP playtest probe in Game Feel,
NOT tuned on paper" — shipping a value and testing it beats re-deriving it. (2)
Milestone 02 exists to make the payoff loop testable by a human; a ~4.5-minute
cycle gives a single 10-minute silent walkthrough (R8) **two** observations of
urgency → build → recovery instead of one. (3) The reversal is cheap and stays
in range: if the playtest reports "nagging", `decay_per_tick` 0.07 → 0.035 is a
one-line config change inside the declared 0.03–0.2 band. Option A's cascade
(two ACs, two test files, three GDD arithmetic passages) is the expensive
direction to take on paper before any human has played it.

**If Option A is chosen**, this story's scope grows to include the lockstep edits
to AC7/AC27, `design/gdd/needs-mood-system.md`'s F1/F2 worked examples, and the
assertions in `decay_state_machine_test.gd` and
`burst_pause_warp_determinism_test.gd` — all in one change, or the suite goes
green against a stale anchor.

---

## Acceptance Criteria

*From `production/milestones/milestone-02-mvp-completion.md` criterion #4, against `design/gdd/needs-mood-system.md`:*

- [ ] Every rate in the Needs & Mood Tuning Knobs table carries a **stated real-time equivalent at `ticks_per_second = 4.0`** — `decay_per_tick`, `base_recovery_per_tick`, `mood_smoothing_ticks`, and the derived time-to-urgent / sleep-duration figures.
- [ ] The GDD's pacing cross-reference (~9 min to urgent; the deliberate ~6–7 min build-to-urgency gap) is either **CONFIRMED** at the new rate or **RETUNED with rationale** — explicitly, by name, not implicitly by leaving the old prose in place.
- [ ] Every stale 2.0-rate real-time figure in `design/gdd/needs-mood-system.md` is corrected: F1's "~1429 ticks ≈ 11.9 min" and "1072 ticks ≈ 8.9 min", F2's "140 ticks = 70s / 200 ticks = 100s / 350 ticks ≈ 2.9 min", F3's "= 20s at 1x", and the Tuning Knobs pacing note.
- [ ] The GDD burst-rule prose "`max_ticks_per_frame` = 10" is corrected to the landed value (**12**) or restated as "the configured value" — tests already assert against config (story 008).
- [ ] The decision (Option A or B) and its rationale are recorded in `design/quick-specs/needs-mood-real-time-rate-pass-2026-07-XX.md`, following the `design/quick-specs/tick-rate-retune-2026-07-25.md` precedent.
- [ ] The `time-tick-system` GDD Open Question flagging the downstream per-tick-rate re-tune is **closed**, naming this quick-spec as its resolution.
- [ ] `design/registry/entities.yaml` entries touched by the outcome (`decay_per_tick` figures if retuned; the real-time annotations on `ticks_per_second`) are updated in the same change.
- [ ] A **config-anchor regression test** proves the shipped `.tres` values still produce the documented tick anchors — a future silent retune fails the suite instead of drifting.
- [ ] If Option A is chosen: AC7's and AC27's tick counts, the GDD's worked examples, and the two affected test files are updated **in the same change**.

---

## Implementation Notes

*Derived from ADR-0002 Implementation Guidelines:*

- Conversion is one line of arithmetic per knob: `real_time_seconds = ticks / 4.0`. The trap is not the math, it is **missing an occurrence** — the stale figures are spread across F1, F2, F3, and the Tuning Knobs table.
- Do not change how any formula is *expressed*. Rates stay per-tick; only the annotation changes (Option B) or the value changes (Option A). Wall-clock must never enter the code.
- The quick-spec should state, in this order: the trigger (`ticks_per_second` 2.0 → 4.0), the affected knobs, the option chosen, the resulting real-time figures, and the falsification plan (the MVP playtest probe, story 011).
- Coordinate with the building-system side: `building-system` F3's build pacing inherited the same doubling, so the "room+bed builds in ~1–2 min" half of the gap claim is also 2× off. State the corrected gap using **both** corrected halves, or the confirmed/retuned verdict rests on one stale number.
- Record this as a **config change with rationale**, exactly as the Sprint 8 tick-rate re-tune was — same file shape, same discipline.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Stories 002/003/005/008: the math and tests this pass is measured against.
- Story 011: the playtest that falsifies the pacing hypothesis.
- `time-tick-system`: the tick rate itself (already landed and ratified).
- Building System's own F3 pacing re-statement — coordinate, but do not edit its GDD from this story.

---

## QA Test Cases

*Config/Data story — smoke check plus one regression guard (testing standards).*

- **Anchor guard**: Given the shipped `NeedsMoodConfig.tres`, When the time-to-urgent and time-to-satisfied tick counts are derived from it, Then they equal the values documented in the GDD and asserted by stories 002/008 — a mismatch fails the suite.
- **Range guard**: Given any retuned value, When `validate()` runs, Then no clamp warning is produced (i.e. the new value is genuinely inside its declared safe range, not clamped into it).
- **Doc completeness**: Given `design/gdd/needs-mood-system.md`, When searched for second-based figures, Then every one of them is consistent with `ticks_per_second = 4.0` — no surviving 2.0-rate figure.
- **Smoke check**: `production/qa/smoke-[date].md` records a boot + one full observed cycle at the shipped values, with the real-time duration measured and compared to the documented figure.

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `production/qa/smoke-[date].md` (smoke check pass) **plus** `neues-spiel/tests/unit/needs_mood/config_pacing_anchor_test.gd` (regression guard) **plus** the recorded quick-spec `design/quick-specs/needs-mood-real-time-rate-pass-2026-07-XX.md`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: 002 (decay anchors), 003 (recovery rates), 005 (smoothing), 008 (the determinism tests this pass must not silently break)
- Blocked on: the Option A / Option B decision above (user call)
- Unlocks: 010 (the live pair should run against ratified values), 011 (the playtest probe measures the shipped pacing)
