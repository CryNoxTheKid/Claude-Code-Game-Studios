## AStar3D-backed shared travel-pathfinding graph (Story villager-ai-007,
## ADR-0007 Decision Section 2: "Villager AI's own travel pathfinding uses
## `AStar3D`... built once at boot... queried via `get_id_path()`/
## `get_point_path()`").
##
## **Architecture note** -- ONE instance for the whole villager population,
## never one per villager. ADR-0007's Performance Implications section is
## explicit: "Memory: One AStar3D instance holding the settlement-core
## region's standable cells" -- a per-[VillagerAi]-instance graph would
## duplicate tens of thousands of points across a population of up to 30
## villagers, for zero benefit (every villager's graph would be byte-for-byte
## identical). This is the SAME "separate shared collaborator, factored out
## of any single [VillagerAi] instance" resolution
## [VillagerDecidingScheduler] already applied to ADR-0008's per-tick budget
## for exactly this class of reason -- see that class's own doc comment for
## the full rationale this one mirrors. Deliberately a plain [RefCounted]
## (no Inspector authoring need, no scene-tree presence needed), constructed
## once by whichever code assembles the villager population (a headless
## test, or a future boot/world-generation story) and shared read-only by
## every consumer thereafter -- wiring it into [VillagerAi]'s own Traveling
## state is story villager-ai-009's scope, out of this story entirely.
##
## **Predicates, not a second copy of walkability** (ADR-0007 Decision
## Section 1 / Control Manifest Feature Layer: "EVERY consumer... calls
## these same two functions -- single source of truth"): [method build]
## takes a `predicate_source` parameter (a [VillagerAi] reference in
## practice, since that is the sole implementer of [method
## VillagerAi.is_standable]/[method VillagerAi.is_step_legal] this codebase
## has) and calls ONLY those two functions to decide which cells become
## points and which pairs become connections -- this class never re-derives
## an equivalent standability/step-legality rule of its own, and never reads
## [VoxelWorldGrid] cell contents directly (the one exception is [method
## VoxelWorldGrid.cell_to_world], the single source of truth for cell<->world
## conversion, reused here rather than a second, locally-duplicated formula).
class_name VillagerNavGraph
extends RefCounted

## Bit width per axis field of the deterministic point-id packing (ADR-0007
## Key Interfaces: `x&0x1FFFFF | y<<21 | z<<42`) -- 21 bits comfortably covers
## both the current (2048) and 16k production world extents (2^21 ~= 2.09M),
## with room to spare on every axis.
const AXIS_BITS: int = 21

## Bitmask for one 21-bit axis field (`(1 << 21) - 1`).
const AXIS_MASK: int = 0x1FFFFF

## The 4 horizontal (dx, dz) neighbor offsets that, taken together with their
## negations, cover exactly the 8 horizontal neighbors of a cell (GDD Rule 9:
## orthogonal + flanked-diagonal steps) -- deliberately only HALF of the 8
## directions. [method build]'s connection pass visits every standable cell
## as a "from" cell exactly once, so processing only this canonical half here
## (rather than all 8) means each UNORDERED neighbor pair is evaluated
## exactly once, never twice -- [method build]'s own doc comment explains why
## that matters (Villager AI's [method VillagerAi.is_step_legal] is not
## guaranteed symmetric for a diagonal step with a height difference, so
## "evaluate each ordered direction independently, exactly once each" is the
## correct, non-redundant connection strategy, not an accidental
## simplification).
const HORIZONTAL_HALF_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
]

## The 3 vertical offsets a legal step may span (GDD Rule 9:
## `|height difference| <= 1`) -- checked against every horizontal neighbor
## column, since a standable cell's neighbor column may hold a standable cell
## at a different Y (a step up or down, e.g. a staircase).
const VERTICAL_STEP_OFFSETS: Array[int] = [-1, 0, 1]

