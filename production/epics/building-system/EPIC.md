# Epic: Building System

> **Layer**: Core
> **GDD**: design/gdd/building-system.md
> **Architecture Module**: Building System (blueprint/project lifecycle; construction job queue/claim contract; placement validity; undo/redo stack; tool state machine)
> **Manifest Version**: 2026-07-23
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories building-system`

## Overview

Building System is the game's central verb — it turns player intent into
structures. It owns the persistent project-entity lifecycle
(DRAFT → BUILDING ⇄ PAUSED → DONE, ADR-0016), the placement toolset (walls/floors/
roofs drag tools, free single-block, furniture), placement validity, pooled-
MeshInstance3D ghost previews, plan-only undo/redo, the worker-claimed
construction job queue (`claim_job`/`release_job`/`on_site_check`), change orders,
and worker-executed demolition (uniform for blocks and furniture). Its placement
pick is DDA-only (structurally incapable of hitting villagers, zero physics
queries). Built cells are authoritative Voxel World data mutated ONLY via worker-
executed jobs — never a direct edit or an undo.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0016: Build-Project Entity Lifecycle | Persistent draft→released→paused→done project entities; 26-neighborhood grouping/merge; change orders attach without recreation; plan-only undo; job-based demolition incl. furniture; cell→project reverse index (O(1) selection); worker attribution — **Accepted, prototype-validated 2026-07-22/23** | MEDIUM |
| ADR-0014: Chunked Voxel Rendering & Large-World Storage | Ghost previews = pooled `MeshInstance3D` (`max_cells_per_command = 512`); ghost-anchored `extra_solid` picking predicate on the §4 DDA path; state colors live on ghost/overlay, never committed-block materials | HIGH |
| ADR-0004: Physics Backend & Picking Strategy | Building System pick calls ONLY the DDA step — zero `intersect_ray`/`PhysicsDirectSpaceState3D` in the pick path (grep-verifiable) | HIGH (shared) |
| ADR-0009: Deterministic Movement & Occupancy Ordering | Seal-prevention negative-write gate: a Planned→Built write that would entrap a villager is gated by reading the discrete `current_cell`/body-column (builder self-seal is the one sanctioned exception, watchdog-healed) | HIGH |
| ADR-0010: Cross-System UI/World Input Arbitration | Build-Mode-gated click routing + Selection arbitration; drag ownership via `_input()` for the drag window; DDA→owning-project resolution feeds Selection | MEDIUM |
| ADR-0012 | `serialize()` includes project entities (`restore_value`, `worker_ids`, pending orders); undo/redo stack excluded — **VS-tier orchestrator** | MEDIUM |
| ADR-0002 / ADR-0001 | Building tunables from typed `.tres` config; injected-tier module | MEDIUM |

Engine-risk basis (4.7 policy): **HIGH** — inherits the rendering/picking HIGH-risk
domain. Ghost rendering (pooled `MeshInstance3D` with `material_override`),
`InputEventKey.echo` for undo/redo repeat, and the DDA-only pick path all sit on
the post-cutoff rendering/input facts flagged in architecture.md. `GridMap` is
forbidden for committed blocks; zero physics in the pick path is grep-verifiable.
Cross-reference `docs/engine-reference/godot/` before any rendering/input API.

## GDD Requirements

96 TRs registered (`TR-building-system-*`) — the largest MVP system. Coverage:

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-building-system-003 / -035 / -039 / -041 | Rendering/ghost representation | ADR-0014 ✅ |
| TR-building-system-002 / -026 | DDA placement pick, zero physics | ADR-0004 / ADR-0014 ✅ |
| TR-building-system-040 | Mid-path solidification race / seal-prevention write gate | ADR-0009 ✅ |
| TR-building-system-038 | Tunables from config | ADR-0002 ✅ |
| TR-building-system-023 / -033 | Serialize projects; exclude undo stack | ADR-0012 / ADR-0016 ✅ (VS orchestrator) |
| (project lifecycle, change orders, demolition, undo) | Draft→built lifecycle, merge, demolition, plan-only undo | ADR-0016 ✅ |

**Coverage summary**: All ADR-worthy TRs trace to Accepted ADRs; the remaining
(majority) are GDD-specified. No untraced requirements.

**At-risk / deferred**: TR-building-system-007 (non-Flat roof formation —
Gable/Hip/Shed) is **VS-tier**; Flat is MVP-sufficient. Do not build the other
three roof algorithms in M01. The save-orchestrator half of ADR-0012 is VS-tier —
M01 builds the `serialize()` contract shape, not the full save/load flow.

## Milestone 01 Notes

- No tech-debt or CD-protected item lands here directly, but M01 delivers the
  **full ADR-0016 lifecycle** as Must-Ship "Building System playable"
  (draft-first projects: draw → release → workers build; room/roof/house tools;
  change orders; worker-executed demolition; plan-only undo), with logic ACs
  covered by unit tests.
- Depends on all five Foundation systems (Voxel World, Camera & Input, RID, Time
  & Tick) + the boot spine being integrated first.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/building-system.md` are verified
- Grep proves zero physics API in the pick path; state colors absent from committed materials
- The full draft→built→demolish lifecycle has passing logic unit tests
- Integration stories have passing tests in `tests/`

## Next Step

Run `/create-stories building-system` to break this epic into implementable stories.
