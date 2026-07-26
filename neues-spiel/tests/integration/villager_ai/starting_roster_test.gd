## Integration test -- Villager AI story villager-ai-021 (starting-roster
## spawn at world generation, GDD Rule 14b / [TR-villager-ai-behavior-065]).
##
## Proves:
## - **AC47**: given `starting_villager_count` = N (mocked config), exactly N
##   villagers exist at valid standable cells near the world center, each
##   starting in Deciding with a well-formed `current_cell` -- both the pure
##   placement half ([VillagerRosterSpawner.select_starting_cells]) and the
##   full DI-assembly half ([VillagerRosterSpawner.assemble_roster] plus
##   [Valley.spawn_starting_roster]'s real wiring against a real hosted
##   [VoxelWorldGrid]).
## - Edge cases: N = 1 (MVP, the shipped `.tres` default) and N = 5 (Vertical
##   Slice); a world without enough standable cells near center degrades
##   deterministically (returns fewer, never crashes) rather than blocking.
## - Growth beyond the starting roster is explicitly out of this story's
##   scope (Township Progression owns it) -- confirmed by this class having
##   no "already spawned" guard of its own.
class_name StartingRosterTest
extends GdUnitTestSuite

const ValleyScene: PackedScene = preload("res://src/scene_world_management/Valley.tscn")


# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

func _solid() -> CellContents:
	return CellContents.new(1, 0)


## Fills a flat, fully-standable plane (solid one cell below, empty at and
## above) across [param half_extent] cells in every horizontal direction from
## [param center] (inclusive) -- large enough that every fixture below finds
## plenty of standable cells near the center. Mirrors the established
## `_make_standable`/`AC-VILLAGER-WALKS` per-cell `set_cell` convention
## (`rescue_search_expansion_test.gd`, `gameworld_e2e_loop_test.gd`) rather
## than a bulk write, since these fixtures are small.
func _fill_flat_plane(voxel_world: VoxelWorldGrid, center: Vector3i, half_extent: int) -> void:
	for dx in range(-half_extent, half_extent + 1):
		for dz in range(-half_extent, half_extent + 1):
			voxel_world.set_cell(Vector3i(center.x + dx, center.y - 1, center.z + dz), _solid())


# ---------------------------------------------------------------------------
# VillagerRosterSpawner.select_starting_cells -- placement (Logic half)
# ---------------------------------------------------------------------------

func test_select_starting_cells_returns_exactly_count_distinct_standable_cells() -> void:
	# Arrange
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()
	var center := Vector3i(20, 1, 20)
	_fill_flat_plane(grid, center, 10)

	# Act
	var cells: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(grid, center, 5)

	# Assert
	assert_int(cells.size()).is_equal(5)
	var seen: Dictionary[Vector3i, bool] = {}
	for cell: Vector3i in cells:
		assert_bool(VillagerWalkabilityRules.is_standable(grid, cell)).is_true()
		assert_bool(seen.has(cell)).is_false()
		seen[cell] = true


func test_select_starting_cells_is_deterministic_across_repeated_calls() -> void:
	# Arrange -- this story's own "keep placement deterministic given the
	# same world seed/config" Implementation Note.
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()
	var center := Vector3i(20, 1, 20)
	_fill_flat_plane(grid, center, 10)

	# Act
	var first: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(grid, center, 5)
	var second: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(grid, center, 5)

	# Assert -- same world, same request -> byte-identical roster, same order.
	assert_array(second).contains_exactly(first)


func test_select_starting_cells_prefers_the_center_cell_itself_when_standable() -> void:
	# Arrange -- unlike VillagerRescueTargetSearch's own ring walk (which
	# excludes ring 0 to avoid "rescuing" a villager to its own cell), ring 0
	# (the center cell itself) IS eligible here -- there is no equivalent
	# hazard for a fresh spawn.
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()
	var center := Vector3i(20, 1, 20)
	_fill_flat_plane(grid, center, 10)

	# Act
	var cells: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(grid, center, 1)

	# Assert
	assert_int(cells.size()).is_equal(1)
	assert_vector(Vector3(cells[0])).is_equal(Vector3(center))


func test_select_starting_cells_returns_fewer_than_count_when_world_lacks_enough_standable_cells() -> void:
	# Arrange -- QA plan edge case: "no standable cell near center within a
	# fallback search (deterministic placement)" -- exactly TWO standable
	# cells exist anywhere near center; five are requested.
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()
	var center := Vector3i(20, 1, 20)
	grid.set_cell(center + Vector3i(0, -1, 0), _solid())
	grid.set_cell(center + Vector3i(1, -1, 0), _solid())

	# Act
	var cells: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(grid, center, 5)

	# Assert -- never crashes, returns however many it actually found.
	assert_int(cells.size()).is_equal(2)


