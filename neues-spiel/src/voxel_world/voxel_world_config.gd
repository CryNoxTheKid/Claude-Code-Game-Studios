## Typed tuning-config Resource for Voxel World / Grid Data (ADR-0002),
## storing every knob from design/gdd/voxel-world.md's Tuning Knobs section.
##
## Wired into [VoxelWorldGrid] (injected-tier, ADR-0001) as a typed `@export`
## dependency; a matching `.tres` instance lives at
## `res://data/config/voxel_world_config.tres`. Defaults are the GDD's
## slice-validated 2000x2000x32 baseline (ADR-0014) -- NOT the 16,000x16,000
## production target, which remains gated behind the storage/streaming spike
## referenced in the GDD's Formulas/Tuning Knobs sections (ADR-0015) and is
## out of this story's scope entirely.
##
## [method validate] applies [ConfigResource]'s two-tier policy: every
## single-field range issue clamps to its nearest GDD-documented safe bound
## and warns; `min_y <= max_y` is the one GDD-declared BLOCKING cross-value
## invariant (there is no single field to clamp for a relationship between
## two fields) -- Core Rule 1 (`design/gdd/voxel-world.md`) requires the grid
## origin fixed at (0,0,0) with no negative cell coordinates, so a violated
## `min_y <= max_y` can never be resolved by clamping either field alone.
class_name VoxelWorldConfig
extends ConfigResource

## Fixed cell edge length (GDD Formulas + Tuning Knobs, TR-voxel-world-012;
## Visual Direction Note §2b) -- blocks are flush, no gap. Deliberately NOT
## an `@export`: the GDD locks this value, it is not a designer tuning knob.
const CELL_SIZE: float = 1.0

## Safe range for [member world_width_cells] (GDD Tuning Knobs: 256-2048
## validated). The 16,000 production target is UNVALIDATED pending the
## storage/streaming spike (ADR-0015) and is out of this story's scope --
## this range intentionally does NOT extend to it.
const WORLD_WIDTH_CELLS_MIN: int = 256
const WORLD_WIDTH_CELLS_MAX: int = 2048

## Safe range for [member world_depth_cells] -- see [constant
## WORLD_WIDTH_CELLS_MIN] (identical range, GDD Tuning Knobs).
const WORLD_DEPTH_CELLS_MIN: int = 256
const WORLD_DEPTH_CELLS_MAX: int = 2048

## [member min_y] carries no GDD-documented safe range of its own beyond
## Core Rule 1's fixed-origin invariant (no negative cell coordinates) --
## this is the only floor enforced as a single-field clamp; the relationship
## to [member max_y] is the separate BLOCKING invariant.
const MIN_Y_FLOOR: int = 0

## Safe range for [member max_y] (GDD Tuning Knobs: 8-32).
const MAX_Y_MIN: int = 8
const MAX_Y_MAX: int = 32

## Floor for [member base_height]. Its GDD-documented upper bound ("0 to
## max_y-1", Tuning Knobs) is relative to [member max_y]'s current value, so
## [method validate] applies it dynamically rather than as a second fixed
## constant.
const BASE_HEIGHT_MIN: int = 0

## Safe range for [member amplitude] (GDD Tuning Knobs: 0-8).
const AMPLITUDE_MIN: float = 0.0
const AMPLITUDE_MAX: float = 8.0

## Safe range for [member frequency] (GDD Tuning Knobs: 0.01-0.2).
const FREQUENCY_MIN: float = 0.01
const FREQUENCY_MAX: float = 0.2

## Horizontal world extent along X, in cells (GDD default: 2000 -- the
## slice-validated baseline, ADR-0014; NOT the 16,000 production target).
## [TR-voxel-world-016] [TR-voxel-world-023]
@export var world_width_cells: int = 2000

## Horizontal world extent along Z, in cells (GDD default: 2000). See
## [member world_width_cells]. [TR-voxel-world-016] [TR-voxel-world-023]
@export var world_depth_cells: int = 2000

## Minimum valid cell Y (GDD default: 0). Recommended fixed at 0 -- Core
## Rule 1 fixes the grid origin at (0,0,0) with no negative cell
## coordinates. [TR-voxel-world-027] [TR-voxel-world-023]
@export var min_y: int = 0

