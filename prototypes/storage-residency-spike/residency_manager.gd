# Residency manager — throwaway prototype code (ADR-0015 storage/residency
# spike).
#
# Implements ADR-0015 Decision:
#   §1 resident set = camera-near window (square, ADR-0014 view radius) UNION
#      active-settlement (always-resident anchor, ADR-0007 nav-region scale)
#   §2 region files (fixed chunk-group binary files) — see region_file.gd
#   §3 load-before-write for far-world mutations (set_cell)
#   §4 save = flush of dirty region files (flush_all)
#   §5 pristine (unmutated) chunks regenerate from seed, never read from disk
#
# Eviction policy (spike's call, documented per task): distance/membership
# based, not true LRU. A chunk is queued for eviction the instant it leaves
# BOTH the camera window and the settlement set; if it re-enters need before
# its turn comes up in the staggered queue, the queued eviction is silently
# dropped (checked at pop time). This is simpler than LRU-with-timestamps,
# reuses the same "in current desired set?" check the page-in path already
# needs, and matches ADR-0014's existing staggered-unload discipline this
# ADR is required to reuse (Decision §1).
class_name ResidencyManager
extends RefCounted

const RegionFileScript := preload("res://region_file.gd")
const TerrainGenScript := preload("res://terrain_gen.gd")

const CHUNK := 16
const CHUNKS_PER_AXIS := 1000   # 16000 / 16
const REGION_SIZE_CHUNKS := 32

var view_radius_chunks: int
var settlement_radius_chunks: int
var settlement_anchor: Vector2i
# ROUND 2 REVISION (spike recommendation, now implemented): TIME-based
# budgets (milliseconds to spend draining the queue per frame), replacing
# round 1's fixed 2-items/frame count. A fixed count under-provisions
# badly once camera speed rises (round 1 finding: 12x under-provisioned at
# the stress speed tested); a time budget scales automatically with
# per-item cost and adapts to how cheap items get once async prefetch
# does the slow work off-thread.
var page_budget_ms: float
var evict_budget_ms: float
var region_dir: String

var terrain := TerrainGenScript.new()

var _resident: Dictionary = {}          # Vector2i chunk -> PackedByteArray
var _dirty: Dictionary = {}             # Vector2i chunk -> true
var _regions: Dictionary = {}           # Vector2i region -> RegionFile
var _settlement_set: Dictionary = {}    # Vector2i chunk -> true (always resident)
var _camera_window_set: Dictionary = {} # Vector2i chunk -> true (current camera window)
var _page_in_queue: Array[Vector2i] = []
var _page_in_queued: Dictionary = {}
var _evict_queue: Array[Vector2i] = []
var _evict_queued: Dictionary = {}
var _last_camera_chunk := Vector2i(-999999, -999999)

# ESCAPE HATCH (ADR-0015 Decision §6): WorkerThreadPool-backed async region
# I/O + regen, dispatched as a PREFETCH the instant a chunk is enqueued for
# page-in (not when budget finally dequeues it) — by the time the budgeted
# drain reaches it, the background task has usually already finished, so
# picking it up is a cheap dictionary read instead of a blocking disk op /
# full terrain-gen pass on the main thread. ROUND 2: now the DEFAULT (not
# just a comparison toggle) — round 1 found it cuts average tick cost ~4x
# and fully removes regen from the main thread; the time-based budget above
# governs how much of the now-cheap integration/bookkeeping work (picking
# up finished background results) happens per frame.
var use_async_io := true
var _pending_tasks: Dictionary = {}   # Vector2i chunk -> WorkerThreadPool task id
var _task_results: Dictionary = {}    # Vector2i chunk -> {data, was_load} — mutex-guarded
var _task_mutex := Mutex.new()

# metrics (cumulative across this manager's lifetime)
var page_in_count := 0
var regen_count := 0
var load_count := 0
var evict_count := 0
var flush_count := 0
var io_usec_total := 0
var regen_usec_total := 0
var last_scan_usec := 0
var last_pagein_usec := 0
var last_evict_usec := 0


