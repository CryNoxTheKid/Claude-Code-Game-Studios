## Root scene script for the injected-tier dependency-injection substrate
## (ADR-0001), owned by Scene/World Management.
##
## Owns the injected-tier child modules listed in [member injected_tier_modules]
## and invokes each one's [code]setup()[/code] explicitly, once scene-file
## (Inspector) wiring has resolved -- never relying on [method _ready]
## ordering. This is the wiring rule ADR-0001 establishes: scene-file
## [code]@export[/code] references between injected-tier modules are already
## populated by the time any child's [method _ready] fires, but code-assigned
## wiring is not, so validation must live in each module's own explicitly
## callable [code]setup()[/code], invoked from here.
##
## Foundation Spine Story 001 scope note: this class stands up the DI
## wiring/[code]setup()[/code] substrate ONLY. Story 002 (ADR-0005) replaces
## the unconditional call in [method _ready] below with the BootState
## machine that gates every [code]setup()[/code] call behind
## [code]ResourceItemDatabase[/code]'s Ready/Failed outcome -- that gate is
## explicitly out of scope here.
class_name GameWorld
extends Node3D

## Ordered list of injected-tier child modules whose [code]setup()[/code]
## this root invokes. Wired via the Inspector on [code]GameWorld.tscn[/code]
## -- the array holds direct node references (resolved at scene
## deserialization, before any child's [method _ready] runs), not
## [NodePath]s, so the full wiring list is visible and editable in one
## place. Order matters when one module's [code]setup()[/code] establishes
## signal connections another module's [code]setup()[/code] depends on;
## callers control that order via this array, not via scene-tree child order.
@export var injected_tier_modules: Array[Node] = []


func _ready() -> void:
	_setup_injected_tier()


## Calls [code]setup()[/code] on every wired injected-tier module, in array
## order. This is the ONLY sanctioned call site for injected-tier
## [code]setup()[/code] invocation (ADR-0005) -- no module may call its own
## [code]setup()[/code] from its own [method _ready].
func _setup_injected_tier() -> void:
	for module: Node in injected_tier_modules:
		assert(
			module.has_method(&"setup"),
			"GameWorld.injected_tier_modules contains a module without setup(): %s" % module.name
		)
		module.setup()
