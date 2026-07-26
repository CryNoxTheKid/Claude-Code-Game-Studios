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
##
## Story build-validation-005 (this revision) adds the analysis PASS
## LIFECYCLE: [method setup] subscribes to [signal
## VoxelWorldGrid.cells_changed_batch] -- and to NOTHING else structural. Per
## TD ruling BV-2 (`production/architecture-decisions-m02-preflight-2026-07-
## 26.md`), this module deliberately does NOT subscribe to [signal
## ConstructionTickLoop.construction_completed]: that signal fires
## unconditionally after [method VoxelWorldGrid.bulk_write], but [method
## VoxelWorldGrid._apply_write] (ADR-0015 "load-before-write") QUEUES a write
## whose chunk is not resident and returns `null` -- the write lands later,
## from [method VoxelWorldGrid._apply_pending_writes], which emits [signal
## VoxelWorldGrid.cells_changed_batch] itself the instant it actually applies
## the deferred write. A pass triggered by `construction_completed` could
## therefore read stale (not-yet-landed) data; [signal
## VoxelWorldGrid.cells_changed_batch] cannot, by construction, since it only
## ever fires when a record actually changed. There is no `ConstructionTickLoop`
## reference anywhere in this file, and none is ever added.
##
## Each pass ([method _run_analysis_pass]) seeds the affected region(s) from
## the batch's own changed cells ([method
## BuildValidationRegionFormation.form_affected_regions], story 003), verdicts
## each ([method BuildValidationReachability.classify_region], story 004), and
## incrementally patches [member _region_snapshot] -- the transient,
## never-serialized analysis memory Rule 11 names (edge-detection memory for a
## LATER story's transition signals, never a compute cache; a full rebuild
## happens ONLY in [method run_load_pass]). Emission of this GDD's own
## player-facing signal contract (`room_recognized`/`shelter_status_changed`/
## `sealed_space_warning`/`unsheltered_furniture_info`) is explicitly deferred
## to stories 006/007/008 (Out of Scope) -- this story builds the snapshot
## those stories diff against and emits nothing of its own.
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

## Region-classification snapshot (Rule 11, [TR-build-validation-navigability-
## 048]/[TR-build-validation-navigability-006]): `cell -> Verdict`, PATCHED
## incrementally by every batched-trigger pass ([method _run_analysis_pass])
## and FULLY rebuilt only by [method run_load_pass] -- transient
## edge-detection memory for a LATER story's transition signals, never a
## compute cache, and never serialized (ADR-0012, Rule 4/28 -- rebuilt from the
## world on every load, nothing persisted here).
var _region_snapshot: Dictionary[Vector3i, BuildValidationReachability.Verdict] = {}

## Per-item shelter-flag snapshot -- Rule 11's OTHER named map ("the snapshot
## is two maps"), scaffolded here alongside [member _region_snapshot] but
## deliberately left UNPOPULATED by this story: no furniture exists in the
## landed build yet ([member furniture_registry] is always `null` until
## `building-028`), so there is nothing yet to classify. Story 006 populates
## and patches this map; this story only reserves its shape so 006 does not
## need to also touch the pass lifecycle.
var _shelter_snapshot: Dictionary[String, bool] = {}

## Instrumented analysis-pass count (AC19/AC20/BV-2's Gate 2 -- "assert
## analysis call-count"). Incremented exactly once per call to [method
## _run_analysis_pass], i.e. once per [signal
## VoxelWorldGrid.cells_changed_batch] emission this module receives --
## NEVER once per cell, per region, or per command within that batch (AC19).
## [method run_load_pass] does NOT touch this counter: the load pass is a
## distinct, explicitly-invoked full rebuild, never a batched-trigger pass
## (Rule 11 -- "no transition events... on load"; AC19/AC20 are both scoped to
## the batched-trigger path only).
var _analysis_pass_count: int = 0


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
	# Story build-validation-005 / BV-2 -- the ONE structural subscription.
	# Idempotent against a repeated setup() call (never double-connects); no
	# `ConstructionTickLoop.construction_completed` subscription exists
	# anywhere in this module -- see class doc comment for the correctness
	# argument (deferred/paged writes can leave that signal naming cells whose
	# data has not landed yet).
	if not voxel_world.cells_changed_batch.is_connected(_on_cells_changed_batch):
		voxel_world.cells_changed_batch.connect(_on_cells_changed_batch)
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


## Instrumented pass-count accessor (AC19/AC20, BV-2's Gate 2 -- "assert
## analysis call-count"). Test-observable instrumentation; [method
## get_region_status] is the GDD-facing queryable-state surface Rule 10 itself
## names.
func get_analysis_pass_count() -> int:
	return _analysis_pass_count


## Queryable region status (Rule 10: "all current statuses are additionally
## queryable at any time"). Returns [constant
## BuildValidationReachability.Verdict.OPEN] for a cell this module has never
## classified as part of any region -- the same default an ordinary
## un-analyzed cell would carry (States table: Open is the "no status" state),
## never a sentinel/error value.
func get_region_status(cell: Vector3i) -> BuildValidationReachability.Verdict:
	return _region_snapshot.get(cell, BuildValidationReachability.Verdict.OPEN)