func setup(region_directory: String, p_view_radius_chunks: int, p_settlement_radius_chunks: int,
		p_settlement_anchor: Vector2i, p_page_budget_ms: float, p_evict_budget_ms: float, p_use_async_io: bool = true) -> void:
	region_dir = region_directory
	view_radius_chunks = p_view_radius_chunks
	settlement_radius_chunks = p_settlement_radius_chunks
	settlement_anchor = p_settlement_anchor
	page_budget_ms = p_page_budget_ms
	evict_budget_ms = p_evict_budget_ms
	use_async_io = p_use_async_io
	DirAccess.make_dir_recursive_absolute(region_dir)
	for dz in range(-settlement_radius_chunks, settlement_radius_chunks + 1):
		for dx in range(-settlement_radius_chunks, settlement_radius_chunks + 1):
			var cc := settlement_anchor + Vector2i(dx, dz)
			if _in_world(cc):
				_settlement_set[cc] = true
	# The bounded settlement-core is a standing cost, not a streaming one
	# (ADR-0007's nav region is always live) — load it immediately, unbudgeted.
	for cc: Vector2i in _settlement_set:
		_ensure_resident(cc)


func _in_world(cc: Vector2i) -> bool:
	return cc.x >= 0 and cc.y >= 0 and cc.x < CHUNKS_PER_AXIS and cc.y < CHUNKS_PER_AXIS


func _region_of(cc: Vector2i) -> Vector2i:
	return Vector2i(cc.x / REGION_SIZE_CHUNKS, cc.y / REGION_SIZE_CHUNKS)


func _slot_of(cc: Vector2i, region: Vector2i) -> int:
	var local := cc - region * REGION_SIZE_CHUNKS
	return local.y * REGION_SIZE_CHUNKS + local.x


func _region_file(region: Vector2i) -> RefCounted:
	if _regions.has(region):
		return _regions[region]
	var path := "%s/r_%d_%d.bin" % [region_dir, region.x, region.y]
	var rf := RegionFileScript.new(path)
	_regions[region] = rf
	return rf


## Pages a chunk in if not already resident. This is the single choke point
## both the streaming path (update()) and the write path (set_cell()) route
## through — ADR-0015 §3's load-before-write rule lives here, once.
func _ensure_resident(cc: Vector2i) -> void:
	if _resident.has(cc):
		return
	page_in_count += 1
	var region := _region_of(cc)
	var rf := _region_file(region)
	var slot := _slot_of(cc, region)
	if rf.has_chunk(slot):
		var t_io := Time.get_ticks_usec()
		_resident[cc] = rf.read_chunk(slot)
		io_usec_total += Time.get_ticks_usec() - t_io
		load_count += 1
	else:
		var t_regen := Time.get_ticks_usec()
		_resident[cc] = terrain.fill_chunk(cc)
		regen_usec_total += Time.get_ticks_usec() - t_regen
		regen_count += 1


func _evict(cc: Vector2i) -> void:
	if not _resident.has(cc):
		return
	if _dirty.has(cc):
		var region := _region_of(cc)
		var rf := _region_file(region)
		var slot := _slot_of(cc, region)
		var t_io := Time.get_ticks_usec()
		rf.write_chunk(slot, _resident[cc])
		io_usec_total += Time.get_ticks_usec() - t_io
		_dirty.erase(cc)
		flush_count += 1
	_resident.erase(cc)
	evict_count += 1


## Load-before-write (ADR-0015 §3 / Key Interfaces _on_write): a write
## targeting a non-resident chunk pages it in FIRST, applies to the resident
## copy, marks dirty. Never applied blind to disk, never silently dropped.
func set_cell(cell: Vector3i, value: int) -> void:
	var cc := Vector2i(cell.x / CHUNK, cell.z / CHUNK)
	_ensure_resident(cc)
	var lx := cell.x - cc.x * CHUNK
	var lz := cell.z - cc.y * CHUNK
	var arr: PackedByteArray = _resident[cc]
	arr[(cell.y * CHUNK + lz) * CHUNK + lx] = value
	_dirty[cc] = true


## Read accessor scoped to RESIDENT chunks only (matches ADR-0015 §3's
## load-before-write guarantee, which is scoped to writes; a production
## get() would likely also page-in, but that's Voxel World's call, not this
## spike's). Returns -1 for a non-resident chunk.
func get_cell(cell: Vector3i) -> int:
	var cc := Vector2i(cell.x / CHUNK, cell.z / CHUNK)
	if not _resident.has(cc):
		return -1
	var lx := cell.x - cc.x * CHUNK
	var lz := cell.z - cc.y * CHUNK
	var arr: PackedByteArray = _resident[cc]
	return arr[(cell.y * CHUNK + lz) * CHUNK + lx]


