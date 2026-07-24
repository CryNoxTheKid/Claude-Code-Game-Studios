## Building System's blueprint (Draft) cell value object (Story
## building-021, GDD Core Rule 11 [TR-building-system-052]: "A valid commit
## does NOT write blocks into the grid. It creates blueprint cells: planned
## cells rendered as ghosts, owned by this system, invisible to Voxel World's
## data layer.")
##
## `RefCounted`, not `Resource` -- owned entirely by [CommitPipeline] (and,
## once it lands, the persistent project entity ADR-0016/Story
## building-002 defines) -- never authored/serialized/shared directly;
## mirrors [CellContents]/[RaycastHitResult]'s shared "fresh lightweight
## value object" precedent, though unlike those transient per-call objects
## this one is RETAINED for as long as the cell remains part of a project
## (RefCounted supports that fine -- it is not a garbage-collected type,
## just automatically freed once nothing references it anymore).
##
## [enum MicroState] names the FULL "Blueprint cell lifecycle" table
## (`design/gdd/building-system.md`, States and Transitions) up front so a
## later story never needs to introduce a second/renamed enum for the same
## per-cell state axis -- naming matches the GDD's own "micro-state"
## terminology (Core Rule 16: "the removal tool's behavior branches on the
## target cell's own micro-state"). [CommitPipeline] (this story) only ever
## constructs a cell in [constant MicroState.PLANNED]; the other three
## values exist here as the documented target shape for future stories to
## drive transitions into -- Story building-004 (release/job eligibility),
## building-029/030 (construction), and building-009/015/032 (demolition/
## cancel/undo). No transition method is implemented by this story.
##
## Story building-029 (this revision) adds [member category]/[member
## contents] -- GDD Formula F3's `cell_build_ticks = base_build_ticks
## [category]` needs to know WHICH tuning knob a cell uses
## ([TR-building-system-079]), and completing a cell needs to know WHAT to
## write into [VoxelWorldGrid] ([TR-building-system-057]). Both default to a
## PLACEHOLDER (`Category.BLOCK` / a generic solid [CellContents]) -- Story
## 022's real material-selection wiring (Core Rule 9) is the future caller
## that will pass a real resolved value into [method _init] instead of
## relying on this default, mirroring [CommitPipeline]'s own established
## placeholder-pending-a-later-story precedent (`_default_cell_set`'s doc
## comment).
class_name BlueprintCell
extends RefCounted

## The GDD's "Blueprint cell lifecycle" table states, verbatim: Planned (UX
## term "Draft" while its project/change-order batch is unreleased -- same
## system state, Slice revision 2026-07-23 doc note) / UnderConstruction /
## Built / Canceled.
enum MicroState {
	PLANNED,
	UNDER_CONSTRUCTION,
	BUILT,
	CANCELED,
}

## GDD Formula F3's `category` axis (`base_build_ticks[block]` = 4,
## `[furniture]` = 8, [TR-building-system-079]) -- Story building-029
## addition (see class doc comment). Determines which tuning knob
## [method ConstructionTickLoop.required_ticks_for] reads for this cell.
enum Category {
	BLOCK,
	FURNITURE,
}

## The cell address this blueprint cell occupies.
var cell: Vector3i

## Current micro-state -- always [constant MicroState.PLANNED] for a cell
## [CommitPipeline] itself creates (this story never drives a transition).
var state: MicroState

## See [enum Category] -- Story building-029 addition. Defaults to
## [constant Category.BLOCK]; [CommitPipeline] does not yet set this
## explicitly (Story 028's furniture placement is the future real caller).
var category: Category

## The [CellContents] [ConstructionTickLoop] writes into [VoxelWorldGrid]
## once this cell completes construction ([TR-building-system-057]) --
## Story building-029 addition, PLACEHOLDER pending Story 022's real
## material selection (see class doc comment).
var contents: CellContents


func _init(
	p_cell: Vector3i,
	p_state: MicroState = MicroState.PLANNED,
	p_category: Category = Category.BLOCK,
	p_contents: CellContents = null
) -> void:
	cell = p_cell
	state = p_state
	category = p_category
	contents = p_contents if p_contents != null else CellContents.new(1, 0)