func test_select_starting_cells_returns_empty_when_world_has_zero_standable_cells() -> void:
	# Arrange -- a genuinely empty grid, mirroring this codebase's own
	# documented "Valley boots with an empty VoxelWorldGrid" gap (ADR-0015 --
	# terrain pages in asynchronously, never synchronously at boot).
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()

	# Act
	var cells: Array[Vector3i] = VillagerRosterSpawner.select_starting_cells(
		grid, Vector3i(20, 1, 20), 5
	)

	# Assert
	assert_int(cells.size()).is_equal(0)


# ---------------------------------------------------------------------------
# VillagerRosterSpawner.assemble_roster -- DI wiring (pure construction)
# ---------------------------------------------------------------------------

func test_assemble_roster_wires_each_villager_with_a_distinct_stable_id_and_its_own_cell() -> void:
	# Arrange
	var grid: VoxelWorldGrid = auto_free(VoxelWorldGrid.new())
	grid.config = VoxelWorldConfig.new()
	var config := VillagerAIConfig.new()
	var scheduler := VillagerDecidingScheduler.new()
	var nav_graph := VillagerNavGraph.new()
	var telemetry := VillagerUnstuckTelemetry.new()
	var cells: Array[Vector3i] = [Vector3i(1, 1, 1), Vector3i(2, 1, 1), Vector3i(3, 1, 1)]

	# Act
	var roster: Array[VillagerAi] = VillagerRosterSpawner.assemble_roster(
		grid, config, scheduler, nav_graph, telemetry, cells, 5
	)
	for villager: VillagerAi in roster:
		auto_free(villager)

	# Assert -- stable-order ids continuing from the caller-supplied start;
	# never calls setup() itself (ADR-0005: that is the caller's job).
	assert_int(roster.size()).is_equal(3)
	for i in range(roster.size()):
		var villager: VillagerAi = roster[i]
		assert_int(villager.get_villager_id()).is_equal(5 + i)
		assert_vector(Vector3(villager.get_current_cell())).is_equal(Vector3(cells[i]))
		assert_object(villager.config).is_same(config)
		assert_object(villager.voxel_world).is_same(grid)
		assert_object(villager.scheduler).is_same(scheduler)
		assert_object(villager.nav_graph).is_same(nav_graph)
		assert_object(villager.unstuck_telemetry).is_same(telemetry)
		assert_bool(villager.is_set_up()).is_false()


# ---------------------------------------------------------------------------
# Valley.spawn_starting_roster -- AC47 end to end
# ---------------------------------------------------------------------------

## Boots a real [GameWorld] + [Valley] through the ADR-0005 boot gate (mirrors
## `world_root_valley_attach_test.gd`'s own established pattern) so every
## hosted module's `setup()` has already run -- including [PlacementPick]/
## [CommitPipeline]/etc, which assert against being touched pre-`setup()` --
## BEFORE this test's own Act step. A bare `add_child(Valley.new())` (this
## file's own earlier draft) skips that gate entirely and trips exactly that
## assertion the instant the scene tree processes its first frame; booting
## through the real [GameWorld] is the correct, production-shaped fixture.
func _boot_valley() -> Valley:
	var world: GameWorld = auto_free(GameWorld.new())
	var database: MockResourceItemDatabase = auto_free(MockResourceItemDatabase.new())
	database.configure_ready_immediately()
	world.resource_item_database = database
	world.valley_scene = ValleyScene
	add_child(world)
	return world.get_valley() as Valley


func test_valley_spawn_starting_roster_places_exactly_n_villagers_each_deciding_on_a_standable_cell() -> void:
	# Arrange -- a real, fully-booted Valley, real hosted VoxelWorldGrid, a
	# mocked config count (Vertical Slice tier, N=5, a FRESH Resource
	# instance -- never the shared `.tres`-loaded default, so mutating it
	# cannot leak into any other test's own Valley instance). World
	# generation is simulated by directly filling terrain around the real
	# world-center cell before spawning (mirrors this story's own "when
	# world generation completes" AC wording).
	var valley: Valley = _boot_valley()
	var voxel_world: VoxelWorldGrid = valley.get_voxel_world()
	var center: Vector3i = VillagerRosterSpawner.world_center_cell(voxel_world.config)
	_fill_flat_plane(voxel_world, center, 10)
	valley.villager_ai_config = VillagerAIConfig.new()
	valley.villager_ai_config.starting_villager_count = 5

	# Act
	var spawned: Array[VillagerAi] = valley.spawn_starting_roster()

	# Assert -- AC47: exactly N villagers, each standable/Deciding/well-formed.
	assert_int(spawned.size()).is_equal(5)
	for villager: VillagerAi in spawned:
		assert_bool(villager.is_set_up()).is_true()
		assert_int(villager.get_state()).is_equal(VillagerAi.State.DECIDING)
		assert_bool(
			VillagerWalkabilityRules.is_standable(voxel_world, villager.get_current_cell())
		).is_true()
		assert_object(villager.get_parent()).is_same(valley)


