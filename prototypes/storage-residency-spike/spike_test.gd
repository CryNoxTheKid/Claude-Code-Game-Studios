# ADR-0015 storage/residency spike — throwaway prototype code.
# Validates (or refutes) the five gate criteria in
# docs/architecture/adr-0015-large-world-storage-residency.md "Validation
# Criteria" against a synthetic 16,000x16,000x32 world. Data layer only — no
# rendering/meshing (ADR-0014 unaffected, unexercised here).
#
# Usage: Godot_v4.7-stable_win64_console.exe --headless --path
#   F:/Neues_Spiel/prototypes/storage-residency-spike res://SpikeTest.tscn
#
# Design choices made for this spike (see README.md for the full write-up):
#   - region_size_chunks = 32 (1024 chunks/region, 512 cells/region axis)
#   - eviction policy = distance/membership-based staggered eviction, not LRU
#   - ROUND 2 REVISION: page-in/evict budgets are now TIME-based
#     (page_budget_ms = evict_budget_ms = 4.0 ms/frame, tunable below),
#     replacing round 1's fixed 2-items/frame count that was found to
#     under-provision badly once camera speed rose. Async region I/O +
#     regen prefetch (ADR-0015 Decision §6) is now the DEFAULT, not just a
#     comparison toggle — round 1 found it cuts average tick cost ~4x.
#   - camera speed: round 2 measures BOTH the game's actual real max pan
#     speed (144 cells/sec, derived from camera_input.gd — see below) and
#     round 1's 120 cells/sec stress assumption, side by side.
extends Node

const ResidencyManagerScript := preload("res://residency_manager.gd")
const TerrainGenScript := preload("res://terrain_gen.gd")
const SpikeMetricsScript := preload("res://metrics.gd")

const CHUNK := 16
const MAX_Y := 32
const WORLD_SIZE := 16000
const CHUNKS_PER_AXIS := WORLD_SIZE / CHUNK          # 1000
const VIEW_RADIUS_CHUNKS := 24                       # ADR-0014 view_radius_chunks
const SETTLEMENT_RADIUS_CHUNKS := 8                  # bounded settlement-core (ADR-0007 nav-region scale)
const SETTLEMENT_ANCHOR := Vector2i(500, 500)        # world-center chunk
const PAGE_BUDGET_MS := 4.0                          # ROUND 2: time budget, not item count — leaves ~12ms for game work at 60 FPS
const EVICT_BUDGET_MS := 4.0                         # ROUND 2: same rationale, symmetric knob
const FRAME_BUDGET_USEC := 16600                     # 16.6 ms
const MEMORY_CEILING_BYTES := 4 * 1024 * 1024 * 1024

# REAL MAX CAMERA SPEED — derived from prototypes/last-seal-vertical-slice/
# camera_input.gd's _update_pan(): pan = input_dir.normalized() *
# PAN_SPEED_FACTOR * _distance * delta, i.e. steady-state speed (units/sec)
# = PAN_SPEED_FACTOR * _distance. input_dir is always normalized (length 1
# even for diagonal WASD combos), so direction never changes the magnitude.
# Speed is maximized at maximum zoom-out (_distance = DISTANCE_MAX), since
# pan scales linearly with distance (a deliberate "same angular pan feel at
# any zoom" design). PAN_SPEED_FACTOR = 1.2, DISTANCE_MAX = 120.0 (world
# units == cells, ADR-0014/0015's 1-unit-per-cell convention) =>
#   real max speed = 1.2 * 120.0 = 144.0 cells/sec
# Notably HIGHER than round 1's 120 cells/sec "aggressive stress"
# assumption — the real game's fastest achievable pan is not a rare edge
# case relative to what round 1 tested, it's slightly beyond it.
const REAL_MAX_CAMERA_SPEED_CELLS_PER_SEC := 144.0
const STRESS_CAMERA_SPEED_CELLS_PER_SEC := 120.0     # round 1's value, kept for a direct before/after comparison
const ASSUMED_FRAME_HZ := 60.0