## The one full-world pass (Rule 11, Edge Case 11, AC31): rebuilds [member
## _region_snapshot] and [member _shelter_snapshot] from scratch -- the ONLY
## place either snapshot is fully rebuilt rather than incrementally patched
## (Rule 11: "a full snapshot rebuild happens ONLY on the load pass"). Fires no
## transition events (this module emits none of its own at all yet -- see
## [method _run_analysis_pass]'s doc comment; stories 006-008 own the actual
## silence-on-load contract for their signals). Does NOT increment [member
## _analysis_pass_count] -- see that member's own doc comment.
##
## Seeds from every occupied cell's directly-above neighbor ([method
## VoxelWorldGrid.iterate_occupied], [TR-voxel-world-021]) rather than scanning
## every empty cell in the world bounds: a candidate interior cell always has
## SOME solid cell directly beneath it ([method
## VillagerWalkabilityRules.is_standable]'s own floor requirement), so this
## seed set is provably complete without an O(world-volume) empty-cell scan --
## only O(occupied-cell-count). Reuses [method
## BuildValidationRegionFormation.form_region] plus the same already-covered
## dedup [method _run_analysis_pass] uses, just seeded from the whole world's
## occupied cells instead of one pass's changed cells.
func run_load_pass() -> void:
	_region_snapshot.clear()
	_shelter_snapshot.clear()
	var already_covered: Dictionary[Vector3i, bool] = {}
	for record: CellOccupantRecord in voxel_world.iterate_occupied():
		var seed: Vector3i = record.cell + Vector3i(0, 1, 0)
		if already_covered.has(seed):
			continue
		var region: BuildValidationRegion = BuildValidationRegionFormation.form_region(
			voxel_world, seed, config.max_room_height
		)
		if region.size() == 0:
			continue
		var verdict: BuildValidationReachability.Verdict = BuildValidationReachability.classify_region(
			voxel_world, region, config.min_room_cells, config.max_room_height
		)
		for cell: Vector3i in region.cell_list():
			already_covered[cell] = true
			_region_snapshot[cell] = verdict


## [signal VoxelWorldGrid.cells_changed_batch] handler -- THE single
## structural trigger this module ever subscribes to (TD ruling BV-2). Extracts
## every changed cell from [param changes] (the record's own [member
## CellChangeRecord.cell], never its before/after contents -- this module
## re-reads CURRENT grid state itself via the shared predicates, the same
## "re-query, don't inspect the payload" discipline [VillagerNavGraph]'s own
## batch handler already established) and runs exactly ONE [method
## _run_analysis_pass] per emission -- never per cell (AC19).
func _on_cells_changed_batch(changes: Array[CellChangeRecord]) -> void:
	var changed_cells: Array[Vector3i] = []
	for record: CellChangeRecord in changes:
		changed_cells.append(record.cell)
	_run_analysis_pass(changed_cells)


## One analysis pass (Rule 7/11, AC19): seeds the affected region(s) from
## [param changed_cells] ([method
## BuildValidationRegionFormation.form_affected_regions] -- story 003's own
## scoping, never re-derived here), classifies each ([method
## BuildValidationReachability.classify_region] -- story 004), and patches
## [member _region_snapshot] for every cell of every returned region -- an
## INCREMENTAL patch (Rule 11): only the entries the affected region(s)
## actually touch are written; every other snapshot entry persists unchanged.
## Increments [member _analysis_pass_count] exactly once per call, regardless
## of how many regions [param changed_cells] resolves into (Edge Case 10: a
## batch spanning two disjoint regions is still ONE pass, two regions
## evaluated) -- the counter tracks PASSES, not regions or cells.
##
## Emission of this GDD's own signal contract (`room_recognized`/
## `shelter_status_changed`/`sealed_space_warning`/`unsheltered_furniture_info`)
## is explicitly OUT OF SCOPE here (Out of Scope: "Story 006/007/008: the four
## signals' payloads, edge-detection semantics, and pacing") -- this method
## builds the snapshot those stories diff against; it emits nothing of its
## own.
##
## Never calls any Building System or Villager AI API beyond the shared,
## static [VillagerWalkabilityRules] predicates (Rule 9's second half, AC33):
## [method BuildValidationRegionFormation.form_affected_regions] and [method
## BuildValidationReachability.classify_region] are this method's only calls,
## and neither holds nor accepts a villager/gameplay-entity reference.
func _run_analysis_pass(changed_cells: Array[Vector3i]) -> void:
	_analysis_pass_count += 1
	var regions: Array[BuildValidationRegion] = BuildValidationRegionFormation.form_affected_regions(
		voxel_world, changed_cells, config.max_room_height
	)
	for region: BuildValidationRegion in regions:
		var verdict: BuildValidationReachability.Verdict = BuildValidationReachability.classify_region(
			voxel_world, region, config.min_room_cells, config.max_room_height
		)
		for cell: Vector3i in region.cell_list():
			_region_snapshot[cell] = verdict
