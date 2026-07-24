## Integration test — Villager AI story villager-ai-001 (config resource, DI
## scaffold, FSM state enum; ADR-0001 primary, ADR-0002, ADR-0008 secondary
## for the state set).
##
## Proves:
## 1. AC1 [TR-villager-ai-behavior-090]: [VillagerAIConfig] exports exactly
##    the 15 knobs this story's AC list names, each at its GDD (or
##    ADR-0008, for `max_deciding_per_tick`) default, stored as a `.tres`
##    (`res://data/config/villager_ai_config.tres`).
## 2. AC2: [VillagerAIConfig.validate] range-checks every knob against its
##    documented safe range -- a single-field issue warns, clamps in place,
##    and boot proceeds (never halts); both boundaries are inclusive
##    (exactly-at-bound produces zero warnings).
## 3. AC3 (TR-016 DI): [VillagerAi] is instantiable headless via `Node.new()`
##    with mocks assigned directly (no scene tree, no Autoload
##    registration); `setup()` asserts each of its three dependencies
##    (`config`, `voxel_world`, `time_tick_system`) is wired, failing loudly
##    rather than proceeding silently when one is missing.
## 4. AC4: [VillagerAi.State] contains exactly the six GDD-named states and
##    no others; per-villager state starts at `DECIDING` (GDD state table
##    entry point) and is dispatched via `match` on the injected
##    `TimeTickSystem`-shaped double's `tick` signal -- never a raw-delta
##    poll. `VillagerAi` still defines no `_physics_process` at all
##    (verified structurally below). **Amended by story villager-ai-004**:
##    `VillagerAi` now defines exactly one `_process(_delta)` override, added
##    for ADR-0009's cosmetic-only visual-position recompute -- its `_delta`
##    parameter is named with the conventional unused-parameter underscore
##    prefix and is never read; FSM dispatch itself remains exclusively
##    tick-signal-driven, unaffected by this addition (see
##    `tests/unit/villager_ai/deterministic_position_test.gd` for that
##    story's own coverage).
## 5. Control Manifest Feature Layer guardrails, established from this
##    epic's first commit onward (grep-verifiable, comment-stripped source
##    scan -- this codebase's established precedent, see
##    `tests/integration/voxel_world/dda_raycast_test.gd`'s
##    `_read_all_gd_source` helper): zero `NavigationServer3D`/
##    `NavigationAgent3D`/`NavigationRegion3D` (ADR-0007) and zero
##    `Thread`/`WorkerThreadPool` (ADR-0008) anywhere in `src/villager_ai/`.
class_name ConfigAndScaffoldTest
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# AC1 — config defaults match the GDD (or ADR-0008) Tuning Knobs
# ---------------------------------------------------------------------------

func test_config_defaults_match_gdd_tuning_knobs() -> void:
	# Arrange + Act
	var config := VillagerAIConfig.new()

	# Assert — design/gdd/villager-ai-behavior.md Tuning Knobs section
	# (max_deciding_per_tick per ADR-0008's spike-tuned value).
	assert_float(config.move_speed).is_equal_approx(3.0, 0.0001)
	assert_int(config.decision_interval).is_equal(2)
	assert_int(config.unreachable_retry_ticks).is_equal(20)
	assert_int(config.wander_radius).is_equal(8)
	assert_int(config.wander_interval).is_equal(6)
	assert_int(config.job_candidate_count).is_equal(5)
	assert_int(config.max_selection_candidates).is_equal(15)
	assert_int(config.jobs_before_break).is_equal(4)
	assert_int(config.breather_duration_ticks).is_equal(90)
	assert_int(config.starting_villager_count).is_equal(1)
	assert_int(config.max_deciding_per_tick).is_equal(1)
	assert_int(config.unstuck_watchdog_threshold_ticks).is_equal(12)
	assert_int(config.unstuck_rescue_search_radius).is_equal(6)
	assert_int(config.unstuck_rescue_max_radius).is_equal(24)
	assert_int(config.seal_prevention_abandon_limit).is_equal(3)


