## Unit test — Time & Tick System Story tick-005 (max-ticks-per-frame safety
## cap; ADR-0002 governing).
##
## Proves: (1) the GDD Formulas worked example, bit-for-bit -- an alt-tab
## stall banks the accumulator to 12.3s (`tick_interval=0.25`,
## `max_ticks_per_frame=10` default); processing it fires exactly 10 ticks
## and discards the ~9.8s excess rather than deferring it (AC-1, GDD AC11,
## TR-time-tick-system-035); (2) the discard leaves NO banked residue behind
## to "catch up" on a later frame -- repeatedly hitting the cap is memoryless
## past the discard, a performance signal only, never self-correcting
## (AC-2, GDD Edge Case, TR-time-tick-system-037); (3) the two literal
## boundary cases the QA Test Cases call out explicitly: `raw_ticks` exactly
## equal to the cap fires all of them with NO discard (residue carries
## forward normally, matching tick-004's undiscarded drain), and `raw_ticks`
## one past the cap discards exactly one tick's worth of leftover time;
## (4) the cap value itself is read from config, not hardcoded -- a
## non-default `max_ticks_per_frame` changes the fired count accordingly
## (GDD Tuning Knobs, TR-time-tick-system-020).
##
## `raw_ticks = floor(tick_accumulator / tick_interval)` requires banking the
## accumulator itself to 12.3s. `compute_game_delta`'s `max_raw_delta` clamp
## (default 0.1s) caps what a SINGLE `_physics_process` call can add, and the
## drain fires/subtracts every due tick each call -- so no realistic sequence
## of small per-frame deltas can ever let the accumulator itself grow past a
## couple of `tick_interval`s before draining. The QA Test Cases phrase this
## test's arrange step as "Given accumulator = 12.3s" (a pre-existing banked
## value), not "given a 12.3s raw_delta stall" -- so these tests assign
## [code]_tick_accumulator[/code] directly (mirroring the existing precedent
## of calling the underscore-prefixed [method _physics_process] directly from
## a test) and then call the underscore-prefixed [method _advance_ticks]
## directly with a `0.0` [param game_delta] to trigger the cap check against
## that pre-set value in isolation, without exercising the raw-delta pipeline
## at all.
##
## Per the tick-001..004 precedent (`autoload_config_boot_test.gd`,
## `game_delta_computation_test.gd`, `pause_warp_state_test.gd`,
## `tick_accumulator_test.gd`): `time_tick_system.gd` deliberately carries no
## `class_name` (it would hide the "TimeTickSystem" Autoload singleton -- a
## Godot 4.7 parse error), so isolated instances are constructed via a
## preloaded [GDScript] and duck-typed at each access site.
##
## Signal-count assertions use a direct `.connect()` listener that APPENDS to
## a captured `Array`, never a reassigned captured scalar -- a GDScript
## lambda closure over a reassigned captured `int` local does NOT write back
## to the outer scope (documented the hard way in `tick_accumulator_test.gd`).
## Every tick counter below is therefore `var some_name: Array = []` +
## `.append(true)` inside the lambda, read via `.size()`.
##
## Every input below is a fixed literal chosen so no floating-point rounding
## can flip an assertion near a tick boundary -- deterministic, no random
## seeds, no time-dependent assertions, no scene tree, no Autoload
## registration.
class_name MaxTicksCapTest
extends GdUnitTestSuite

const TimeTickSystemScript: GDScript = preload("res://src/time_tick_system/time_tick_system.gd")

## Floating-point tolerance shared by the approx assertions below.
const TOLERANCE: float = 0.000001


## Returns a fresh, never-autoloaded TimeTickSystem-script instance, wired
## with a GDD-default [TimeTickConfig] (or [param custom_config] if supplied,
## to exercise a non-default `max_ticks_per_frame`) and already through
## [code]setup()[/code] -- isolated from the registered Autoload and the
## scene tree entirely. Untyped return -- see class doc comment.
func _new_system(custom_config: TimeTickConfig = null) -> Object:
	var system: Object = TimeTickSystemScript.new()
	@warning_ignore("unsafe_property_access")
	system.config = custom_config if custom_config != null else TimeTickConfig.new()
	@warning_ignore("unsafe_method_access")
	system.setup()
	return system


## Connects a tick-counting spy listener to [param system] and returns the
## backing `Array` -- `.size()` reflects the number of ticks fired so far.
func _connect_tick_spy(system: Object) -> Array:
	var ticks_fired: Array = []
	@warning_ignore("unsafe_property_access")
	system.tick.connect(func() -> void: ticks_fired.append(true))
	return ticks_fired


# ---------------------------------------------------------------------------
# AC-1 — GDD Formulas worked example, bit-for-bit: 12.3s stall -> 10 fired,
# ~9.8s discarded (GDD AC11, TR-time-tick-system-035)
# ---------------------------------------------------------------------------

func test_advance_ticks_worked_example_12_3s_stall_fires_exactly_ten_and_discards_rest() -> void:
	# Arrange — GDD Formulas worked example: accumulator already banked to
	# 12.3s (default config: tick_interval=0.25, max_ticks_per_frame=10), so
	# raw_ticks = floor(12.3 / 0.25) = 49.
	var system: Object = auto_free(_new_system())
	var ticks_fired: Array = _connect_tick_spy(system)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 12.3

	# Act — process the stalled accumulator in one call.
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)

	# Assert — exactly max_ticks_per_frame (10) fired, not 49; the ~9.8s
	# excess (12.3 - 10*0.25 = 9.8) is discarded entirely, not left banked.
	assert_int(ticks_fired.size()).is_equal(10)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal(0.0)


