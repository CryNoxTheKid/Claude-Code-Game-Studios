## Integration test — Foundation Spine Story 001 (ADR-0001 DI scaffold).
##
## Proves GameWorld.tscn exists with a GameWorld root script that owns
## injected-tier children and exposes them for scene-file (Inspector)
## wiring, and that GameWorld invokes each wired child's setup() explicitly
## — never relying on that child's own _ready() ordering (AC-1, AC-3).
class_name GameworldDiScaffoldTest
extends GdUnitTestSuite

const GameWorldScene := preload("res://src/scene_world_management/game_world.tscn")


func test_gameworld_tscn_instantiate_returns_gameworld_root_with_empty_wiring() -> void:
	# Arrange + Act
	var world: GameWorld = auto_free(GameWorldScene.instantiate())

	# Assert
	assert_object(world).is_not_null()
	assert_bool(world is GameWorld).is_true()
	assert_array(world.injected_tier_modules).is_empty()


func test_gameworld_ready_invokes_setup_on_each_wired_injected_tier_module() -> void:
	# Arrange — simulates scene-file (Inspector) wiring: the
	# injected_tier_modules array and each module's own @export
	# dependencies are populated BEFORE the subtree enters the live tree,
	# exactly as Godot resolves a real .tscn's Inspector-assigned @export
	# fields before any _ready() fires.
	var world: GameWorld = auto_free(GameWorld.new())
	var module: ReferenceInjectedModule = auto_free(ReferenceInjectedModule.new())
	module.dependency_one = auto_free(Node.new())
	module.dependency_two = auto_free(Node.new())
	world.add_child(module)
	world.injected_tier_modules = [module]
	assert_bool(module.is_set_up()).is_false()

	# Act — entering the live tree fires GameWorld._ready().
	add_child(world)

	# Assert
	assert_bool(module.is_set_up()).is_true()


func test_gameworld_module_setup_is_never_invoked_by_the_modules_own_ready() -> void:
	# Arrange — a module added directly to the live tree WITHOUT GameWorld
	# ever wiring/calling setup() must stay un-set-up: the only sanctioned
	# setup() call site is GameWorld's explicit invocation (ADR-0005),
	# never a module's own _ready().
	var module: ReferenceInjectedModule = auto_free(ReferenceInjectedModule.new())
	module.dependency_one = auto_free(Node.new())
	module.dependency_two = auto_free(Node.new())

	# Act
	add_child(module)

	# Assert
	assert_bool(module.is_set_up()).is_false()
