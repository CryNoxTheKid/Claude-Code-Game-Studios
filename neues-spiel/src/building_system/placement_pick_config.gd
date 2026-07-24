## Typed tuning-config Resource for [PlacementPick] (ADR-0002), storing the one
## tuning knob this story's DDA pick needs.
##
## Wired into [PlacementPick] (injected-tier, ADR-0001) as another typed
## `@export` dependency; a matching `.tres` instance lives at
## `res://data/config/placement_pick_config.tres`. Mirrors
## [CameraInputConfig]/[VoxelWorldConfig]'s established one-config-per-module
## precedent -- created fresh here rather than folded into a not-yet-existing
## shared `BuildingSystemConfig`, matching [ToolStateMachine]'s own doc-comment
## precedent ("no tuning knob is introduced by the state machine itself").
class_name PlacementPickConfig
extends ConfigResource

## Sanity floor for [member max_pick_distance] -- a non-positive pick distance
## would make every raycast an instant miss, which is nonsensical. Mirrors
## [CameraInputConfig]'s "sanity floor, not a GDD-documented tuning range"
## precedent (`FOV_DEGREES_MIN` doc comment) for a value the GDD's Tuning
## Knobs table does not yet list.
const MAX_PICK_DISTANCE_MIN: float = 1.0

## Maximum ray length, world units, for [method VoxelWorldGrid.raycast_cells]
## calls in the placement pick path. `[assumption]` -- building-system.md's
## Tuning Knobs table does not yet list a pick-distance knob; this default
## (200.0) comfortably exceeds [CameraInputConfig.distance_max]'s 60.0 zoom
## ceiling plus reasonable off-center screen-ray travel, so a valid on-screen
## pick is never truncated by this bound in ordinary play. Flagged for the GDD
## to adopt explicitly at its next revision, mirroring [CameraInputConfig
## .fov_degrees]'s own `[assumption]` precedent.
@export var max_pick_distance: float = 200.0


## See [ConfigResource.validate]. Clamps [member max_pick_distance] to its
## sanity floor and appends a warning string if violated -- no BLOCKING
## cross-value invariant exists for this single-field config (ADR-0002
## two-tier policy), mirroring [CameraInputConfig]'s clamp-only precedent.
func validate() -> Array[String]:
	var issues: Array[String] = []
	if max_pick_distance < MAX_PICK_DISTANCE_MIN:
		issues.append(
			"max_pick_distance must be >= %s, got %s -- clamped" %
			[MAX_PICK_DISTANCE_MIN, max_pick_distance]
		)
		max_pick_distance = MAX_PICK_DISTANCE_MIN
	return issues