## TEST/VERIFICATION-ONLY accessor: explicitly pages a chunk in (if absent)
## and returns its full byte array. Not part of the production-shaped
## public API — used by the spike harness to assert round-trip correctness
## (C3 / C5).
func debug_read_chunk(cc: Vector2i) -> PackedByteArray:
	_ensure_resident(cc)
	return _resident[cc]


func debug_evict_chunk(cc: Vector2i) -> void:
	_evict(cc)


func is_resident(cc: Vector2i) -> bool:
	return _resident.has(cc)


## Recomputes the desired camera window ONLY when the camera actually
## crosses a chunk boundary (the window is a pure function of camera chunk —
## re-scanning for an unchanged chunk would be wasted O(radius^2) work every
## single engine tick) and enqueues page-ins / evictions. Drains both queues
## by TIME budgets (round 2 revision — see page_budget_ms/evict_budget_ms
## above), not a fixed item count. Returns a timing breakdown (usec) for the
## caller's per-frame metrics — this is what lets C1 attribute time to
## scan vs page-in vs eviction, and (via io_usec_total delta) to I/O
## specifically.
func update(camera_chunk: Vector2i) -> Dictionary:
	var io_before := io_usec_total
	var regen_before := regen_usec_total

	var t_scan := Time.get_ticks_usec()
	if camera_chunk != _last_camera_chunk:
		_rescan_window(camera_chunk)
		_last_camera_chunk = camera_chunk
	last_scan_usec = Time.get_ticks_usec() - t_scan

	var t_page := Time.get_ticks_usec()
	var page_deadline := t_page + int(page_budget_ms * 1000.0)
	while not _page_in_queue.is_empty() and Time.get_ticks_usec() < page_deadline:
		var cc: Vector2i = _page_in_queue.pop_front()
		_page_in_queued.erase(cc)
		if _camera_window_set.has(cc) or _settlement_set.has(cc):
			if use_async_io and _pending_tasks.has(cc):
				_collect_async(cc)
			else:
				_ensure_resident(cc)
		elif _pending_tasks.has(cc):
			# no longer needed (camera reversed before its turn) — still have
			# to drain the WorkerThreadPool task so the thread pool doesn't
			# leak an unclaimed result.
			WorkerThreadPool.wait_for_task_completion(_pending_tasks[cc])
			_pending_tasks.erase(cc)
	last_pagein_usec = Time.get_ticks_usec() - t_page

	var t_evict := Time.get_ticks_usec()
	var evict_deadline := t_evict + int(evict_budget_ms * 1000.0)
	while not _evict_queue.is_empty() and Time.get_ticks_usec() < evict_deadline:
		var cc: Vector2i = _evict_queue.pop_front()
		_evict_queued.erase(cc)
		if not _camera_window_set.has(cc) and not _settlement_set.has(cc):
			_evict(cc)
	last_evict_usec = Time.get_ticks_usec() - t_evict

	return {
		"scan_usec": last_scan_usec,
		"pagein_usec": last_pagein_usec,
		"evict_usec": last_evict_usec,
		"io_usec": io_usec_total - io_before,
		"regen_usec": regen_usec_total - regen_before,
	}


# BUG FOUND AND FIXED (round 2, this exact run): dispatching a background
# task for EVERY enqueue with no concurrency cap let WorkerThreadPool's own
# internal task queue grow unbounded once demand outpaced completion
# throughput — a single _collect_async() call could then block for however
# long that backlog took to drain (observed: a 10.1-SECOND single-tick
# hitch in the uncapped version, far worse than round 1's synchronous
# worst case). This is an implementation defect in "naive unbounded
# prefetch," not a property of async I/O itself — fixed by capping how
# many tasks may be in flight at once; beyond the cap, a chunk is simply
# left undispatched and falls back to the existing synchronous path
# (_ensure_resident) when its turn comes up in the drain loop. This bounds
# the worst case to "synchronous cost of one chunk," same ceiling round 1
# already measured, while still getting the async benefit for whatever
# fraction of demand fits within the cap.
const MAX_CONCURRENT_ASYNC_TASKS := 16   # generous vs. typical core counts; a tunable knob