# ---------------------------------------------------------------------------
# AC-2 — memoryless past the discard: no catch-up cascade on a later frame,
# repeated cap hits get no special handling (GDD Edge Case,
# TR-time-tick-system-037)
# ---------------------------------------------------------------------------

func test_advance_ticks_no_catch_up_cascade_on_frame_after_a_discard() -> void:
	# Arrange — same 12.3s stall as the worked example; process it once so
	# the discard has already happened.
	var system: Object = auto_free(_new_system())
	var ticks_fired: Array = _connect_tick_spy(system)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 12.3
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)
	assert_int(ticks_fired.size()).is_equal(10)

	# Act — a normal next frame's worth of game_delta, far below one
	# tick_interval on its own (0.05 < 0.25) -- if any of the discarded 9.8s
	# had secretly survived, this frame would fire extra "catch-up" ticks.
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.05)

	# Assert — no new ticks fired; the discard truly erased the excess, it
	# did not defer it. The accumulator holds only this frame's own delta.
	assert_int(ticks_fired.size()).is_equal(10)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal_approx(0.05, TOLERANCE)


func test_advance_ticks_repeated_stalls_each_capped_independently_no_accrual() -> void:
	# Arrange — hitting the cap on consecutive "frames" (successive
	# _advance_ticks calls) is not corrected or smoothed by this system; each
	# call is judged solely on its own current accumulator value.
	var system: Object = auto_free(_new_system())
	var ticks_fired: Array = _connect_tick_spy(system)

	# Act — three independent large stalls in a row, each processed in turn.
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 12.3
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 5.0
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 3.0
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)

	# Assert — each stall independently capped to 10 (never more, because no
	# banked residue accrues across calls); 30 total across three calls.
	assert_int(ticks_fired.size()).is_equal(30)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal(0.0)


# ---------------------------------------------------------------------------
# QA Test Cases edge cases — raw_ticks exactly at the cap (fires all, no
# discard) and raw_ticks one past the cap (exactly one tick discarded)
# ---------------------------------------------------------------------------

func test_advance_ticks_raw_ticks_exactly_at_cap_fires_all_with_no_discard() -> void:
	# Arrange — accumulator = 10 * tick_interval + a sub-tick residue
	# (2.5 + 0.1 = 2.6), so raw_ticks = floor(2.6 / 0.25) = 10, exactly equal
	# to the default cap. This must NOT trigger the discard branch — the
	# 0.1 residue should survive untouched, proving the cap boundary is
	# inclusive of "no discard" at raw_ticks == max_ticks_per_frame.
	var system: Object = auto_free(_new_system())
	var ticks_fired: Array = _connect_tick_spy(system)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 2.6

	# Act
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)

	# Assert — all 10 due ticks fired, and the 0.1 sub-tick residue carried
	# forward normally (no discard) -- matching tick-004's undiscarded drain.
	assert_int(ticks_fired.size()).is_equal(10)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal_approx(0.1, TOLERANCE)


func test_advance_ticks_raw_ticks_one_past_cap_discards_exactly_one_ticks_worth() -> void:
	# Arrange — accumulator = 11 * tick_interval exactly (2.75), so
	# raw_ticks = 11, one past the default cap of 10.
	var system: Object = auto_free(_new_system())
	var ticks_fired: Array = _connect_tick_spy(system)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 2.75

	# Act
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)

	# Assert — only 10 fired (the 11th is the one discarded tick's worth);
	# the discard branch resets the accumulator to 0.0, not to the
	# undiscarded residue (2.75 - 10*0.25 = 0.25) a purely-uncapped drain
	# would have left behind.
	assert_int(ticks_fired.size()).is_equal(10)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal(0.0)


# ---------------------------------------------------------------------------
# Config-driven, not hardcoded (GDD Tuning Knobs, TR-time-tick-system-020)
# ---------------------------------------------------------------------------

func test_advance_ticks_respects_non_default_max_ticks_per_frame_from_config() -> void:
	# Arrange — a custom config with a non-default cap (6, still inside the
	# GDD's safe range [5, 30] so `setup()`'s `config.validate()` call does
	# NOT clamp it -- proving the value that reaches `_advance_ticks` truly
	# flows from config, not a hardcoded `10`).
	var custom_config: TimeTickConfig = TimeTickConfig.new()
	custom_config.max_ticks_per_frame = 6
	var system: Object = auto_free(_new_system(custom_config))
	@warning_ignore("unsafe_property_access")
	assert_int(system.config.max_ticks_per_frame).is_equal(6)  # unclamped
	var ticks_fired: Array = _connect_tick_spy(system)
	@warning_ignore("unsafe_property_access")
	system._tick_accumulator = 2.0  # raw_ticks = floor(2.0 / 0.25) = 8

	# Act
	@warning_ignore("unsafe_method_access")
	system._advance_ticks(0.0)

	# Assert — capped to the CONFIGURED 6, not the GDD-default 10; the excess
	# (2.0 - 6*0.25 = 0.5) is discarded.
	assert_int(ticks_fired.size()).is_equal(6)
	@warning_ignore("unsafe_method_access")
	assert_float(system.get_tick_accumulator()).is_equal(0.0)
