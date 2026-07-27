## Typed tuning-config Resource for [ConstructionTickLoop] (ADR-0002) --
## GDD Formula F3's `base_build_ticks[category]` tuning knobs (Story
## building-029, [TR-building-system-079]/[TR-building-system-080]).
##
## Wired into [ConstructionTickLoop] (injected-tier, ADR-0001) as another
## typed `@export` dependency; a matching `.tres` instance lives at
## `res://data/config/construction_tick_loop_config.tres`. Mirrors
## [PlacementPickConfig]/[VoxelWorldConfig]'s established one-config-per-
## module precedent.
class_name ConstructionTickLoopConfig
extends ConfigResource

## Safe range for [member base_build_ticks_block] (`design/gdd/building-system.md`
## Tuning Knobs table: 1-20, default 4 -- "Construction pacing per block (F3)").
const BASE_BUILD_TICKS_BLOCK_MIN: int = 1
const BASE_BUILD_TICKS_BLOCK_MAX: int = 20

## Safe range for [member base_build_ticks_furniture] (Tuning Knobs table:
## 1-40, default 8 -- "Furniture construction pacing (F3)").
const BASE_BUILD_TICKS_FURNITURE_MIN: int = 1
const BASE_BUILD_TICKS_FURNITURE_MAX: int = 40

## `base_build_ticks[block]` (GDD Formula F3, [TR-building-system-079]):
## tick events a claimed on-site job needs to complete a BLOCK-category
## blueprint cell. Default 4 -- per the CURRENT Control Manifest's
## `ticks_per_second = 4.0` (ADR-0008 resolution 2026-07-23) that is 1.0s at
## 1x warp; the GDD F3 table's own "2.0s at 1x" annotation predates that
## tick-rate resolution -- the tuning VALUE (4 ticks) is unaffected either
## way, only the wall-clock gloss differs.
@export var base_build_ticks_block: int = 4

## `base_build_ticks[furniture]` (GDD Formula F3): tick events needed for a
## FURNITURE-category cell -- "more deliberate" than a block per the GDD.
## Default 8 (same tick-rate caveat as [member base_build_ticks_block]).
@export var base_build_ticks_furniture: int = 8

## Safe range for [member base_demolition_ticks_block] (`design/gdd/building-system.md`
## Tuning Knobs table: 1-20, default 4 -- "Demolition pacing per block (F3
## addendum, Rule 14j)").
const BASE_DEMOLITION_TICKS_BLOCK_MIN: int = 1
const BASE_DEMOLITION_TICKS_BLOCK_MAX: int = 20

## Safe range for [member base_demolition_ticks_furniture] (Tuning Knobs
## table: 1-40, default 8 -- "Demolition pacing for furniture (F3 addendum,
## Rule 14j/16)").
const BASE_DEMOLITION_TICKS_FURNITURE_MIN: int = 1
const BASE_DEMOLITION_TICKS_FURNITURE_MAX: int = 40

## `base_demolition_ticks[block]` (Story building-009, GDD Formula F3
## addendum, Rule 14j, [TR-building-system-114]/[TR-building-system-115]):
## tick events a claimed on-site demolition job needs to tear down a
## BLOCK-category Built cell -- "mirrors Rule 12's construction job contract
## in reverse... taking base_demolition_ticks per cell." Default 4 -- an
## `[assumption]` per the GDD's own provenance rule (mirrors
## [member base_build_ticks_block]'s default as a neutral placeholder,
## pending a dedicated demolition-pacing playtest the GDD names explicitly).
@export var base_demolition_ticks_block: int = 4

## `base_demolition_ticks[furniture]` (Story building-009, same GDD F3
## addendum): tick events needed to demolish a FURNITURE-category Built cell.
## Default 8 (same `[assumption]` provenance caveat as
## [member base_demolition_ticks_block]) -- landed here for Story 017's
## future furniture-demolition reuse of this SAME config, not consumed by
## this story's own BLOCK-only scope.
@export var base_demolition_ticks_furniture: int = 8


## See [ConfigResource.validate]. Clamps all four fields to their respective
## bounds and appends a warning string per clamped field -- no BLOCKING
## cross-value invariant exists for this config (ADR-0002 two-tier policy),
## mirroring [PlacementPickConfig]'s clamp-only precedent.
func validate() -> Array[String]:
	var issues: Array[String] = []
	if base_build_ticks_block < BASE_BUILD_TICKS_BLOCK_MIN or base_build_ticks_block > BASE_BUILD_TICKS_BLOCK_MAX:
		issues.append(
			"base_build_ticks_block out of range [%s, %s], got %s -- clamped" %
			[BASE_BUILD_TICKS_BLOCK_MIN, BASE_BUILD_TICKS_BLOCK_MAX, base_build_ticks_block]
		)
		base_build_ticks_block = clampi(base_build_ticks_block, BASE_BUILD_TICKS_BLOCK_MIN, BASE_BUILD_TICKS_BLOCK_MAX)
	if (
		base_build_ticks_furniture < BASE_BUILD_TICKS_FURNITURE_MIN
		or base_build_ticks_furniture > BASE_BUILD_TICKS_FURNITURE_MAX
	):
		issues.append(
			"base_build_ticks_furniture out of range [%s, %s], got %s -- clamped" %
			[BASE_BUILD_TICKS_FURNITURE_MIN, BASE_BUILD_TICKS_FURNITURE_MAX, base_build_ticks_furniture]
		)
		base_build_ticks_furniture = clampi(
			base_build_ticks_furniture, BASE_BUILD_TICKS_FURNITURE_MIN, BASE_BUILD_TICKS_FURNITURE_MAX
		)
	if (
		base_demolition_ticks_block < BASE_DEMOLITION_TICKS_BLOCK_MIN
		or base_demolition_ticks_block > BASE_DEMOLITION_TICKS_BLOCK_MAX
	):
		issues.append(
			"base_demolition_ticks_block out of range [%s, %s], got %s -- clamped" %
			[BASE_DEMOLITION_TICKS_BLOCK_MIN, BASE_DEMOLITION_TICKS_BLOCK_MAX, base_demolition_ticks_block]
		)
		base_demolition_ticks_block = clampi(
			base_demolition_ticks_block, BASE_DEMOLITION_TICKS_BLOCK_MIN, BASE_DEMOLITION_TICKS_BLOCK_MAX
		)
	if (
		base_demolition_ticks_furniture < BASE_DEMOLITION_TICKS_FURNITURE_MIN
		or base_demolition_ticks_furniture > BASE_DEMOLITION_TICKS_FURNITURE_MAX
	):
		issues.append(
			"base_demolition_ticks_furniture out of range [%s, %s], got %s -- clamped" %
			[BASE_DEMOLITION_TICKS_FURNITURE_MIN, BASE_DEMOLITION_TICKS_FURNITURE_MAX, base_demolition_ticks_furniture]
		)
		base_demolition_ticks_furniture = clampi(
			base_demolition_ticks_furniture, BASE_DEMOLITION_TICKS_FURNITURE_MIN, BASE_DEMOLITION_TICKS_FURNITURE_MAX
		)
	return issues
