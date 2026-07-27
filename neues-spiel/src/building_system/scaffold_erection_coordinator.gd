## Scaffold erection coordinator (story `building-034`, TD ruling D5 point 3:
## "The Building System subscribes to the existing `job_reported_unreachable`
## signal and owns the erection response. **The AI detects; the Building
## System builds.**").
##
## Injected-tier collaborator (ADR-0001 shared-object style, mirrors
## [ConstructionJobQueue]'s own "population-wide shared object, code-assigned"
## precedent) -- constructed once, subscribes to [signal
## ConstructionJobQueue.job_reported_unreachable] in its own `_init`, exactly
## like [VillagerOnSiteGate]/[VillagerSealPreventionGate]'s established
## "wires itself into its own predicate/signal seam from `_init`" shape.
##
## **Bound the response** (D5, required): a cell can be unreachable for
## reasons scaffolding cannot fix (walled off, no support within the
## cantilever limit). [ScaffoldErectionPlanner.plan_for_target] returning
## [method ScaffoldPlan.has_plan] `false` is a genuine no-op here -- the cell
## stays flagged unreachable (the report itself already set that), and this
## class never retries the SAME cell again ([member _served_cells] is a
## permanent per-cell latch, not a cooldown) -- never erects a structure that
## does not make the target reachable, never loops.
class_name ScaffoldErectionCoordinator
extends RefCounted

var voxel_world: VoxelWorldGrid
var scaffold_registry: Object
var build_project_registry: BuildProjectRegistry
var construction_job_queue: ConstructionJobQueue
var furniture_registry: Object
var config: ScaffoldConfig

## Every blueprint cell this coordinator has already produced a plan attempt
## for (successful or not) -- latched permanently so a repeated
## `job_reported_unreachable` for the SAME cell (the retry cadence already
## re-fires it periodically) never re-plans or double-erects.
var _served_cells: Dictionary[Vector3i, bool] = {}


func _init(
	p_voxel_world: VoxelWorldGrid,
	p_scaffold_registry: Object,
	p_build_project_registry: BuildProjectRegistry,
	p_construction_job_queue: ConstructionJobQueue,
	p_furniture_registry: Object,
	p_config: ScaffoldConfig,
) -> void:
	assert(p_voxel_world != null, "ScaffoldErectionCoordinator requires voxel_world")
	assert(p_build_project_registry != null, "ScaffoldErectionCoordinator requires build_project_registry")
	assert(p_construction_job_queue != null, "ScaffoldErectionCoordinator requires construction_job_queue")
	assert(p_config != null, "ScaffoldErectionCoordinator requires config")
	voxel_world = p_voxel_world
	scaffold_registry = p_scaffold_registry
	build_project_registry = p_build_project_registry
	construction_job_queue = p_construction_job_queue
	furniture_registry = p_furniture_registry
	config = p_config
	construction_job_queue.job_reported_unreachable.connect(_on_job_reported_unreachable)


## [signal ConstructionJobQueue.job_reported_unreachable] handler (AC1: "the
## system detects an unreachable target cell and erects scaffolding exactly
## there... automatic, on demand"). Only ever responds for a cell belonging
## to a `BUILD`-kind project (never `DIG`/`SCAFFOLD` -- Out of Scope: "Build
## projects only").
func _on_job_reported_unreachable(cell: Vector3i) -> void:
	if _served_cells.has(cell):
		return
	var owning_id: int = build_project_registry.project_at_cell(cell)
	if owning_id == -1:
		return
	var owning_project: BuildProject = build_project_registry.get_project(owning_id)
	if owning_project == null or owning_project.kind != BuildProject.Kind.BUILD:
		return
	var plan: ScaffoldPlan = ScaffoldErectionPlanner.plan_for_target(
		voxel_world, scaffold_registry, build_project_registry, furniture_registry,
		cell, config.scaffold_max_cantilever_cells
	)
	if not plan.has_plan():
		# Deliberately NOT latched. `_served_cells` used to be written before
		# this check, so a cell whose plan failed ONCE was suppressed forever —
		# even after the world changed and a plan became possible. A failed plan
		# is a "not yet", never a "never": the report seam re-fires on its own
		# throttle, and the next attempt sees a different world.
		return
	_served_cells[cell] = true
	_erect(plan, owning_id)


## D3 (RULED: Option (a)) -- a scaffold structure is its OWN `SCAFFOLD`-kind
## project, linked to its owner via [member BuildProject.owner_project_id],
## never a member of the project it serves. Registered into BOTH
## [member build_project_registry] (the reverse cell index) and [member
## construction_job_queue] (so its cells become real, worker-executed jobs,
## AC2), then released immediately -- a scaffold project needs no player
## "Bau starten" step; it is system-generated and job-eligible the instant it
## exists (AC1: "the player only draws the room").
func _erect(plan: ScaffoldPlan, owner_project_id: int) -> void:
	var scaffold_project := BuildProject.new(
		build_project_registry.allocate_project_id(), BuildProject.Kind.SCAFFOLD, owner_project_id
	)
	for scaffold_cell: Vector3i in plan.cells:
		var blueprint_cell := BlueprintCell.new(
			scaffold_cell, BlueprintCell.MicroState.PLANNED, BlueprintCell.Category.SCAFFOLD
		)
		scaffold_project.add_cell(blueprint_cell)
	build_project_registry.register_project(scaffold_project)
	construction_job_queue.add_project(scaffold_project)
	scaffold_project.release()
