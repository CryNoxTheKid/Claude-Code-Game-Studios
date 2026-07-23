## Resource & Item Database Autoload (ADR-0001 Autoload tier; ADR-0005 boot
## gate; ADR-0006 two-type split consumer).
##
## Loads every [ItemDefinitionResource] `.tres` file under [member data_dir]
## exactly once at boot, following the GDD's `Unloaded -> Validating ->
## Ready | Failed` lifecycle (design/gdd/resource-item-database.md States
## and Transitions table). [signal validation_complete] fires exactly once,
## when [method setup] resolves -- the boot-gate hook [GameWorld] (ADR-0005)
## already check-then-connects against via [method is_ready] first, this
## signal as a fallback.
##
## Story rid-002 scope note: full field-level/cross-value schema validation
## (id uniqueness, category/family pairing, tier-0 coverage, reserved-id
## rejection, retired-ids ledger, `visual_asset` resolution, etc.) is
## deliberately NOT implemented here -- Stories 004/005/006/008 own that
## pipeline (design/gdd/resource-item-database.md States and Transitions,
## Validating row). This story implements only the minimal placeholder
## Validating->Ready|Failed decision ADR-0006's own Risks section already
## anticipates: a `.tres` file that fails to load entirely, or loads as the
## wrong Resource type, fails the whole batch (Failed, TERMINAL, ADR-0006
## Risk 2 / TR-resource-item-database-006) -- never a partially valid
## database. A missing or empty [member data_dir] is NOT a failure at this
## story's scope (no schema invariant exists yet to violate) -- it resolves
## Ready with zero definitions until Story 009 authors real MVP data content.
##
## The lookup entry point [method get_by_id] carries Story 002's minimal
## non-Ready guard contract (TR-resource-item-database-034 -- outside Ready,
## always an explicit error, never data, never a partial read) using the
## exact `get_by_id(id) -> ItemDefinition` signature ADR-0006's Key
## Interfaces section specifies. Story 003 completes the read-only lookup
## surface on this same guard: [method get_by_id] now logs an unknown id
## once before returning `null` (GDD Edge Case 2 / AC8), and four listing
## queries -- [method list_ids_by_category], [method
## list_ids_by_material_family], [method list_ids_by_tier], [method
## list_all_ids] -- are added, each returning an empty typed list (never an
## error) both outside Ready and for a zero-match query (GDD Edge Case 8 /
## AC12; GDD Core Rule 8 -- no write API is exposed anywhere on this
## surface). The `missing_item` fallback resolution and its exclusion from
## these listings remain Story 007's job, layered on this same surface
## without changing any signature here.
##
## Deliberately carries NO `class_name` -- Godot 4.7 hard-errors "Class
## 'ResourceItemDatabase' hides an autoload singleton" if a script both
## declares that `class_name` AND is registered as the Autoload singleton of
## the same name (the exact `TimeTickSystem` precedent -- see that script's
## own doc comment). Callers use the registered singleton name directly
## (`ResourceItemDatabase.is_ready()`), never `@export`-injected (ADR-0001
## forbids `@export`ing an Autoload into any module).
extends Node

## Boot-sequencing lifecycle (GDD States and Transitions table). Progresses
## UNLOADED -> VALIDATING -> READY | FAILED exactly once per session; a
## second [method setup] call after leaving UNLOADED is rejected (see that
## method) rather than re-entering VALIDATING.
enum BootState { UNLOADED, VALIDATING, READY, FAILED }

## Emitted exactly once, when [method setup] resolves to Ready or Failed.
## Payload shape: `{"success": bool, "issues": Array}` -- a plain
## [Dictionary] rather than a typed `ValidationResult` (that class does not
## exist yet; Stories 004/005 introduce the structured validation-result
## contract). [GameWorld]'s existing boot gate (ADR-0005) already consumes
## exactly this shape via its `MockResourceItemDatabase` test double.
signal validation_complete(result: Dictionary)

