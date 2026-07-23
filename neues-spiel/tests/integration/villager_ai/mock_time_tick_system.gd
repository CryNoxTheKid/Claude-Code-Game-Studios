## Minimal Time & Tick System-shaped test double (mirrors
## `MockResourceItemDatabase`'s established precedent under
## `tests/unit/foundation/`).
##
## Implements exactly the one member [VillagerAi.setup] depends on: `signal
## tick()`. Lives under tests/ only -- the real `TimeTickSystem` Autoload
## (`src/time_tick_system/time_tick_system.gd`) is a separate epic's
## singleton; this double never claims to BE it, only to duck-type the
## single signal a tick-driven consumer needs, letting a test fire ticks
## deterministically without depending on real `_physics_process` frames or
## the shared registered Autoload's mutable state.
class_name MockTimeTickSystem
extends Node

## Fires exactly when this double's [method fire_tick] is called -- a
## manually-driven stand-in for the real Autoload's drift-free accumulator
## broadcast.
signal tick()


## Manually fires [signal tick] once, simulating one drift-free tick-boundary
## crossing (GDD Formulas) without needing any real physics frame.
func fire_tick() -> void:
	tick.emit()