func _rescan_window(camera_chunk: Vector2i) -> void:
	var new_window: Dictionary = {}
	for dz in range(-view_radius_chunks, view_radius_chunks + 1):
		for dx in range(-view_radius_chunks, view_radius_chunks + 1):
			var cc := camera_chunk + Vector2i(dx, dz)
			if _in_world(cc):
				new_window[cc] = true
	for cc: Vector2i in new_window:
		if not _camera_window_set.has(cc) and not _resident.has(cc) and not _page_in_queued.has(cc):
			_page_in_queue.append(cc)
			_page_in_queued[cc] = true
			if use_async_io and not _pending_tasks.has(cc) and _pending_tasks.size() < MAX_CONCURRENT_ASYNC_TASKS:
				_dispatch_async_load(cc)
	for cc: Vector2i in _camera_window_set:
		if not new_window.has(cc) and not _settlement_set.has(cc) and not _evict_queued.has(cc):
			_evict_queue.append(cc)
			_evict_queued[cc] = true
	_camera_window_set = new_window


## ESCAPE HATCH prefetch dispatch (ADR-0015 Decision §6). Reads the region's
## header (cheap, main-thread) to know whether the chunk is present-on-disk
## or must regenerate, then hands the actual (slow) work — file read OR
## terrain gen — to a WorkerThreadPool task. The task touches no shared
## mutable state (its own FileAccess handle, its own fresh TerrainGen
## instance), so it's safe to run concurrently with main-thread work.
func _dispatch_async_load(cc: Vector2i) -> void:
	var region := _region_of(cc)
	var rf: SpikeRegionFile = _region_file(region)
	var slot := _slot_of(cc, region)
	var present: bool = rf.has_chunk(slot)
	var offset: int = rf.offset_of(slot) if present else 0
	var path := rf.path
	var task_id := WorkerThreadPool.add_task(Callable(self, "_bg_page_in").bind(cc, present, path, offset))
	_pending_tasks[cc] = task_id


## NOTE: WorkerThreadPool.wait_for_task_completion() returns an Error code,
## NOT the Callable's return value (verified empirically against 4.7 before
## relying on it — see README "Escalation path" caveats). The background
## task therefore writes its result into a mutex-guarded dictionary itself;
## the main thread reads it back AFTER wait_for_task_completion establishes
## the happens-before relationship, never concurrently.
func _bg_page_in(cc: Vector2i, present: bool, path: String, offset: int) -> void:
	var data: PackedByteArray
	var was_load: bool
	if present:
		var f := FileAccess.open(path, FileAccess.READ)
		f.seek(offset)
		data = f.get_buffer(RegionFileScript.CHUNK_BYTES)
		f.close()
		was_load = true
	else:
		# Own TerrainGen instance — never shares noise-generator state with
		# the main thread's `terrain` (or another concurrent background task's).
		var bg_terrain := TerrainGenScript.new()
		data = bg_terrain.fill_chunk(cc)
		was_load = false
	_task_mutex.lock()
	_task_results[cc] = {"data": data, "was_load": was_load}
	_task_mutex.unlock()


## Picks up an already-dispatched background task. wait_for_task_completion
## returns immediately if the task finished before its budgeted turn came up
## (the common case — that's the whole point of prefetch); it still
## correctly (if rarely) blocks if the budget outran the background thread.
func _collect_async(cc: Vector2i) -> void:
	var task_id: int = _pending_tasks[cc]
	var t_wait := Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task_id)
	_pending_tasks.erase(cc)
	_task_mutex.lock()
	var result: Dictionary = _task_results[cc]
	_task_results.erase(cc)
	_task_mutex.unlock()
	page_in_count += 1
	if result["was_load"]:
		load_count += 1
		io_usec_total += Time.get_ticks_usec() - t_wait   # ~0 in the common (already-finished) case
	else:
		regen_count += 1
	_resident[cc] = result["data"]


## Flushes every currently-dirty resident chunk to its region file WITHOUT
## evicting it from memory (a "save," not an unload). This is Decision §4:
## the save format IS the set of persisted region files.
func flush_all() -> void:
	for cc: Vector2i in _dirty.keys():
		var region := _region_of(cc)
		var rf := _region_file(region)
		var slot := _slot_of(cc, region)
		var t_io := Time.get_ticks_usec()
		rf.write_chunk(slot, _resident[cc])
		io_usec_total += Time.get_ticks_usec() - t_io
		flush_count += 1
	_dirty.clear()


func resident_count() -> int:
	return _resident.size()