## Default directory scanned for `.tres` [ItemDefinitionResource] entries
## (ADR-0002 authoring idiom, ADR-0006 storage location).
const DEFAULT_DATA_DIR: String = "res://data/items/"

## Directory this instance scans at [method setup]. Production leaves this
## at [constant DEFAULT_DATA_DIR]; a headless test assigns a fixture
## directory before calling [method setup] directly (Test Evidence:
## `Node.new()`, inject a mock data path, call `setup()` directly -- zero
## scene tree, zero Autoload registration).
var data_dir: String = DEFAULT_DATA_DIR

## Current lifecycle state. Read-only from outside this class -- see
## [method get_state] / [method is_ready].
var _state: BootState = BootState.UNLOADED

## Loaded definitions, keyed by [member ItemDefinitionResource.id]. Only
## ever populated on a successful [method setup] resolution; stays empty in
## every other state.
var _definitions: Dictionary[StringName, ItemDefinitionResource] = {}


func _ready() -> void:
	setup()


## Explicitly callable wiring/validation entry point (ADR-0001/ADR-0005
## Autoload-tier convention, mirroring `TimeTickSystem.setup()`). Runs the
## GDD's Unloaded->Validating->Ready|Failed pipeline against
## [member data_dir] and emits [signal validation_complete] exactly once.
##
## Load-once guard (GDD Core Rule 2 / TR-resource-item-database-025, story
## QA plan AC-2): once this instance has left [constant BootState.UNLOADED]
## (Ready OR Failed -- both terminal for the session), a further call is
## rejected outright -- no re-scan, no second [signal validation_complete]
## emission, [member _definitions] left completely untouched -- and returns
## an explicit error result describing the rejection.
##
## Returns the same `{"success": bool, "issues": Array}` result
## [signal validation_complete] carries, so a direct caller (production
## `_ready()`, or a test) can inspect the outcome inline without a signal
## listener.
func setup() -> Dictionary:
	if _state != BootState.UNLOADED:
		var template: String = (
			"ResourceItemDatabase.setup() called again after the database "
			+ "already resolved to %s -- rejected; a database loads exactly "
			+ "once per session and Ready contents are never re-scanned"
		)
		return {"success": false, "issues": [template % BootState.keys()[_state]]}
	_state = BootState.VALIDATING
	var load_result: Dictionary = _load_definitions()
	var result: Dictionary = {
		"success": load_result["success"],
		"issues": load_result["issues"],
	}
	if load_result["success"]:
		_definitions = load_result["definitions"]
		_state = BootState.READY
	else:
		_state = BootState.FAILED
	validation_complete.emit(result)
	return result


## Returns whether the database has resolved to Ready (ADR-0005's
## check-then-connect synchronous first check). `false` in every other
## state, including Failed.
func is_ready() -> bool:
	return _state == BootState.READY


## Returns the current lifecycle state -- the test/observability seam for
## the pipeline's progress (mirrors `GameWorld.get_boot_state()`).
func get_state() -> BootState:
	return _state


## Full lookup implementation (Story 003, ADR-0006 Decision + GDD Core
## Rule 8): outside Ready, always returns `null` -- an explicit "no data"
## result, never a partial read, never a stale/previous value
## (TR-resource-item-database-034). Inside Ready, wraps the stored
## [ItemDefinitionResource] in a fresh [ItemDefinition] per call (ADR-0006 --
## wraps, never copies), or logs the unknown id once and returns `null` if
## [param id] is not present (GDD Edge Case 2 / AC8 -- an explicit not-found
## result, never a crash; the `missing_item` fallback resolution is Story
## 007's job, layered on this same guard without changing this signature).
func get_by_id(id: StringName) -> ItemDefinition:
	if _state != BootState.READY:
		return null
	var source: ItemDefinitionResource = _definitions.get(id)
	if source == null:
		push_warning(
			(
				"ResourceItemDatabase.get_by_id(): unknown id '%s' queried -- "
				+ "returning null (GDD Edge Case 2; missing_item fallback is "
				+ "Story 007's scope)"
			) % String(id)
		)
		return null
	return ItemDefinition.new(source)


