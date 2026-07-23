## Root scene script for the injected-tier dependency-injection substrate
## (ADR-0001) and the boot-sequencing gate (ADR-0005), owned by Scene/World
## Management.
##
## Owns the injected-tier child modules listed in [member injected_tier_modules]
## and invokes each one's [code]setup()[/code] explicitly, once scene-file
## (Inspector) wiring has resolved -- never relying on [method _ready]
## ordering (ADR-0001). Additionally (ADR-0005), [method _ready] is the
## SINGLE unified boot gate: every injected-tier [code]setup()[/code] call is
## withheld until the Resource & Item Database dependency reports its
## Ready/Failed outcome via check-then-connect (a synchronous
## [code]is_ready()[/code] check first, a [code]validation_complete[/code]
## signal connect fallback otherwise). On Failed, [signal boot_halted] fires
## and NO injected-tier [code]setup()[/code] is ever called -- terminal, no
## recovery.
##
## Foundation Spine Story 003 scope note (ADR-0002): the WIRING loop
## additionally duck-types each injected-tier module for an optional
## [code]get_boot_blocking_issues() -> Array[String][/code] method, called
## immediately after that module's [code]setup()[/code]. A non-empty result
## means the module's config Resource failed a GDD-declared BLOCKING
## cross-value invariant (ADR-0002's two-tier `validate()` policy) -- the
## SAME terminal halt path as a RID Failed outcome fires (HALTED,
## [signal boot_halted], no further injected-tier `setup()` calls). This is
## an additive check, not a new call site: [method _setup_injected_tier]
## remains the sole place any injected-tier `setup()` is invoked.
##
## Foundation Spine Story 002 scope note (ADR-0005): [member
## resource_item_database] is deliberately NOT [code]@export[/code]ed --
## Resource & Item Database is Autoload-tier (ADR-0001 forbids
## [code]@export[/code]ing an Autoload into any module). The real
## [code]ResourceItemDatabase[/code] Autoload does not exist yet in this
## The ResourceItemDatabase autoload (rid-002) resolves at /root/ResourceItemDatabase.
## touch [code]project.godot[/code]), so the dependency is resolved lazily
## against [code]/root/ResourceItemDatabase[/code] the first time this node
## enters the tree, or assigned directly to a mock RID-shaped double in
## headless tests before that -- mirroring the existing
## [ReferenceInjectedModule] mock-assignment convention. rid-002's autoload
## the real Autoload, this resolves automatically with no further change
## here. Similarly, [signal validation_complete]'s payload is a plain
## [Dictionary] ([code]{"success": bool, "issues": Array}[/code]) rather than
## a typed [code]ValidationResult[/code] -- that class does not exist yet
## (rid-004/005); this shape is forward-compatible with the eventual typed
## contract.
##
## Scene/World Management Story 001 scope note (ADR-0001 ownership note +
## ADR-0013): this [code]GameWorld[/code] root IS the World Root
## [TR-scene-world-management-035]. [member valley_scene] / [method
## _attach_valley] add this story's scene-TOPOLOGY behavior on the SAME node
## the Foundation Spine's boot gate already lives on -- a separate concern
## from the gate. Scene handoff uses ONLY [method Node.add_child] -- never
## [code]change_scene_to_file[/code]/[code]change_scene_to_packed[/code]/
## [code]reload_current_scene[/code], and [member SceneTree.current_scene] is
## never assigned directly [TR-scene-world-management-037] -- this World Root
## node itself is never freed [TR-scene-world-management-038].
##
## Scene/World Management Story 002 scope note (ADR-0005 host relationship,
## AC17a/AC17b): [method _attach_valley] is no longer called unconditionally
## from [method _ready] -- it is now gated behind the boot gate's SUCCESS
## path only, invoked from [method _on_database_settled] at the start of
## WIRING, before the injected-tier [code]setup()[/code] sweep. On a
## Resource & Item Database `Failed` outcome, the Valley is never attached --
## no empty-palette Valley [TR-scene-world-management-004]. This is the
## scene-topology REACTION to the Foundation Spine's gate (story 002 of this
## epic); it does not re-implement the gate mechanism itself (that remains
## `foundation-spine` story 002 / [method _on_database_settled]).
class_name GameWorld
extends Node3D

