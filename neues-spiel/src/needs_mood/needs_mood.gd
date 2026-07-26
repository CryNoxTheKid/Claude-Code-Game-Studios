## Needs & Mood System module scaffold (Story needs-mood-001, ADR-0002
## primary config; ADR-0001 injected-tier DI; ADR-0005 boot gate). This
## story's scope is EXACTLY the config resource + DI scaffold + the fixed
## need schema + the AC29 BLOCKING ladder invariant + the tick-subscription
## skeleton -- no F1 decay state machine, no F2 recovery-report API/source
## table, no F3 mood math (those are stories 002/003/005).
##
## Per TD ruling NM-3 (`production/architecture-decisions-m02-preflight-
## 2026-07-26.md`), Core Rule 4's THREE-rung recovery ladder is
## authoritative -- the GDD's own F2 variable-table row (a stale
## two-multiplier form) is a known doc-hygiene defect and is never
## implemented anywhere in this module or a future story.
##
## Story needs-mood-002 (this revision) fills in [method _pass_f1_decay]
## for real: F1 decay, the per-need queryable state machine (Satisfied ->
## Urgent; [enum NeedState.RECOVERING] is wired as an enum value only,
## story 003's `start_recovery` report is the sole way to ever enter it),
## the edge-triggered [signal need_urgent] notification, and the
## Villager-AI-facing query surface -- [method has_urgent_need] (TD ruling
## NM-6, a REQUIRED pure query, matched verbatim to
## `villager_ai.gd`'s `needs_provider.has_urgent_need` seam),
## [method get_need_value], and [method get_need_state]. [method
## set_need_value] is this story's own initialization/test seam (NOT the
## GDD's F4 spawn-init feature, which remains unowned -- see that method's
## own doc comment). F2 recovery ([method _pass_f2_recovery]) and F3 mood
## smoothing ([method _pass_f3_mood]) remain untouched no-op stubs --
## stories 003/005's scope.
##
## Tick dispatch is driven EXCLUSIVELY by [member time_tick_system]'s `tick`
## signal (GDD: "all decay/recovery/mood math runs on Time & Tick events",
## TR-needs-mood-system-051), connected with Godot's plain synchronous
## default (never `CONNECT_DEFERRED`) -- load-bearing for story 003's
## intra-tick start/stop-before-F-pass ordering rule (GDD Core Rule 10).
## [method _on_tick] is the strict F1 -> F2 -> F3 skeleton this story lands;
## each pass is a documented no-op stub until its owning story (002/003/005)
## fills in the real body -- this story's own AC requires only that the
## entry point fires exactly once per tick, in that fixed order.
class_name NeedsMood
extends Node

## Fixed need schema (GDD Core Rule 2, TR-needs-mood-system-031): known from
## day one, same pattern as the item database's category set. Adding a need
## type is a design/code change, never a data edit -- this enum is
## deliberately NOT a config `@export` field.
enum Need { SLEEP, FOOD, COMPANY }

## The active-set subset of [enum Need] that actually carries values in MVP
## (GDD Core Rule 2: "MVP fills only sleep"). `mean_active` (story 005)
## iterates exactly this set -- an inactive need (FOOD/COMPANY) is never
## defaulted into any computation.
const ACTIVE_NEEDS: Array[Need] = [Need.SLEEP]

## Per-need queryable state (GDD "States and Transitions" table,
## TR-needs-mood-system-032/048). [constant RECOVERING] is wired by story
## needs-mood-003's `start_recovery` report -- this story's own state
## machine only ever transitions Satisfied <-> Urgent; the enum value
## exists now (not added later) so story 003 introduces no enum migration,
## matching this file's own F1/F2/F3 stub-now-fill-later precedent.
enum NeedState { SATISFIED, URGENT, RECOVERING }

## One flat record per (villager_id, need) pair actually tracked -- created
## ONLY by [method set_need_value] (never as a side effect of a query, see
## [method has_urgent_need]'s own doc comment, NM-6). Keyed by a composite
## string (see [method _record_key]) rather than a nested
## `Dictionary[int, Dictionary[Need, NeedRecord]]` -- deliberately flat to
## avoid nested typed-Dictionary/Array surface area entirely; a single
## `Dictionary[String, NeedRecord]` keeps every lookup/iteration statically
## typed with zero unsafe casts.
class NeedRecord:
	extends RefCounted

	## Denormalized alongside the composite key so [method _pass_f1_decay]'s
	## iteration (which walks every tracked record, not a per-villager
	## sub-map) can still emit [signal need_urgent] with the right
	## `villager_id`/need name without parsing the key back apart.
	var villager_id: int = 0
	var need: Need = Need.SLEEP
	## Current need value, 0-100 (GDD F1). Only ever written by [method
	## set_need_value] (initialization/test seam) and [method
	## _pass_f1_decay] (per-tick decay) in this story's own scope --
	## story 003 adds the F2 recovery writer.
	var value: float = 100.0
	## Queryable per-need state (GDD States and Transitions table). Only
	## ever SATISFIED or URGENT in this story's own scope (see [enum
	## NeedState]'s own doc comment).
	var state: NeedState = NeedState.SATISFIED


