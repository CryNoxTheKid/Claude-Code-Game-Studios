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
## Story rid-004 scope note: this story extends the rid-002 placeholder
## pipeline with the PER-ENTRY schema-check pass (design/gdd/resource-item-
## database.md States and Transitions, Validating row; TR-resource-item-
## database-005/024/028/040/041/043/049/050/051): id snake_case format,
## duplicate ids across files, unknown category/material_family, required-
## field presence, category<->material_family pairing, tier >= 0, and
## max_stack_size >= 1 where stackable. Every check appends a STRUCTURED
## record (see [method _make_issue]) to the result -- entry id, source
## file, violated check, offending field -- never a log string, and the
## pipeline never short-circuits on the first failure (every entry is
## checked). Reserved-id/-category rejection, the retired-ids ledger,
## tier-0 family coverage, and the >=3-violation aggregate proof are
## Story 005's scope; `visual_asset` resolution is Story 006's; the
## `missing_item` fallback is Story 007's; `footprint` category-pairing/
## presence validation is Story 008's -- none of those checks are
## implemented here.
##
## Engine note (verified via a headless load probe against this exact
## script during rid-004 implementation): [member ItemDefinitionResource.tier]
## is a statically `int`-typed [code]@export[/code] field, so Godot's
## resource deserializer silently truncates any authored non-integer value
## (e.g. `tier = 1.5`) to an `int` (`1`) BEFORE this pipeline ever inspects
## it -- there is no runtime code path by which a non-integer value can
## reach [method _validate_single_entry]. The GDD's "non-integer tier"
## boot-halt sub-case (AC23) is therefore structurally satisfied by the
## schema's type declaration itself, not by a runtime check; only the
## negative-tier sub-case is independently validated below (see
## `validation_schema_checks_test.gd` for the regression test proving the
## coercion, cited as a Deviation in this story's implementation report).
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
## exist yet; Story 005 introduces the full aggregate/terminal-halt
## contract on top of this story's structured per-entry records). Each
## element of `issues` is itself a structured [Dictionary] -- see
## [method _make_issue] -- never a log string.
signal validation_complete(result: Dictionary)

## Default directory scanned for `.tres` [ItemDefinitionResource] entries
## (ADR-0002 authoring idiom, ADR-0006 storage location).
const DEFAULT_DATA_DIR: String = "res://data/items/"

## Fixed, five-entry authorable category set (GDD Core Rule 5) checked by
## [method _validate_single_entry]'s unknown-category check. The reserved,
## non-authorable sixth category (`missing`) is deliberately EXCLUDED here --
## its rejection is Story 005's scope (TR-resource-item-database-030); an
## authored `missing` category still fails THIS check too (it is simply not
## in this whitelist), which is a harmless overlap, not a conflict.
const _KNOWN_CATEGORIES: Array[StringName] = [
	&"building_material", &"furniture_fixture", &"raw_resource", &"consumable", &"equipment"
]

## Fixed material-family set (Visual Direction Note) plus `none` for
## non-material items (GDD Core Rule 4), checked by [method
## _validate_single_entry]'s unknown-material_family check.
const _KNOWN_MATERIAL_FAMILIES: Array[StringName] = [&"wood", &"stone", &"thatch", &"none"]

## Violated-check identifiers -- the `"check"` value of a structured issue
## record (see [method _make_issue]). Exposed as constants (mirroring
## [enum BootState]'s exposure pattern) so tests reference the exact
## identifier rather than a duplicated string literal.
const CHECK_RESOURCE_LOAD_FAILED: StringName = &"resource_load_failed"
const CHECK_MISSING_REQUIRED_FIELD: StringName = &"missing_required_field"
const CHECK_INVALID_ID_FORMAT: StringName = &"invalid_id_format"
const CHECK_DUPLICATE_ID: StringName = &"duplicate_id"
const CHECK_UNKNOWN_CATEGORY: StringName = &"unknown_category"
const CHECK_UNKNOWN_MATERIAL_FAMILY: StringName = &"unknown_material_family"
const CHECK_CATEGORY_FAMILY_PAIRING: StringName = &"category_family_pairing"
const CHECK_INVALID_TIER: StringName = &"invalid_tier"
const CHECK_INVALID_MAX_STACK_SIZE: StringName = &"invalid_max_stack_size"

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


