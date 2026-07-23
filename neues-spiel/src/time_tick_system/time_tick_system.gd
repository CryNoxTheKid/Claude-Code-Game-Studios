## Time & Tick System Autoload skeleton (ADR-0001 Autoload tier + ADR-0002
## config loading) -- story tick-001 scope only: config-driven tunables and
## boot defaults. The game_delta formula (tick-002), pause/warp toggle
## behaviour (tick-003), and the tick accumulator/signal (tick-004) are
## implemented in their own stories and are deliberately NOT present here.
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


func _ready() -> void:
	setup()


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
