---
name: project-scene-world-management-review-history
description: Status and recurring defect pattern for design/gdd/scene-world-management.md across its review cycles (as of 2026-07-10 re-review #2)
metadata:
  type: project
---

`design/gdd/scene-world-management.md` has gone through 2 full reviews plus
2 post-review revisions, all on 2026-07-10. Full history in
`design/gdd/reviews/scene-world-management-review-log.md`.

- Review #1 (first full review): 3 blockers (warp-reset trap, reset-vs-signal
  race, missing boot-order). Fixed same session.
- Re-review #1: found the fix for one trap (warp-reset) reintroduced a new
  trap in a different subsystem (undo-abort trap via Building's undo-clear on
  transition-begin) — same irreversible-side-effect-on-begin bug class, plus
  a World Root topology contradiction. Fixed same session (Core Rule 7
  side-effect discipline: begin=reversible, complete=irreversible/success-only).
- Re-review #2 (my pass, 2026-07-10): found the re-review #1 fix (Core Rule 7)
  closed the irreversible-effect trap but opened a mirror-image trap on the
  *reversible*-effect side — see [[feedback-signal-abort-unwind-check]].
  Transition-abort now permanently freezes Camera & Input's Suspended state
  (cascading through Building System, Building UI, Villager Info UI), with no
  defined recovery signal, directly contradicting AC8 ("full control" after
  abort). Also found the Booting state's failure-exit was never formalized in
  the States table the way Transitioning's was (Edge Cases/AC17 describe
  boot-halt, but the States table's Booting row still only has the
  happy-path exit condition). Verdict: NEEDS REVISION (2 BLOCKING + several
  RECOMMENDED — AC13 missing scope tag, Core Rule 2's hosted-systems list
  incomplete vs. Dependencies table, cancel-order wording contradiction with
  building-system.md).

**Why this matters for future reviews:** this GDD has now shown the same
defect SHAPE three times in a row — a fix for one abort/failure-path bug
introduces a structurally similar bug elsewhere in the same signal chain.
**How to apply:** if asked to re-review this file again (re-review #3+),
specifically re-audit every signal-gated recovery/unwind path as its own
checklist item, not just re-verify the two bugs found in re-review #2.
