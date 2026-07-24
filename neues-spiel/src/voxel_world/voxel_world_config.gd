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

## Safe range for [member region_size_chunks] (Story vox-010, ADR-0015
## Decision §2 -- "a spike-tuned knob", not a GDD Tuning Knob; range is this
## story's own choice, wide enough to cover the spike's validated 32 default
## while still catching a degenerate 0/negative or absurdly large value).
const REGION_SIZE_CHUNKS_MIN: int = 4
const REGION_SIZE_CHUNKS_MAX: int = 128

## Safe range for [member view_radius_chunks] (Story vox-010, ADR-0015
## Decision §1's "camera-near chunks (ADR-0014 view radius)"; spike default
## 24 -- see [member view_radius_chunks]'s own doc comment).
const VIEW_RADIUS_CHUNKS_MIN: int = 2
const VIEW_RADIUS_CHUNKS_MAX: int = 64

## Safe range for [member settlement_radius_chunks] (Story vox-010, ADR-0015
## Decision §1's "active-settlement chunks (ADR-0007 nav region)"; spike
## default 8 -- see [member settlement_radius_chunks]'s own doc comment).
const SETTLEMENT_RADIUS_CHUNKS_MIN: int = 1
const SETTLEMENT_RADIUS_CHUNKS_MAX: int = 32

## Fallback used by [method validate] when [member region_directory] is
## empty (a single-field clamp-to-default, same two-tier policy as every
## other ranged knob here).
const REGION_DIRECTORY_DEFAULT: String = "user://regions"

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

## Deterministic seed for [method VoxelWorldGrid.generate_terrain]'s
## `noise2D` (TR-voxel-world-039: "deterministic, seeded 2D noise function").
## Not itself a named row in the GDD's Tuning Knobs table (added this story
## to satisfy TR-voxel-world-039's seeding requirement without a hardcoded
## literal, per ADR-0002's "data-driven, never hardcoded" mandate) -- any
## `int` is a valid seed, so [method validate] applies no range check here.
## Two [VoxelWorldGrid.generate_terrain] runs with the same [member
## terrain_seed] (and otherwise-identical config) produce byte-identical
## terrain; a different seed produces different terrain (ADR-0015's
## deterministic-seeded-regen premise). [TR-voxel-world-039] [TR-voxel-world-023]
@export var terrain_seed: int = 12345

## Root directory for on-disk region files (Story vox-010, ADR-0015 Decision
## §2/§4) -- the paged residency tier's storage location. Production default
## is a `user://` path: region files are user data, `.gitignore`d BY
## CONSTRUCTION since `user://` resolves to the OS-specific user-data
## directory, entirely outside this project's git-tracked tree -- never
## `res://`, which is git-tracked and read-only at runtime once exported.
## Tests MUST override this to an isolated per-test temp directory and
## remove it in `after_test` -- never share a region directory across test
## runs (region-file test-isolation pitfall).
@export var region_directory: String = REGION_DIRECTORY_DEFAULT

## Region file dimensions, in chunks per axis (ADR-0015 Decision §2's
## `region_size_chunks` -- "a spike-tuned knob"; spike default 32x32
## chunks/region, `prototypes/storage-residency-spike/README.md` "Design
## choices made"). [TR-voxel-world-053]
@export var region_size_chunks: int = 32

## Camera-near residency window radius, in chunks (ADR-0015 Decision §1's
## "camera-near chunks (ADR-0014 view radius)"; spike default 24). Camera &
## Input's own view-window streaming (Story 015) does not exist in
## production yet -- this knob is residency's own copy of the same concept
## until that story lands and the two are reconciled. [TR-voxel-world-053]
@export var view_radius_chunks: int = 24

## Active-settlement residency window radius, in chunks, around an injected
## settlement anchor (ADR-0015 Decision §1's "active-settlement chunks
## (ADR-0007 nav region)"; spike default 8 -- "smaller than the 24-chunk
## camera view radius"). Villager AI's own nav-region wiring (ADR-0007) does
## not exist in production yet -- this knob stands in for that scale until
## that story lands. [TR-voxel-world-053]
@export var settlement_radius_chunks: int = 8


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
	if region_directory.is_empty():
		issues.append(
			"region_directory is empty -- clamped to default '%s'" % REGION_DIRECTORY_DEFAULT
		)
		region_directory = REGION_DIRECTORY_DEFAULT
	if region_size_chunks < REGION_SIZE_CHUNKS_MIN or region_size_chunks > REGION_SIZE_CHUNKS_MAX:
		issues.append(
			"region_size_chunks out of range [%s, %s], got %s -- clamped" %
			[REGION_SIZE_CHUNKS_MIN, REGION_SIZE_CHUNKS_MAX, region_size_chunks]
		)
		region_size_chunks = clampi(region_size_chunks, REGION_SIZE_CHUNKS_MIN, REGION_SIZE_CHUNKS_MAX)
	if view_radius_chunks < VIEW_RADIUS_CHUNKS_MIN or view_radius_chunks > VIEW_RADIUS_CHUNKS_MAX:
		issues.append(
			"view_radius_chunks out of range [%s, %s], got %s -- clamped" %
			[VIEW_RADIUS_CHUNKS_MIN, VIEW_RADIUS_CHUNKS_MAX, view_radius_chunks]
		)
		view_radius_chunks = clampi(view_radius_chunks, VIEW_RADIUS_CHUNKS_MIN, VIEW_RADIUS_CHUNKS_MAX)
	if settlement_radius_chunks < SETTLEMENT_RADIUS_CHUNKS_MIN or settlement_radius_chunks > SETTLEMENT_RADIUS_CHUNKS_MAX:
		issues.append(
			"settlement_radius_chunks out of range [%s, %s], got %s -- clamped" %
			[SETTLEMENT_RADIUS_CHUNKS_MIN, SETTLEMENT_RADIUS_CHUNKS_MAX, settlement_radius_chunks]
		)
		settlement_radius_chunks = clampi(settlement_radius_chunks, SETTLEMENT_RADIUS_CHUNKS_MIN, SETTLEMENT_RADIUS_CHUNKS_MAX)
	if min_y > max_y:
		issues.append(ConfigResource.format_blocking(
			"min_y (%s) must be <= max_y (%s)" % [min_y, max_y]
		))
	return issues
