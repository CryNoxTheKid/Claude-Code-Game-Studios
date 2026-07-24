## Building System's undo/redo stack core (Story building-032, ADR-0016
## primary -- "Plan-only undo/redo: the undo stack governs the plan ONLY --
## draft cells and queued orders ... redo re-creates only still-valid
## cells, dropping invalidated ones with feedback." ADR-0012 secondary --
## the undo stack is excluded from serialization, TR-building-system-033).
##
## Models each player command (Core Rule 17: "one wall drag = one command =
## one undo step") as one plain [Array][Vector3i] entry on a bounded LIFO
## undo stack, with a matching LIFO redo stack. This story owns ONLY the
## stack mechanics named by its own Acceptance Criteria:
## - AC30/Edge Case 9: bounded depth (`undo_stack_depth`, default 50) --
##   beyond capacity the oldest command is discarded silently.
## - AC31/Edge Case 9: any new command commit clears the redo branch.
## - AC28/Edge Case 8: redo re-validates every cell of the command
##   independently via [member recreate_cell_callable]; cells that fail are
##   dropped with feedback ([signal redo_cells_dropped]); a redo where ZERO
##   cells survive is a no-op with feedback ([signal redo_no_op]) -- nothing
##   is pushed back onto the undo stack for a fully-dropped redo.
## - AC32/AC32b/Core Rule 17: the stack clears ONLY on [signal
##   GameWorld.transition_ended] with `success == true` (transition-COMPLETE)
##   -- an aborted/failed transition ([param success] `== false`) leaves
##   every command untouched, and [signal GameWorld.transition_begun] is
##   NEVER connected at all, so a begin-signal side effect on the stack is
##   structurally impossible, not merely avoided by a runtime check.
##
## **What this story deliberately does NOT own** (see the story's own Out of
## Scope section):
## - WHICH cells make up a command, and how a cell is actually canceled
##   (undo) or actually re-validated-and-recreated as a fresh blueprint
##   (redo) against [CommitPipeline]/[BuildProject]. That real behavior is
##   this class's own [member cancel_cell_callable]/[member
##   recreate_cell_callable] seam -- `Callable(cell: Vector3i) -> bool`,
##   called once per cell -- mirroring [CommitPipeline]'s own established
##   "future story wires a real Callable into this seam" pattern exactly
##   ([method CommitPipeline.set_cell_set_resolver]/[method
##   CommitPipeline.set_furniture_support_predicate]). Story 011 (the
##   plan-only invariant -- undo never reaches a Built cell) is this seam's
##   real future caller for [member cancel_cell_callable]: it supplies a
##   callable that skips (returns `false`, does nothing) any cell whose
##   [member BlueprintCell.state] is already [constant
##   BlueprintCell.MicroState.BUILT]. Story 033 (the self-write-exemption /
##   batched-write listener) is a future caller of the same general area.
##   Until either lands, a caller (a headless test, or a future
##   population-assembly story) wires its own callable directly -- exactly
##   how [CommitPipeline]'s own seams are exercised in isolation today.
## - Plan-only enforcement itself. This file's own code contains ZERO
##   references to any committed-block/Voxel-World write API (no
##   [VoxelWorldGrid] call, no [ConstructionTickLoop] call, no `set_cell(`/
##   `bulk_write(`/`clear_cell(` of any kind) -- every cell-level effect
##   this class ever produces flows exclusively through the two injected
##   `Callable`s above (this story's own "plan-only invariant hook,"
##   verified by this story's own grep-guard test). Story 011 constrains
##   WHAT those callables do; this class only guarantees WHERE they are
##   called from, and that nowhere else in this class reaches further.
##
## `Node`, not `RefCounted` -- mirrors [ToolStateMachine]'s exact injected-
## tier shape (an OPTIONAL [member game_world] dependency this class itself
## connects to inside [method setup], never asserted non-null, exactly
## [ToolStateMachine]'s own `_connect_transition_signals` guard shape): the
## transition-COMPLETE-only clear rule (AC32/AC32b) needs a live signal
## connection to [signal GameWorld.transition_ended], the same seam
## [ToolStateMachine] already established for its own Suspended entry/exit
## wiring -- this class reuses that exact pattern rather than inventing a
## second one.
class_name UndoRedoStack
extends Node

## Fires on every successful [method undo] (AC held-key-repeat edge case:
## each call is exactly one step) -- carries the UNDONE command's original
## cell list, in commit order, exactly as [method record_command] received
## it. This is the requested cancellation set, not a report of which cells
## [member cancel_cell_callable] actually canceled (that per-cell outcome is
## the callable's own concern, e.g. Story 011's future Built-cell skip).
signal command_undone(cells: Array[Vector3i])

## Fires on every [method redo] call that produces at least one surviving
## cell -- carries the SURVIVING cell subset only (never the original,
## possibly-larger command), exactly as re-created and pushed back onto the
## undo stack as a fresh command.
signal command_redone(cells: Array[Vector3i])

