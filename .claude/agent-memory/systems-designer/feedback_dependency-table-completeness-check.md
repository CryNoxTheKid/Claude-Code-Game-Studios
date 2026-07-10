---
name: feedback-dependency-table-completeness-check
description: For a Foundation/leaf GDD, cross-check its Downstream/Dependents table against every OTHER already-authored GDD that actually references it by name or file path — not just the ones it remembers to list
metadata:
  type: feedback
---

A Foundation-layer or leaf-system GDD's own Dependencies section is written
from memory at authoring time and goes stale as sibling GDDs are authored or
revised later. Do not trust it at face value during review. Instead:

1. Grep every other GDD in `design/gdd/` for the target file's name/path AND
   for its plain-English system name (both — some GDDs reference by name
   only, not by path).
2. Build the actual consumer list from those hits.
3. Diff against the target GDD's own Downstream/Dependents table.

Two distinct defect shapes show up from this diff:

- **Missing row entirely**: a sibling GDD's approved Core Rule bakes in a
  real dependency (e.g., a boot-order gate keyed off this system reaching
  Ready) but the target GDD's Dependencies section never mentions that
  sibling at all — sometimes because the target GDD waves the relationship
  off as "an implementation/architecture concern" even though the sibling
  GDD treats it as a *design-level* rule. The sibling's classification wins
  if it's already approved/designed — a leaf system doesn't get to
  unilaterally downgrade a dependency another GDD has already formalized.
- **Inconsistent treatment of the same relationship class**: the target GDD
  documents SOME "shared vocabulary / no runtime call" consumers with an
  explicit row (with the caveat spelled out) but silently omits OTHERS that
  have the identical relationship shape — an asymmetry with no principled
  reason, just an authoring oversight.
- **Stale status**: the row exists but still says "Undesigned / provisional"
  for a system that has since been authored (check the referenced GDD's own
  `Last Updated` date against the target's — if the referenced GDD is
  newer, the provisional marker is probably stale and the contract may
  already be confirmed on the other side).

**Why:** Found in `design/gdd/resource-item-database.md` (2026-07-10 first
full review). `scene-world-management.md` (APPROVED, references this DB's
Ready state as a Core Rule 1 boot-HALT gate) and `needs-mood-system.md`
(Designed, keys its recovery-source table by this DB's item ids, same
"shared vocabulary" shape as the Voxel World row this DB DOES list) were
both absent from the DB's own Downstream table. Separately, `building-ui.md`
(Draft, dated one day AFTER this DB's Last Updated) was still marked
"Undesigned / provisional" in the DB's table despite already confirming the
exact contract cited.

**How to apply:** Run this check any time a Foundation/leaf-layer GDD is
under adversarial review, especially if 2+ sibling GDDs have been authored
or revised since the target's `Last Updated` date. Cheap to run (a few
greps), catches real bidirectionality violations of the project's own
`design/CLAUDE.md` / `.claude/rules/design-docs.md` rule ("Dependencies
must be bidirectional"). Related: [[feedback-directional-asymmetry-check]]
(same family, applied to state-machine wording instead of dependency
tables).