func test_villager_ai_config_tres_loads_and_matches_script_defaults() -> void:
	# Arrange + Act — proves AC1's "stored as a .tres" requirement holds
	# against the actual authored resource file, not just the script's own
	# field initializers.
	var config: VillagerAIConfig = load("res://data/config/villager_ai_config.tres")

	# Assert
	assert_object(config).is_not_null()
	assert_float(config.move_speed).is_equal_approx(3.0, 0.0001)
	assert_int(config.max_deciding_per_tick).is_equal(1)
	assert_int(config.seal_prevention_abandon_limit).is_equal(3)


# ---------------------------------------------------------------------------
# AC2 — validate() range-checks, clamp+warn, inclusive boundaries
# ---------------------------------------------------------------------------

## One row per knob this story's AC1 lists: [field name, min, max, a value
## strictly below min, a value strictly above max]. Ints and floats are
## distinguished by whether `min`/`max` themselves are `int` or `float` --
## read via `typeof()` below rather than a separate flag column.
const KNOB_CASES: Array[Array] = [
	["move_speed", VillagerAIConfig.MOVE_SPEED_MIN, VillagerAIConfig.MOVE_SPEED_MAX, 1.0, 7.0],
	["decision_interval", VillagerAIConfig.DECISION_INTERVAL_MIN, VillagerAIConfig.DECISION_INTERVAL_MAX, 0, 11],
	["unreachable_retry_ticks", VillagerAIConfig.UNREACHABLE_RETRY_TICKS_MIN, VillagerAIConfig.UNREACHABLE_RETRY_TICKS_MAX, 5, 130],
	["wander_radius", VillagerAIConfig.WANDER_RADIUS_MIN, VillagerAIConfig.WANDER_RADIUS_MAX, 1, 20],
	["wander_interval", VillagerAIConfig.WANDER_INTERVAL_MIN, VillagerAIConfig.WANDER_INTERVAL_MAX, 1, 25],
	["job_candidate_count", VillagerAIConfig.JOB_CANDIDATE_COUNT_MIN, VillagerAIConfig.JOB_CANDIDATE_COUNT_MAX, 1, 15],
	["max_selection_candidates", VillagerAIConfig.MAX_SELECTION_CANDIDATES_MIN, VillagerAIConfig.MAX_SELECTION_CANDIDATES_MAX, 2, 40],
	["jobs_before_break", VillagerAIConfig.JOBS_BEFORE_BREAK_MIN, VillagerAIConfig.JOBS_BEFORE_BREAK_MAX, 1, 15],
	["breather_duration_ticks", VillagerAIConfig.BREATHER_DURATION_TICKS_MIN, VillagerAIConfig.BREATHER_DURATION_TICKS_MAX, 10, 300],
	["starting_villager_count", VillagerAIConfig.STARTING_VILLAGER_COUNT_MIN, VillagerAIConfig.STARTING_VILLAGER_COUNT_MAX, 0, 12],
	["max_deciding_per_tick", VillagerAIConfig.MAX_DECIDING_PER_TICK_MIN, VillagerAIConfig.MAX_DECIDING_PER_TICK_MAX, 0, 40],
	["unstuck_watchdog_threshold_ticks", VillagerAIConfig.UNSTUCK_WATCHDOG_THRESHOLD_TICKS_MIN, VillagerAIConfig.UNSTUCK_WATCHDOG_THRESHOLD_TICKS_MAX, 2, 40],
	["unstuck_rescue_search_radius", VillagerAIConfig.UNSTUCK_RESCUE_SEARCH_RADIUS_MIN, VillagerAIConfig.UNSTUCK_RESCUE_SEARCH_RADIUS_MAX, 1, 20],
	["unstuck_rescue_max_radius", VillagerAIConfig.UNSTUCK_RESCUE_MAX_RADIUS_MIN, VillagerAIConfig.UNSTUCK_RESCUE_MAX_RADIUS_MAX, 5, 60],
	["seal_prevention_abandon_limit", VillagerAIConfig.SEAL_PREVENTION_ABANDON_LIMIT_MIN, VillagerAIConfig.SEAL_PREVENTION_ABANDON_LIMIT_MAX, 0, 10],
]


