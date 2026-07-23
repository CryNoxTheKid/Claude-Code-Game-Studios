## Time & Tick System Autoload (ADR-0001 Autoload tier + ADR-0002 config
## loading). Story tick-001 landed the config-driven tunables and boot
## defaults; story tick-002 (this story) adds the `game_delta` formula --
## computed once per physics frame in [method _physics_process] and exposed
## read-only via [method get_game_delta]. Pause/warp TOGGLE behaviour
## (tick-003 -- the API to CHANGE [member paused]/[member time_warp]) and the
## tick accumulator/signal (tick-004) are implemented in their own stories
## and are deliberately NOT present here; this story only READS the two
## fields, it does not add any way to mutate them beyond what tick-001 (boot
## defaults) already set.
##
## Registered as one of the project's only two genuinely-global Foundation
## Autoloads alongside ResourceItemDatabase (ADR-0001) -- called by its
## global singleton name directly in method bodies everywhere
## (`TimeTickSystem.get_game_delta()` once tick-002 lands), never
## `@export`-injected into any module. `_ready()` runs before the Main Scene
## loads (declared Autoload order, synchronous) and does nothing beyond
## calling [method setup] -- all wiring/validation logic lives there so the
## identical code path runs when a headless test constructs this script
## directly and calls [method setup] without ever entering the SceneTree.
##
## Deliberately carries NO `class_name` (engine constraint discovered during
## tick-001 implementation): Godot 4.7 hard-errors "Class 'TimeTickSystem'
## hides an autoload singleton" if a script both declares `class_name
## TimeTickSystem` AND is registered as the Autoload singleton named
## "TimeTickSystem" -- the Autoload's own global name already provides the
## only reference path this ADR-0001 tier ever uses (nothing holds a typed
## `@export` reference to an Autoload; that is Forbidden). Callers duck-type
## via the registered singleton name, exactly like [GameWorld]'s existing
## `resource_item_database` duck-typed dependency.
extends Node

## Path to this Autoload's own config Resource (ADR-0002 Autoload-tier
## loading: `const CONFIG_PATH` + `load()` inside [method setup] -- no
## injected `@export` wiring layer, unlike Core/Feature/Presentation
## modules).
const CONFIG_PATH: String = "res://data/config/time_tick_config.tres"

## Tuning-config dependency (ADR-0002). Production leaves this null and
## [method setup] `load()`s it from [constant CONFIG_PATH]; a headless test
## may assign a constructed [TimeTickConfig] directly before calling
## [method setup], which then leaves the pre-assigned instance untouched.
var config: TimeTickConfig

## Player-toggleable pause state (GDD Edge Case "Game boot"). Defaults to
## `false` per TR-time-tick-system-038; re-affirmed explicitly in [method
## setup] rather than relying solely on the field initializer.
var paused: bool = false

## Player-selected time-warp speed, one of [member TimeTickConfig.
## time_warp_options] (GDD Core Rule 2). Defaults to `1` per
## TR-time-tick-system-038; re-affirmed explicitly in [method setup].
var time_warp: int = 1

## Owned runtime state (ADR-0002: never a config field -- this is Time &
## Tick System's own derived value, recomputed every physics frame, not a
## tuning knob). Most recently computed game delta-time (GDD Formulas:
## `game_delta = clamp(raw_delta, 0, max_raw_delta) * time_warp * (paused ?
## 0 : 1)`), exposed read-only to every other system via [method
## get_game_delta] (TR-time-tick-system-022 -- simulation-tier consumers
## query this, never raw engine delta). Starts at `0.0` before the first
## physics frame runs.
var _game_delta: float = 0.0


func _ready() -> void:
	setup()


## Computes this frame's `game_delta` (GDD Formulas) from the engine's own
## raw physics-frame [param delta] via [method compute_game_delta], and
## stores the result in [member _game_delta] for [method get_game_delta] to
## return. Runs in `_physics_process` (fixed step, per the GDD Formulas
## section and this story's Engine Notes), never `_process` -- so simulation
## timing stays frame-rate-independent. [param delta] is only READ here,
## never written back to -- every other system's own raw `_process`/
## `_physics_process` delta remains completely unmodified and available as
## normal (TR-time-tick-system-026).
func _physics_process(delta: float) -> void:
	_game_delta = compute_game_delta(delta)


## Explicitly callable wiring/validation entry point -- the Autoload-tier
## equivalent of ADR-0001's injected-tier `setup()` convention. Loads
## [member config] from [constant CONFIG_PATH] if not already assigned (test
## override), calls `config.validate()` exactly once (ADR-0002 -- single-field
## range issues warn via `push_warning` and clamp in place; this config
## carries no BLOCKING cross-value invariant, so boot always proceeds), then
## sets the GDD-mandated boot defaults for [member paused] and
## [member time_warp].
func setup() -> void:
	if config == null:
		config = load(CONFIG_PATH) as TimeTickConfig
	assert(config != null, "TimeTickSystem.config could not be loaded from %s" % CONFIG_PATH)
	var issues: Array[String] = config.validate()
	for issue: String in issues:
		push_warning(issue)
	paused = false
	time_warp = 1


## Pure formula (GDD Formulas, canonical form -- REVISED 2026-07-10 review:
## the clamp is the authoritative statement, not just an Edge Case note).
## Clamps [param raw_delta] to `[0, config.max_raw_delta]` BEFORE any other
## use (TR-time-tick-system-031), then applies the [member time_warp]
## multiplier and the [member paused] factor (TR-time-tick-system-021).
## Deterministic and side-effect-free -- reads only [member config],
## [member time_warp], and [member paused]; writes nothing -- callable
## directly with fixed inputs in a test, no physics frame or scene tree
## required.
func compute_game_delta(raw_delta: float) -> float:
	var clamped_delta: float = clampf(raw_delta, 0.0, config.max_raw_delta)
	var pause_factor: float = 0.0 if paused else 1.0
	return clamped_delta * float(time_warp) * pause_factor


## Public query surface for [member _game_delta] (TR-time-tick-system-022 --
## every simulation-tier consumer queries THIS, never raw engine delta).
## Read-only: there is no setter, matching ADR-0002's "config/derived state
## is read-only from every consumer's perspective" discipline, extended here
## to this system's own owned runtime state as well.
func get_game_delta() -> float:
	return _game_delta
