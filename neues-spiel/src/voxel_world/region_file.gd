## On-disk region file (Story vox-010, ADR-0015 Decision §2/§6) -- one file
## per fixed [member VoxelWorldConfig.region_size_chunks] x
## [member VoxelWorldConfig.region_size_chunks] block of chunk columns.
##
## Format: a fixed header of `slots_per_region` int64 byte offsets (`0` ==
## chunk absent -- pristine/regenerable, ADR-0015 Decision §5 -- never
## written), followed by fixed-size `chunk_payload_bytes` chunk payloads,
## appended in first-write order and overwritten IN PLACE on a later mutation
## of the same chunk (every payload is the same fixed size, so no reflow is
## ever needed). A region that never has a dirty chunk never gets a file on
## disk at all (Decision §5) -- [method _ensure_header] never creates the
## file itself; only [method write_chunk] does, on its own first call.
##
## Per-region header I/O ([method _ensure_header]) is the ONE sanctioned
## synchronous disk operation in Voxel World's residency tier (ADR-0015
## Decision §6) -- it runs exactly once per instance (guarded by [member
## _header_loaded]), never per-tick; [member header_load_count] exists purely
## so a test can observe that guarantee directly (TR-voxel-world-053, story
## QA plan AC-3). Every other region operation in THIS story
## (`has_chunk`/`read_chunk`/`write_chunk`'s own payload I/O) is ALSO
## synchronous today -- moving it onto a `WorkerThreadPool` is Story 011's
## explicit scope, layered behind this same class's public contract.
##
## `RefCounted`, not `Resource` -- an internal storage-tier handle, never
## authored/serialized/shared as project data. Unlike this directory's other
## `RefCounted` value objects ([CellContents], [CellChangeRecord], etc.) this
## one is intentionally stateful/mutable and long-lived: [VoxelWorldGrid]
## caches exactly one instance per region for its own lifetime so the header
## is never re-read.
##
## Reference-only note: `prototypes/storage-residency-spike/region_file.gd`
## validated this exact format (header + fixed-size appended payloads, via
## `store_buffer`/`get_buffer`) at 5/5 spike criteria; this file is written
## fresh against that measured design, not copied from it (per this story's
## Engine Notes).
class_name VoxelWorldRegionFile
extends RefCounted

## Byte width of one header offset entry (`FileAccess.store_64`/`get_64`).
const HEADER_ENTRY_BYTES: int = 8

## This region's on-disk (or not-yet-created) file path.
var path: String

## Number of chunk slots in this region (`region_size_chunks^2`) -- the
## caller computes and passes this in; this class has no knowledge of chunk-
## coordinate geometry itself.
var slots_per_region: int

## Fixed serialized byte length of one chunk's payload -- constant for a
## given [VoxelWorldConfig] (depends only on that config's chunk cell count),
## passed in by the caller ([method VoxelWorldGrid._chunk_payload_bytes]).
var chunk_payload_bytes: int

## Incremented exactly once per [method _ensure_header] call that actually
## runs past its cache guard (never on a repeat call) -- the test-observable
## proof that header I/O happens exactly once per region (TR-voxel-world-053,
## story QA plan AC-3).
var header_load_count: int = 0

## Per-slot byte offset into this region's file body; `0` means "absent"
## (pristine/regenerable). Populated by [method _ensure_header].
var _offsets: PackedInt64Array = PackedInt64Array()

## True once [method _ensure_header] has run for this instance.
var _header_loaded: bool = false

## Next unused append offset in this region's file body -- starts right after
## the header, advances by [member chunk_payload_bytes] each time a
## previously-absent slot is written for the first time.
var _next_append_offset: int = 0


func _init(p_path: String, p_slots_per_region: int, p_chunk_payload_bytes: int) -> void:
	path = p_path
	slots_per_region = p_slots_per_region
	chunk_payload_bytes = p_chunk_payload_bytes


## True if [param slot] holds a persisted chunk payload (a non-zero header
## offset) -- false for a pristine/never-mutated slot. Triggers [method
## _ensure_header] (a no-op past the first call).
func has_chunk(slot: int) -> bool:
	_ensure_header()
	return _offsets[slot] != 0


## Reads [param slot]'s [member chunk_payload_bytes]-sized payload. Caller
## MUST have already confirmed [method has_chunk] is true for this slot --
## this method does not itself check.
func read_chunk(slot: int) -> PackedByteArray:
	_ensure_header()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(
		f != null,
		"VoxelWorldRegionFile.read_chunk: could not open %s for read (%s)" % [path, FileAccess.get_open_error()]
	)
	f.seek(_offsets[slot])
	var data: PackedByteArray = f.get_buffer(chunk_payload_bytes)
	f.close()
	return data


## Writes (or overwrites in place -- every payload is the same fixed [member
## chunk_payload_bytes] size) [param slot]'s payload and updates its header
## entry, creating this region's file (header-only, all-zero offsets) on the
## very first write to it (and its parent directory, if missing). Returns
## `false` (and `push_error`s, never silently swallows -- Foundation Layer's
## "detect, push_error, return false" precedent, ADR-0012) on any file-I/O
## failure; returns `true` on success.
func write_chunk(slot: int, data: PackedByteArray) -> bool:
	_ensure_header()
	if not FileAccess.file_exists(path):
		var dir_result: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if dir_result != OK:
			push_error("VoxelWorldRegionFile.write_chunk: could not create directory for %s (error %s)" % [path, dir_result])
			return false
		var create_f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if create_f == null:
			push_error("VoxelWorldRegionFile.write_chunk: could not create %s (%s)" % [path, FileAccess.get_open_error()])
			return false
		for i in slots_per_region:
			if not create_f.store_64(0):
				push_error("VoxelWorldRegionFile.write_chunk: failed writing header slot %d in %s" % [i, path])
				create_f.close()
				return false
		create_f.close()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		push_error("VoxelWorldRegionFile.write_chunk: could not open %s for read/write (%s)" % [path, FileAccess.get_open_error()])
		return false
	var offset: int = _offsets[slot]
	if offset == 0:
		offset = _next_append_offset
		_offsets[slot] = offset
		_next_append_offset += chunk_payload_bytes
	f.seek(offset)
	if not f.store_buffer(data):
		push_error("VoxelWorldRegionFile.write_chunk: failed writing payload for slot %d in %s" % [slot, path])
		f.close()
		return false
	f.seek(slot * HEADER_ENTRY_BYTES)
	if not f.store_64(offset):
		push_error("VoxelWorldRegionFile.write_chunk: failed updating header for slot %d in %s" % [slot, path])
		f.close()
		return false
	f.close()
	return true


## Reads (or, for a not-yet-existing file, initializes an all-absent) header
## exactly once per instance -- see class doc comment and [member
## header_load_count]. A missing file is NOT created here (see [method
## write_chunk]) -- "a region that never has a dirty chunk never gets a file
## on disk at all."
func _ensure_header() -> void:
	if _header_loaded:
		return
	_offsets.resize(slots_per_region)
	var header_bytes: int = slots_per_region * HEADER_ENTRY_BYTES
	_next_append_offset = header_bytes
	if FileAccess.file_exists(path):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		assert(f != null, "VoxelWorldRegionFile._ensure_header: could not open %s for read (%s)" % [path, FileAccess.get_open_error()])
		for i in slots_per_region:
			_offsets[i] = f.get_64()
		_next_append_offset = maxi(header_bytes, f.get_length())
		f.close()
	header_load_count += 1
	_header_loaded = true
