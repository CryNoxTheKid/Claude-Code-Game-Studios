# VERTICAL SLICE - NOT FOR PRODUCTION
# Headless E2E loop test: build hut -> bed -> room recognized -> villager
# builds, sleeps in bed, recovers, wakes. Drives simulation by emitting ticks
# directly (natural ticks disabled via pause). Exits 0 on PASS, 1 on FAIL.
extends Node

const GameWorldScene := preload("res://GameWorld.tscn")

var gw: Node3D
var _room_recognized := false
var _room_cells: Array = []
var _bed_sheltered := false
var _slept := false
var _woke := false
var _fail := false


func _ready() -> void:
	gw = GameWorldScene.instantiate()
	add_child(gw)
	await get_tree().process_frame
	TimeTickSystem.set_paused(true)  # we drive ticks manually
	gw.build_validation.room_recognized.connect(func(cells: Array, _c: bool) -> void:
		_room_recognized = true
		_room_cells = cells)
	gw.build_validation.shelter_status_changed.connect(func(_cell: Vector3i, sheltered: bool) -> void:
		if sheltered:
			_bed_sheltered = true)
	_run()


func _run() -> void:
	var vw: Node3D = gw.voxel_world
	var bs: Node3D = gw.building_system
	var va: Node3D = gw.villager_ai
	var nm: Node = gw.needs_mood

	var ids: Array = va.get_villager_ids()
	_check(ids.size() == 3, "three villagers spawned (Hilda, Bruno, Mira)")
	var vid: int = ids[0]
	var spawn: Vector3i = va.get_info(vid)["cell"]
	print("TEST villager %s at %s" % [va.get_info(vid)["name"], spawn])

	# --- find a flat 5x5 site near the villager ---
	var site: Vector3i = _find_flat_site(vw, spawn)
	_check(site != Vector3i(-1, -1, -1), "flat 5x5 build site found near spawn")
	var h: int = site.y
	print("TEST hut site at %s" % site)

	# --- commit hut blueprints: perimeter walls h..h+2 (one door column open), roof 5x5 at h+3 ---
	var wall_cells: Array[Vector3i] = []
	for i in 5:
		for j in 5:
			var edge: bool = i == 0 or i == 4 or j == 0 or j == 4
			if not edge:
				continue
			if i == 2 and j == 0:
				continue  # door gap column (full height) on the -z wall
			for dy in 3:
				wall_cells.append(Vector3i(site.x + i, h + dy, site.z + j))
	var roof_cells: Array[Vector3i] = []
	for i in 5:
		for j in 5:
			roof_cells.append(Vector3i(site.x + i, h + 3, site.z + j))
	bs._create_blueprint_cells(wall_cells, "wood_block", false)
	bs._create_blueprint_cells(roof_cells, "thatch_block", false)
	var bp: Dictionary = bs.get_blueprint_cells()
	_check(bp.size() == wall_cells.size() + roof_cells.size(),
		"all %d blueprint cells committed (got %d)" % [wall_cells.size() + roof_cells.size(), bp.size()])

	# --- run ticks until construction done ---
	var ticks := await _run_ticks_until(6000, func() -> bool: return bs.get_blueprint_cells().is_empty())
	_check(ticks >= 0, "hut fully built by villager (ticks=%d)" % ticks)
	if ticks < 0:
		_dump_villager_surroundings(vw, va, vid)
		var left: Dictionary = bs.get_blueprint_cells()
		print("    remaining blueprints (%d): %s" % [left.size(), left.keys().slice(0, 12)])
	_check(vw.get_cell(Vector3i(site.x, h + 1, site.z)) > 0, "wall cell written to voxel world")
	await get_tree().process_frame  # let build_validation's deferred pass run
	await get_tree().process_frame
	_check(_room_recognized, "room recognized after roof closed (interior cells: %d)" % _room_cells.size())

	# --- place bed inside ---
	var bed_cell := Vector3i(site.x + 2, h, site.z + 2)
	bs._create_blueprint_cells([bed_cell], "bed", true)
	ticks = await _run_ticks_until(1500, func() -> bool: return bs.get_furniture_cells().has(bed_cell))
	_check(ticks >= 0, "bed built inside the room (ticks=%d)" % ticks)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_bed_sheltered or gw.build_validation.is_cell_sheltered(bed_cell), "bed classified sheltered")

	# --- drain sleep until urgent, expect villager to claim bed and sleep ---
	var t0 := Time.get_ticks_msec()
	ticks = await _run_ticks_until(4000, func() -> bool: return va.get_info(vid)["state"] == 3)
	_check(ticks >= 0, "villager reached SLEEPING (ticks=%d, %.1fs)" % [ticks, (Time.get_ticks_msec() - t0) / 1000.0])
	if ticks >= 0:
		var vcell: Vector3i = va.get_info(vid)["cell"]
		var near_bed := vcell.distance_squared_to(bed_cell) <= 4
		_check(near_bed, "sleeping at/near the bed (villager %s, bed %s)" % [vcell, bed_cell])
		_check(va.get_info(vid)["distress"] == "", "no distress while sleeping in bed")

	# --- recovery until wake ---
	ticks = await _run_ticks_until(4000, func() -> bool: return va.get_info(vid)["state"] != 3)
	_check(ticks >= 0, "villager woke up after recovery (ticks=%d)" % ticks)
	await _run_ticks_until(400, func() -> bool: return nm.get_display(vid)["band_label"] == "Happy")
	var display: Dictionary = nm.get_display(vid)
	_check(display["sleep"] >= 85.0, "sleep need recovered (%.0f)" % display["sleep"])
	_check(display["why"] == "" or display["band_label"] == "Happy", "why-slot empty when content (why='%s')" % display["why"])

	print("LOOP_TEST %s" % ("PASS" if not _fail else "FAIL"))
	get_tree().quit(1 if _fail else 0)


