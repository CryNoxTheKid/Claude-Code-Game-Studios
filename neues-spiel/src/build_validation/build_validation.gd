## Build Validation & Navigability module scaffold (Story build-validation-001,
## ADR-0001 injected-tier DI + ADR-0002 config; ADR-0007 walkability-
## consumption contract). This story's scope is EXACTLY the config resource +
## DI scaffold + the AC27 blocking lockstep invariant -- no candidate-cell
## predicate, no region formation, no reachability trace (those are stories
## 002-005).
##
## Per TD ruling BV-4 (`production/architecture-decisions-m02-preflight-
## 2026-07-26.md`), this module injects NO walkability provider of any kind --
## it calls [VillagerWalkabilityRules]'s static functions directly,
## `VillagerWalkabilityRules.is_standable(voxel_world, cell)`, using the SAME
## [member voxel_world] reference this module already injects for its own
## region analysis (stories 002+). This module therefore holds no reference
## to [VillagerAi] or any other gameplay entity, and cannot be null-ref'd by a
## despawned villager (BV-4 rationale). There is deliberately no `@export`
## of any `VillagerAi`-typed field anywhere in this module.
##
## [member voxel_world] plays BOTH roles this story's AC names separately
## ("Voxel World ref, structural-change signal source"): it is both the data
## source this module's (future) analysis reads AND the emitter of
## [signal VoxelWorldGrid.cells_changed_batch], the single structural trigger
## a later story (005, per TD ruling BV-2) subscribes to -- ONE injected
## dependency, two documented roles, not two separate `@export` fields.
## [method setup]'s single assertion on [member voxel_world] therefore covers
## both named dependencies.
##
## Per BV-1 §5, [member furniture_registry] is a duck-typed, nil-safe `Object`
## dependency (the landed precedent: `VillagerAi.needs_provider`/`job_queue`)
## -- a `null` value is a valid, correct state ("no furniture exists," true
## until `building-028` lands) and is therefore NEVER asserted by
## [method setup].
class_name BuildValidation
extends Node

## Tuning config (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Asserted wired by
## [method setup] -- never read inside `_ready()`.
@export var config: BuildValidationConfig

## Voxel World reference (ADR-0001). Serves BOTH roles this story's AC names
## separately -- see class doc comment. Asserted wired by [method setup].
@export var voxel_world: VoxelWorldGrid

## Furniture-registry provider (BV-1 §5) -- duck-typed, nil-safe, deliberately
## NOT `@export`ed as a typed dependency (no `FurnitureRegistry` class exists
## yet; `building-028` is a future story) and deliberately NOT asserted by
## [method setup] -- `null` means "no furniture exists," a correct default,
## exactly true until `building-028` lands.
var furniture_registry: Object = null

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## The BLOCKING-tagged subset of the most recent `config.validate()` result,
## if any. Populated by [method setup]; read by [GameWorld]'s boot gate via
## [method get_boot_blocking_issues] (ADR-0002/0005).
var _boot_blocking_issues: Array[String] = []


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config] and [member voxel_world] are wired, then applies
## ADR-0002's two-tier `validate()` policy exactly like
## [ReferenceConfigConsumer]: every non-BLOCKING issue is a clamp+warn
## (already applied by `validate()` itself) and is logged via `push_warning`;
## any BLOCKING issue (AC27's lockstep invariant) is recorded for
## [method get_boot_blocking_issues] instead of being treated as fatal here --
## the actual halt decision and terminal-path reuse live in [GameWorld]'s boot
## gate (ADR-0005), not in this module. Deliberately asserts NOTHING about a
## walkability provider (BV-4 -- there is none) or [member furniture_registry]
## (BV-1 §5 -- `null` is a valid state).
func setup() -> void:
	assert(config != null, "BuildValidation.config not wired")
	assert(voxel_world != null, "BuildValidation.voxel_world not wired")
	var issues: Array[String] = config.validate()
	_boot_blocking_issues = issues.filter(
		func(issue: String) -> bool: return issue.begins_with(ConfigResource.BLOCKING_PREFIX)
	)
	for issue: String in issues:
		if not issue.begins_with(ConfigResource.BLOCKING_PREFIX):
			push_warning(issue)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the BLOCKING-tagged issues (if any) found in the most recent
## `config.validate()` call. [GameWorld]'s boot gate duck-types this method
## on every injected-tier module after calling `setup()` (ADR-0002 Decision,
## ADR-0005 reuse) -- a non-empty result triggers the same terminal boot-halt
## path used for RID's Failed outcome, no new severity model, no new halt
## mechanism.
func get_boot_blocking_issues() -> Array[String]:
	return _boot_blocking_issues
