---
name: project-ridb-gdd-review-history
description: resource-item-database.md first adversarial AC review (2026-07-10) — 7 BLOCKING findings, verdict NEEDS REVISION; check before any re-review
metadata:
  type: project
---

`design/gdd/resource-item-database.md` received its first full adversarial
Acceptance-Criteria review on 2026-07-10 (no prior review log existed for this
GDD). **Verdict: NEEDS REVISION** — not MAJOR REVISION NEEDED; the schema, Core
Rules, and most of the 22 ACs are sound, and the issues found are a focused patch
pass, not a re-author.

7 BLOCKING findings from review round 1:
1. All 22 ACs missing test-type tags entirely (see
   [[project-gdd-tag-convention-state]] for the corrected framing of why/how much
   this matters — it is not "everyone else already does this").
2. Tuning Knob invariant "tier-0 set must always contain ≥1 entry per material
   family" (Core Rule 6 / Tuning Knobs table) is asserted but never boot-validated
   — absent from the States-table Validating checks list — and untested by any AC.
3. AC3 vs. Edge Case 4 wording mismatch: AC3's error names "both entries," Edge
   Case 4's error names "both files" — same failure mode, different assertion
   (mirror-defect pattern, same class documented in the SWM review history).
4. No defined interface contract for how boot-failure/warning message content is
   exposed for testing — blocks implementing ~9 of 22 ACs (3, 4, 5, 6, 7, 9, 10,
   11, 20, 21) as headless GUT unit tests per the project's DI-over-singleton
   testability standard (asserting on raw stdout/log output is not compliant).
5. AC19 (mutation-resistance) depends on an unresolved architecture decision —
   Godot 4.7 GDScript `Resource`s are reference types; whether queries return
   defensive copies or live references (with a per-frame query performance cost
   either way, given Building System's placement-palette usage) is undecided.
6. States table's Failed-state exit condition ("Session ends") is inconsistent
   with `scene-world-management.md`'s AC17b / Open-Questions model of boot-HALT as
   persistent non-progression / an error screen, not process termination — and
   RIDB's own Dependencies section disclaims boot-sequencing ownership while the
   States table still asserts a definitive terminal behavior, pre-empting the
   pending boot-order ADR.
7. AC17 ("fails/errors rather than returning data") is a disjunctive, ambiguous
   pass condition that also touches boot-ordering behavior RIDB explicitly defers
   to the future ADR — internal contradiction.

Also ~11 RECOMMENDED and 3 NICE-TO-HAVE findings: AC4/AC6 bundle 2-3 violation
sub-cases behind "or"/"e.g." without requiring each be independently tested; AC5
doesn't specify which required-field class is tested (risk: validator skips the
"unused until Alpha" fields); AC7 only proves the "names every invalid entry"
claim at N=2; AC9 bundles a cross-system Save/Load cell-preservation assertion
that can't be tested until that Undesigned GDD exists, plus an ambiguous "logged
exactly once per load" event boundary; AC13/14/16 couple tests to live "MVP data
set" content rather than a frozen fixture; AC18/AC19 have near-duplicate coverage;
AC22 is blocked pending Open Question 5's data-format ADR (path string vs. typed
Resource); missing AC for `missing_item`'s own visual asset resolving at boot;
missing AC guarding Core Rule 2's "loads once" claim; missing Visual/Feel evidence
hook for the tier-0 color-language requirement; Safe Range enforcement ambiguity
for `tier` (0-9) and `max_stack_size` (1-999, only the lower bound is tested).

**Why**: First-review baseline for this GDD — captures what actually needs fixing
so a future re-review can verify fixes against the live file text rather than
trusting a "previous blockers fixed" summary, per
[[feedback-verify-fix-claims-against-file]].

**How to apply**: On re-review, grep the current AC text and States table
directly for each of the 7 blockers above. Specifically re-check: AC3 vs. Edge
Case 4 wording now match; AC19's copy-vs-reference question was actually resolved
(not just asserted resolved); the Failed-state wording against the *current*
`scene-world-management.md` text (SWM is a moving target — its own AC17b wording
may have changed since 2026-07-10, don't assume it's static).