## Boot-sequencing states (ADR-0005). Progresses
## WAITING_FOR_DATABASE -> WIRING -> ACTIVE on the database dependency's
## Ready outcome. HALTED (from WAITING_FOR_DATABASE, on Failed) is terminal
## -- there is no path out of it.
enum BootState { WAITING_FOR_DATABASE, WIRING, ACTIVE, HALTED }

## Emitted exactly once, only on the HALTED transition (database dependency
## reported Failed). Carries the reported validation issues through
## untouched. This story's contract ends at "the halt path fires and no
## setup() is ever called" (ADR-0005 Implementation Notes) -- the concrete
## full-screen presentation (reusing the transition-overlay UI
## infrastructure, TR-scene-world-management-032) is a later scene-world-
## management story's job; this signal is the hook it connects to.
signal boot_halted(issues: Array)

## Ordered list of injected-tier child modules whose [code]setup()[/code]
## this root invokes. Wired via the Inspector on [code]GameWorld.tscn[/code]
## -- the array holds direct node references (resolved at scene
## deserialization, before any child's [method _ready] runs), not
## [NodePath]s, so the full wiring list is visible and editable in one
## place. Order matters when one module's [code]setup()[/code] establishes
## signal connections another module's [code]setup()[/code] depends on;
## callers control that order via this array, not via scene-tree child order.
@export var injected_tier_modules: Array[Node] = []

## The Resource & Item Database boot-gate dependency (ADR-0005). See the
## class doc comment's Story 002 scope note for why this is a plain var, not
## [code]@export[/code]. Duck-typed against exactly two members: [code]
## is_ready() -> bool[/code] and [code]signal validation_complete(result:
## Dictionary)[/code]. Assign a mock double directly before this node enters
## the tree in headless tests; production leaves this null and [method
## _ready] resolves it against the real Autoload.
var resource_item_database: Object = null

## Current boot state (ADR-0005). Read-only from outside this class -- see
## [method get_boot_state].
var _boot_state: BootState = BootState.WAITING_FOR_DATABASE

## Scene/World Management Story 001 (ADR-0001 + ADR-0013): the Valley scene
## this World Root attaches as its child at boot
## [TR-scene-world-management-034] [TR-scene-world-management-035]. Wired via
## [code]GameWorld.tscn[/code]'s Inspector in production to [code]Valley.tscn[/code].
## Deliberately optional -- left null, [method _attach_valley] is a no-op, so
## the existing DI/boot-gate-only test suites (which predate this story and
## never set this field) continue to construct a bare [code]GameWorld[/code]
## and boot to [constant BootState.ACTIVE] unaffected.
@export var valley_scene: PackedScene = null

## Runtime instance of [member valley_scene], once [method _attach_valley]
## has run. Null until then, and null forever if [member valley_scene] was
## never wired. See [method get_valley].
var _valley: Node = null


func _ready() -> void:
	if resource_item_database == null:
		resource_item_database = get_node_or_null(^"/root/ResourceItemDatabase")
	assert(
		resource_item_database != null,
		"GameWorld requires a ResourceItemDatabase-shaped dependency (assign"
		+ " a mock in tests; the real Autoload is registered since rid-002) before"
		+ " the boot gate can run"
	)
	_boot_state = BootState.WAITING_FOR_DATABASE
	@warning_ignore("unsafe_method_access")
	var database_already_ready: bool = resource_item_database.is_ready()
	if database_already_ready:
		_on_database_settled(true, [])
	else:
		@warning_ignore("unsafe_property_access")
		resource_item_database.validation_complete.connect(
			func(result: Dictionary) -> void:
				_on_database_settled(bool(result["success"]), result["issues"] as Array),
			CONNECT_ONE_SHOT
		)


## Returns the current boot state (ADR-0005) -- the test/observability seam
## for the gate's progress.
func get_boot_state() -> BootState:
	return _boot_state


