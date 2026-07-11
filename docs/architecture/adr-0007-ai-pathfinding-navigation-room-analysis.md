# ADR-0007: AI Pathfinding, Navigation & Room-Analysis Architecture

## Status
Accepted (2026-07-11 — pre-VS performance spike QQ3 PASSED at ADR-ceiling scale; see prototypes/perf-spike-qq3/REPORT.md. User-delegated decision.)

## Date
2026-07-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.7-stable |
| **Domain** | Navigation / AI-Pathfinding |
| **Knowledge Risk** | HIGH per the Phase 0 gap inventory — though this ADR's chosen mechanism (`AStar3D`, a standalone graph-search utility) is deliberately NOT `NavigationServer3D`/navmesh-based, sidestepping most of that HIGH-risk surface |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `breaking-changes.md`, `deprecated-apis.md`, `current-best-practices.md`, `modules/navigation.md` |
| **Post-Cutoff APIs Used** | None identified — `AStar3D` is a stable pre-4.3 utility class, not part of the Navigation module that changed post-cutoff |
| **Verification Required** | Confirmed via `godot-specialist` validation (2026-07-11) — `AStar3D`'s API surface is stable and unaffected 4.4→4.7; confirmed no `AStarGrid3D` class exists in Godot 4.7 (verified against official docs), the decision's load-bearing premise. See Engine Specialist Validation note in Consequences. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0014 (Chunked Voxel Rendering; formerly ADR-0014 (formerly ADR-0003) — same authoritative data layer, unchanged public accessor API) — this ADR's graph is built from Voxel World's own occupancy data, the same data layer ADR-0014 (formerly ADR-0003) established as authoritative |
| **Enables** | Villager AI and Build Validation & Navigability `/dev-story` implementation |
| **Blocks** | Both of the above — neither can implement its movement/analysis logic without this decision |
| **Ordering Note** | Was provisional pending the pre-VS performance spike — spike PASSED 2026-07-11 (patch avg 0.46 ms, query p95 1.9 ms; see prototypes/perf-spike-qq3/REPORT.md) |

## Context

### Problem Statement
`villager-ai-behavior.md` states walkability rules as "the canonical ground truth" (standability = solid cell below + 3-cell vertical clearance; step-legality = height difference ≤1; diagonal legal only if both flanking orthogonal cells are passable — no corner-cutting) and leaves the pathfinding algorithm itself as an open architectural choice (TR-villager-ai-behavior-035). `build-validation-navigability.md` requires its room/enclosure connectivity analysis to "reuse Villager AI's exact walkability rules... not a plain 4/8-neighbor flood-fill" (TR-build-validation-navigability-008) and defers its own engine-capability choice (NavigationServer3D rebake vs. custom cell-flood-fill) to this same ADR (TR-build-validation-navigability-019). Both consumers need the identical rules; they need different traversal algorithms (Villager AI needs shortest-path for actual travel; Build Validation needs full reachability, not shortest-path, for its "is this room connected to the outside" check).

