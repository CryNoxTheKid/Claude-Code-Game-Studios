# Story 024: A villager cannot finish a wall

> **Epic**: Villager AI & Behavior
> **Status**: Ready — BLOCKING. This breaks the game's core promise.
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2 days (1 day spike + 1 day fix; the spike may re-scope the fix)
> **Manifest Version**: 2026-07-23
> **Last Updated**: 2026-07-27

## Context

**GDD**: `design/gdd/villager-ai-behavior.md` (job selection, pathfinding),
`design/gdd/building-system.md` (construction jobs)
**ADR Governing Implementation**: ADR-0007 (AStar3D pathfinding & room analysis) — primary;
ADR-0008 (villager AI execution), ADR-0009 (deterministic movement)

**Engine**: Godot 4.7-stable | **Risk**: HIGH

### The finding

**A single autonomous villager cannot fully enclose any `WallTool`-built room, of any
size, in the shipped game today.** Construction always plateaus at the topmost wall
layer.

Found while implementing `scene-009`, by instrumenting the real booted `GameWorld` —
real `WallTool` → `CommitPipeline` → `ConstructionTickLoop` → both villager gates, one
real villager — across multiple room shapes and sizes (1×2 interior matching the
shipped demo, 4×5 interior), and multiple build orders (all segments at once, one
segment at a time, and a "leave a doorway open until the villager is confirmed
outside" strategy). **Not one configuration reached full enclosure.**

### It is NOT what Sprint 12's plateau spike assumes

`sprint-12.md`'s `spike-plateau` row hypothesises "the villager cycling through
seal-prevention write refusals as the room closes around it." The evidence rules that
out:

- Stuck cells read `BlueprintCell.state == PLANNED`, `claimed_by_villager_id == -1` —
  **never claimed at all**, not claimed-and-refused.
- `VillagerSealPreventionGate.get_abandon_count(cell) == 0` for every stuck cell.

`abandon_count` only increments on an actually-refused write, and refusing requires an
existing claim. The seal-prevention path is never even consulted for these cells:
**job selection excludes them before any claim is attempted.**

`would_trap_builder` was observed both true and false depending on villager position,
which is consistent with it being irrelevant here.

### Working hypothesis, evidence-supported

Job-selection reachability can extend **one** step past an already-known-standable
graph node to reach an unbaked destination — which explains why a wall's **second**
layer reliably completes, since it sits one step above always-standable original
ground. It cannot chain **two** such extensions — which explains why the **third**
layer never does, because standing there requires a height that is only standable
because of the second layer's own construction.

Independent of tick budget: identical stalls at 600 and at 5000 ticks, zero improvement.

`WallToolConfig.wall_height` ships as **3**, and villager clearance requires 3 clear
cells. So this is not an edge case — it is every wall the player will ever draw.

### Second, independent finding (same investigation)

`CandidateCellRules.is_candidate_interior_cell` requires a cell to be **roofed** (solid
within `max_room_height` directly above) before it is even a candidate for Room
classification. `tools/payoff_loop_demo.gd` builds **walls only, never a roof**. So even
if the walls completed, `is_bed_sheltered()` could not read true for a bed inside.

Two independent reasons the demo's bed has never been sheltered.

---

## Acceptance Criteria

- [ ] AC1: A single villager, given a drawn room of `WallToolConfig.wall_height` and any
      reasonable footprint, completes **every** wall cell — no plateau at the top layer.
- [ ] AC2: The root cause is named in the story before the fix lands: state precisely
      which reachability/job-selection rule excluded the cells, with the evidence.
- [ ] AC3: The fix does not weaken seal prevention. A villager must still refuse a write
      that would trap it, and `villager-ai-016`'s livelock escape must still be reachable.
- [ ] AC4: Determinism survives (ADR-0009): same world, same villager, same job order.
- [ ] AC5: `tools/payoff_loop_demo.gd` builds a **roof** as well as walls, so a finished
      room is actually Room-classifiable and its bed can be sheltered.
- [ ] AC6: The demo reaches a fully enclosed, roofed room with one villager, and says so
      in its own report.

## Anti-Vacuity Lever

Assert on the real booted game, not a fixture: draw a room through the hosted `WallTool`,
run the real tick loop with one real villager, and assert **every** blueprint cell reaches
`BUILT` within a stated tick budget. Today this fails at the top layer in every shape and
size tried, so it cannot pass vacuously. Record the observed plateau — cell coordinates,
`state`, `claimed_by_villager_id`, `abandon_count` — in the commit body.

## Out of Scope

- Retuning `wall_height` to dodge the bug. Three is the designed height; a fix that only
  works at two is not a fix.
- The hen-and-egg pacing question (D10) — separate, and a creative-director call.
- Multi-villager work sharing.

## QA Test Cases

**AC1 — a room actually gets finished**
- Given: the real booted game, a room drawn through the hosted wall tool, one villager.
- Then: every blueprint cell reaches BUILT inside the stated budget.

**AC3 — seal prevention still works**
- Given: a villager whose next write would trap it.
- Then: it still refuses, `abandon_count` still increments, and the livelock escape is
  still reachable after the configured number of abandons.

**AC5/AC6 — the demo builds a real room**
- Given: `tools/payoff_loop_demo.tscn` run end to end.
- Then: walls AND roof complete, the interior classifies as a Room, and the report says so.