## Attaches [member valley_scene] as a child of this World Root
## (TR-scene-world-management-034/035/038). Uses ONLY plain [method
## Node.add_child] -- never [code]change_scene_to_file[/code]/
## [code]change_scene_to_packed[/code]/[code]reload_current_scene[/code],
## nor ever a direct [member SceneTree.current_scene] assignment (all
## forbidden, TR-scene-world-management-037) -- this World Root node itself
## is never replaced or freed by this call (TR-scene-world-management-038).
##
## Gated at story 002 (AC17a/AC17b, ADR-0005 host relationship): called
## exactly once, from [method _on_database_settled]'s SUCCESS path only, at
## the start of WIRING -- before the injected-tier [code]setup()[/code] sweep
## (Implementation Notes: attach the Valley, THEN sweep injected-tier
## [code]setup()[/code], so Building System / Villager AI initialize only
## after the Valley exists -- AC17a holds by construction). On a Resource &
## Item Database `Failed` outcome, [method _on_database_settled] returns
## before this method is ever called -- no empty-palette Valley is ever
## attached [TR-scene-world-management-004]. A null [member valley_scene]
## (the existing DI/boot-gate-substrate tests that predate this story) is a
## no-op, never an error.
func _attach_valley() -> void:
	if valley_scene == null:
		return
	_valley = valley_scene.instantiate()
	add_child(_valley)


## Returns the runtime Valley instance attached by [method _attach_valley],
## or null if none was ever attached (see that method's doc comment).
func get_valley() -> Node:
	return _valley


## Settles the boot gate on the database dependency's Ready/Failed outcome
## (ADR-0005 Decision §3). On failure: HALTED, [signal boot_halted] fires,
## [method _attach_valley] is NEVER called -- no empty-palette Valley
## (Scene/World Management story 002, AC17b) -- and NO injected-tier
## [code]setup()[/code] is ever called -- terminal. On success: WIRING, the
## Valley is attached FIRST (story 002 -- the scene-topology reaction to this
## gate), THEN every injected-tier module's [code]setup()[/code] runs (until/
## unless one halts on a BLOCKING config invariant -- ADR-0002, see [method
## _setup_injected_tier]), then ACTIVE -- unless that WIRING pass already
## settled HALTED, in which case ACTIVE is never reached either.
func _on_database_settled(success: bool, issues: Array) -> void:
	if not success:
		_boot_state = BootState.HALTED
		_show_boot_halt_screen(issues)
		return
	_boot_state = BootState.WIRING
	_attach_valley()
	_setup_injected_tier()
	if _boot_state != BootState.HALTED:
		_boot_state = BootState.ACTIVE


## Calls [code]setup()[/code] on every wired injected-tier module, in array
## order. This is the ONLY sanctioned call site for injected-tier
## [code]setup()[/code] invocation (ADR-0005) -- no module may call its own
## [code]setup()[/code] from its own [method _ready]. Only ever reached from
## [method _on_database_settled]'s success path.
##
## Story 003 addition (ADR-0002): immediately after each module's
## [code]setup()[/code], duck-types an optional
## [code]get_boot_blocking_issues() -> Array[String][/code] getter. A
## non-empty result -- a GDD-declared BLOCKING config invariant failure --
## reuses the exact same terminal halt path as a RID Failed outcome and
## stops calling further modules' [code]setup()[/code] (terminal, no
## recovery, matching ADR-0005's existing halt semantics).
func _setup_injected_tier() -> void:
	for module: Node in injected_tier_modules:
		assert(
			module.has_method(&"setup"),
			"GameWorld.injected_tier_modules contains a module without setup(): %s" % module.name
		)
		module.setup()
		if module.has_method(&"get_boot_blocking_issues"):
			@warning_ignore("unsafe_method_access")
			var blocking_issues: Array[String] = module.get_boot_blocking_issues()
			if not blocking_issues.is_empty():
				_boot_state = BootState.HALTED
				_show_boot_halt_screen(blocking_issues)
				return


## Fires [signal boot_halted] with the reported validation issues. The
## concrete full-screen presentation is scene-world-management's own story
## to build (see class doc comment) -- this story's responsibility ends at
## firing the hook and guaranteeing no [code]setup()[/code] call happened.
func _show_boot_halt_screen(issues: Array) -> void:
	boot_halted.emit(issues)