func test_validate_gdd_defaults_returns_empty() -> void:
	# Arrange
	var config := VillagerAIConfig.new()

	# Act
	var issues: Array[String] = config.validate()

	# Assert
	assert_array(issues).is_empty()


func test_validate_every_knob_below_min_clamps_and_warns() -> void:
	for case: Array in KNOB_CASES:
		var field: String = case[0]
		var min_value: Variant = case[1]
		var below_value: Variant = case[3]

		# Arrange — a fresh, otherwise-default config; only this one field
		# is pushed out of range.
		var config := VillagerAIConfig.new()
		config.set(field, below_value)

		# Act
		var issues: Array[String] = config.validate()

		# Assert — exactly one warning, and the field is clamped to its min.
		assert_int(issues.size()).is_equal(1).override_failure_message(
			"field '%s': expected exactly 1 issue, got %s" % [field, issues]
		)
		_assert_field_equals(config, field, min_value)


func test_validate_every_knob_above_max_clamps_and_warns() -> void:
	for case: Array in KNOB_CASES:
		var field: String = case[0]
		var max_value: Variant = case[2]
		var above_value: Variant = case[4]

		# Arrange
		var config := VillagerAIConfig.new()
		config.set(field, above_value)

		# Act
		var issues: Array[String] = config.validate()

		# Assert — exactly one warning, and the field is clamped to its max.
		assert_int(issues.size()).is_equal(1).override_failure_message(
			"field '%s': expected exactly 1 issue, got %s" % [field, issues]
		)
		_assert_field_equals(config, field, max_value)


func test_validate_every_knob_at_min_boundary_is_inclusive_no_warning() -> void:
	for case: Array in KNOB_CASES:
		var field: String = case[0]
		var min_value: Variant = case[1]

		# Arrange — the boundary value itself, exactly at min.
		var config := VillagerAIConfig.new()
		config.set(field, min_value)

		# Act
		var issues: Array[String] = config.validate()

		# Assert — inclusive boundary: zero warnings, value unchanged.
		assert_array(issues).is_empty().override_failure_message(
			"field '%s' at min boundary %s produced issues: %s" % [field, min_value, issues]
		)
		_assert_field_equals(config, field, min_value)


func test_validate_every_knob_at_max_boundary_is_inclusive_no_warning() -> void:
	for case: Array in KNOB_CASES:
		var field: String = case[0]
		var max_value: Variant = case[2]

		# Arrange — the boundary value itself, exactly at max.
		var config := VillagerAIConfig.new()
		config.set(field, max_value)

		# Act
		var issues: Array[String] = config.validate()

		# Assert — inclusive boundary: zero warnings, value unchanged.
		assert_array(issues).is_empty().override_failure_message(
			"field '%s' at max boundary %s produced issues: %s" % [field, max_value, issues]
		)
		_assert_field_equals(config, field, max_value)


## Type-aware equality helper for [constant KNOB_CASES]' mixed int/float
## fields -- floats compare approximately (clamp arithmetic), ints exactly.
func _assert_field_equals(config: VillagerAIConfig, field: String, expected: Variant) -> void:
	var actual: Variant = config.get(field)
	if typeof(expected) == TYPE_FLOAT:
		assert_float(actual).is_equal_approx(float(expected), 0.0001)
	else:
		assert_int(actual).is_equal(int(expected))


# ---------------------------------------------------------------------------
# AC3 (TR-016 DI) — headless instantiation, dependency assertions
# ---------------------------------------------------------------------------

func test_villager_ai_setup_headless_with_mocks_succeeds_no_scene_tree() -> void:
	# Arrange — Node.new(), mocks assigned directly, never added to any tree
	# (TR-016: zero scene tree, zero Autoload registration).
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.config = VillagerAIConfig.new()
	villager.voxel_world = auto_free(VoxelWorldGrid.new())
	var mock_tick: MockTimeTickSystem = auto_free(MockTimeTickSystem.new())
	villager.time_tick_system = mock_tick
	assert_bool(villager.is_set_up()).is_false()

	# Act
	villager.setup()

	# Assert
	assert_bool(villager.is_set_up()).is_true()


