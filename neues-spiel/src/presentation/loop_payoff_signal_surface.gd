## Loop-payoff communication signal surface (Presentation Experience epic,
## story presentation-002; ADR-0001 primary).
##
## Scaffolding-only event/signal surface representing core-loop "payoff"
## moments (a project completes, a villager's satisfied-state changes, ...).
## This module is deliberately thin: it defines and re-emits a single,
## stable, keyed signal shape. It contains NO payoff mechanic of any kind
## (no simulation formulas, no reward-feedback presentation, no UI) -- that
## is the Feature-layer mechanic's job, plugged into this exact surface
## later without the surface needing to change shape (milestone-01 exit
## criterion #10's scaffolding-vs-mechanic split).
##
## Injected-tier per ADR-0001: headless-mockable via [method setup], wired
## into whichever owning scene needs it once real emitters/consumers exist.
## This module currently has no upstream [code]@export[/code] dependencies
## of its own -- it IS the shared dependency later systems bind to -- but
## still exposes the same explicitly-callable [method setup] entry point so
## GameWorld's uniform injected-tier wiring loop applies to it identically
## to every other module, in production and in headless tests alike.
class_name LoopPayoffSignalSurface
extends Node

## Emitted for every core-loop payoff moment. [param payoff_type] identifies
## the KIND of payoff (e.g. [code]&"project_completed"[/code],
## [code]&"villager_satisfied"[/code]); [param subject] identifies the
## specific instance it happened to (a project id, a villager id, ...).
## This is the SOLE signal shape for every payoff moment the Feature-layer
## mechanic will ever fire -- a new payoff kind is a new [param payoff_type]
## value, never a new signal or a reshaped parameter list.
signal payoff_signaled(payoff_type: StringName, subject: StringName)

## True once [method setup] has completed at least once.
var _is_set_up: bool = false

## Keyed by "[param payoff_type]:[param subject]" -> true. Tracks which
## payoff keys are currently live so re-emission of the SAME key is a
## refresh-in-place, never a second/duplicate entry -- the idempotent,
## level-triggered-safe discipline this story's AC-3 requires, mirroring the
## toast/anchor "keyed by (signal type, subject); re-emission of a live key
## refreshes in place" discipline already established
## (design/ux/interaction-patterns.md).
var _active_payoffs: Dictionary[String, bool] = {}


## Explicitly-callable wiring entry point (ADR-0001). This module has no
## dependencies to assert -- the call exists purely so the uniform
## injected-tier wiring loop treats every module identically. Never called
## from [method _ready].
func setup() -> void:
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Signals a loop-payoff moment for ([param payoff_type], [param subject]).
## Called by the real emitters (Building System project-completion,
## Villager AI contentment changes -- both out of scope for this story,
## stood in for by test stubs) and, in production, ultimately observed by
## the Feature-layer mechanic (also out of scope here).
##
## Re-invoking with the same ([param payoff_type], [param subject]) pair
## does not grow or duplicate any internal state -- the key is simply marked
## (still) live -- and the signal still re-emits so bound consumers can
## refresh their own presentation in place, never treating it as a fresh
## occurrence requiring new state.
func emit_payoff(payoff_type: StringName, subject: StringName) -> void:
	_active_payoffs[_make_key(payoff_type, subject)] = true
	payoff_signaled.emit(payoff_type, subject)


## Returns whether ([param payoff_type], [param subject]) is currently a
## live (most-recently-signaled, not yet cleared) payoff key.
func is_payoff_active(payoff_type: StringName, subject: StringName) -> bool:
	return _active_payoffs.get(_make_key(payoff_type, subject), false)


## Clears a payoff key's live state (e.g. once a consumer's presentation of
## it has fully resolved). Provided for the later Feature-layer consumer's
## convenience -- not exercised by this scaffolding story itself.
func clear_payoff(payoff_type: StringName, subject: StringName) -> void:
	_active_payoffs.erase(_make_key(payoff_type, subject))


## Returns the number of currently-live payoff keys. Test-facing: proves
## re-emitting the same key never grows this count (AC-3 idempotency).
func get_active_payoff_count() -> int:
	return _active_payoffs.size()


func _make_key(payoff_type: StringName, subject: StringName) -> String:
	return "%s:%s" % [payoff_type, subject]