func _find_flat_site(vw: Node3D, near: Vector3i) -> Vector3i:
	for r in range(4, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := near.x + dx
				var z := near.z + dz
				var h: int = vw.terrain_height(x, z)
				var flat := true
				for i in 5:
					for j in 5:
						if vw.terrain_height(x + i, z + j) != h:
							flat = false
							break
					if not flat:
						break
				if flat and vw.is_in_region(Vector3i(x, h, z)) and vw.is_in_region(Vector3i(x + 4, h, z + 4)):
					return Vector3i(x, h, z)
	return Vector3i(-1, -1, -1)


# Emits ticks in batches until predicate true or budget exhausted.
# Returns ticks used, or -1 on timeout.
func _run_ticks_until(max_ticks: int, pred: Callable) -> int:
	var used := 0
	while used < max_ticks:
		for i in 10:
			TimeTickSystem.tick.emit()
			used += 1
		await get_tree().process_frame  # let per-frame batching/passes flush
		if pred.call():
			return used
		if used % 500 == 0:
			var ids: Array = gw.villager_ai.get_villager_ids()
			var info: Dictionary = gw.villager_ai.get_info(ids[0])
			print("    t=%d bp_left=%d villager state=%s cell=%s distress='%s'" % [
				used, gw.building_system.get_blueprint_cells().size(),
				info["state_label"], info["cell"], info["distress"]])
	return -1


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  OK   %s" % what)
	else:
		print("  FAIL %s" % what)
		_fail = true


func _dump_villager_surroundings(vw: Node3D, va: Node3D, vid: int) -> void:
	var VA := preload("res://villager_ai.gd")
	var c: Vector3i = va.get_info(vid)["cell"]
	print("    DUMP villager at %s standable=%s" % [c, VA.is_standable(vw, c)])
	for dy in range(-1, 4):
		var row := "      y=%+d: " % dy
		for dx in range(-2, 3):
			row += "%3d" % vw.get_cell(Vector3i(c.x + dx, c.y + dy, c.z))
		print(row + "   (x row, z=%d)" % c.z)
	for n: Vector3i in [c + Vector3i(1,0,0), c + Vector3i(-1,0,0), c + Vector3i(0,0,1), c + Vector3i(0,0,-1)]:
		print("      step %s -> standable=%s legal=%s" % [n, VA.is_standable(vw, n), VA.is_step_legal(vw, c, n)])
