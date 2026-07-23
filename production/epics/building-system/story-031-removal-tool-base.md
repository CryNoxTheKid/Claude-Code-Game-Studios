# Story 031: Removal tool base — Planned→Canceled + job revoke

> **Epic**: Building System
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 0.5 day
> **Manifest Version**: 2026-07-23
> **Last Updated**: —

## Context

**GDD**: `design/gdd/building-system.md`
**Requirement**: `TR-building-system-068` (Canceled transition), `TR-building-system-063` (base removal branch)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0016 (Build-Project Entity Lifecycle) — primary
**ADR Decision Summary**: Removing a blueprint (not-yet-Built) cell is instant/free: Draft → instant cancel; Queued/UnderConstruction → instant cancel with claim revoke. The removal tool's behavior branches on the target cell's own micro-state.

**Engine**: Godot 4.7-stable | **Risk**: MEDIUM
**Engine Notes**: No post-cutoff APIs. The graceful claim-revoke mirrors the pause/undo revocation contract (Villager AI Rule 3 / Edge Case 4).

**Control Manifest Rules (this layer — Core):**
- Required: removal of a not-yet-Built cell is instant — Draft → Canceled (no job); Queued/UnderConstruction → Canceled with the claiming villager's job revoked (graceful abandon); Canceled is terminal and never reachable from Built.
- Forbidden: never remove a Built cell via this base path (Built → demolition order is Story 015/009); Built cells mutate only via worker jobs.
- Guardrail: cancel is O(1) per cell.

---

## Acceptance Criteria

*From GDD `design/gdd/building-system.md`, scoped to this story:*

- [ ] AC41: GIVEN a Planned blueprint cell, WHEN the player directly removes it (not via undo), THEN it transitions to Canceled, the ghost is removed, and any claimed job is revoked (Blueprint lifecycle). [TR-068]
- [ ] Removing a Queued/UnderConstruction (released but not yet Built) cell cancels instantly and revokes the claiming villager's job. [TR-063]

---

## Implementation Notes

*Derived from ADR-0016 + building-system Core Rule 16 (blueprint branch) + Blueprint lifecycle table, TR-068/063:*

- The removal tool on a not-yet-Built cell: Draft → instant cancel, no job; Queued/UnderConstruction → instant cancel and the claiming villager's job is revoked (graceful abandon, mirroring the pause/undo revocation contract).
- On cancel: remove the ghost, transition the cell to Canceled (terminal). Canceled is never reachable from Built.
- If the canceled cell was a floor-excavation entry, write back its `restore_value` (Story 012) — do not leave empty.
- This is the pre-slice removal BASE. The full micro-state branch (adding Built → demolition order, and the draft-eraser/door-gap semantics) is the slice story 015, which builds on this. Furniture removal is Story 017.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 015: the Built → demolition-order branch and draft-eraser semantics (extends this base).
- Story 009: demolition-order execution.
- Story 017: furniture-specific removal.

---

## QA Test Cases

**AC41 — Planned cell direct removal**
- Given: a Planned blueprint cell.
- When: the removal tool targets it (not via undo).
- Then: it transitions to Canceled, the ghost is removed, any claimed job is revoked.

**Queued/UnderConstruction cancel + revoke**
- Given: a released-but-unbuilt cell (possibly claimed).
- When: removed.
- Then: instant cancel + graceful job revoke.
- Edge cases: a floor-excavation cell restores its `restore_value` on cancel (Story 012); a Built cell is NOT handled here (routes to Story 015/009).

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/building_system/removal_tool_base_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 021 (blueprint cells), Story 029 (cell micro-states + claims to revoke).
- Unlocks: Story 015 (extends to Built → demolition), Story 027 (block-tool remove mode).