const CORRIDOR_Z := WORLD_SIZE / 2                   # 8000 — full-span straight line
const CORRIDOR_X_MIN := 8
const CORRIDOR_X_MAX := WORLD_SIZE - 9               # 15991
const NUM_PASSES := 4                                # 4 one-way crossings ~= 3996 chunks travelled

const MEMORY_SAMPLE_INTERVAL := 25                   # ticks between MEMORY_STATIC samples
const WRITE_INJECT_INTERVAL := 50                    # simulated far-write activity during travel (dig orders)

const NUM_C3_CHUNKS := 20
const NUM_C5_MUTATED := 30
const NUM_C5_PRISTINE := 10
const WRITES_PER_CHUNK := 5
const MARKER_VALUE_C3 := 200
const MARKER_VALUE_C5 := 201

var region_dir: String
var residency: ResidencyManager   # C3/C5 only — speed-independent correctness checks
var terrain_gen := TerrainGenScript.new()
var metrics := SpikeMetricsScript.new()

var results: Dictionary = {}   # criterion key -> {pass: bool, detail: String}


func _ready() -> void:
	region_dir = ProjectSettings.globalize_path("res://regions")
	DirAccess.make_dir_recursive_absolute(region_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://results"))
	_clean_region_dir()

	residency = ResidencyManagerScript.new()
	residency.setup(region_dir, VIEW_RADIUS_CHUNKS, SETTLEMENT_RADIUS_CHUNKS, SETTLEMENT_ANCHOR, PAGE_BUDGET_MS, EVICT_BUDGET_MS, true)

	metrics.record("meta/world", "%dx%dx%d" % [WORLD_SIZE, MAX_Y, WORLD_SIZE])
	metrics.record("meta/region_size_chunks", str(ResidencyManagerScript.REGION_SIZE_CHUNKS))
	metrics.record("meta/view_radius_chunks", str(VIEW_RADIUS_CHUNKS))
	metrics.record("meta/settlement_radius_chunks", str(SETTLEMENT_RADIUS_CHUNKS))
	metrics.record("meta/page_budget_ms", str(PAGE_BUDGET_MS))
	metrics.record("meta/evict_budget_ms", str(EVICT_BUDGET_MS))
	metrics.record("meta/use_async_io", "true")
	metrics.record("meta/real_max_camera_speed_cells_per_sec", str(REAL_MAX_CAMERA_SPEED_CELLS_PER_SEC))
	metrics.record("meta/stress_camera_speed_cells_per_sec", str(STRESS_CAMERA_SPEED_CELLS_PER_SEC))
	metrics.record("meta/settlement_resident_at_boot", str(residency.resident_count()))

	await _run()


func _clean_region_dir() -> void:
	var d := DirAccess.open(region_dir)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir():
			d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()


func _random_chunk(rng: RandomNumberGenerator) -> Vector2i:
	for _attempt in 1000:
		var cc := Vector2i(rng.randi_range(0, CHUNKS_PER_AXIS - 1), rng.randi_range(0, CHUNKS_PER_AXIS - 1))
		if maxi(absi(cc.x - SETTLEMENT_ANCHOR.x), absi(cc.y - SETTLEMENT_ANCHOR.y)) > SETTLEMENT_RADIUS_CHUNKS + 2:
			return cc
	return Vector2i(1, 1)   # unreachable given the tiny settlement footprint vs 1000x1000 chunks


func _total_region_bytes(dir: String) -> int:
	var total := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".bin"):
			var f := FileAccess.open(dir + "/" + fname, FileAccess.READ)
			if f != null:
				total += f.get_length()
				f.close()
		fname = d.get_next()
	d.list_dir_end()
	return total