func test_valley_spawn_starting_roster_mvp_default_count_places_exactly_one() -> void:
	# Arrange -- the shipped .tres default (starting_villager_count = 1, MVP)
	# -- never mutated, this test reads it as-is.
	#
	# Story scene-005 (World genesis in the boot sequence): _boot_valley()'s
	# real GameWorld boot now runs world genesis (AC-ROSTER-AFTER-WORLD), which
	# calls spawn_starting_roster() itself ONCE automatically before this
	# test's own Act step -- so by the time _boot_valley() returns, one roster
	# villager already exists. baseline_next_id captures wherever that
	# boot-time call left villager_id numbering (Valley.get_villagers().size()
	# is always exactly the next id spawn_starting_roster() will assign, since
	# ids start at 1 and continue from the current roster size) rather than
	# hardcoding the pre-scene-005 assumption that this test's OWN call is the
	# very first one ever made.
	var valley: Valley = _boot_valley()
	var voxel_world: VoxelWorldGrid = valley.get_voxel_world()
	var center: Vector3i = VillagerRosterSpawner.world_center_cell(voxel_world.config)
	_fill_flat_plane(voxel_world, center, 10)
	var baseline_next_id: int = valley.get_villagers().size()

	# Act
	var spawned: Array[VillagerAi] = valley.spawn_starting_roster()

	# Assert
	assert_int(spawned.size()).is_equal(1)
	assert_int(spawned[0].get_villager_id()).is_equal(baseline_next_id)


func test_valley_spawn_starting_roster_does_not_disturb_the_pre_existing_default_villager() -> void:
	# Arrange -- regression guard: the pre-existing single hosted villager
	# (villager_id 0) predates this story and stays exactly as-is, completely
	# separate from the new config-driven roster.
	var valley: Valley = _boot_valley()
	var voxel_world: VoxelWorldGrid = valley.get_voxel_world()
	var center: Vector3i = VillagerRosterSpawner.world_center_cell(voxel_world.config)
	_fill_flat_plane(voxel_world, center, 10)

	# Act
	valley.spawn_starting_roster()

	# Assert
	assert_object(valley.get_villager_ai()).is_not_null()
	assert_int(valley.get_villager_ai().get_villager_id()).is_equal(0)
	assert_array(valley.get_villagers()).contains([valley.get_villager_ai()])


func test_valley_spawn_starting_roster_has_no_growth_bookkeeping_of_its_own() -> void:
	# Arrange -- Out of Scope confirmation (Township Progression owns
	# growth/arrivals/recruitment): calling spawn_starting_roster() a SECOND
	# time is not this story's own growth mechanism -- it simply repeats the
	# same deterministic placement with continuing villager_id numbering; no
	# "already spawned the starting roster" guard exists anywhere in this
	# class, by design (that bookkeeping belongs to whichever future story
	# decides WHEN to call this exactly once).
	#
	# Story scene-005: see the sibling MVP-default test's own updated comment
	# above -- _boot_valley() now runs world genesis, which calls
	# spawn_starting_roster() once automatically before this test's own Act
	# step. baseline_next_id captures wherever that left villager_id
	# numbering, exactly as that test does.
	var valley: Valley = _boot_valley()
	var voxel_world: VoxelWorldGrid = valley.get_voxel_world()
	var center: Vector3i = VillagerRosterSpawner.world_center_cell(voxel_world.config)
	_fill_flat_plane(voxel_world, center, 10)
	valley.villager_ai_config = VillagerAIConfig.new()
	valley.villager_ai_config.starting_villager_count = 1
	var baseline_next_id: int = valley.get_villagers().size()

	# Act
	var first_call: Array[VillagerAi] = valley.spawn_starting_roster()
	var second_call: Array[VillagerAi] = valley.spawn_starting_roster()

	# Assert -- ids keep incrementing from wherever boot-time genesis left off.
	assert_int(first_call[0].get_villager_id()).is_equal(baseline_next_id)
	assert_int(second_call[0].get_villager_id()).is_equal(baseline_next_id + 1)