## Scans [member data_dir] for `.tres` files, loads each as an
## [ItemDefinitionResource], and runs the full per-entry + cross-entry
## schema-check pipeline (Story 004) over every entry that loaded
## successfully. Returns
## `{"success": bool, "issues": Array[Dictionary], "definitions":
## Dictionary[StringName, ItemDefinitionResource]}` -- `definitions` is
## populated ONLY when `success` is true (GDD Failed-state philosophy: never
## launch with a partially valid database, TR-resource-item-database-006 --
## a load failure OR any schema-check violation fails the WHOLE batch, not
## just the offending entry).
##
## A missing or empty [member data_dir] is NOT a failure (no entries to
## validate) -- it resolves as zero entries, `success = true`.
func _load_definitions() -> Dictionary:
	var definitions: Dictionary[StringName, ItemDefinitionResource] = {}
	var directory: DirAccess = DirAccess.open(data_dir)
	if directory == null:
		return {"success": true, "issues": [] as Array[Dictionary], "definitions": definitions}

	var file_names: Array[String] = _scan_entry_file_names(directory)
	var load_result: Dictionary = _load_entries(file_names)
	var entries: Array[Dictionary] = load_result["entries"]

	var issues: Array[Dictionary] = []
	issues.append_array(load_result["issues"] as Array[Dictionary])
	issues.append_array(_validate_entries(entries))

	if issues.is_empty():
		for entry: Dictionary in entries:
			var resource: ItemDefinitionResource = entry["resource"]
			definitions[resource.id] = resource

	return {"success": issues.is_empty(), "issues": issues, "definitions": definitions}


## Returns every `.tres` file name directly under [param directory], sorted
## for deterministic boot-load order. Extracted from the original rid-002
## scan loop so the schema-check pipeline can run over the full entry list
## (not a by-id-deduped [Dictionary]) before deciding uniqueness.
func _scan_entry_file_names(directory: DirAccess) -> Array[String]:
	var file_names: Array[String] = []
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	file_names.sort()
	return file_names


## Loads each file in [param file_names] (relative to [member data_dir]) as
## an [ItemDefinitionResource]. Returns `{"issues": Array[Dictionary],
## "entries": Array[Dictionary]}` where each `entries` element is
## `{"source_file": String, "resource": ItemDefinitionResource}`. A file
## that fails to load entirely, or loads as something other than an
## [ItemDefinitionResource], produces one structured [constant
## CHECK_RESOURCE_LOAD_FAILED] issue (ADR-0006 Risk 2's "resource failed to
## load entirely" case) and is excluded from `entries` -- it cannot be
## schema-checked since its fields are unreadable.
func _load_entries(file_names: Array[String]) -> Dictionary:
	var issues: Array[Dictionary] = []
	var entries: Array[Dictionary] = []
	for name: String in file_names:
		var path: String = data_dir.path_join(name)
		var loaded: Resource = load(path)
		if loaded == null or not (loaded is ItemDefinitionResource):
			issues.append(_make_issue(&"", path, CHECK_RESOURCE_LOAD_FAILED))
			continue
		entries.append({"source_file": path, "resource": loaded as ItemDefinitionResource})
	return {"issues": issues, "entries": entries}


## Runs the full schema-check pipeline (Story 004) over every entry in
## [param entries] -- per-entry checks first, then the cross-entry
## duplicate-id check -- accumulating every violation without
## short-circuiting on the first (GDD "Failed... naming EVERY invalid
## entry", TR-resource-item-database-005/035).
func _validate_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for entry: Dictionary in entries:
		issues.append_array(
			_validate_single_entry(entry["resource"], entry["source_file"])
		)
	issues.append_array(_check_duplicate_ids(entries))
	return issues