## Need-enum <-> the external `StringName` need id every public query/report
## method in `docs/architecture/architecture.md`'s API Boundaries block
## actually uses (`get_need_value(villager_id, need: StringName)`,
## `start_recovery(villager_id, need: StringName, ...)`, etc.) -- [enum Need]
## itself stays an internal implementation detail, never exposed across the
## module boundary directly.
const NEED_NAMES: Dictionary[Need, StringName] = {
	Need.SLEEP: &"sleep",
	Need.FOOD: &"food",
	Need.COMPANY: &"company",
}

## The reverse of [constant NEED_NAMES] -- resolves an external caller's
## `StringName` need id back to the internal [enum Need] value. An
## unrecognized name is handled by every caller via `.has()` (never a
## sentinel int smuggled through a typed enum-valued lookup) -- see
## [method get_need_value]/[method get_need_state]/[method set_need_value].
const NEED_NAME_TO_ENUM: Dictionary[StringName, Need] = {
	&"sleep": Need.SLEEP,
	&"food": Need.FOOD,
	&"company": Need.COMPANY,
}

## Edge-triggered "need is urgent" notification (GDD Core Rule 3,
## TR-needs-mood-system-033) -- a LATENCY HINT layered on top of the
## queryable state [method get_need_state]/[method has_urgent_need] already
## expose; fires exactly once per downward `urgency_threshold` cross, per
## (villager_id, need) -- never on equality, never a repeat while parked at
## or below the threshold (Edge Cases 2/4). A dropped connection must be
## harmless (ADR-0008: Villager AI polls state, never trusts this alone).
signal need_urgent(villager_id: int, need: StringName)

## Tuning config (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Asserted wired by
## [method setup] -- never read inside `_ready()`.
@export var config: NeedsMoodConfig

## Time & Tick System dependency (ADR-0001). Deliberately NOT `@export`ed --
## `TimeTickSystem` is Autoload-tier and per ADR-0001 is never injected via
## the Inspector. Duck-typed against the one member [method setup] needs:
## `signal tick()`. Mirrors [VillagerAi.time_tick_system]'s and
## [ConstructionTickLoop.time_tick_system]'s established precedent exactly:
## a headless test assigns a mock double directly before calling
## [method setup]; production resolves the real Autoload lazily.
var time_tick_system: Object = null

## Per-(villager_id, need) simulation state (GDD F1 + States/Transitions
## table). See [NeedRecord]'s own doc comment for the flat composite-key
## design rationale. A record is created ONLY by [method set_need_value] --
## every query method ([method has_urgent_need], [method get_need_value],
## [method get_need_state]) reads with `.get(key, null)` and never inserts
## (NM-6's "no lazy record init" guarantee, extended here to the sibling
## queries for the same consistency reason even though NM-6 only strictly
## requires it of has_urgent_need).
var _need_records: Dictionary[String, NeedRecord] = {}

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## The BLOCKING-tagged subset of the most recent `config.validate()` result,
## if any. Populated by [method setup]; read by [GameWorld]'s boot gate via
## [method get_boot_blocking_issues] (ADR-0002/0005).
var _boot_blocking_issues: Array[String] = []

## Number of times [method _on_tick] has run. Test-observability only --
## proves "the F-pass entry point runs exactly once" per tick dispatch, this
## story's own AC.
var _tick_pass_count: int = 0