## Returns the id of every entry whose [member ItemDefinitionResource.category]
## equals [param category]. A category with zero authored entries (e.g.
## `raw_resource` in MVP) returns an empty list -- a valid result, never an
## error (GDD Edge Case 8 / AC12). Outside Ready, also returns an empty list
## -- the same non-Ready guard [method get_by_id] applies
## (TR-resource-item-database-034): a listing query never partially answers.
func list_ids_by_category(category: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	if _state != BootState.READY:
		return ids
	for id: StringName in _definitions:
		if _definitions[id].category == category:
			ids.append(id)
	return ids


## Returns the id of every entry whose [member
## ItemDefinitionResource.material_family] equals [param material_family] --
## all and only entries of that family (GDD AC15). Same empty-list-on-zero-
## matches and non-Ready guard as [method list_ids_by_category].
func list_ids_by_material_family(material_family: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	if _state != BootState.READY:
		return ids
	for id: StringName in _definitions:
		if _definitions[id].material_family == material_family:
			ids.append(id)
	return ids


## Returns the id of every entry whose [member ItemDefinitionResource.tier]
## equals [param tier] (GDD AC14 -- proves the query logic on a fixture; the
## tier-0 building-material CONTENT assertion against shipped MVP data is
## Story 009's scope). Same empty-list-on-zero-matches and non-Ready guard
## as [method list_ids_by_category].
func list_ids_by_tier(tier: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	if _state != BootState.READY:
		return ids
	for id: StringName in _definitions:
		if _definitions[id].tier == tier:
			ids.append(id)
	return ids


## Returns every authored entry's id exactly once, in boot-load (sorted
## filename) order -- no unauthored id ever appears (GDD AC16). Same
## non-Ready guard as [method list_ids_by_category].
func list_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if _state != BootState.READY:
		return ids
	for id: StringName in _definitions:
		ids.append(id)
	return ids


## Scans [member data_dir] for `.tres` files and attempts to load each as an
## [ItemDefinitionResource]. Returns
## `{"success": bool, "issues": Array[String], "definitions":
## Dictionary[StringName, ItemDefinitionResource]}` -- `definitions` is
## populated ONLY when `success` is true (GDD Failed-state philosophy: never
## launch with a partially valid database, TR-resource-item-database-006 --
## applied here at this story's minimal placeholder scope: a load failure
## fails the WHOLE batch, not just the offending entry).
##
## A missing or empty [member data_dir] is NOT a failure at this scope (see
## class doc comment) -- it resolves as zero entries, `success = true`. A
## file that fails to load entirely, or loads as something other than an
## [ItemDefinitionResource], is the one failure condition this placeholder
## pipeline checks (ADR-0006 Risk 2's "resource failed to load entirely"
## case) -- full field-level schema validation is Stories 004/005/006/008's
## job.
func _load_definitions() -> Dictionary:
	var issues: Array[String] = []
	var definitions: Dictionary[StringName, ItemDefinitionResource] = {}
	var directory: DirAccess = DirAccess.open(data_dir)
	if directory == null:
		return {"success": true, "issues": issues, "definitions": definitions}
	var file_names: Array[String] = []
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	file_names.sort()
	for name: String in file_names:
		var path: String = data_dir.path_join(name)
		var loaded: Resource = load(path)
		if loaded == null or not (loaded is ItemDefinitionResource):
			issues.append("failed to load ItemDefinitionResource from %s" % path)
			continue
		var definition: ItemDefinitionResource = loaded as ItemDefinitionResource
		definitions[definition.id] = definition
	return {"success": issues.is_empty(), "issues": issues, "definitions": definitions}
