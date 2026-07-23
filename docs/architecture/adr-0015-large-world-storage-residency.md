# ADR-0015: Large-World Storage & Residency (16k Target)

## Status
Proposed (pending storage/streaming spike — 2026-07-23). Supersedes ONLY ADR-0014's full-world-at-boot allocation clause (Decision §1) for the 16,000×16,000×32 production target; ADR-0014's mesher, view-window, and streaming design remain Accepted and unchanged. This ADR becomes Accepted only after the spike defined below passes, mirroring the ADR-0007/0008 provisional-until-QQ3 gate pattern.

## Date
2026-07-23

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7-stable |
| **Domain** | Rendering / World Data (storage residency) |
| **Knowledge Risk** | MEDIUM — the residency mechanism is plain file I/O + the existing chunk model; the risk is empirical (page-in latency, sustained-travel memory) not API-novelty. `FileAccess` region-file reads/writes and `store_var`/`get_var` on packed arrays are the same 4.4+ surface ADR-0012 already vetted. |
| **References Consulted** | `docs/engine-reference/godot/` (modules/rendering.md, current-best-practices.md); ADR-0014 measurements; `prototypes/last-seal-vertical-slice/REPORT.md` |
| **Post-Cutoff APIs Used** | None beyond ADR-0014's baseline and ADR-0012's `store_var`/`get_var` return-type handling |
| **Verification Required** | PENDING — this ADR is Proposed; the storage/streaming spike (see Validation Criteria) is its empirical gate, exactly as QQ3 gated ADR-0007/0008. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0014 (Chunked Voxel Rendering) — this ADR changes only *which chunks are resident and where far chunks live*, behind ADR-0014's unchanged chunk model and public accessor API |
| **Supersedes** | ADR-0014 Decision §1's "allocated for the FULL world at boot" clause (for the 16k target only) — nothing else in ADR-0014 |
| **Enables** | The 16,000×16,000×32 production world target (voxel-world.md Tuning Knobs, Slice revision 2026-07-23) |
| **Blocks** | ADR-0012's chunked-save decision, ADR-0013's dungeon-offset recompute, ADR-0005's window-build timing note — all three await this ADR's residency model (see Cascading Updates) |
| **Ordering Note** | Not implementation-startable until the spike passes and Status flips to Accepted. The 2000×2000×32 baseline (ADR-0014) is unaffected and remains buildable now. |

## Context

### Problem Statement
ADR-0014 allocates the full world's packed chunk data at boot — validated at 2000×2000×32 (~172 MB). The vertical slice's production target is **16,000×16,000×32** (voxel-world.md, Slice revision 2026-07-23): an 8× linear / ~64× areal jump. A naive linear projection is **≈11 GB resident at boot** (172 MB × ~64), ~3× over the project's 4 GB memory ceiling (`.claude/docs/technical-preferences.md`). This is a **storage/residency problem, not a rendering problem** — draw calls are already decoupled from world size by ADR-0014's streamed view window; the only open question is whether all 16k×16k×32 cell data can stay resident at once (it cannot) and what to do instead.

### Constraints
- Godot 4.7-stable; the residency change must sit entirely behind ADR-0014's existing chunk model and Voxel World's unchanged public accessor API (O(1) `get`/`set` by `Vector3i`, `cell_changed` signal, `raycast_cells` DDA)
- 4 GB memory ceiling (`technical-preferences.md`); must hold during sustained travel across the world, not just at boot
- The world is bounded (16k×16k×32), not infinite/streaming-scale — a genuinely infinite-world architecture over-solves this
- Far-world writes exist and are not rare: terrain dig orders (TR-voxel-world-051) and building writes can target chunks not currently resident; villager nav (ADR-0007) covers only a bounded settlement region, so most far chunks have no live consumer but can still be mutated by player-directed orders
- The existing streaming budget/discipline (ADR-0014 §3: `stream_chunk_budget`, staggered unload) must be reused, not replaced — the slice's one 133 ms hitch came from an unload burst, a solved-by-discipline problem this ADR must not reintroduce