## The underlying AStar3D graph. Never exposed directly to a consumer --
## every read goes through [method find_path]/[method has_point] so this
## class stays the sole owner of the id-packing scheme.
var _astar: AStar3D = AStar3D.new()

## True once [method build] has completed at least once (observability for
## tests/callers -- e.g. asserting a query against an unbuilt graph behaves
## sanely rather than silently returning garbage).
var _is_built: bool = false


## Deterministic `Vector3i -> int64` point-id packing (ADR-0007 Key
## Interfaces, this story's AC: "the same cell always yields the same ID; no
## counter state"). Pure and stateless -- collision-free for every
## non-negative cell coordinate this project's fixed-origin world (Core Rule
## 1: no negative cell coordinates) can ever produce, up to [constant
## AXIS_MASK] (~2.09M) per axis, far beyond both the current (2048) and 16k
## production world extents. Deliberately NEVER an incrementing counter
## (ADR-0007 Risk: counter-based ids drift/collide under `remove_point()`
## churn -- story villager-ai-008's incremental-patch scope; this scheme has
## no counter state to drift in the first place).
static func cell_to_astar_id(cell: Vector3i) -> int:
	return (
		(cell.x & AXIS_MASK)
		| ((cell.y & AXIS_MASK) << AXIS_BITS)
		| ((cell.z & AXIS_MASK) << (AXIS_BITS * 2))
	)


## Inverse of [method cell_to_astar_id] -- round-trips a point id produced by
## that function back to its originating cell. Never itself required by
## AStar3D (whose own [method AStar3D.get_point_path] already returns world
## positions directly) -- exists purely as a convenience for [method
## find_path]'s `get_id_path()` variant and for tests asserting the packing
## scheme's own round-trip/no-collision guarantee.
static func astar_id_to_cell(id: int) -> Vector3i:
	return Vector3i(
		id & AXIS_MASK,
		(id >> AXIS_BITS) & AXIS_MASK,
		(id >> (AXIS_BITS * 2)) & AXIS_MASK,
	)


## Builds the graph once from Voxel World's CURRENT terrain (this story's AC:
## "built once at boot... one point per standable cell (via `is_standable`),
## connections for every legal-step pair (via `is_step_legal`)"), bounded to
## an `region_size` x `region_size` horizontal window centered on
## [param region_center] (ADR-0007's bounded settlement-core region,
## [member VillagerAIConfig.nav_region_size] -- "never the full world") and
## the full configured vertical extent ([param voxel_world]'s own [member
## VoxelWorldConfig.min_y]/[member VoxelWorldConfig.max_y] -- the ADR's
## "200x200" figure is explicitly horizontal-only, matching
## [member VoxelWorldConfig.settlement_radius_chunks]'s own horizontal-only
## precedent). A region edge that extends past the world's own configured
## bounds simply contributes no points there -- [method
## VillagerAi.is_standable] already reads back `false` for any cell [method
## VoxelWorldGrid.get_cell] reports out of bounds, so no special-case
## clamping is needed here for that edge case.
##
## Idempotent/re-buildable: clears any previous graph state first, so calling
## this again fully rebuilds from scratch rather than accumulating stale
## points/connections -- incremental patching in response to a single Voxel
## World write (never a full rebuild per edit) is story villager-ai-008's
## explicit scope, not this one.
##
## Two passes, in order (a connection can only be added between cells that
## already exist as points): (1) walk every cell in the bounded region,
## adding a point for each one [param predicate_source] reports standable
## via [method VillagerAi.is_standable]; (2) for every standable cell added in
## pass 1, walk its [constant HORIZONTAL_HALF_OFFSETS] x
## [constant VERTICAL_STEP_OFFSETS] neighbor candidates and connect any that
## are ALSO points (added in pass 1) and pass [method VillagerAi.is_step_legal]
## -- see that check's own per-direction handling below for why it is
## evaluated independently in each direction rather than assumed symmetric.
func build(
	voxel_world: VoxelWorldGrid,
	predicate_source: VillagerAi,
	region_center: Vector3i,
	region_size: int,
) -> void:
	assert(voxel_world != null, "VillagerNavGraph.build requires voxel_world")
	assert(predicate_source != null, "VillagerNavGraph.build requires predicate_source")
	assert(voxel_world.config != null, "VillagerNavGraph.build requires voxel_world.config wired")
	_astar.clear()
	_is_built = false

	var half: int = region_size / 2
	var min_x: int = region_center.x - half
	var max_x: int = min_x + region_size - 1
	var min_z: int = region_center.z - half
	var max_z: int = min_z + region_size - 1
	var min_y: int = voxel_world.config.min_y
	var max_y: int = voxel_world.config.max_y

	var standable_cells: Array[Vector3i] = []
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			for y in range(min_y, max_y + 1):
				var cell := Vector3i(x, y, z)
				if predicate_source.is_standable(cell):
					var id: int = VillagerNavGraph.cell_to_astar_id(cell)
					_astar.add_point(id, VoxelWorldGrid.cell_to_world(cell))
					standable_cells.append(cell)

	for from_cell: Vector3i in standable_cells:
		var from_id: int = VillagerNavGraph.cell_to_astar_id(from_cell)
		for offset: Vector2i in HORIZONTAL_HALF_OFFSETS:
			for dy: int in VERTICAL_STEP_OFFSETS:
				var to_cell := Vector3i(from_cell.x + offset.x, from_cell.y + dy, from_cell.z + offset.y)
				var to_id: int = VillagerNavGraph.cell_to_astar_id(to_cell)
				if not _astar.has_point(to_id):
					continue
				_connect_if_legal(predicate_source, from_cell, from_id, to_cell, to_id)

	_is_built = true