### Constraints
- Movement rules are a custom tile/grid model (clearance, step-height, flanked-diagonal-only), not a generic navmesh-agent-radius problem
- Villagers move cell-to-cell with discrete tick-boundary arrival (F1's "no partial credit" rule) — not continuous navmesh-agent movement
- Population ceiling 20-30 villagers. *(Revised 2026-07-11, ADR-0014 large world)*: the world bound is now ~128M cells — the nav graph therefore covers a bounded settlement-core region (where villager life happens), NOT the whole world; region sizing spike tracked as architecture.md QQ5
- Build Validation's analysis must be event-driven and incremental (TR-build-validation-navigability-006: "only entries touched by a pass's affected region are updated"), not a full-world recompute per edit
- The two systems must share the RULES verbatim (TR-build-validation-navigability-010: "no independently duplicated copies") without necessarily sharing internal data structures — Build Validation is a read-only consumer of Villager AI's walkability, never a caller into its pathfinding internals

### Requirements
- One shared, canonical implementation of the walkability predicates (standability, step-legality), called by both systems — never two independently-written copies of the same rule
- Villager AI needs efficient shortest-path queries (F1 travel-time, F2 job selection by path-distance)
- Build Validation needs an efficient full-reachability trace from a region's interior to any open-sky standable cell — a different traversal shape than shortest-path
- Both must support incremental updates on a Voxel World write, not a full-graph rebuild per edit

## Decision

**Villager AI owns the walkability predicates as shared pure functions. Villager AI's own travel pathfinding uses `AStar3D` (a manually-built, incrementally-patched graph of standable cells and legal-step connections) for shortest-path queries. Build Validation runs its own independent BFS/flood-fill, calling the same shared predicates directly — not `NavigationServer3D`/navmesh baking, and not sharing Villager AI's internal `AStar3D` graph object.**

**1. Shared predicates, single source of truth.** Villager AI exposes two pure query functions as part of its public API (extending what's already in `architecture.md`'s API Boundaries):
```gdscript
func is_standable(cell: Vector3i) -> bool
func is_step_legal(from_cell: Vector3i, to_cell: Vector3i) -> bool
```
Both consult Voxel World's occupancy data directly and the shared movement constants (`villager_clearance`, `max_step_height`) from the registry — no duplicated logic, no duplicated constants, anywhere. Every consumer of walkability (Villager AI's own pathfinder, Build Validation's flood-fill) calls these same two functions.

**2. Villager AI's travel pathfinding: `AStar3D`, incrementally maintained.** Godot's `AStar3D` is a standalone graph-search utility (unrelated to `NavigationServer3D`/navmesh baking) — Villager AI adds one point per standable cell (`add_point(id, position)`) and connects legal-step pairs (`connect_points(id1, id2)`), then queries shortest paths via `get_id_path()`/`get_point_path()`. This graph is built once at boot (from Voxel World's initial terrain) and incrementally patched — not rebuilt — whenever a Voxel World write changes standability or step-legality in the affected region (adding/removing points and connections only for the cells actually touched), consistent with Villager AI's already-specified re-path-filtering contract (TR-villager-ai-behavior-012).

**3. Build Validation's room/enclosure analysis: independent BFS, not a shared graph.** Build Validation's reachability trace ("graph walk from region interior to any open-sky standable cell," TR-build-validation-navigability-009) is a full-connectivity question, not a shortest-path one — a plain breadth-first or depth-first walk over cells that pass `is_standable`/`is_step_legal` is the right tool, and it's cheaper to write and reason about than extracting an equivalent answer from `AStar3D`'s shortest-path-oriented API. Build Validation never touches Villager AI's `AStar3D` instance — it calls the two shared predicate functions directly, which is sufficient to satisfy "reuse the exact rules" without coupling the two systems' internal data structures. This preserves the already-established "read-only reference, zero calls into Villager AI's mutators" boundary (`architecture.md` Module Ownership) — predicate functions are pure queries, not mutators, and Build Validation's own BFS state is entirely its own.

**4. `NavigationServer3D` / navmesh baking is explicitly rejected for both use cases** — see Alternatives.

### Architecture Diagram
```
Voxel World (occupancy data, ADR-0014 (formerly ADR-0003))
        │
        ▼
Villager AI — shared predicates (single source of truth):
  is_standable(cell), is_step_legal(from, to)
        │                                    │
        ▼                                    ▼
  AStar3D graph                    Build Validation's own BFS
  (points = standable cells,       (full reachability trace,
   edges = legal steps)             region-interior → open-sky cell)
        │                                    │
        ▼                                    ▼
  get_id_path() / get_point_path()   room/enclosure connectivity verdict
  → Villager AI's F1-F4 formulas     → shelter_status_changed,
    (travel time, job selection,       room_recognized, sealed_space_warning
     wander, nudge-aside)

Both incrementally patched (add/remove points+connections, or re-run BFS
only over the affected region) on Voxel World write signals — never a
full-graph rebuild or full-world recompute per edit.
```

### Key Interfaces
```gdscript
# Villager AI's shared predicate API (extends architecture.md's API Boundaries):
func is_standable(cell: Vector3i) -> bool
func is_step_legal(from_cell: Vector3i, to_cell: Vector3i) -> bool

# Villager AI's internal pathfinding (implementation detail, not a public API):
var _astar: AStar3D = AStar3D.new()

# AStar3D point IDs are manually-assigned 64-bit ints with no auto-recycling
# on remove_point() — a deterministic Vector3i -> int64 packing scheme keeps
# incremental patch operations collision-free and idempotent (never an
# incrementing counter, which would drift under add/remove churn):
func _cell_to_astar_id(cell: Vector3i) -> int:
    return (cell.x & 0x1FFFFF) | ((cell.y & 0x1FFFFF) << 21) | ((cell.z & 0x1FFFFF) << 42)

func _on_voxel_world_cell_changed(cell: Vector3i, before: CellData, after: CellData) -> void:
    # patch only the affected cell + its clearance/step neighborhood —
    # add/remove points and connections via _cell_to_astar_id(), never a
    # full rebuild
    ...

# F1's diagonal=1.4 / orthogonal=1.0 step-cost weighting (already specified
# in villager-ai-behavior.md) maps directly onto AStar3D's per-point
# weight_scale / default Euclidean heuristic — no custom
# _compute_cost/_estimate_cost override needed, since Euclidean distance
# between adjacent cell centers already yields ~1.0 orthogonal / ~1.41
# diagonal, matching F1's stated constants closely enough that no override
# is required for MVP; revisit only if the pre-VS spike finds a mismatch.

# Build Validation's own BFS (implementation detail, not a public API):
func _trace_reachability(region_interior: Vector3i) -> bool:
    var visited: Dictionary[Vector3i, bool] = {}
    var frontier: Array[Vector3i] = [region_interior]
    while not frontier.is_empty():
        var current: Vector3i = frontier.pop_back()
        if visited.has(current): continue
        visited[current] = true
        if _is_open_sky(current): return true
        for neighbor in _standable_neighbors(current):  # calls VillagerAI.is_standable/is_step_legal
            if not visited.has(neighbor): frontier.append(neighbor)
    return false
```

## Alternatives Considered

### Alternative A: `AStar3D` (shared predicates, separate traversal algorithms per consumer) — CHOSEN
- **Description**: as detailed in Decision above.
- **Pros**: `AStar3D` is a stable, C++-implemented, general-purpose graph-search primitive — efficient shortest-path search without hand-rolling a priority queue in GDScript; full control over exactly which cell-pairs count as connected (no lossy geometric approximation); Build Validation's BFS is simple, decoupled, and exactly matches its actual need (reachability, not shortest-path).
- **Cons**: two separate traversal implementations to maintain (Villager AI's `AStar3D` usage, Build Validation's own BFS) — though they share the predicates, which is the part that actually needed to be shared.
- **Rejection Reason**: N/A — chosen.

### Alternative B: `NavigationServer3D` + baked `NavigationRegion3D`
- **Description**: bake a navmesh from Voxel World's geometry, use `NavigationAgent3D`/`NavigationServer3D.query_path()` for villager movement, and derive room-connectivity from navmesh region membership for Build Validation.
- **Pros**: Godot's "standard" navigation solution, built-in avoidance (`NavigationAgent3D`'s RVO2 support) if ever needed for crowding.
- **Cons**: navmesh generation approximates walkable geometry via agent-radius/height/climb parameters — it does not naturally express this project's exact custom rules (3-cell clearance derived from block occupancy, step-height ≤1, flanked-diagonal-only corner rule); reconciling a geometric navmesh approximation with an exact cell-rule requirement risks subtle mismatches between "navmesh says walkable" and "the GDD's rules say walkable." Rebake cost on every block edit is exactly the risk `systems-index.md`'s High-Risk table flags, and rebaking is proportional to the region size, not O(1) like an incremental `AStar3D` point/connection patch. Villager movement is cell-discrete (tick-boundary arrival), not the continuous agent-glide model `NavigationAgent3D` is built for.
- **Rejection Reason**: fights the project's exact-rule requirement and its discrete movement model; the rebake-cost risk this project's own risk register already flagged is real and avoided entirely by Alternative A.

### Alternative C: Fully custom pathfinding (hand-rolled A*/BFS, no Godot utility class at all)
- **Description**: implement A* and BFS directly against Voxel World's data dictionary in GDScript, without `AStar3D`.
- **Pros**: maximum control, no dependency on any built-in pathfinding primitive's internal behavior.
- **Cons**: reimplements what `AStar3D` already provides (an efficient, tested priority-queue-based search) for villager travel specifically, for no capability gain — Build Validation's flood-fill was always going to be hand-rolled either way (a simple BFS doesn't benefit from `AStar3D`'s shortest-path machinery), so this alternative only affects Villager AI's half.
- **Rejection Reason**: reinventing `AStar3D`'s shortest-path search in GDScript is strictly more work for no benefit this project's constraints need.

## Consequences

### Positive
- One shared, canonical rule implementation (`is_standable`/`is_step_legal`) — the exact "no independently duplicated copies" requirement (TR-build-validation-navigability-010) is satisfied structurally, not by discipline.
- Sidesteps the `NavigationServer3D` rebake-cost risk entirely rather than mitigating it, by not using navmesh baking at all — consistent with ADR-0014 (formerly ADR-0003)'s pattern of resolving a flagged risk by removing its precondition rather than working around it.
- `AStar3D`'s incremental point/connection patching matches both systems' already-specified incremental-update requirements (Villager AI's re-path filtering, Build Validation's incremental snapshot patching) without needing new mechanism design.

### Negative
- Two traversal implementations (Villager AI's `AStar3D` usage, Build Validation's own BFS) rather than one unified graph object — a deliberate decoupling choice, but real code to write and maintain in two places.
- `AStar3D`'s scaling behavior at Township scale (thousands of points, frequent incremental patches under a 20-30 villager population issuing pathfinds) is unmeasured — see Risks.

### Risks
- **Risk** (addressed during engine-specialist validation): `AStar3D` point IDs are manually-assigned, never auto-recycled on `remove_point()` — an incrementing-counter ID scheme would drift and risk collisions under add/remove churn from incremental patching.
  **Mitigation**: a deterministic `Vector3i → int64` bit-packing scheme (Key Interfaces above) makes every cell's ID derivable from its coordinates alone, with no counter state to drift.
- **Risk**: `AStar3D`'s scaling behavior under thousands of points with frequent incremental patches (a 20-30 villager population issuing pathfinds) is unmeasured — general engine knowledge confirms no thread-safety or spatial-acceleration concern for this project's single-threaded, non-`get_closest_point()` usage pattern, but raw throughput at Township scale is not yet benchmarked.
  **Mitigation**: folds into the same pre-VS performance spike already tracked for ADR-0003 (`architecture.md` QQ3).

**Engine Specialist Validation** (2026-07-11, `godot-specialist`, run before finalizing this ADR): confirmed `AStar3D`'s API surface (`add_point`, `connect_points`, `disconnect_points`, `remove_point`, `has_point`, `get_id_path`, `get_point_path`) is correct and unaffected by any 4.4–4.7 change. **Confirmed the decision's load-bearing premise**: Godot does NOT ship an `AStarGrid3D` class — verified against the official docs (only `AStarGrid2D` exists; a 3D grid-specialized variant has been an open, unimplemented feature request since March 2023) — so manual `AStar3D` point-graph management is genuinely the only built-in option, not an oversight of a better-fitting class. Confirmed `AStar3D` has no hidden dependency on or shared cost with `NavigationServer3D`. Flagged the ID-recycling gotcha (addressed above) and confirmed no custom cost-heuristic override is needed for F1's diagonal/orthogonal weighting (Euclidean distance between cell centers already approximates it closely). Verdict: "safe to accept as written," pending the ID-packing clarification, which is now included in Key Interfaces.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|----------------------------|
| villager-ai-behavior.md | TR-villager-ai-behavior-009/010: standability + step-legality predicates | `is_standable`/`is_step_legal`, Decision §1 |
| villager-ai-behavior.md | TR-villager-ai-behavior-011: "Walkability rules exposed as the canonical ground truth queried by Build Validation" | Shared predicate functions, called by both systems |
| villager-ai-behavior.md | TR-villager-ai-behavior-035: "Pathfinding algorithm itself is an open architectural choice" | `AStar3D`, Decision §2 |
| villager-ai-behavior.md | TR-villager-ai-behavior-036: "Mid-travel re-path required when a Voxel World write blocks the current path" | Incremental graph patching, Decision §2 |
| build-validation-navigability.md | TR-build-validation-navigability-008: "must reuse Villager AI's exact walkability rules... not a plain 4/8-neighbor flood-fill" | Shared predicates called directly, Decision §3 |
| build-validation-navigability.md | TR-build-validation-navigability-009: "graph walk from region interior to any open-sky standable cell" | Build Validation's own BFS, Decision §3 |
| build-validation-navigability.md | TR-build-validation-navigability-019: "Deferred engine-capability decision (ADR-owned): NavigationServer3D rebake vs. custom cell-flood-fill" | Resolved here — custom cell-flood-fill (BFS), not NavigationServer3D |

## Performance Implications
- **CPU**: `AStar3D` shortest-path queries are O(edges explored) via its internal priority queue — efficient for the graph sizes this project's world scale implies, but unmeasured at Township scale; folds into the pre-VS spike. Build Validation's BFS is O(region size) per analysis pass, already the accepted cost model per its own GDD (TR-build-validation-navigability-020's "unbounded, no caching" is a documented, accepted risk, not new here).
- **Memory**: One `AStar3D` instance holding the settlement-core region's standable cells (spike QQ3 measured 11k points / 278 ms build at the old bound; region bound to be set by the QQ5 spike — never the full ~128M-cell world, per ADR-0014).
- **Load Time**: Initial graph construction at boot is proportional to standable-cell count — expected fast for MVP's small starting structure, unmeasured at scale.
- **Network**: N/A — single-player project.

## Migration Plan
N/A — no existing code.

## Validation Criteria
- A unit test constructs a small synthetic Voxel World region and asserts `is_standable`/`is_step_legal` produce identical results whether called from Villager AI's own pathfinding path or from a mock Build Validation caller — proving the shared-predicate contract holds.
- The pre-VS performance spike (already tracked, `architecture.md` QQ3) measures `AStar3D` graph-patch cost and Build Validation BFS cost at Township scale; a PASS keeps this ADR Accepted as-is.
- Grep-verifiable: zero `NavigationServer3D`/`NavigationAgent3D`/`NavigationRegion3D` usage anywhere in Villager AI's or Build Validation's implementation.

## Related Decisions
- Depends on ADR-0014 (formerly ADR-0003) for Voxel World's occupancy data as the graph's data source.
- Both this ADR and ADR-0014 (formerly ADR-0003) share the same pending pre-VS performance spike as their empirical validation step — `architecture.md` QQ3 covers both.