### Requirements
- Resident memory bounded to a function of the view/settlement footprint, NOT of world size — flat as the world scales from 2k to 16k
- Correct reads AND writes to chunks not currently resident (a dig order on a far chunk must not corrupt or drop data)
- Save/load must scale without a single monolithic multi-GB pass (aligns ADR-0012's named chunking escape hatch)
- No new frame hitch at the streaming edge beyond ADR-0014's already-accepted streaming cost

## Decision

**Paged / on-demand chunk residency via region files. Only camera-near and active-settlement chunks are resident; far chunks live in on-disk region files, paged in on approach and evicted staggered when they leave the margin. A load-before-write rule guarantees correctness for far-world mutations. The save format IS the set of region files, aligning ADR-0012's chunking escape hatch. Sparse regeneration of unvisited far terrain (Candidate B) is a planned optimization layer within this model, not the load-bearing mechanism.**

**1. Residency set = camera-near ∪ active-settlement, bounded, world-size-independent.** The resident working set is the union of (a) chunks within ADR-0014's existing view radius of the camera, and (b) the bounded settlement-core region the villager nav graph already covers (ADR-0007, `nav_region_size`). Everything else is not resident. Resident memory is therefore a function of that footprint, not of the 16k×16k extent — flat as the world grows. ADR-0014's `view_radius_chunks`, `stream_chunk_budget`, and staggered-unload discipline drive paging; this ADR adds the disk tier they page against.

**2. Region files (fixed-size chunk groups on disk).** The world is partitioned into fixed-size **regions** (a square block of chunks, exact dimensions a spike-tuned knob `region_size_chunks`), each a single file of packed chunk arrays (`store_var` on the same `PackedByteArray`-class storage ADR-0014 §1 uses). A region is read into memory when any of its chunks enters the residency margin and written back when its dirty chunks are evicted. Region granularity (not per-chunk files) bounds file-handle churn and amortizes I/O.

**3. Load-before-write rule (correctness for far-world mutations).** Any write to a cell in a non-resident chunk (a dig order, a building write, a save-triggered flush) MUST first page in that chunk's region, apply the write to the resident copy, mark it dirty, and let normal staggered eviction flush it. A write is never applied to disk blind or dropped. Because writes route through Voxel World's existing batched write API (voxel-world Core Rule 6/8), this rule lives in one place — the write path — not in every caller (Building System, dig-order execution, etc. are unchanged). For the MVP/slice scope, far-world writes are player-directed and low-frequency, so a synchronous page-in on the write path is acceptable; an async pre-load hint is a named optimization if a measured hitch appears.

**4. Save format = region files.** A save is the set of dirty/persisted region files plus the small non-voxel state (project entities, villager state, etc.). This is exactly the chunked-save escape hatch ADR-0012 §Alt-C named — adopting paged residency makes chunked saves fall out of the storage model rather than being a separate decision. Region files are user data (`.gitignore`d), consistent with ADR-0012's save-data category.

**5. Sparse far-terrain regeneration (Candidate B) — planned optimization layer, not load-bearing.** Unvisited far regions need not occupy region files at all if terrain generation is deterministic from the seed: store only *mutated* far chunks (player deltas) and regenerate untouched terrain on page-in. This shrinks both resident and persisted footprint dramatically (settlements are a tiny fraction of 16k²) but leans on cheap, deterministic, versioned regen — a real constraint on terrain gen. It is therefore layered *within* the paging model (a region file that holds only deltas + a "regen the rest" flag) as a fast-follow after the paging mechanism is validated, never the primary mechanism.

**6. Escalation path.** If the spike shows synchronous page-in cannot hold the frame budget at the streaming edge, the escape hatch is `WorkerThreadPool`-backed async region I/O behind the same interface — an implementation swap, not an architecture change (matching ADR-0014's GDExtension-mesher and ADR-0008's threading escape-hatch pattern).

### Architecture Diagram
```
Voxel World public API (UNCHANGED — ADR-0014 §1):
  get(Vector3i) / set(Vector3i) / cell_changed / raycast_cells
        │
        ▼
Residency manager (NEW — this ADR):
  resident set = camera-near chunks (ADR-0014 view radius)
               ∪ active-settlement chunks (ADR-0007 nav region)
        │                                   │
   page-in on approach                 staggered eviction
   (ADR-0014 stream budget)            (ADR-0014 unload discipline)
        │                                   │
        ▼                                   ▼
  Region files on disk (packed chunk arrays; region_size_chunks)
        ▲
        │ load-before-write: a write to a non-resident chunk pages in
        │ its region FIRST, applies to the resident copy, marks dirty
   Far-world write (dig order TR-voxel-world-051, building write)

Save = set of persisted region files + small non-voxel state
       (project entities per ADR-0016, villager state per ADR-0012)

Optimization layer (Candidate B, fast-follow): unvisited far regions
  store only player deltas; untouched terrain regenerated from seed
  on page-in (requires deterministic versioned terrain gen)
```

### Key Interfaces
```gdscript
# Internal to Voxel World — NOT a new public API (ADR-0014's accessors are unchanged).
# The residency tier is transparent to every consumer.

# Residency manager (implementation detail):
func _ensure_resident(chunk: Vector3i) -> void   # page in the chunk's region if absent
func _on_write(cell: Vector3i, value: int) -> void:
    _ensure_resident(_chunk_of(cell))            # load-before-write rule (Decision §3)
    _apply_write(cell, value)                    # existing batched write path
    _mark_region_dirty(_region_of(cell))

func _evict(chunk: Vector3i) -> void             # staggered, ADR-0014 unload budget;
                                                 # flushes dirty region to disk first
```

## Alternatives Considered

### Alternative A: Paged / on-demand region-file residency (+ B as a layer) — CHOSEN
- **Description**: as detailed in Decision above.
- **Pros**: the only candidate that decouples resident memory from world size *structurally*; reuses ADR-0014's streaming budget/discipline wholesale; the save format falls out for free (aligns ADR-0012); B slots in as an optimization without re-architecting.
- **Cons**: introduces disk I/O on the (low-frequency) far-world write path and the streaming edge — the exact thing the spike must prove stays under budget; a dirty-region flush discipline that must be correct (a dropped flush is data loss).
- **Rejection Reason**: N/A — chosen (pending spike).

### Alternative B: Sparse storage for far/unvisited regions (procedural + delta) — ADOPTED AS A LAYER, NOT STANDALONE
- **Description**: keep only mutated far chunks; regenerate unvisited terrain from the seed on demand, storing only player deltas.
- **Pros**: smallest possible resident + save footprint (settlements are a tiny fraction of 16k²); no full-terrain region files for untouched world.
- **Cons**: requires deterministic, cheap, *versioned* regen from seed (a hard constraint on terrain gen — any gen change must not silently alter already-visited-but-unsaved terrain); "has this cell been touched?" bookkeeping.
- **Rejection Reason**: powerful but too load-bearing to rest the whole residency guarantee on; adopted as a fast-follow optimization *within* A (Decision §5) where its regen-determinism risk is contained.

### Alternative C: Reduced persisted footprint (compression / bit-packing), still fully resident
- **Description**: shrink bytes-per-cell (palette/RLE/bitfield) to fit 16k²×32 under 4 GB without paging at all.
- **Pros**: simplest — no paging, no disk I/O on the hot path, smallest change from ADR-0014.
- **Cons**: the required reduction is ~64× areal growth under a 4 GB ceiling; realistic compression buys ~4–8× at meaningful density, not 64× — a scaling *ceiling*, not a solution. It defers the problem rather than solving it and still fails at the target.
- **Rejection Reason**: does not reach the 16k target; would need paging anyway once density rises. Compression may still be applied *inside* region files as an orthogonal win, but it is not the residency mechanism.

## Consequences

### Positive
- Resident memory is bounded by footprint, not world size — the 4 GB ceiling holds at 16k and beyond.
- ADR-0014's entire rendering/streaming design is preserved; this is purely a storage tier beneath it.
- Chunked saves (ADR-0012) and a natural on-disk format fall out of the residency model rather than being separate work.
- B's sparse-regen optimization has a clean home without a second architecture pass.

### Negative
- Introduces a disk tier with dirty-flush correctness obligations (a dropped or mis-ordered flush is data loss) — mitigated by centralizing flush in eviction and load-before-write in the single write path.
- Far-world writes incur a synchronous page-in in the base design — acceptable at MVP/slice far-write frequency, but the named async escape hatch (Decision §6) exists if measured otherwise.

### Risks
- **Risk**: page-in latency at the streaming edge causes a frame hitch during fast travel.
  **Mitigation**: reuse ADR-0014's per-frame stream budget for region loads; async `WorkerThreadPool` I/O is the named escape hatch. **The spike measures this directly.**
- **Risk**: sustained travel across a 16k-scale world leaks resident memory if eviction lags page-in.
  **Mitigation**: eviction shares ADR-0014's staggered-unload budget; the spike asserts a held ceiling under sustained travel, not just steady state.
- **Risk (B layer)**: a terrain-gen change silently alters unvisited terrain that a save assumed regenerable.
  **Mitigation**: versioned seed/gen; a gen-version bump forces affected regions to persist rather than regen. Deferred with the B layer itself.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|----------------------------|
| voxel-world.md | Tuning Knobs (Slice revision 2026-07-23): "Production target 16,000×16,000×32 ... gated behind a dedicated storage/streaming spike (a successor to ADR-0014) that must resolve one of: paged/on-demand chunk loading, sparse storage for far/unvisited regions, or a reduced persisted footprint" | Paged/on-demand region-file residency (option 1), with sparse-regen (option 2) as a layer; reduced-footprint (option 3) rejected as insufficient |
| voxel-world.md | TR-voxel-world-051 (terrain dig orders on any cell) | Load-before-write rule (Decision §3) makes far-world dig-order writes correct against non-resident chunks |
| voxel-world.md | Dependencies (Slice revision): save payload scales ~64× at the 16k target | Save format = region files (Decision §4), aligning ADR-0012's chunking escape hatch |

## Performance Implications
- **CPU**: region page-in/flush is amortized file I/O on the existing stream budget; far-world writes add one synchronous page-in each (low frequency). Spike-measured.
- **Memory**: bounded to the resident working set (camera-near ∪ settlement) — target flat vs world size; the whole point of the ADR. Spike asserts the 4 GB ceiling holds under sustained travel.
- **Load Time**: boot no longer allocates the full world — it loads only the initial residency set, which should *reduce* ADR-0014's ~2.6 s initial window build's storage component (feeds ADR-0005's timing note).
- **Network**: N/A — single-player project.

## Migration Plan
N/A — no production voxel storage implemented yet. This ADR is authored before Voxel World's production `/dev-story` work; ADR-0014's full-boot allocation was never shipped beyond the prototype.

## Validation Criteria (THE SPIKE — this ADR's Accept gate, modeled on ADR-0007/0008 QQ3)

Status flips Proposed → Accepted only when a synthetic-16k-scale storage/streaming spike PASSES all of:

1. **Page-in latency at the streaming edge**: sustained camera travel across the synthetic world pages regions in within ADR-0014's per-frame stream budget with **zero frame exceeding 16.6 ms attributable to region I/O** (p95 in-frame, matching ADR-0014's own streaming measurement discipline).
2. **Memory ceiling under sustained travel**: resident memory stays **≤ 4 GB** (and target: roughly flat, independent of distance travelled) across a long continuous traverse of a 16,000×16,000×32-scale synthetic world — not merely at boot or steady state.
3. **Write-to-unloaded-chunk correctness**: a batched write (dig order / building write) targeting a non-resident chunk pages in, applies, marks dirty, evicts, and on re-page-in reads back **byte-identical** — no dropped or corrupted mutation. Round-trip asserted.
4. **Eviction under budget**: chunks leaving the residency margin are unloaded **staggered within the stream budget**, reproducing zero unload-burst hitch (explicitly guarding against the slice's one 133 ms unload-burst regression).
5. **Save/load round-trip via region files**: a populated world saves to region files and reloads byte-identical, at a per-region cost that does not require a monolithic multi-GB single pass.

A PASS keeps the paged-residency decision as-is and flips Status to Accepted. A FAIL on (1) triggers the async-I/O escape hatch (Decision §6); a FAIL on (2) reopens the B-layer as mandatory rather than optional.

## Cascading Updates This ADR Unlocks (on Accept)
- **ADR-0012 (Save/Load)**: finalize the chunked-save decision — region files become the save format; the no-chunking clause is superseded for the 16k target. (Impact note already recorded there, Slice propagation 2026-07-23.)
- **ADR-0013 (Multi-Scene)**: recompute the dungeon spatial-offset/coordinate budget against the 16k world span (the `100_000` offset's margin, ~6× at 16k). (Impact note already recorded there.)
- **ADR-0005 (Boot Sequencing)**: revise the initial-window-build timing note — boot loads only the initial residency set, not the full world.

## Related Decisions
- Supersedes only ADR-0014's full-world-at-boot clause; depends on the rest of ADR-0014 unchanged.
- Aligns ADR-0012's Alternative C chunking escape hatch as the adopted save format.
- Feeds the coordinate-budget recompute ADR-0013 defers.
- Follows the ADR-0007/0008 provisional-until-spike gate pattern (QQ3) for its own Accept criteria.