func _count_region_files(dir: String) -> int:
	var count := 0
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".bin"):
			count += 1
		fname = d.get_next()
	d.list_dir_end()
	return count


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	print("PROGRESS phase=C3 (write-to-unloaded correctness — speed-independent, run once)")
	var c3 := _run_c3(rng)

	# Two FRESH ResidencyManager instances, separate region subdirectories
	# (so one run's injected writes can't contaminate the other's disk
	# state), both using ROUND 2's time-based-budget + async-by-default
	# design. C1/C2/C4 are speed-dependent, so each gets its own full
	# 4-pass corridor traverse.
	print("PROGRESS phase=travel_real (C1/C2/C4 @ real max camera speed = %.1f cells/sec)" % REAL_MAX_CAMERA_SPEED_CELLS_PER_SEC)
	var real_dir := ProjectSettings.globalize_path("res://regions_real_speed")
	var mgr_real := ResidencyManagerScript.new()
	mgr_real.setup(real_dir, VIEW_RADIUS_CHUNKS, SETTLEMENT_RADIUS_CHUNKS, SETTLEMENT_ANCHOR, PAGE_BUDGET_MS, EVICT_BUDGET_MS, true)
	var travel_real: Dictionary = await _run_travel(mgr_real, NUM_PASSES, "travel_real", REAL_MAX_CAMERA_SPEED_CELLS_PER_SEC)

	print("PROGRESS phase=travel_stress (C1/C2/C4 @ round-1 stress speed = %.1f cells/sec)" % STRESS_CAMERA_SPEED_CELLS_PER_SEC)
	var stress_dir := ProjectSettings.globalize_path("res://regions_stress_speed")
	var mgr_stress := ResidencyManagerScript.new()
	mgr_stress.setup(stress_dir, VIEW_RADIUS_CHUNKS, SETTLEMENT_RADIUS_CHUNKS, SETTLEMENT_ANCHOR, PAGE_BUDGET_MS, EVICT_BUDGET_MS, true)
	var travel_stress: Dictionary = await _run_travel(mgr_stress, NUM_PASSES, "travel_stress", STRESS_CAMERA_SPEED_CELLS_PER_SEC)

	print("PROGRESS phase=C5 (save/load round-trip — speed-independent, run once)")
	var c5 := _run_c5(rng)

	var c1_real: Dictionary = _report_speed(travel_real, "REAL", REAL_MAX_CAMERA_SPEED_CELLS_PER_SEC)
	var c1_stress: Dictionary = _report_speed(travel_stress, "STRESS", STRESS_CAMERA_SPEED_CELLS_PER_SEC)
	_report_shared(c3, c5, mgr_real, mgr_stress)

	metrics.save_csv("res://results/storage_residency_spike.csv")

	# Gating verdict uses the REAL max camera speed (the game-relevant
	# measurement) — the stress-speed result is reported alongside as
	# additional, non-gating information (matches round 1's framing: this
	# spike's job is to find the edge of the envelope, not to assume every
	# speed tested is production-representative).
	var all_pass: bool = c1_real["c1_pass"] and c1_real["c2_pass"] and results["C3"]["pass"] \
		and c1_real["c4_pass"] and results["C5"]["pass"]
	print("SPIKE_RESULT_STRESS_ONLY %s" % ("PASS" if (c1_stress["c1_pass"] and c1_stress["c2_pass"] and c1_stress["c4_pass"]) else "FAIL"))
	if all_pass:
		print("SPIKE_RESULT PASS")
		get_tree().quit(0)
	else:
		print("SPIKE_RESULT FAIL")
		get_tree().quit(1)


## C3 — write-to-unloaded-chunk correctness (ADR-0015 Validation Criteria #3).
## Mutate scattered far chunks, force eviction, re-page-in, assert
## byte-identical against a locally-computed ground truth (fresh gen +
## same writes applied directly to the array, never through the manager).
func _run_c3(rng: RandomNumberGenerator) -> Dictionary:
	var mismatches := 0
	var tested := 0
	for _i in NUM_C3_CHUNKS:
		var cc := _random_chunk(rng)
		var expected := terrain_gen.fill_chunk(cc)
		for _w in WRITES_PER_CHUNK:
			var lx := rng.randi_range(0, CHUNK - 1)
			var lz := rng.randi_range(0, CHUNK - 1)
			var ly := rng.randi_range(0, MAX_Y - 1)
			var world_cell := Vector3i(cc.x * CHUNK + lx, ly, cc.y * CHUNK + lz)
			residency.set_cell(world_cell, MARKER_VALUE_C3)
			expected[(ly * CHUNK + lz) * CHUNK + lx] = MARKER_VALUE_C3
		residency.debug_evict_chunk(cc)   # force eviction — flushes the dirty chunk to its region file
		var actual: PackedByteArray = residency.debug_read_chunk(cc)   # re-page-in
		tested += 1
		if actual != expected:
			mismatches += 1
	metrics.record("c3/tested", str(tested))
	metrics.record("c3/mismatches", str(mismatches))
	return {"tested": tested, "mismatches": mismatches}


