---
name: project-needs-mood-gdd-review-history
description: needs-mood-system.md adversarial AC review history — r1 (2026-07-10) NEEDS REVISION, 7 blockers incl. unspecified why-string contract and untested Edge Case 11
metadata:
  type: project
---

`design/gdd/needs-mood-system.md` review history (Gameplay-layer GDD, zero
AC tags — consistent with [[project-gdd-tag-convention-state]], not a
blocker).

**r1 (2026-07-10, adversarial first full review of 27 ACs) — NEEDS REVISION.**
Formulas independently re-simulated in Node (double-precision) and confirmed
correct: F1's 1072-tick urgency boundary, F2's 140-tick bed / 350-tick ground
recovery worked examples, and F3's snap-to-70.0-exactly all reproduce bit-for-
bit as the GDD claims — the math itself is sound.

7 BLOCKING findings:
1. **Why-string generation is completely unspecified** — no Core Rule, no
   Formula, no AC define how "the strongest current drain plus its missing
   source" is computed; it appears only as a one-line UI Requirements bullet,
   yet `villager-info-ui.md` depends on it verbatim (its Rule 5, AC9). Biggest
   gap in the doc.
2. Edge Case 11 (recovery source upgraded/downgraded mid-recovery, re-
   evaluated per tick, added 2026-07-10 from a cross-review walkthrough) has
   **zero AC coverage** — a Logic/state-transition rule with no test evidence.
3. Edge Case 3's "re-enters ... Urgent" branch (interruption landing BELOW
   `urgency_threshold`) has no AC — AC13 only tests the above-threshold
   ("re-enters Satisfied") landing at value=60.
4. AC14's GIVEN doesn't exclude the F3 snap-rule zone (`abs(mean-mood)<0.05`)
   — as literally written a test author could pick a mock value inside the
   snap zone and the "moves by exactly (mean-mood)/smoothing" assertion would
   be false (snap should fire instead). Needs an explicit "≥0.05" precondition.
5. AC27's "within ±5%" on a fully deterministic tick-based cycle (exact ticks:
   1072 decay + 140 bed recovery = 1212 ticks = 606s at 1x) is unjustified
   slack that contradicts every other AC's exactness and risks being
   implemented as a literal wall-clock assertion (violates the project's
   no-time-dependent-assertions determinism rule). Should assert the exact
   tick count instead.
6. The recovery-ladder ordering invariant (`ground_penalty` < the-
   `unsheltered_bed_multiplier` < 1.0, documented in Tuning Knobs as a hard
   "collapse" failure mode) has **no AC and no described runtime/config
   validation** — confirmed by full-text read, not just AC-list scan.
7. The "Villager AI reports a recovery activity" boundary (mocked by ACs 3,
   8-13) has no concrete interface (method/signal signature, param shape for
   source id + shelter flag) defined in either this GDD or
   `villager-ai-behavior.md` — and that GDD's own Dependencies/Cross-
   References tables (lines 280-283, 586) still say "undesigned —
   PROVISIONAL" / "(not yet authored)" despite this GDD's Dependencies table
   claiming to have "CONFIRMED" and resolved that provisional marker. Stale
   cross-doc reference, verified via grep per [[feedback-verify-fix-claims-against-file]].

8 RECOMMENDED findings (non-blocking clarity/coverage nits): AC4's "parked at
25.0 for many ticks" describes a state natural decay can never produce
(needs a direct-state-injection framing note); Edge Case 6's specific
double-threshold-cross-in-one-burst scenario has no dedicated AC (only
generic burst ordering, AC21); AC11's "one increment" doesn't say it's
source-rate-dependent; AC19's exact-70.00/40.00 crossing is ambiguous about
mocked-comparator vs. natural-EMA framing; the Game Feel section's playtest
criteria are never referenced from the AC list (orphaned — unlike the sibling
`villager-info-ui.md` AC20, which does reference its own Game Feel criterion);
AC24/25's `[PROVISIONAL — Save/Load]` tag format doesn't match the peer
`[Integration, VS+ — DEFERRED pending the Save/Load & World Persistence GDD]`
convention used in `resource-item-database.md` AC9b and
`scene-world-management.md` AC18b; intra-tick F1→F2→F3 ordering (does F3 on
tick N consume tick N's post-decay value?) isn't explicitly asserted; AC5/AC6
overlap (AC6 is a superset of AC5).

Cross-checks that PASSED cleanly (no defects): `design/registry/entities.yaml`
matches the GDD exactly on `urgency_threshold`(25), `satisfied_threshold`(95),
`ground_penalty`(0.4), `unsheltered_bed_multiplier`(0.7); `decay_per_tick`/
`base_recovery_per_tick` are correctly NOT registered (internal-only per the
registry's own rule, since no other GDD needs the raw value).
`villager-info-ui.md`'s AC7 (raw unsmoothed need bars), AC8 (band-event-only
icon update), AC9 (verbatim why-string pass-through) are all consistent with
what this GDD promises to supply, modulo blocker #1 above.

**Why**: first full adversarial pass — the doc's formulas and state machine
are fundamentally sound (verified independently, not just trusted), but a
load-bearing UI contract (why-string) was never actually specified, and two
state-transition edge cases (11, and half of 3) shipped without test
evidence despite the doc's own "Logic ACs are BLOCKING" framing.

**How to apply**: Do not approve this GDD until at minimum blockers 1-7 are
addressed. When re-reviewing, grep the actual current AC/Core-Rule text for
a why-string Core Rule/Formula and for new ACs covering Edge Case 11 and the
Edge Case 3 Urgent-branch before trusting a "fixed" changelog summary — see
[[feedback-verify-fix-claims-against-file]].