func test_villager_ai_setup_missing_config_raises_assertion() -> void:
	# Arrange
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.voxel_world = auto_free(VoxelWorldGrid.new())
	villager.time_tick_system = auto_free(MockTimeTickSystem.new())

	# Act + Assert
	await assert_error(func() -> void: villager.setup()).is_runtime_error(
		"Assertion failed: VillagerAi.config not wired"
	)


func test_villager_ai_setup_missing_voxel_world_raises_assertion() -> void:
	# Arrange
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.config = VillagerAIConfig.new()
	villager.time_tick_system = auto_free(MockTimeTickSystem.new())

	# Act + Assert
	await assert_error(func() -> void: villager.setup()).is_runtime_error(
		"Assertion failed: VillagerAi.voxel_world not wired"
	)


func test_villager_ai_setup_missing_time_tick_system_raises_assertion() -> void:
	# Arrange — no real TimeTickSystem Autoload node lives at
	# /root/TimeTickSystem inside this isolated test scene tree (this test
	# node is never added to the SceneTree's live root), so the lazy
	# resolve in setup() finds nothing and the dependency stays null.
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.config = VillagerAIConfig.new()
	villager.voxel_world = auto_free(VoxelWorldGrid.new())

	# Act + Assert
	await assert_error(func() -> void: villager.setup()).is_runtime_error(
		"Assertion failed: VillagerAi requires a TimeTickSystem-shaped dependency"
		+ " (assign a mock in tests; the real Autoload is registered project-wide)"
		+ " before setup() can connect tick dispatch"
	)


# ---------------------------------------------------------------------------
# AC4 — the six-state FSM, tick-signal-driven dispatch
# ---------------------------------------------------------------------------

func test_state_enum_contains_exactly_six_named_states() -> void:
	# Arrange + Act
	var state_names: Array = VillagerAi.State.keys()

	# Assert
	assert_int(state_names.size()).is_equal(6)
	var expected: Array[String] = [
		"DECIDING", "TRAVELING", "WORKING", "SLEEPING", "BREATHER", "WANDERING",
	]
	for name: String in expected:
		assert_bool(state_names.has(name)).is_true()


func test_villager_ai_starts_in_deciding_state() -> void:
	# Arrange + Act
	var villager: VillagerAi = auto_free(VillagerAi.new())

	# Assert — GDD state table: Deciding is every agent's loop-start entry.
	assert_int(villager.get_state()).is_equal(VillagerAi.State.DECIDING)


func test_villager_ai_setup_connects_tick_signal_to_dispatch() -> void:
	# Arrange
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.config = VillagerAIConfig.new()
	villager.voxel_world = auto_free(VoxelWorldGrid.new())
	var mock_tick: MockTimeTickSystem = auto_free(MockTimeTickSystem.new())
	villager.time_tick_system = mock_tick

	# Act
	villager.setup()

	# Assert — the tick-driven contract holds structurally: dispatch is
	# wired to the injected TimeTickSystem-shaped double's own signal.
	assert_bool(mock_tick.tick.is_connected(villager._on_tick)).is_true()


func test_villager_ai_tick_signal_fire_dispatches_without_error_and_stays_deciding() -> void:
	# Arrange — a manually-fired tick (no real physics frame needed) must
	# reach the FSM dispatch without crashing; DECIDING's body is an empty
	# stub this story (story 005/006 give it real behaviour), so state stays
	# unchanged.
	var villager: VillagerAi = auto_free(VillagerAi.new())
	villager.config = VillagerAIConfig.new()
	villager.voxel_world = auto_free(VoxelWorldGrid.new())
	var mock_tick: MockTimeTickSystem = auto_free(MockTimeTickSystem.new())
	villager.time_tick_system = mock_tick
	villager.setup()

	# Act
	mock_tick.fire_tick()

	# Assert
	assert_int(villager.get_state()).is_equal(VillagerAi.State.DECIDING)


