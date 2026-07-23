# Epic: Voxel World / Grid Data

> **Layer**: Foundation
> **GDD**: design/gdd/voxel-world.md
> **Architecture Module**: Voxel World / Grid Data (the `Vector3i`-addressed cell grid; raw read/write primitives; change-signal emission; procedural terrain; chunked mesher + paged residency storage tier)
> **Manifest Version**: 2026-07-23
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories voxel-world`

## Overview

Voxel World is the single source of truth for the block-level composition of the
world — procedural valley terrain and every placed building block, on one
`Vector3i`-addressed grid. It owns the O(1) accessor API (`get_cell`,
`raycast_cells`, `get_neighbors`, `set_cell`/`clear_cell`, `bulk_write` with its
exactly-one-signal guarantee, `iterate_occupied`), the `cell_changed` /
`cells_changed_batch` signals, the chunked face-culled mesher (ADR-0014), and the
paged region-file residency tier (ADR-0015) that keeps resident memory bounded by
footprint, not world size — transparently to every consumer. Block picking is DDA
grid-walk on the data layer, never a physics collider.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0014: Chunked Voxel Rendering & Large-World Storage | 16×16 chunk `ArrayMesh` face-culled mesher; **faces wind CW, backface culling ENABLED** (4.7 front-face is clockwise); view-window streaming with per-frame build+unload budgets; ghosts = pooled `MeshInstance3D`; DDA picking on the data layer | HIGH |
| ADR-0015: Large-World Storage & Residency (16k) | Paged region-file residency (supersedes ADR-0014's full-world-at-boot clause); resident set = camera-near ∪ settlement chunks; time-based page/evict budgets; read-through in-flight-write cache; region I/O + terrain-gen on a capped `WorkerThreadPool`, never synchronous on the frame — **Accepted, spike-validated 2026-07-23** | HIGH |
| ADR-0004: Physics Backend & Picking Strategy | Block picking = manual DDA grid-walk driven by `get_world_ray()`; zero physics colliders on blocks | HIGH |
| ADR-0012: Save/Load Serialization Strategy | Voxel save format IS ADR-0015's region files (chunked by construction); occupied cells only via `iterate_occupied()` — **VS-tier for the save orchestrator** | MEDIUM |
| ADR-0002 / ADR-0001 | Terrain/streaming tunables from typed `.tres` config; injected-tier module | MEDIUM |

Engine-risk basis (4.7 policy): **HIGH** — the rendering domain is the top
flagged knowledge gap. LLM instinct is wrong on multiple post-cutoff facts that
this epic depends on: Godot 4.7 front-face winding is **clockwise** (the slice's
multi-session "missing faces" root cause), `WorkerThreadPool.wait_for_task_completion()`
returns an Error code (not the Callable's return value — a spike bug), and
`GridMap` is measurably non-viable at scale. Every mesher/residency API must be
cross-referenced against `docs/engine-reference/godot/` and audited against the
engine's actual convention, never a self-stored assumption.

## GDD Requirements

38 TRs registered (`TR-voxel-world-*`). Coverage:

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-voxel-world-025 | Rendering representation (chunked mesher, not GridMap) | ADR-0014 ✅ |
| TR-voxel-world-052 | CW winding + backface culling ENABLED per engine convention | ADR-0014 ✅ (slice propagation) |
| TR-voxel-world-017 / -018 | DDA cell-picking mechanism, no colliders | ADR-0004 / ADR-0014 ✅ |
| TR-voxel-world-051 | Load-before-write for far-world (non-resident) mutations | ADR-0015 ✅ |
| TR-voxel-world-021 | Serialize occupied cells only; region-file format | ADR-0012 / ADR-0015 ✅ |
| TR-voxel-world-023 | Terrain/streaming tunables from config | ADR-0002 ✅ |

**Coverage summary**: All ADR-worthy TRs trace to Accepted ADRs; remaining TRs
are GDD-specified. No untraced requirements.

**At-risk / deferred**: `duplicate_deep()` / typed `Dictionary[Vector3i,...]`
syntax (4.4+) are MEDIUM-risk API-verification items, not open decisions. The
save-orchestrator half of ADR-0012 is VS-tier; M01 builds the region-file storage
format and residency, not the full save/load flow.

## Milestone 01 Notes — HOME OF TWO TECH DEBTS

- **TECH DEBT 1 — Mesher CW-winding rewrite lands here.** The slice shipped on
  CCW + `CULL_DISABLED` (a documented, now-EXPIRED 2× overdraw mitigation). This
  epic rewrites faces to wind CW with backface culling RE-ENABLED (TR-voxel-world-052),
  audited against the engine's actual convention, with no missing-face regressions.
  Milestone-01 Must-Ship "Mesher CW-winding rewrite + culling re-enable"
  (nominal owner `godot-shader-specialist`); architecturally it is Voxel World's
  mesher. Do it early, before asset scale-up (milestone risk register).
- **TECH DEBT 3 — ADR-0015 C1/C4 residency tuning lands here.** The two carried
  tuning items are implemented as stories with **measured** values (not open
  decisions), recorded as config changes with rationale (using the Foundation
  Spine `.tres` + rationale pattern). Milestone-01 Must-Ship "ADR-0015 C1/C4
  residency tuning."
- Performance gate: 60 FPS on the production window with culling RE-ENABLED
  (headroom expected — slice held 60 FPS at 2× faces on `CULL_DISABLED`).

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/voxel-world.md` are verified
- The CW-winding rewrite passes with culling re-enabled and no missing-face regressions
- ADR-0015 C1/C4 values are measured and recorded as config changes with rationale
- Logic/Integration stories have passing test files in `tests/`

## Next Step

Run `/create-stories voxel-world` to break this epic into implementable stories.