## Connects [param from_id]<->[param to_id] according to [method
## VillagerAi.is_step_legal]'s result in EACH direction, evaluated
## INDEPENDENTLY -- deliberately not assumed symmetric. [method
## VillagerAi.is_step_legal]'s diagonal flanking check reads both flanker
## cells at `from_cell.y` (that predicate's own, already-shipped
## implementation, story villager-ai-002, out of this story's scope to
## alter) -- so for a diagonal step spanning a height difference, legality
## can genuinely differ between the A->B and B->A directions (a corner
## blocked from one cell's own floor height need not be blocked from the
## other's). A single `AStar3D.connect_points(a, b, true)` bidirectional call
## would silently assume symmetry and could admit an illegal reverse step, or
## reject a legal forward one -- verified against the live engine (Godot
## 4.7-stable) that calling `connect_points(a, b, false)` then, separately,
## `connect_points(b, a, false)` correctly yields a fully bidirectional
## connection when both directions are legal, and a one-way connection when
## only one is -- so exactly one `connect_points` call is made per direction
## that is actually legal, never a blind bidirectional call.
func _connect_if_legal(
	predicate_source: VillagerAi, from_cell: Vector3i, from_id: int, to_cell: Vector3i, to_id: int
) -> void:
	var forward_legal: bool = predicate_source.is_step_legal(from_cell, to_cell)
	var backward_legal: bool = predicate_source.is_step_legal(to_cell, from_cell)
	if forward_legal and backward_legal:
		_astar.connect_points(from_id, to_id, true)
	elif forward_legal:
		_astar.connect_points(from_id, to_id, false)
	elif backward_legal:
		_astar.connect_points(to_id, from_id, false)


## Whether [method build] has completed at least once.
func is_built() -> bool:
	return _is_built


## Whether [param cell] is a point in this graph (i.e. was standable at the
## most recent [method build] call) -- observability for tests and future
## consumers (story villager-ai-008's incremental patching will need this to
## decide add-vs-remove).
func has_point(cell: Vector3i) -> bool:
	return _astar.has_point(VillagerNavGraph.cell_to_astar_id(cell))