## The pass names [method _on_tick] ran, in the order it ran them, reset at
## the start of every call. Test-observability only -- proves the strict
## F1 -> F2 -> F3 call order this story's AC requires.
var _last_tick_pass_order: Array[StringName] = []


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config] and a [member time_tick_system]-shaped dependency are
## wired, applies ADR-0002's two-tier `validate()` policy exactly like
## [BuildValidation]/[ReferenceConfigConsumer], then connects this module's
## tick dispatch to the sole global tick broadcast (`TimeTickSystem.tick`,
## plain synchronous default connection -- never `CONNECT_DEFERRED`).
func setup() -> void:
	assert(config != null, "NeedsMood.config not wired")
	if time_tick_system == null:
		time_tick_system = get_node_or_null(^"/root/TimeTickSystem")
	assert(
		time_tick_system != null,
		"NeedsMood requires a TimeTickSystem-shaped dependency (assign a mock in"
		+ " tests; the real Autoload is registered project-wide) before setup() can"
		+ " connect tick dispatch"
	)
	var issues: Array[String] = config.validate()
	_boot_blocking_issues = issues.filter(
		func(issue: String) -> bool: return issue.begins_with(ConfigResource.BLOCKING_PREFIX)
	)
	for issue: String in issues:
		if not issue.begins_with(ConfigResource.BLOCKING_PREFIX):
			push_warning(issue)
	@warning_ignore("unsafe_property_access")
	time_tick_system.tick.connect(_on_tick)
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the BLOCKING-tagged issues (if any) found in the most recent
## `config.validate()` call. [GameWorld]'s boot gate duck-types this method
## on every injected-tier module after calling `setup()` (ADR-0002 Decision,
## ADR-0005 reuse) -- a non-empty result triggers the same terminal boot-halt
## path used for RID's Failed outcome, no new severity model, no new halt
## mechanism. Under a violated ladder invariant (AC29), this is the
## mechanism by which the module "does not proceed to normal operation":
## [GameWorld] halts before reaching ACTIVE, so no production tick is ever
## dispatched into this module.
func get_boot_blocking_issues() -> Array[String]:
	return _boot_blocking_issues


## Number of times [method _on_tick] has fired since [method setup]. Test
## observability only -- not part of any other module's contract.
func get_tick_pass_count() -> int:
	return _tick_pass_count


## The most recent tick's pass order (see [member _last_tick_pass_order]).
## Test observability only.
func get_last_tick_pass_order() -> Array[StringName]:
	return _last_tick_pass_order


## Story needs-mood-002, TD ruling NM-6 (`production/architecture-
## decisions-m02-preflight-2026-07-26.md`; canonized into
## `docs/architecture/architecture.md`'s Needs & Mood API Boundaries block).
## Returns whether ANY of [constant ACTIVE_NEEDS] currently reads
## [constant NeedState.URGENT] for `villager_id` -- the queryable state,
## never a cached event (Core Rule 3). This is [VillagerAi]'s tier-1
## priority gate (`villager_ai.gd`'s `needs_provider.has_urgent_need`,
## `_has_urgent_need()`), matched here verbatim in name and arity.
##
## GUARANTEE (NM-6, asserted by this story's own test suite, not merely
## documented): emits no signal, mutates no state, and never lazily
## initializes a villager's need record as a side effect of being asked. An
## unknown/despawned `villager_id` -- one with no tracked record at all --
## returns `false` WITHOUT creating one; nil-safety for an unwired provider
## belongs to the CALLER ([method VillagerAi._has_urgent_need]'s existing
## guard), never to a null-provider branch here.
func has_urgent_need(villager_id: int) -> bool:
	for need_enum: Need in ACTIVE_NEEDS:
		var need_name: StringName = NEED_NAMES.get(need_enum, &"")
		var key: String = _record_key(villager_id, need_name)
		if _need_records.has(key) and _need_records[key].state == NeedState.URGENT:
			return true
	return false


## `docs/architecture/architecture.md` API Boundaries:
## `get_need_value(villager_id: int, need: StringName) -> float`. Read-only;
## never creates a record for an untracked villager or an unrecognized need
## name -- both answer the same safe, non-urgent default (100.0, "fully
## satisfied") a fresh spawn would start at (GDD F4), consistent with
## [method has_urgent_need]'s own "unknown answers as if fine, never
## crashes" bias.
func get_need_value(villager_id: int, need: StringName) -> float:
	if not NEED_NAME_TO_ENUM.has(need):
		return 100.0
	var key: String = _record_key(villager_id, need)
	if not _need_records.has(key):
		return 100.0
	return _need_records[key].value


## The "per-need state query" this story's own AC list requires alongside
## [method get_need_value] (not yet named in `architecture.md`'s API
## Boundaries block -- the GDD's own query-API section/TR is a non-blocking
## follow-up per NM-6). Same unknown-id/unknown-need default bias as
## [method get_need_value]: [constant NeedState.SATISFIED], never an error.
func get_need_state(villager_id: int, need: StringName) -> NeedState:
	if not NEED_NAME_TO_ENUM.has(need):
		return NeedState.SATISFIED
	var key: String = _record_key(villager_id, need)
	if not _need_records.has(key):
		return NeedState.SATISFIED
	return _need_records[key].state