## Fires whenever a [method redo] call drops at least one cell because
## [member recreate_cell_callable] reported it no longer valid (Edge Case 8,
## AC28's "standard invalid-feedback") -- carries only the DROPPED subset.
## Fires alongside [signal command_redone] when some cells survive, and
## alongside [signal redo_no_op] when none do.
signal redo_cells_dropped(cells: Array[Vector3i])

## Fires whenever a [method redo] call ends with ZERO surviving cells (Edge
## Case 8: "a redo where zero cells survive is a no-op with feedback") --
## nothing is pushed back onto the undo stack for this attempt; the popped
## redo entry is fully consumed and discarded.
signal redo_no_op()

## Tuning config dependency (ADR-0002, `undo_stack_depth`,
## [TR-building-system-089]). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: UndoRedoStackConfig

## Optional injected-tier dependency (ADR-0001), mirroring
## [ToolStateMachine]'s own [member ToolStateMachine.game_world] shape
## exactly: wired via a scene file's Inspector in production once a future
## scene-assembly story attaches this node to `GameWorld.tscn`, or assigned
## directly in a headless test. Deliberately nullable -- a null value MUST
## remain a no-op, exactly as no scene-assembly story has wired a live
## [ToolStateMachine] node yet either.
@export var game_world: GameWorld = null

## Per-cell undo hook (see class doc comment) -- `Callable(cell: Vector3i)
## -> bool`. Default `Callable()` (invalid) is a permissive no-op: [method
## undo] simply skips calling it, mirroring [CommitPipeline]'s own
## `_all_cells_supported`/[member CommitPipeline._furniture_support_predicate]
## "no predicate wired => no restriction" default. Set via [method
## set_cancel_cell_callable].
var cancel_cell_callable: Callable = Callable()

## Per-cell redo re-validation hook (see class doc comment) --
## `Callable(cell: Vector3i) -> bool`, `true` meaning "still valid, recreate
## it," `false` meaning "no longer valid, drop it" (Edge Case 8, AC28).
## Default `Callable()` (invalid) treats every cell as surviving -- there is
## no validity information available at all without a wired callable,
## mirroring the same permissive-default precedent as [member
## cancel_cell_callable]. Set via [method set_recreate_cell_callable].
var recreate_cell_callable: Callable = Callable()

## The undo stack -- each entry is one command's [Array][Vector3i] cell
## list, oldest first ([Array.pop_front] discards the oldest on overflow,
## AC30). The most recent command is [Array.pop_back].
var _undo_stack: Array = []

## The redo stack -- each entry is one command's [Array][Vector3i] cell
## list, most-recently-undone last ([Array.pop_back] is the next [method
## redo] target). Cleared in full by [method record_command] (AC31) and by
## [method clear] (AC32/AC32b) -- never mutated by [method undo] beyond
## appending the command it just popped from [member _undo_stack].
var _redo_stack: Array = []

## True once [method setup] has completed at least once.
var _is_set_up: bool = false


