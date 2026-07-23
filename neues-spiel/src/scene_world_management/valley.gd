## The Valley scene (Scene/World Management Story 001, ADR-0001 + ADR-0013).
##
## A thin, self-contained hosting container -- NOT an injected-tier DI module
## in its own right (it owns no [method setup] and takes no part in the boot
## gate, ADR-0005). Its sole responsibility is scene TOPOLOGY: it is the
## child the World Root ([GameWorld]) attaches at boot
## [TR-scene-world-management-034], and it is the structural PARENT every
## Foundation/Core system that needs a stable session-lifetime root attaches
## under [TR-scene-world-management-035] [TR-scene-world-management-036] --
## a hosting relationship, not a data dependency: this class never calls any
## hosted child's [code]setup()[/code]. [GameWorld]'s
## [code]_setup_injected_tier()[/code] remains the ONLY sanctioned call site
## for that (ADR-0005) -- wiring a hosted child into that array, if/when its
## own epic's boot-integration story needs it, is out of this story's scope.
##
## Hosted children landed by this story -- both already exist as
## injected-tier modules per their own epics, and are wired here purely
## structurally (config assigned so the node is inspector-sane; `setup()`
## is deliberately never called from here): [VoxelWorldGrid], [CameraInput].
##
## Two of the GDD's four named hosted systems are deliberately NOT structural
## children here -- by design, not omission:
##   - Time & Tick System is Autoload-tier (ADR-0001; `neues-spiel/CONTRACTS.md`
##     §1) -- it is never a scene child of anything, including Valley. This is
##     a standing architectural fact predating this story, not a gap it
##     introduces.
##   - Villager AI & Behavior has no landed code yet (its own epic's story 001
##     has not been implemented) -- it cannot be attached until that epic
##     lands. This story's Dependencies section does not name that epic, so
##     it does not block on it.
class_name Valley
extends Node3D

## Hosted Voxel World / Grid Data instance (ADR-0001 injected-tier module;
## `voxel-world` epic, already-landed story vox-001). Structural child only
## -- see the class doc comment's hosting-vs-DI distinction.
@onready var _voxel_world: VoxelWorldGrid = $VoxelWorldGrid

## Hosted Camera & Input instance (ADR-0001 injected-tier module;
## `camera-input` epic, already-landed story cam-001/002). Structural child
## only -- see [member _voxel_world]'s doc comment.
@onready var _camera_input: CameraInput = $CameraInput


## Returns the hosted Voxel World / Grid Data instance.
func get_voxel_world() -> VoxelWorldGrid:
	return _voxel_world


## Returns the hosted Camera & Input instance.
func get_camera_input() -> CameraInput:
	return _camera_input