## Per-entry schema checks (Story 004 Implementation Notes): required-field
## presence, id snake_case format, known category/material_family,
## category<->material_family pairing, `tier >= 0`, and `max_stack_size >= 1`
## where `stackable`. Every violated check appends its own structured
## record -- an entry with multiple problems reports all of them, never
## just the first.
func _validate_single_entry(resource: ItemDefinitionResource, source_file: String) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var id: StringName = resource.id

	# --- required-field presence (GDD AC5 / TR-028) -----------------------
	# `id` missing skips the snake_case check below (nothing valid to
	# format-check) rather than double-reporting the same root cause.
	var id_present: bool = String(id) != ""
	if not id_present:
		issues.append(_make_issue(id, source_file, CHECK_MISSING_REQUIRED_FIELD, &"id"))
	elif not _is_valid_snake_case(String(id)):
		issues.append(_make_issue(id, source_file, CHECK_INVALID_ID_FORMAT, &"id"))

	if resource.display_name == "":
		issues.append(_make_issue(id, source_file, CHECK_MISSING_REQUIRED_FIELD, &"display_name"))

	if String(resource.category) == "":
		issues.append(_make_issue(id, source_file, CHECK_MISSING_REQUIRED_FIELD, &"category"))
	elif not _KNOWN_CATEGORIES.has(resource.category):
		issues.append(_make_issue(id, source_file, CHECK_UNKNOWN_CATEGORY, &"category"))

	if String(resource.storage_category) == "":
		issues.append(_make_issue(id, source_file, CHECK_MISSING_REQUIRED_FIELD, &"storage_category"))

	# --- known material_family enum (GDD AC4b / TR-041) ---------------------
	if not _KNOWN_MATERIAL_FAMILIES.has(resource.material_family):
		issues.append(_make_issue(id, source_file, CHECK_UNKNOWN_MATERIAL_FAMILY, &"material_family"))

	# --- category<->material_family pairing (GDD AC24 / TR-051) -------------
	# building_material requires a real family (not `none`, not empty);
	# every other category requires exactly `none`.
	if resource.category == &"building_material":
		if resource.material_family == &"none" or String(resource.material_family) == "":
			issues.append(_make_issue(id, source_file, CHECK_CATEGORY_FAMILY_PAIRING, &"material_family"))
	elif resource.material_family != &"none":
		issues.append(_make_issue(id, source_file, CHECK_CATEGORY_FAMILY_PAIRING, &"material_family"))

	# --- tier >= 0 (GDD AC23 / TR-050) --------------------------------------
	# See this script's class doc comment: a non-integer authored value is
	# structurally impossible to observe here -- Godot's resource loader
	# coerces it to `int` before this pipeline ever runs -- so only the
	# negative-value sub-case is a reachable runtime check.
	if resource.tier < 0:
		issues.append(_make_issue(id, source_file, CHECK_INVALID_TIER, &"tier"))

	# --- max_stack_size >= 1 where stackable (GDD AC20/AC21 / TR-049/043) --
	# A non-stackable entry with max_stack_size authored is intentionally
	# NOT checked at all here -- ignored silently, per Edge Case 7.
	if resource.stackable and resource.max_stack_size < 1:
		issues.append(_make_issue(id, source_file, CHECK_INVALID_MAX_STACK_SIZE, &"max_stack_size"))

	return issues


## Cross-entry check: two (or more) entries sharing the same [member
## ItemDefinitionResource.id] across different source files (GDD Edge
## Case 4 / AC3, TR-resource-item-database-040). Emits one structured
## record PER duplicated file -- every record shares the same `entry_id`
## but names a different `source_file`, so the aggregated result names
## both entries AND both source files without a combined-list field shape.
## Entries with a missing (empty) id are excluded -- already reported by
## [method _validate_single_entry]'s required-field check, and grouping
## them here would misreport unrelated missing-id entries as "duplicates"
## of each other.
func _check_duplicate_ids(entries: Array[Dictionary]) -> Array[Dictionary]:
	var files_by_id: Dictionary[StringName, Array] = {}
	for entry: Dictionary in entries:
		var resource: ItemDefinitionResource = entry["resource"]
		if String(resource.id) == "":
			continue
		if not files_by_id.has(resource.id):
			files_by_id[resource.id] = []
		(files_by_id[resource.id] as Array).append(entry["source_file"])

	var issues: Array[Dictionary] = []
	for id: StringName in files_by_id:
		var files: Array = files_by_id[id]
		if files.size() > 1:
			for source_file: String in files:
				issues.append(_make_issue(id, source_file, CHECK_DUPLICATE_ID, &"id"))
	return issues


## Builds one structured validation-result record (design/gdd/resource-
## item-database.md's Validation-result contract: "a list of records, each
## carrying at least the entry id, source file, violated check, and
## offending field where applicable" -- TR-resource-item-database-007).
## [param field] defaults to an empty [StringName] for checks with no single
## offending field (currently unused by any Story 004 check, since every
## check below names exactly one field).
static func _make_issue(
	entry_id: StringName, source_file: String, check: StringName, field: StringName = &""
) -> Dictionary:
	return {
		"entry_id": entry_id,
		"source_file": source_file,
		"check": check,
		"field": field,
	}


## Returns whether [param value] is valid `snake_case`: non-empty, entirely
## lowercase, and containing neither spaces nor hyphens (GDD AC6 / TR-024,
## sub-cases 6a uppercase / 6b spaces / 6c hyphens).
static func _is_valid_snake_case(value: String) -> bool:
	if value.is_empty():
		return false
	if value != value.to_lower():
		return false
	if value.contains(" ") or value.contains("-"):
		return false
	return true
