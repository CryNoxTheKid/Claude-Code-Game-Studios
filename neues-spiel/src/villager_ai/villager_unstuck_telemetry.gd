## Unstuck-rescue telemetry accumulator (Story villager-ai-015, GDD Rule 15/F5:
## "a `villager_unstuck` event fires, incrementing a per-villager counter and
## a world total counter, exposed to the F3 debug console now and reserved
## for future production analytics"; Control Manifest Feature Layer
## Guardrail: "`villager_unstuck` per-villager + world total counters exposed
## to F3 debug (hard requirement, sizing input for production
## build-order/scaffolding work)").
##
## A REAL, fully-owned-by-this-story concrete class -- unlike [VillagerAi]'s
## other mocked-boundary Object dependencies ([member VillagerAi.
## needs_provider]/[member VillagerAi.job_queue], which stand in for
## NOT-YET-BUILT external systems), this telemetry surface belongs entirely
## to Villager AI and has nothing external to duck-type against.
##
## Deliberately a plain [RefCounted] (no Inspector authoring need, no
## scene-tree presence needed), constructed ONCE and shared across the whole
## villager population -- mirrors [VillagerDecidingScheduler]/
## [VillagerNavGraph]'s own established "one shared instance, not duplicated
## per villager" precedent (see either class's own doc comment for the full
## rationale this one repeats): the world-total half of this class's own job
## is meaningless if each villager held its own separate copy. NOT a
## static/class-level singleton either, for the identical test-isolation
## reason those two classes already document -- whichever code assembles a
## population constructs exactly one instance and assigns it to every
## [VillagerAi.unstuck_telemetry] field in that population, explicit
## dependency injection (ADR-0001's pattern), never a hidden global.
##
## The F3 debug console itself (the actual on-screen rendering of these
## counters) is a separate, not-yet-built dev tool this GDD explicitly calls
## out as having "no dedicated GDD" -- this class supplies only the data
## surface ([method get_world_total]/[method get_villager_count]) a future
## console reads; it renders nothing itself.
class_name VillagerUnstuckTelemetry
extends RefCounted

## World-total rescue count across every villager sharing this instance (GDD
## Rule 15's "a world total counter"). Read via [method get_world_total] --
## never mutated directly by an outside consumer.
var _world_total: int = 0

## Per-villager rescue counts (GDD Rule 15's "a per-villager counter"), keyed
## by `villager_id`. A villager id absent from this map has never been
## rescued -- [method get_villager_count] reports `0` for it, not an error.
var _per_villager_counts: Dictionary[int, int] = {}


## Records exactly one rescue for [param villager_id] -- increments BOTH the
## world total and that villager's own count atomically (a single synchronous
## call, no partial-update state ever observable). Called exactly once per
## actual rescue by [method VillagerAi._perform_watchdog_rescue] -- never
## called for a deferred/failed search (that path never reaches this
## method at all, see [VillagerAi._attempt_watchdog_rescue]'s own doc
## comment).
func record_rescue(villager_id: int) -> void:
	_world_total += 1
	_per_villager_counts[villager_id] = _per_villager_counts.get(villager_id, 0) + 1


## The world-total rescue count across every villager sharing this instance.
func get_world_total() -> int:
	return _world_total


## [param villager_id]'s own rescue count -- `0` if that villager has never
## been rescued (absent from [member _per_villager_counts]), never an error.
func get_villager_count(villager_id: int) -> int:
	return _per_villager_counts.get(villager_id, 0)