## Explicitly callable wiring entry point (ADR-0001). Applies ADR-0002's
## clamp+warn `validate()` policy to [member config] (constructing a
## default instance if none was wired, mirroring [ConstructionTickLoop]'s
## own "config is optional at this story's isolated-test scope" tolerance),
## and connects to [member game_world]'s transition-COMPLETE signal only
## (idempotent via [method Signal.is_connected], mirroring
## [ToolStateMachine._connect_transition_signals]'s exact guard shape).
func setup() -> void:
	if config == null:
		config = UndoRedoStackConfig.new()
	for issue: String in config.validate():
		push_warning(issue)
	_connect_transition_signals()
	_is_set_up = true


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Wires [member cancel_cell_callable] (see that member's doc comment) --
## Story 011's real future caller.
func set_cancel_cell_callable(callable: Callable) -> void:
	cancel_cell_callable = callable


## Wires [member recreate_cell_callable] (see that member's doc comment).
func set_recreate_cell_callable(callable: Callable) -> void:
	recreate_cell_callable = callable


## Records a freshly-committed command (Core Rule 17: "one wall drag = one
## command = one undo step") -- [param cells] is the full cell list a single
## commit produced, in commit order. Clears the ENTIRE redo branch first
## (AC31: "any new command commit clears the redo branch"), then pushes the
## command onto the undo stack, discarding the oldest entry if the bounded
## depth ([member UndoRedoStackConfig.undo_stack_depth]) is now exceeded
## (AC30) -- both effects are observed from this ONE call, exactly as the
## story's own Edge Case demands. A future [CommitPipeline]-listening caller
## (not wired by this story) is the intended real caller; directly callable
## by tests in the meantime.
func record_command(cells: Array[Vector3i]) -> void:
	_redo_stack.clear()
	_push_undo(cells)


## Whether at least one command is currently undoable.
func can_undo() -> bool:
	return not _undo_stack.is_empty()


## Whether at least one command is currently redoable.
func can_redo() -> bool:
	return not _redo_stack.is_empty()


## Number of commands currently on the undo stack -- observability/test seam.
func get_undo_stack_size() -> int:
	return _undo_stack.size()


## Number of commands currently on the redo stack -- observability/test seam.
func get_redo_stack_size() -> int:
	return _redo_stack.size()


## Undoes the most recently recorded (or redone) command -- one call is
## exactly one undo step (a held Ctrl+Z key-repeat at OS rate therefore
## consumes exactly one step per repeat event, with neither acceleration nor
## double-consumption of a single repeat, since each repeat is its own
## discrete call into this method). Calls [member cancel_cell_callable] once
## per cell in the popped command, in order, when a callable is wired (a
## no-op skip otherwise) -- see class doc comment for why this is the
## story's own "plan-only invariant hook," not full plan-only enforcement.
## Pushes the popped command onto the redo stack and fires [signal
## command_undone]. Returns `false` (no-op) if the undo stack is empty.
func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cells: Array[Vector3i] = _undo_stack.pop_back()
	if cancel_cell_callable.is_valid():
		for cell: Vector3i in cells:
			cancel_cell_callable.call(cell)
	_redo_stack.append(cells)
	command_undone.emit(cells)
	return true


## Redoes the most recently undone command (Edge Case 8, AC28) --
## re-validates EVERY cell of the popped command independently via [member
## recreate_cell_callable] (a cell survives when the callable returns `true`
## or when no callable is wired at all -- see that member's doc comment).
## Cells that fail are dropped: [signal redo_cells_dropped] fires with
## exactly the dropped subset whenever at least one cell was dropped.
## If at least one cell survives, the SURVIVING subset is pushed onto the
## undo stack as a fresh command (subject to the same bounded-depth discard
## as [method record_command]'s own push -- see [method _push_undo]) and
## [signal command_redone] fires with that subset; this does NOT touch the
## redo branch otherwise (only a NEW command via [method record_command]
## clears it, per AC31). If ZERO cells survive, [signal redo_no_op] fires
## instead and nothing is pushed back onto the undo stack -- the popped
## entry is fully consumed and discarded, a genuine no-op (Edge Case 8: "a
## redo where zero cells survive is a no-op with feedback"). Returns `false`
## if the redo stack was empty, or if the redo was a zero-survivor no-op;
## returns `true` only when at least one cell was actually redone.
func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var cells: Array[Vector3i] = _redo_stack.pop_back()
	var survivors: Array[Vector3i] = []
	var dropped: Array[Vector3i] = []
	for cell: Vector3i in cells:
		var still_valid: bool = true
		if recreate_cell_callable.is_valid():
			still_valid = bool(recreate_cell_callable.call(cell))
		if still_valid:
			survivors.append(cell)
		else:
			dropped.append(cell)
	if not dropped.is_empty():
		redo_cells_dropped.emit(dropped)
	if survivors.is_empty():
		redo_no_op.emit()
		return false
	_push_undo(survivors)
	command_redone.emit(survivors)
	return true


## Clears both stacks in full (Core Rule 17, AC32) -- the ONLY sanctioned
## caller-visible way either stack is emptied outside normal undo/redo
## traffic. Called by [method _on_transition_ended] on transition-COMPLETE
## ([param success] `== true`) ONLY; directly callable by a future
## save/load-adjacent caller if one is ever needed, mirroring this
## codebase's "public method, real caller may not exist yet" precedent.
func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()


## Connects this instance to [member game_world]'s transition-COMPLETE
## signal ONLY -- mirrors [ToolStateMachine._connect_transition_signals]'s
## exact idempotent-guard shape, but deliberately connects [signal
## GameWorld.transition_ended] alone. [signal GameWorld.transition_begun] is
## NEVER connected anywhere in this class (AC32b: "no begin-signal side
## effect touched the stack" holds structurally -- there is no handler for
## it to call). A no-op when [member game_world] is null.
func _connect_transition_signals() -> void:
	if game_world == null:
		return
	if not game_world.transition_ended.is_connected(_on_transition_ended):
		game_world.transition_ended.connect(_on_transition_ended)


## Handles [signal GameWorld.transition_ended]. Clears both stacks only when
## [param success] is `true` (transition-COMPLETE, AC32) -- an aborted/
## failed transition ([param success] `== false`, AC32b) is a deliberate
## no-op: every previously recorded command remains exactly as undoable as
## before the transition was even attempted.
func _on_transition_ended(success: bool) -> void:
	if not success:
		return
	clear()


## Shared push helper for [method record_command] and [method redo]'s own
## surviving-cell re-push -- appends [param cells] as a new top-of-stack
## command, then discards the oldest entry if [member
## UndoRedoStackConfig.undo_stack_depth] is now exceeded (AC30, Edge Case
## 9). [method redo] deliberately calls this directly rather than through
## [method record_command], so a successful redo never ALSO clears the
## remaining redo branch (AC31 only fires for a genuinely new command).
func _push_undo(cells: Array[Vector3i]) -> void:
	_undo_stack.append(cells)
	if _undo_stack.size() > config.undo_stack_depth:
		_undo_stack.pop_front()
