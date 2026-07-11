# Performance Spike QQ3 — Report

> **Date**: 2026-07-11 · **Hardware**: dev machine (AMD GPU, Windows 11, D3D12 backend, vsync on)
> **Engine**: Godot 4.7-stable · **Seed**: 1337 · **Raw data**: `results/*.csv`
> **Verdict: PASS on all three gated ADRs** (ADR-0008 with a tuning deliverable + watch-item)

## Measurement caveat

Frame times are vsync-locked at 16.667 ms — "p95 = 16.667" means "held 60 FPS",
headroom below that is not visible. All GDScript stand-in costs (Deciding pass,
BFS) are conservative upper bounds: production code can early-out and cache
where the stand-in brute-forces.

## S1 — Rendering scale (ADR-0003) — PASS

| Metric | C1 (64×16×64) | C2 (100×32×100) | Threshold |
|---|---|---|---|
| Cells committed | 19,664 | 87,280 | — |
| Populate time | 13 ms | 70 ms | ≤ 3000 ms ✅ |
| Frame p95 (worst view) | 16.667 ms | 16.667 ms | ≤ 16.6 ms ✅ |
| Draw calls max | 609 | **1,598** | ≤ 2000 ✅ |
| Memory static | 57 MB | 89 MB | ≤ 4 GB ✅ |

**Margin note**: 1,598 draw calls at C2 with only 36 houses leaves ~20% margin.
A denser settlement could cross 2,000 — first mitigation lever is
`GridMap.cell_octant_size` (default 8 → 16 quarters octant count), before any
Alternative-C migration talk. Not a blocker; recorded as a density watch-item.

## S2 — 30-villager stress at 1x/3x warp (ADR-0008) — PASS with deliverable

| Config | warp1 p95 | warp3 p95 | warp3 avg |
|---|---|---|---|
| `max_deciding_per_tick = 4` | 16.667 ms | **83.3 ms FAIL** | 30.5 ms |
| `max_deciding_per_tick = 1` | 16.667 ms | **16.667 ms PASS** | 16.9 ms |

- **Tuning deliverable: `max_deciding_per_tick = 1`** (the ADR named this
  empirical value as the spike's job). The staggering mechanism itself works
  exactly as designed — the budget just has to be 1 at this per-pass cost.
- Includes the S2b synchronized mass-Deciding event (all 30 enqueue in one
  tick) in both phases: queue drains at 1/tick with no sustained degradation.
- **Watch-item**: a single Deciding pass costs avg 11 ms / p95 35 ms in the
  GDScript stand-in (15 candidates × 200-cell bounded BFS ≈ 560 µs per
  candidate check) — one pass alone can blow a frame (rare hitches, worst
  144 ms, <5% of frames). In-design mitigations before reaching ADR-0008's
  threading escape hatch: cheaper candidate pre-filter (Chebyshev only),
  smaller BFS bound, or slicing one pass across ticks. No architecture change
  needed now.

## S3 — AStar3D dynamics (ADR-0007) — PASS

| Metric | Value | Assessment |
|---|---|---|
| Graph build (11,281 points @ C2) | 278 ms | boot-time, one-off — fine |
| Incremental patch (write-storm, n=4800) | avg 0.46 ms, worst 1.0 ms | absorbed in-frame ✅ |
| Live path query (n=9600) | avg 63 µs | negligible ✅ |
| Cold query bench (200 long paths) | avg 0.46 ms, p95 1.9 ms | event-driven, fine ✅ |

35% of random bench pairs were unconnected (roof/floor islands in the
generated map) — an artifact of the synthetic world, and the live loop handles
empty paths by re-Deciding; no finding against the ADR.

## S4 — Build Validation BFS scaling (ADR-0007 accepted-risk) — PASS, boundary quantified

Linear at **~1.4 ms per 1,000 connected cells** (C2: 1k→1.3 ms, 5k→6.1 ms,
20k→24 ms, 60k→84 ms). The GDD's "unbounded, no caching" pass exceeds one
frame budget above **~12,000 connected build cells**. For MVP (houses of
~200 cells) this is orders of magnitude away; record ~12k as the boundary
that triggers the incremental/cached re-analysis conversation, per
build-validation-navigability.md TR-020's documented risk.

## ADR consequences applied

- **ADR-0003 → Accepted** (spike PASS; draw-call density watch-item noted)
- **ADR-0007 → Accepted** (patch/query costs absorbed; S4 boundary recorded)
- **ADR-0008 → Accepted** (stagger validated; `max_deciding_per_tick = 1`
  initial value; per-pass-cost watch-item with named in-design mitigations)
- **ADR-0009 / ADR-0013 → unblocked** (their hold was ADR-0007's provisional
  status)
- `architecture.md` QQ3 → resolved by this report.

## C1-vs-C2 headroom

C2 (ADR ceiling) passes everything, so the GDD-default C1 world is not the
thing keeping us honest — no world-size cap needed. The flagged GDD/ADR scale
discrepancy stays a documentation note, not a constraint.