## C1/C2/C4 — sustained straight-line travel across the corridor's full
## 16k span, several passes (~3996 chunks travelled total). One "frame" =
## one engine tick of this coroutine (no rendering/meshing runs alongside
## it — see README "Honesty notes" on why camera movement is decoupled
## from real elapsed time while residency-work timing is not).
## `mgr`, `num_passes`, and `speed_cells_per_sec` are parameterized so the
## same routine drives both the real-speed and stress-speed measurements
## (see _run()) against independent ResidencyManager instances.
func _run_travel(mgr: ResidencyManager, num_passes: int, label: String, speed_cells_per_sec: float) -> Dictionary:
	var cells_per_tick := speed_cells_per_sec / ASSUMED_FRAME_HZ
	var camera_x := float(CORRIDOR_X_MIN)
	var direction := 1.0
	var passes_done := 0
	var tick_index := 0

	var frame_usec_samples: Array = []
	var io_usec_samples: Array = []
	var regen_usec_samples: Array = []
	var mem_samples: Array = []
	var worst_frame_usec := 0
	var worst_evict_frame_usec := 0
	var eviction_active_ticks := 0

	while passes_done < num_passes:
		camera_x += direction * cells_per_tick
		if camera_x >= float(CORRIDOR_X_MAX):
			camera_x = float(CORRIDOR_X_MAX)
			direction = -1.0
			passes_done += 1
		elif camera_x <= float(CORRIDOR_X_MIN):
			camera_x = float(CORRIDOR_X_MIN)
			direction = 1.0
			passes_done += 1

		var camera_chunk := Vector2i(int(camera_x) / CHUNK, CORRIDOR_Z / CHUNK)
		var evict_count_before: int = mgr.evict_count
		var t0 := Time.get_ticks_usec()
		var timing: Dictionary = mgr.update(camera_chunk)
		var frame_usec := Time.get_ticks_usec() - t0
		tick_index += 1

		frame_usec_samples.append(frame_usec)
		if frame_usec > worst_frame_usec:
			worst_frame_usec = frame_usec
		# Genuine eviction activity = evict_count actually changed this tick
		# (checking timing["evict_usec"] > 0 is NOT reliable: even a no-op
		# pass through the evict block measures a nonzero usec delta from
		# timer-call overhead alone — found during this spike's first run).
		if mgr.evict_count > evict_count_before:
			eviction_active_ticks += 1
			if frame_usec > worst_evict_frame_usec:
				worst_evict_frame_usec = frame_usec
		if int(timing["io_usec"]) > 0:
			io_usec_samples.append(int(timing["io_usec"]))
		if int(timing["regen_usec"]) > 0:
			regen_usec_samples.append(int(timing["regen_usec"]))

		if tick_index % WRITE_INJECT_INTERVAL == 0:
			# Simulated far-write activity while travelling (dig orders per
			# ADR-0015 Context — "far-world writes exist and are not rare").
			# Gives C1's I/O-attribution a non-zero signal instead of the
			# degenerate all-regen case (this synthetic route otherwise
			# never mutates anything).
			var wy := 4 + (tick_index % 10)
			mgr.set_cell(Vector3i(int(camera_x), wy, CORRIDOR_Z), 250)

		if tick_index % MEMORY_SAMPLE_INTERVAL == 0:
			mem_samples.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))

		if tick_index % 4000 == 0:
			print("PROGRESS travel[%s] tick=%d pass=%d/%d camera_x=%.0f resident=%d" % [
				label, tick_index, passes_done, num_passes, camera_x, mgr.resident_count()])

		await get_tree().process_frame

	var frame_stats: Dictionary = SpikeMetricsScript.stats(frame_usec_samples)
	var io_stats: Dictionary = SpikeMetricsScript.stats(io_usec_samples)
	var regen_stats: Dictionary = SpikeMetricsScript.stats(regen_usec_samples)

	var mem_peak := 0
	for m in mem_samples:
		mem_peak = maxi(mem_peak, int(m))
	var first_n: int = maxi(1, mem_samples.size() / 10)
	var last_n: int = maxi(1, mem_samples.size() / 10)
	var mem_first_avg := 0.0
	for i in first_n:
		mem_first_avg += float(mem_samples[i])
	mem_first_avg /= first_n
	var mem_last_avg := 0.0
	for i in range(mem_samples.size() - last_n, mem_samples.size()):
		mem_last_avg += float(mem_samples[i])
	mem_last_avg /= last_n

	metrics.record("%s/ticks" % label, str(tick_index))
	metrics.record("%s/frame_usec_avg" % label, "%.1f" % frame_stats["avg"])
	metrics.record("%s/frame_usec_p95" % label, "%.1f" % frame_stats["p95"])
	metrics.record("%s/frame_usec_worst" % label, "%.1f" % frame_stats["worst"])
	metrics.record("%s/io_usec_avg" % label, "%.1f" % io_stats["avg"])
	metrics.record("%s/io_usec_worst" % label, "%.1f" % io_stats["worst"])
	metrics.record("%s/io_active_ticks" % label, str(io_usec_samples.size()))
	metrics.record("%s/regen_usec_avg" % label, "%.1f" % regen_stats["avg"])
	metrics.record("%s/regen_usec_worst" % label, "%.1f" % regen_stats["worst"])
	metrics.record("%s/regen_active_ticks" % label, str(regen_usec_samples.size()))
	metrics.record("%s/eviction_active_ticks" % label, str(eviction_active_ticks))
	metrics.record("%s/worst_evict_frame_usec" % label, str(worst_evict_frame_usec))
	metrics.record("%s/mem_peak_mb" % label, "%.1f" % (mem_peak / 1048576.0))
	metrics.record("%s/mem_first_avg_mb" % label, "%.1f" % (mem_first_avg / 1048576.0))
	metrics.record("%s/mem_last_avg_mb" % label, "%.1f" % (mem_last_avg / 1048576.0))

	return {
		"ticks": tick_index,
		"frame_stats": frame_stats,
		"io_stats": io_stats,
		"io_active_ticks": io_usec_samples.size(),
		"regen_stats": regen_stats,
		"regen_active_ticks": regen_usec_samples.size(),
		"worst_frame_usec": worst_frame_usec,
		"worst_evict_frame_usec": worst_evict_frame_usec,
		"eviction_active_ticks": eviction_active_ticks,
		"mem_peak": mem_peak,
		"mem_first_avg": mem_first_avg,
		"mem_last_avg": mem_last_avg,
	}