## Initialization/test seam -- the ONE entry point that creates a
## (villager_id, need) record (see [member _need_records]'s own doc
## comment). Deliberately NOT this story's F4 spawn-initialization feature
## (TR-needs-mood-system-056 is out of this story's TR list) -- a future
## spawn story calls this once per active need at 100.0, exactly like this
## story's own tests do to arrange a "Given value = ..." precondition.
## Clamps to the declared 0-100 domain and derives [enum NeedState] purely
## from the clamped value against [member NeedsMoodConfig.urgency_threshold]
## (`Satisfied` if strictly above, `Urgent` otherwise, per the GDD's own
## State table) -- this is initialization, never a "cross" (Edge Case 4's
## "crossing, not equality" applies to TICKS; assigning a value out of band
## is not a tick and never emits [signal need_urgent], regardless of which
## side of the threshold the new value lands on.
func set_need_value(villager_id: int, need: StringName, value: float) -> void:
	if not NEED_NAME_TO_ENUM.has(need):
		return
	var need_enum: Need = NEED_NAME_TO_ENUM[need]
	var key: String = _record_key(villager_id, need)
	if not _need_records.has(key):
		var new_record := NeedRecord.new()
		new_record.villager_id = villager_id
		new_record.need = need_enum
		_need_records[key] = new_record
	var record: NeedRecord = _need_records[key]
	record.value = clampf(value, 0.0, 100.0)
	record.state = NeedState.SATISFIED if record.value > config.urgency_threshold else NeedState.URGENT


## Composite storage key for [member _need_records] (see [NeedRecord]'s own
## doc comment for why this is flat rather than nested).
static func _record_key(villager_id: int, need: StringName) -> String:
	return "%d:%s" % [villager_id, need]


## F1's per-need decay rate lookup (GDD Core Rule 1: "decay_per_tick
## [need]"). Only [constant Need.SLEEP] has a real configured rate this
## story's own TR scope covers (Core Rule 2: "MVP fills only sleep with
## values") -- FOOD/COMPANY answer 0.0 (inert, never decays) until their own
## future story adds a knob; this is honest MVP behavior, not a stub
## shortcut, since a record for either can only exist at all via [method
## set_need_value] (no production caller does that yet).
func _decay_rate_for_need(need: Need) -> float:
	match need:
		Need.SLEEP:
			return config.decay_per_tick_sleep
		_:
			return 0.0


## F1 -- need decay (GDD Formulas: `value <- max(0, value -
## decay_per_tick[need])`, TR-needs-mood-system-030), plus the
## edge-triggered `urgency_threshold` downward-cross detection layered on
## top (GDD Core Rule 3, TR-needs-mood-system-033). Story needs-mood-002's
## own scope -- F2 recovery ([method _pass_f2_recovery]) and F3 mood
## smoothing ([method _pass_f3_mood]) remain story 003/005 stubs, untouched
## here.
##
## Crossing compares the PRE-tick value vs the POST-tick value against
## [member NeedsMoodConfig.urgency_threshold] (`>` then `<=`, never `==`) --
## Edge Case 4's "a value parked at 25.0 emits nothing new" falls out of
## this comparison directly: once `state == URGENT`, `previous_value` can
## never again read `> threshold` without a recovery report ([constant
## NeedState.RECOVERING], story 003's scope, never entered anywhere in this
## story's own code -- AC12's own negative-space proof), so no repeat
## emission is possible by construction, not by a separate dedup check.
## Skips any record already `RECOVERING` (F1's own "except while Recovering"
## clause) -- always true today since nothing sets that state yet, but
## written now so story 003 needs no edit here.
func _pass_f1_decay() -> void:
	_last_tick_pass_order.append(&"f1_decay")
	for key: String in _need_records.keys():
		var record: NeedRecord = _need_records[key]
		if record.state == NeedState.RECOVERING:
			continue
		var previous_value: float = record.value
		var rate: float = _decay_rate_for_need(record.need)
		record.value = maxf(0.0, previous_value - rate)
		if previous_value > config.urgency_threshold and record.value <= config.urgency_threshold:
			record.state = NeedState.URGENT
			need_urgent.emit(record.villager_id, NEED_NAMES.get(record.need, &""))


## F2 -- need recovery via the source-rate table (GDD Formulas). Story 003's
## scope; a documented no-op here that only records its own name in
## [member _last_tick_pass_order].
func _pass_f2_recovery() -> void:
	_last_tick_pass_order.append(&"f2_recovery")


## F3 -- mood smoothing (GDD Formulas). Story 005's scope; a documented
## no-op here that only records its own name in
## [member _last_tick_pass_order].
func _pass_f3_mood() -> void:
	_last_tick_pass_order.append(&"f3_mood")


## The sole tick-dispatch entry point (GDD: "all decay/recovery/mood math
## runs on Time & Tick events"). Runs the strict F1 -> F2 -> F3 pass order
## exactly once per broadcast tick -- this story's scope is the skeleton
## only; see [method _pass_f1_decay]/[method _pass_f2_recovery]/
## [method _pass_f3_mood]'s own doc comments.
func _on_tick() -> void:
	_tick_pass_count += 1
	_last_tick_pass_order = []
	_pass_f1_decay()
	_pass_f2_recovery()
	_pass_f3_mood()