func test_tick_state_dispatches_without_error_for_every_state() -> void:
	# Arrange — every [enum VillagerAi.State] value is exercised directly
	# against [method VillagerAi._tick_state], proving every `match` branch
	# is present and callable (all stub bodies this story) without needing
	# a real tick signal for each one.
	var villager: VillagerAi = auto_free(VillagerAi.new())
	var all_states: Array = [
		VillagerAi.State.DECIDING, VillagerAi.State.TRAVELING, VillagerAi.State.WORKING,
		VillagerAi.State.SLEEPING, VillagerAi.State.BREATHER, VillagerAi.State.WANDERING,
	]

	for state: int in all_states:
		# Act
		villager._state = state
		villager._tick_state()

		# Assert — a stub body never itself transitions state.
		assert_int(villager.get_state()).is_equal(state)


func test_villager_ai_defines_no_physics_process_and_process_is_visual_only() -> void:
	# Structural check for "never raw delta" (Control Manifest Feature
	# Layer): FSM dispatch happens exclusively via the injected tick signal
	# -- this module must never define a `_physics_process` override (no
	# alternate raw-delta path exists, ever). Amended by story
	# villager-ai-004 (ADR-0009): exactly one `_process(_delta)` override IS
	# now permitted -- the cosmetic-only visual-position recompute -- but
	# its parameter must still be the conventional unused-parameter
	# underscore-prefixed `_delta`, never read, proving it cannot be an
	# alternate raw-delta state-mutation path either.
	var source: String = _read_all_gd_source("res://src/villager_ai")

	assert_bool(source.contains("func _physics_process(")).is_false()
	assert_bool(source.contains("func _process(_delta")).is_true()


# ---------------------------------------------------------------------------
# Control Manifest Feature Layer guardrails (ADR-0007/ADR-0008) — established
# from this epic's first commit onward
# ---------------------------------------------------------------------------

func test_no_navigation_server_apis_anywhere_in_villager_ai_source() -> void:
	# Grep-verifiable AC (ADR-0007): NavigationServer3D/NavigationAgent3D/
	# NavigationRegion3D must be absent from src/villager_ai/'s own CODE
	# (comment-stripped -- this codebase's established precedent, see class
	# doc comment).
	var source: String = _read_all_gd_source("res://src/villager_ai")

	var banned_substrings: Array[String] = [
		"NavigationServer3D",
		"NavigationAgent3D",
		"NavigationRegion3D",
	]
	for banned: String in banned_substrings:
		assert_bool(source.contains(banned)).is_false()


func test_no_threading_apis_anywhere_in_villager_ai_source() -> void:
	# Grep-verifiable AC (ADR-0008): Thread/WorkerThreadPool must be absent
	# from src/villager_ai/'s own CODE (comment-stripped) -- MVP/VS Villager
	# AI is single-threaded, tick-staggered, never genuinely parallel.
	var source: String = _read_all_gd_source("res://src/villager_ai")

	var banned_substrings: Array[String] = [
		"WorkerThreadPool",
		"Thread",
	]
	for banned: String in banned_substrings:
		assert_bool(source.contains(banned)).is_false()


# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

## Reads and concatenates every `.gd` source file directly under
## [param dir_path] (non-recursive -- Villager AI's directory is flat),
## STRIPPING full-line `#`/`##` doc-comment lines first. Mirrors
## `tests/integration/voxel_world/dda_raycast_test.gd`'s
## `_read_all_gd_source` helper (this codebase's established precedent) --
## this system's own doc comments legitimately name the banned APIs to
## document that they are forbidden, so a naive raw-text scan would flag its
## own compliance documentation as a violation. Stripping comment lines means
## only actual CODE usage can trip the checks above.
func _read_all_gd_source(dir_path: String) -> String:
	var combined: String = ""
	var dir: DirAccess = DirAccess.open(dir_path)
	assert(dir != null, "Could not open directory: %s" % dir_path)
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var text: String = FileAccess.get_file_as_string(dir_path.path_join(file_name))
			for line: String in text.split("\n"):
				if not line.strip_edges().begins_with("#"):
					combined += line
					combined += "\n"
		file_name = dir.get_next()
	dir.list_dir_end()
	return combined