## C5 — save/load round-trip via region files (ADR-0015 Validation Criteria
## #5). Mutate a scattering of chunks, flush (save), then read back through
## a BRAND-NEW ResidencyManager instance (simulating an app restart) pointed
## at the same on-disk region directory. Both mutated chunks (must match the
## mutated ground truth) and untouched pristine chunks (must match a fresh
## regen) must be byte-identical — no monolithic full-world pass involved.
func _run_c5(rng: RandomNumberGenerator) -> Dictionary:
	var mutated_expected: Dictionary = {}     # Vector2i -> PackedByteArray
	var pristine_expected: Dictionary = {}    # Vector2i -> PackedByteArray

	for _i in NUM_C5_MUTATED:
		var cc := _random_chunk(rng)
		if mutated_expected.has(cc):
			continue
		var expected := terrain_gen.fill_chunk(cc)
		for _w in WRITES_PER_CHUNK:
			var lx := rng.randi_range(0, CHUNK - 1)
			var lz := rng.randi_range(0, CHUNK - 1)
			var ly := rng.randi_range(0, MAX_Y - 1)
			var world_cell := Vector3i(cc.x * CHUNK + lx, ly, cc.y * CHUNK + lz)
			residency.set_cell(world_cell, MARKER_VALUE_C5)
			expected[(ly * CHUNK + lz) * CHUNK + lx] = MARKER_VALUE_C5
		mutated_expected[cc] = expected

	for _i in NUM_C5_PRISTINE:
		var cc := _random_chunk(rng)
		if mutated_expected.has(cc) or pristine_expected.has(cc):
			continue
		pristine_expected[cc] = terrain_gen.fill_chunk(cc)

	var naive_full_world_bytes := CHUNKS_PER_AXIS * CHUNKS_PER_AXIS * (CHUNK * CHUNK * MAX_Y)
	residency.flush_all()   # "save" — dirty region files only, no monolithic pass
	var bytes_written := _total_region_bytes(region_dir)
	var region_file_count := _count_region_files(region_dir)

	# Simulate an app restart: brand-new manager instance, fresh in-memory
	# state, same on-disk region directory.
	var residency2 := ResidencyManagerScript.new()
	residency2.setup(region_dir, VIEW_RADIUS_CHUNKS, SETTLEMENT_RADIUS_CHUNKS, SETTLEMENT_ANCHOR, PAGE_BUDGET_MS, EVICT_BUDGET_MS, true)

	var mismatches := 0
	var tested := 0
	for cc: Vector2i in mutated_expected:
		var actual: PackedByteArray = residency2.debug_read_chunk(cc)
		tested += 1
		if actual != mutated_expected[cc]:
			mismatches += 1
	for cc: Vector2i in pristine_expected:
		var actual: PackedByteArray = residency2.debug_read_chunk(cc)
		tested += 1
		if actual != pristine_expected[cc]:
			mismatches += 1

	metrics.record("c5/mutated_count", str(mutated_expected.size()))
	metrics.record("c5/pristine_count", str(pristine_expected.size()))
	metrics.record("c5/tested", str(tested))
	metrics.record("c5/mismatches", str(mismatches))
	metrics.record("c5/bytes_written", str(bytes_written))
	metrics.record("c5/naive_full_world_bytes", str(naive_full_world_bytes))
	metrics.record("c5/region_file_count", str(region_file_count))

	return {
		"tested": tested,
		"mismatches": mismatches,
		"mutated_count": mutated_expected.size(),
		"pristine_count": pristine_expected.size(),
		"bytes_written": bytes_written,
		"naive_full_world_bytes": naive_full_world_bytes,
		"region_file_count": region_file_count,
		"residency2": residency2,
	}


