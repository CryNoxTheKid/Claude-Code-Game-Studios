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


## F1 -- need decay (GDD Formulas). Story 002's scope; a documented no-op
## here that only records its own name in [member _last_tick_pass_order].
func _pass_f1_decay() -> void:
	_last_tick_pass_order.append(&"f1_decay")


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