## Direct edge existence -- exposed for tests (and any future consumer
## needing "can this exact step be taken right now" without running a full
## shortest-path search) via `AStar3D`'s own `are_points_connected()`.
## [param bidirectional] defaults to `true` (matching [method
## AStar3D.are_points_connected]'s own default) -- pass `false` to ask about
## ONLY the [param from_cell] -> [param to_cell] direction specifically,
## relevant for the asymmetric-legality case [method _connect_if_legal]'s own
## doc comment describes (verified against the live engine: with a one-way
## connection A->B only, `are_points_connected(A, B, false)` is `true` while
## `are_points_connected(B, A, false)` is `false`). Returns `false`
## immediately if either cell is not currently a point in the graph.
func has_direct_connection(from_cell: Vector3i, to_cell: Vector3i, bidirectional: bool = true) -> bool:
	var from_id: int = VillagerNavGraph.cell_to_astar_id(from_cell)
	var to_id: int = VillagerNavGraph.cell_to_astar_id(to_cell)
	if not _astar.has_point(from_id) or not _astar.has_point(to_id):
		return false
	return _astar.are_points_connected(from_id, to_id, bidirectional)


## Shortest-path query (ADR-0007 Decision Section 2: "queried via
## `get_id_path()`/`get_point_path()`"). Returns the path as an ordered
## `Array[Vector3i]` of cells INCLUDING both endpoints, via `AStar3D`'s own
## `get_id_path()` unpacked back through [method astar_id_to_cell] -- never a
## second, hand-rolled path-search algorithm. Returns an empty array if
## either endpoint is not currently a point in the graph, or if no path
## connects them (this story's edge case: "unreachable target returns an
## empty path"). A [param from_cell] equal to [param to_cell] (both the same
## point) returns a single-element array containing just that one cell --
## [method path_length_cells] of a single-element path is `0.0`, F1's "target
## is the current/adjacent cell... immediate arrival" (verified against the
## live engine: `AStar3D.get_id_path(id, id)` returns `[id]`, not an empty
## array).
func find_path(from_cell: Vector3i, to_cell: Vector3i) -> Array[Vector3i]:
	var from_id: int = VillagerNavGraph.cell_to_astar_id(from_cell)
	var to_id: int = VillagerNavGraph.cell_to_astar_id(to_cell)
	if not _astar.has_point(from_id) or not _astar.has_point(to_id):
		return []
	var ids: PackedInt64Array = _astar.get_id_path(from_id, to_id)
	var path: Array[Vector3i] = []
	for id: int in ids:
		path.append(VillagerNavGraph.astar_id_to_cell(id))
	return path


## GDD F1's path-length classification summed over every consecutive step of
## [param path] -- orthogonal = `1.0`, diagonal = `1.4`, via [method
## VillagerAi.classify_step_length_cells] (the SAME static classifier
## [VillagerAi]'s own Traveling-step math uses, reused here rather than
## re-derived -- Control Manifest Feature Layer: "never duplicate... rules or
## constants" applies equally to this F1 formula, not only to walkability).
## A `path` of fewer than 2 cells (empty -- unreachable, per [method
## find_path] -- or a single cell -- already-arrived) returns `0.0`,
## matching this story's AC: "a target on the current/adjacent cell yields
## length 0."
static func path_length_cells(path: Array[Vector3i]) -> float:
	if path.size() < 2:
		return 0.0
	var total: float = 0.0
	for i in range(path.size() - 1):
		total += VillagerAi.classify_step_length_cells(path[i], path[i + 1])
	return total


## GDD F1: `travel_time_game_seconds = path_length_cells / move_speed`. A
## [param length_cells] of `0.0` (or less, defensively) short-circuits to
## `0.0` immediately -- this story's AC: "`path_length_cells = 0` (target is
## current/adjacent cell) yields immediate arrival" -- regardless of
## [param move_speed]'s value, never a division at all in that case.
static func travel_time_game_seconds(length_cells: float, move_speed: float) -> float:
	if length_cells <= 0.0:
		return 0.0
	return length_cells / move_speed