## Reports C1/C2/C4 (the speed-dependent criteria) for ONE travel run,
## tagged with a speed label ("REAL" / "STRESS") so both sets print side by
## side without overwriting each other. Only the "REAL" call's results are
## used for the official results["C1"]/["C2"]/["C4"] (and hence
## SPIKE_RESULT) — see _run()'s gating comment.
func _report_speed(travel: Dictionary, speed_label: String, speed_cells_per_sec: float) -> Dictionary:
	# --- C1: page-in latency at the streaming edge ---
	var c1_pass: bool = int(travel["worst_frame_usec"]) <= FRAME_BUDGET_USEC
	var c1_detail := "worst=%.2fms p95=%.2fms avg=%.2fms io_worst=%.2fms io_avg=%.2fms regen_worst=%.2fms ticks=%d speed=%.1fcells_per_sec budget=16.6ms" % [
		float(travel["worst_frame_usec"]) / 1000.0,
		float(travel["frame_stats"]["p95"]) / 1000.0,
		float(travel["frame_stats"]["avg"]) / 1000.0,
		float(travel["io_stats"]["worst"]) / 1000.0,
		float(travel["io_stats"]["avg"]) / 1000.0,
		float(travel["regen_stats"]["worst"]) / 1000.0,
		int(travel["ticks"]),
		speed_cells_per_sec,
	]
	print("SPIKE C1[%s] %s %s" % [speed_label, "PASS" if c1_pass else "FAIL", c1_detail])

	# --- C2: memory ceiling under sustained travel ---
	var mem_peak: int = travel["mem_peak"]
	var mem_first: float = travel["mem_first_avg"]
	var mem_last: float = travel["mem_last_avg"]
	# "Flat" tolerance (documented spike judgment call, README): last-decile
	# average resident memory must not exceed 1.5x the first-decile average.
	var flat: bool = mem_first <= 0.0 or mem_last <= mem_first * 1.5
	var c2_pass: bool = mem_peak <= MEMORY_CEILING_BYTES and flat
	var c2_detail := "peak=%.1fMB ceiling=4096MB first10pct=%.1fMB last10pct=%.1fMB flat=%s" % [
		mem_peak / 1048576.0, mem_first / 1048576.0, mem_last / 1048576.0, str(flat),
	]
	print("SPIKE C2[%s] %s %s" % [speed_label, "PASS" if c2_pass else "FAIL", c2_detail])

	# --- C4: eviction under budget (no unload-burst hitch) ---
	var c4_pass: bool = int(travel["worst_evict_frame_usec"]) <= FRAME_BUDGET_USEC
	var c4_detail := "worst_eviction_active_tick=%.2fms eviction_active_ticks=%d evict_budget_ms=%.1f" % [
		float(travel["worst_evict_frame_usec"]) / 1000.0, int(travel["eviction_active_ticks"]), EVICT_BUDGET_MS,
	]
	print("SPIKE C4[%s] %s %s" % [speed_label, "PASS" if c4_pass else "FAIL", c4_detail])

	if speed_label == "REAL":
		results["C1"] = {"pass": c1_pass, "detail": c1_detail}
		results["C2"] = {"pass": c2_pass, "detail": c2_detail}
		results["C4"] = {"pass": c4_pass, "detail": c4_detail}

	return {"c1_pass": c1_pass, "c2_pass": c2_pass, "c4_pass": c4_pass}