## Maximum valid cell Y (GDD default: 16). [TR-voxel-world-023]
@export var max_y: int = 16

## Valley-floor terrain height fed into the procedural terrain height
## formula (GDD default: 4; Story 006 scope). [TR-voxel-world-023]
@export var base_height: int = 4

## Max height variation from noise, fed into the procedural terrain height
## formula (GDD default: 3.0; Story 006 scope). [TR-voxel-world-023]
@export var amplitude: float = 3.0

## Noise scale, fed into the procedural terrain height formula (GDD
## default: 0.05; Story 006 scope). [TR-voxel-world-023]
@export var frequency: float = 0.05


## See [ConfigResource.validate]. Clamps every ranged knob to its
## GDD-documented safe bound in place (the sole sanctioned runtime write to
## this config) and appends a warning string per clamped field; reports
## `min_y <= max_y` as BLOCKING when violated instead of clamping either
## field (ADR-0002 two-tier policy).
func validate() -> Array[String]:
	var issues: Array[String] = []
	if world_width_cells < WORLD_WIDTH_CELLS_MIN or world_width_cells > WORLD_WIDTH_CELLS_MAX:
		issues.append(
			"world_width_cells out of range [%s, %s], got %s -- clamped" %
			[WORLD_WIDTH_CELLS_MIN, WORLD_WIDTH_CELLS_MAX, world_width_cells]
		)
		world_width_cells = clampi(world_width_cells, WORLD_WIDTH_CELLS_MIN, WORLD_WIDTH_CELLS_MAX)
	if world_depth_cells < WORLD_DEPTH_CELLS_MIN or world_depth_cells > WORLD_DEPTH_CELLS_MAX:
		issues.append(
			"world_depth_cells out of range [%s, %s], got %s -- clamped" %
			[WORLD_DEPTH_CELLS_MIN, WORLD_DEPTH_CELLS_MAX, world_depth_cells]
		)
		world_depth_cells = clampi(world_depth_cells, WORLD_DEPTH_CELLS_MIN, WORLD_DEPTH_CELLS_MAX)
	if min_y < MIN_Y_FLOOR:
		issues.append(
			"min_y below floor %s, got %s -- clamped" % [MIN_Y_FLOOR, min_y]
		)
		min_y = MIN_Y_FLOOR
	if max_y < MAX_Y_MIN or max_y > MAX_Y_MAX:
		issues.append(
			"max_y out of range [%s, %s], got %s -- clamped" % [MAX_Y_MIN, MAX_Y_MAX, max_y]
		)
		max_y = clampi(max_y, MAX_Y_MIN, MAX_Y_MAX)
	var base_height_ceiling: int = maxi(max_y - 1, BASE_HEIGHT_MIN)
	if base_height < BASE_HEIGHT_MIN or base_height > base_height_ceiling:
		issues.append(
			"base_height out of range [%s, %s], got %s -- clamped" %
			[BASE_HEIGHT_MIN, base_height_ceiling, base_height]
		)
		base_height = clampi(base_height, BASE_HEIGHT_MIN, base_height_ceiling)
	if amplitude < AMPLITUDE_MIN or amplitude > AMPLITUDE_MAX:
		issues.append(
			"amplitude out of range [%s, %s], got %s -- clamped" % [AMPLITUDE_MIN, AMPLITUDE_MAX, amplitude]
		)
		amplitude = clampf(amplitude, AMPLITUDE_MIN, AMPLITUDE_MAX)
	if frequency < FREQUENCY_MIN or frequency > FREQUENCY_MAX:
		issues.append(
			"frequency out of range [%s, %s], got %s -- clamped" % [FREQUENCY_MIN, FREQUENCY_MAX, frequency]
		)
		frequency = clampf(frequency, FREQUENCY_MIN, FREQUENCY_MAX)
	if min_y > max_y:
		issues.append(ConfigResource.format_blocking(
			"min_y (%s) must be <= max_y (%s)" % [min_y, max_y]
		))
	return issues
