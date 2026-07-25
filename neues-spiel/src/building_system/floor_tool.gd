## Building System's floor tool (Story building-025, ADR-0016 primary -- a
## valid commit creates blueprint cells grouped into a project).
##
## Owns exactly the GDD's Formula F2 cell-set (`design/gdd/building-system.md`
## "F2 -- Floor cell set from a drag", [TR-building-system-045]/
## [TR-building-system-078]) and the seam that registers it into
## [CommitPipeline] -- nothing else, mirroring [WallTool]'s established F1
## shape (Story building-024). Per this story's Out of Scope: floor-over-
## terrain flush-replace + `restore_value` capture is Story 012 (the slice's
## terrain-start branch, not built here); ghost preview RENDERING is Story
## 023 (not built); the click-vs-drag discrimination trigger, the bounds
## clamp, and the actual write/validity gate remain [CommitPipeline]'s own
## established job (Stories building-021/022).
##
## **F2 formula**: `floor_cell_count = (|dx| + 1) x (|dz| + 1)` -- a
## 1-cell-thick rectangle on the locked working plane (Core Rule 3: the plane
## is locked to the drag's START cell for its entire duration, mirroring
## [WallTool.rasterize_run]'s own Y-anchor discipline), filled via [method
## floor_cell_set]. Unlike F1, F2 has no vertical extrusion step (the
## rectangle IS already the complete 1-cell-thick formula) and no tunable
## knob of its own -- the GDD's own Tuning Knobs table
## (`design/gdd/building-system.md` "## Tuning Knobs") names only
## `wall_height` for the wall tool; per `CONTRACTS.md` §2's "one config per
## GDD Tuning Knob" rule, this tool intentionally carries no `.tres` config
## -- a documented deviation from [WallTool]'s config-driven shape, not an
## oversight.
##
## **Zero-length drag degenerates to a single 1x1 tile** (AC7's own
## documented edge case, F2's "Zero-length drag degenerates to a single 1x1
## tile"): [method floor_cell_set] naturally returns a single-element
## rectangle for identical endpoints -- this is also exactly what a genuine
## click resolves to (mirroring [WallTool]'s AC6b precedent), so [method
## resolve_cell_set] does not branch on its own `is_drag` parameter at all --
## the SAME formula call correctly resolves both the drag (AC7) and
## click/degenerate-drag cases with no branch.
##
## **Grep-guard invariant** (QA plan Sprint 8, Call-out 3): this file never
## constructs a [BlueprintCell] directly and never calls
## [method VoxelWorldGrid.set_cell]/[method VoxelWorldGrid.bulk_write]/
## [method VoxelWorldGrid.clear_cell] -- [CommitPipeline.commit] remains the
## sole creator/writer. [method resolve_cell_set] only ever returns an
## `Array[Vector3i]` candidate set; it is registered into [CommitPipeline] via
## [method CommitPipeline.set_cell_set_resolver], mirroring [WallTool]'s own
## documented "future tool story overrides this" seam exactly.
##
## Unlike [WallTool] (an injected-tier module per ADR-0001 with a `config`
## dependency to wire/validate in `setup()`), this class has no dependency of
## any kind -- there is nothing to wire and nothing to validate, so no
## `setup()`/`is_set_up()` gate exists here. [method resolve_cell_set] is
## callable immediately after construction. A future scene-assembly story
## still attaches this as a plain `Node` (matching [WallTool]'s shape for
## the tool family's uniformity, e.g. a future ghost-preview call site,
## Story 023), it just never needs to call `setup()` on it first.
class_name FloorTool
extends Node


## The [method CommitPipeline.set_cell_set_resolver]-compatible bound entry
## point (`Callable(is_drag: bool, press_cell: Vector3i, release_cell:
## Vector3i) -> Array[Vector3i]`) -- a future scene-assembly story wires this
## via `commit_pipeline.set_cell_set_resolver(floor_tool.resolve_cell_set)`.
## Ignores [param _is_drag] entirely -- see class doc comment for why the
## SAME F2 formula call correctly resolves both the drag (AC7) and
## click/degenerate-drag cases with no branch.
func resolve_cell_set(_is_drag: bool, press_cell: Vector3i, release_cell: Vector3i) -> Array[Vector3i]:
	return FloorTool.floor_cell_set(press_cell, release_cell)


## GDD Formula F2 (pure, stateless -- exercisable directly with arbitrary
## values, mirroring [method WallTool.wall_cell_set]'s established
## testable-pure-function shape, and reusable as-is by a future ghost-preview
## call site, Story 023, per the QA plan's forward-compatibility note):
## `floor_cell_count = (|dx| + 1) x (|dz| + 1)`. Rasterizes a 1-cell-thick
## horizontal (X/Z) rectangle spanning [param press_cell] and [param
## release_cell]'s X/Z coordinates, inclusive of both corners regardless of
## drag direction. [param press_cell]'s OWN Y is used as the fixed height for
## every returned cell, never [param release_cell]'s Y (the working plane is
## locked to the drag's START cell for its entire duration, Core Rule 3,
## mirroring [WallTool.rasterize_run]'s identical Y-anchor discipline).
## `press_cell == release_cell` naturally returns a single-element rectangle
## (AC7's documented degenerate case, "a single 1x1 tile").
static func floor_cell_set(press_cell: Vector3i, release_cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var base_y: int = press_cell.y
	var min_x: int = mini(press_cell.x, release_cell.x)
	var max_x: int = maxi(press_cell.x, release_cell.x)
	var min_z: int = mini(press_cell.z, release_cell.z)
	var max_z: int = maxi(press_cell.z, release_cell.z)
	for z: int in range(min_z, max_z + 1):
		for x: int in range(min_x, max_x + 1):
			cells.append(Vector3i(x, base_y, z))
	return cells