## Reports C3/C5 (speed-independent, run once) + aggregate totals across
## ALL manager instances used this run (main residency + C5's restart
## instance + both speed-travel managers).
func _report_shared(c3: Dictionary, c5: Dictionary, mgr_real: ResidencyManager, mgr_stress: ResidencyManager) -> void:
	# --- C3: write-to-unloaded-chunk correctness ---
	var c3_pass: bool = int(c3["mismatches"]) == 0
	var c3_detail := "tested=%d mismatches=%d" % [c3["tested"], c3["mismatches"]]
	results["C3"] = {"pass": c3_pass, "detail": c3_detail}
	print("SPIKE C3 %s %s" % ["PASS" if c3_pass else "FAIL", c3_detail])

	# --- C5: save/load round-trip via region files ---
	var c5_pass: bool = int(c5["mismatches"]) == 0
	var naive_gb: float = float(c5["naive_full_world_bytes"]) / 1073741824.0
	var written_mb: float = float(c5["bytes_written"]) / 1048576.0
	var c5_detail := "tested=%d(mutated=%d,pristine=%d) mismatches=%d bytes_written=%.2fMB naive_full_world=%.2fGB region_files=%d" % [
		c5["tested"], c5["mutated_count"], c5["pristine_count"], c5["mismatches"], written_mb, naive_gb, c5["region_file_count"],
	]
	results["C5"] = {"pass": c5_pass, "detail": c5_detail}
	print("SPIKE C5 %s %s" % ["PASS" if c5_pass else "FAIL", c5_detail])

	# --- Aggregate reporting (not one of the 5 gated criteria) ---
	var residency2: ResidencyManager = c5["residency2"]
	var total_page_ins: int = residency.page_in_count + residency2.page_in_count + mgr_real.page_in_count + mgr_stress.page_in_count
	var total_regen: int = residency.regen_count + residency2.regen_count + mgr_real.regen_count + mgr_stress.regen_count
	var total_load: int = residency.load_count + residency2.load_count + mgr_real.load_count + mgr_stress.load_count
	var disk_footprint := _total_region_bytes(region_dir) + _total_region_bytes(mgr_real.region_dir) + _total_region_bytes(mgr_stress.region_dir)
	print("SPIKE_AGGREGATE page_ins=%d regen=%d load=%d regen_pct=%.2f disk_footprint_mb=%.2f" % [
		total_page_ins, total_regen, total_load,
		100.0 * total_regen / float(maxi(1, total_page_ins)), disk_footprint / 1048576.0,
	])
	metrics.record("aggregate/page_ins", str(total_page_ins))
	metrics.record("aggregate/regen", str(total_regen))
	metrics.record("aggregate/load", str(total_load))
	metrics.record("aggregate/disk_footprint_mb", "%.2f" % (disk_footprint / 1048576.0))
