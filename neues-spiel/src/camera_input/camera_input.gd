## Camera & Input's spherical-orbit camera position derivation (Foundation
## Spine story cam-001, ADR-0002 + ADR-0001).
##
## Owns the derived camera position formula `target + spherical_offset
## (distance, yaw, pitch)` [TR-camera-input-021] and the fixed pole-safety
## pitch clamp [TR-camera-input-037]. Camera position is NEVER stored --
## [method get_camera_position] recomputes it from state on every call, per
## the GDD's "never independently stored" contract; [method derive_position]
## is the pure, stateless formula itself, callable without an instance.
##
## Injected-tier module (ADR-0001): [member config] is wired via a scene
## file's Inspector in production, or assigned directly in a headless test;
## all wiring/validation lives in [method setup], never `_ready()`.
##
## Story cam-002 (ADR-0010 primary, ADR-0001 secondary) additionally owns the
## InputMap action registrations (project.godot, project scope -- see
## [constant OWNED_ACTIONS]) and the opaque [signal action_fired] passthrough:
## this system reports "this action fired" and nothing more, never
## interpreting the action name or branching on input device identity
## [TR-camera-input-027] [TR-camera-input-032] [TR-camera-input-039].
##
## Story cam-003 (ADR-0002 primary) additionally owns orbit rotation: Q/E
## fixed-step yaw ([method _apply_qe_rotation], GDD Core Rule 3
## [TR-camera-input-023]) and middle-mouse-drag yaw/pitch
## ([method _apply_mouse_drag_rotation], GDD Core Rule 2
## [TR-camera-input-022]). Both are purely event-driven -- neither reads the
## Time & Tick Autoload nor any of its warp/pause-affected accumulator state
## anywhere -- so the raw-delta contract [TR-camera-input-030] holds
## structurally rather than by a conditional bypass. Pitch changes always
## route through the existing
## [method set_pitch] primitive (story cam-001), inheriting its silent
## pole-safety clamp [TR-camera-input-040] for free. Never sets
## `Input.mouse_mode = MOUSE_MODE_CAPTURED` during the drag -- the cursor
## stays visible and free, per the GDD/manifest.
##
## Story cam-004 (ADR-0002 primary) additionally owns mouse-wheel zoom
## ([method _apply_zoom], GDD Core Rule 4 [TR-camera-input-024]): each wheel
## event scales [member _distance] multiplicatively by
## `config.zoom_factor_in` (wheel-up, "zoom in") or `config.zoom_factor_out`
## (wheel-down, "zoom out"), then clamps the result to
## `[config.distance_min, config.distance_max]` via the new
## [method set_distance] primitive -- mirroring [method set_pitch]'s
## clamp-on-write shape from stories cam-001/003. There is no accumulator
## state: every wheel event applies the formula once, independently, so N
## rapid successive events (any N) still respect the clamp with no
## compounding overshoot [TR-camera-input-044]. Purely event-driven like the
## rest of this class's input handling, so the raw-delta contract holds
## structurally rather than by a conditional bypass.
##
## Story cam-005 (ADR-0002 primary) additionally owns WASD ground-plane pan
## (GDD Core Rule 5 [TR-camera-input-025]): [method _apply_pan], driven by
## [method _process]'s own per-frame delta -- this class's ONE sanctioned
## per-frame hook, since a held-key pan (unlike Q/E's discrete step or the
## wheel's discrete event) genuinely needs continuous per-frame movement
## while held. That frame delta is Godot's own engine-provided value; this
## class structurally never reads the Time & Tick Autoload nor any of its
## warp/pause-affected accumulator state anywhere, so the raw-delta contract
## [TR-camera-input-030] holds exactly as it does for rotation/zoom. The
## delta is clamped to `config.max_delta_time` BEFORE entering the pan
## formula [TR-camera-input-043], and the resulting target is clamped to the
## world extent via [method clamp_target_to_bounds] -- silently, with no
## error, and margin 0 (the default) is a fully valid configuration, not an
## edge case [TR-camera-input-026] [TR-camera-input-049]. [method
## derive_pan_delta] and [method clamp_target_to_bounds] are pure/stateless,
## mirroring [method derive_position]'s already-established testable-pure-
## function shape. WASD is read via `Input.get_vector` over
## [constant PAN_ACTIONS] -- deliberately NOT part of [constant
## OWNED_ACTIONS]/[signal action_fired]'s opaque one-shot passthrough (that
## list's semantics are "fired on press," which doesn't fit a continuously-
## held direction key); [constant PAN_ACTIONS] still gets its own boot-time
## registration guard, [method _assert_pan_actions_registered].
##
## Out of scope for this class as authored here (later stories extend this
## same class, not new ones): the mouse world-ray query (story cam-006), and
## the Active/Suspended state machine (story cam-007).
class_name CameraInput
extends Node

## Opaque InputMap action passthrough (ADR-0010 Decision "New-click ownership
## is structural"; architecture.md API Boundaries:
## `signal action_fired(action_name: StringName)`). Payload is ONLY the
## action-name string -- this system never interprets what the action means;
## consumers (Building System, Building UI, Villager Info UI) own that.
## [TR-camera-input-027]
signal action_fired(action_name: StringName)

## The authoritative union of InputMap actions this system owns, registered
## in `project.godot` at project scope (never created at runtime)
## [TR-camera-input-032]. This is the single source of truth [method
## _unhandled_input] iterates over and [method setup] verifies against
## [constant InputMap] at boot -- keep in sync with `project.godot`'s
## `[input]` section by construction (both are hand-authored from the same
## downstream-GDD union; a mismatch fails loudly via [method setup]'s
## assertion rather than silently).
##
## Provenance: `build_place`/`build_remove` (camera-input.md Core Rule 7,
## building-system.md), `camera_rotate_left`/`camera_rotate_right`
## (camera-input.md Core Rule 3 -- Q/E), `tool_select_1..5`, `time_pause`,
## `time_speed_up`/`time_speed_down`, the Rule-9b keyboard-parity set
## (`toast_focus_cycle`, `toast_dismiss`, `toggle_issues`, `palette_next`,
## `palette_prev`, `formation_next`, `formation_prev`, `height_step_up`,
## `height_step_down`), and the Slice-revision set (`build_mode_toggle`,
## `slice_up`, `slice_down`, `slice_reset`) -- all building-ui.md Rule 12.
## `tool_select_room`/`tool_select_roof`/`tool_select_house` (the three
## higher-level tools, building-ui.md Rule 19) are named here as an
## authored `[assumption]` -- the GDD commits to these three actions
## existing but not yet to a specific identifier string; the underlying
## keys for every Rule-9b/Slice-revision/higher-level-tool action are
## themselves already documented `[assumption]`s pending `/ux-design`
## (Open Question 13) -- registering a placeholder default key here does
## not pre-empt that review.
const OWNED_ACTIONS: Array[StringName] = [
	&"build_place", &"build_remove",
	&"camera_rotate_left", &"camera_rotate_right",
	&"tool_select_1", &"tool_select_2", &"tool_select_3", &"tool_select_4", &"tool_select_5",
	&"tool_select_room", &"tool_select_roof", &"tool_select_house",
	&"time_pause", &"time_speed_up", &"time_speed_down",
	&"toast_focus_cycle", &"toast_dismiss", &"toggle_issues",
	&"palette_next", &"palette_prev",
	&"formation_next", &"formation_prev",
	&"height_step_up", &"height_step_down",
	&"build_mode_toggle",
	&"slice_up", &"slice_down", &"slice_reset",
]

## WASD ground-plane pan actions (story cam-005, GDD Core Rule 5)
## [TR-camera-input-025], registered in `project.godot` at project scope like
## every other action this system owns [TR-camera-input-032]. Kept OUT of
## [constant OWNED_ACTIONS] deliberately: that list drives [signal
## action_fired]'s one-shot "fired on press" passthrough (matching Q/E's
## discrete step), whereas pan is read every frame via `Input.get_vector`
## inside [method _apply_pan] while a key is HELD -- a continuously-polled
## direction, not a discrete press event. Re-emitting a one-shot
## `action_fired` for a held key would misrepresent it, so these get their
## own boot-time registration guard instead, [method
## _assert_pan_actions_registered], rather than joining the passthrough list.
const PAN_ACTIONS: Array[StringName] = [
	&"camera_pan_forward", &"camera_pan_back", &"camera_pan_left", &"camera_pan_right",
]

## Tuning config dependency (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: CameraInputConfig

## Orbit target point (ground-plane look-at). Mutated by [method _apply_pan]
## (story cam-005); starts at the world origin. [TR-camera-input-021]
var _target: Vector3 = Vector3.ZERO

## Spherical radius from [member _target] to the camera. Mutated by the zoom
## formula (story cam-004, out of scope here). [TR-camera-input-021]
var _distance: float = 0.0

## Horizontal orbit angle, radians, unbounded/wraps. Mutated by mouse-drag/
## Q-E rotation (story cam-003, out of scope here). [TR-camera-input-021]
var _yaw: float = 0.0

## Vertical orbit angle, radians, always kept within
## `[config.pitch_min, config.pitch_max]` -- the fixed pole-safety margin.
## [TR-camera-input-037]
var _pitch: float = 0.0

## True once [method setup] has completed at least once.
var _is_set_up: bool = false


## Explicitly callable wiring/validation entry point (ADR-0001). Asserts
## [member config] was wired, applies ADR-0002's clamp+warn `validate()`
## policy, and initializes the spherical state from the config's `start_*`
## knobs [TR-camera-input-019] -- never from a hardcoded literal.
func setup() -> void:
	assert(config != null, "CameraInput.config not wired")
	for issue: String in config.validate():
		if not issue.begins_with(ConfigResource.BLOCKING_PREFIX):
			push_warning(issue)
	_target = Vector3.ZERO
	_distance = config.start_distance
	_yaw = config.start_yaw
	_pitch = clampf(config.start_pitch, config.pitch_min, config.pitch_max)
	_assert_owned_actions_registered()
	_assert_pan_actions_registered()
	_is_set_up = true


## Boot-time guard for [TR-camera-input-032]: every entry in
## [constant OWNED_ACTIONS] must already exist in [InputMap] (registered via
## `project.godot` at project scope -- never created here at runtime). A
## missing action means `project.godot` has drifted out of sync with this
## list; fail loudly rather than let a downstream consumer silently query an
## action that was never registered.
func _assert_owned_actions_registered() -> void:
	var missing: Array[StringName] = OWNED_ACTIONS.filter(
		func(action_name: StringName) -> bool: return not InputMap.has_action(action_name)
	)
	assert(missing.is_empty(), "CameraInput owned actions missing from project.godot: %s" % [missing])


## Boot-time guard for [constant PAN_ACTIONS], mirroring [method
## _assert_owned_actions_registered]'s shape exactly but against the separate
## pan-action list (story cam-005) -- same fail-loudly-on-drift reasoning.
func _assert_pan_actions_registered() -> void:
	var missing: Array[StringName] = PAN_ACTIONS.filter(
		func(action_name: StringName) -> bool: return not InputMap.has_action(action_name)
	)
	assert(missing.is_empty(), "CameraInput pan actions missing from project.godot: %s" % [missing])


## Returns whether [method setup] has completed.
func is_set_up() -> bool:
	return _is_set_up


## Returns the camera's world position, recomputed fresh from current state
## on every call -- never cached or independently stored.
## [TR-camera-input-021]
func get_camera_position() -> Vector3:
	return CameraInput.derive_position(_target, _distance, _yaw, _pitch)


## Pure spherical-to-Cartesian derivation (GDD Formulas section):
## `target + Vector3(distance*sin(yaw)*cos(pitch), distance*sin(pitch),
## distance*cos(yaw)*cos(pitch))`. Stateless -- exercisable directly with
## arbitrary values, without an instance or [method setup].
## [TR-camera-input-021]
static func derive_position(target: Vector3, distance: float, yaw: float, pitch: float) -> Vector3:
	return target + Vector3(
		distance * sin(yaw) * cos(pitch),
		distance * sin(pitch),
		distance * cos(yaw) * cos(pitch)
	)


## Sets the vertical orbit angle, clamped to
## `[config.pitch_min, config.pitch_max]` -- the fixed pole-safety margin
## that prevents the spherical derivation from degenerating at the poles
## [TR-camera-input-037]. The rotation input handling that calls this
## (mouse-drag/Q-E) is story cam-003's scope; this is the shared clamp
## primitive that story builds on.
func set_pitch(value: float) -> void:
	assert(config != null, "CameraInput.config not wired")
	_pitch = clampf(value, config.pitch_min, config.pitch_max)


## Returns the current vertical orbit angle (radians).
func get_pitch() -> float:
	return _pitch


## Returns the current horizontal orbit angle (radians).
func get_yaw() -> float:
	return _yaw


## Sets the spherical radius, clamped to
## `[config.distance_min, config.distance_max]` -- the zoom clamp bound
## [TR-camera-input-024]. The zoom input handling that calls this
## (mouse-wheel, story cam-004) is this story's scope; this is the shared
## clamp primitive, mirroring [method set_pitch]'s shape, that any future
## distance-changing input can reuse without duplicating the clamp.
func set_distance(value: float) -> void:
	assert(config != null, "CameraInput.config not wired")
	_distance = clampf(value, config.distance_min, config.distance_max)


## Returns the current spherical radius.
func get_distance() -> float:
	return _distance


## Returns the current orbit target point.
func get_target() -> Vector3:
	return _target


## Opaque InputMap action passthrough (ADR-0010 Decision §1; architecture.md
## API Boundaries). Listens on `_unhandled_input` per ADR-0010 -- an event
## already consumed by an HUD Control (default `mouse_filter = STOP`) never
## reaches here, which is exactly what gives "exactly one owner per click"
## [TR-camera-input-020] without any code of this system's own dedicated to
## checking it.
##
## Deliberately implemented with [method Array.filter] rather than an
## `if`/`match` on [param event]'s action identity: every entry in
## [constant OWNED_ACTIONS] receives IDENTICAL treatment (a uniform
## `is_action_pressed` check), so there is no branch whose behavior differs
## per action name to grep for [TR-camera-input-027]. This method never
## reads the input device identity of [param event] anywhere
## [TR-camera-input-039].
##
## Story cam-003 additionally drives this system's OWN rotation behavior
## from the same event, via two unconditional call sites appended below the
## passthrough loop -- [method _apply_qe_rotation] and
## [method _apply_mouse_drag_rotation]. Neither call line itself branches on
## [param event]'s identity (the branching lives inside those methods, on
## this system's own two owned rotation actions / the middle-mouse button --
## never on the arbitrary [constant OWNED_ACTIONS] list this method's own
## loop still treats uniformly). [TR-camera-input-027]'s "no branch on
## action identity" guarantee is about the opaque re-emission of OTHER
## systems' actions and is unaffected.
##
## Story cam-004 similarly appends a third unconditional call site,
## [method _apply_zoom], for this system's own mouse-wheel zoom -- same
## reasoning: the branch lives inside that method, on the wheel event's own
## button index, never here on [constant OWNED_ACTIONS] identity.
func _unhandled_input(event: InputEvent) -> void:
	var fired: Array[StringName] = OWNED_ACTIONS.filter(
		func(action_name: StringName) -> bool: return event.is_action_pressed(action_name)
	)
	for action_name: StringName in fired:
		action_fired.emit(action_name)
	_apply_qe_rotation(event)
	_apply_mouse_drag_rotation(event)
	_apply_zoom(event)


## Mouse-wheel multiplicative zoom (GDD Core Rule 4) [TR-camera-input-024].
## Each wheel event is a discrete [InputEventMouseButton] with
## `pressed = true` -- never accumulated across frames and never scaled by
## delta-time (the GDD formula applies once per wheel event, matching how
## Q/E applies once per key press in [method _apply_qe_rotation], not once
## per frame). Wheel-up ([constant MOUSE_BUTTON_WHEEL_UP]) zooms in
## (`config.zoom_factor_in`, GDD default 0.9, shrinks distance); wheel-down
## ([constant MOUSE_BUTTON_WHEEL_DOWN]) zooms out (`config.zoom_factor_out`,
## GDD default 1.1, grows distance). Routes through [method set_distance],
## which owns the `[distance_min, distance_max]` clamp -- so any number of
## rapid successive events can never overshoot the bound regardless of event
## count [TR-camera-input-044]. Factors are read from [member config] --
## never a hardcoded literal [TR-camera-input-019].
func _apply_zoom(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_distance(_distance * config.zoom_factor_in)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_distance(_distance * config.zoom_factor_out)


## Q/E fixed-step yaw rotation (GDD Core Rule 3) [TR-camera-input-023].
## `camera_rotate_left` (Q) and `camera_rotate_right` (E) are already
## registered, owned actions (see [constant OWNED_ACTIONS]) -- this reacts to
## the SAME event the passthrough loop above already inspects, applying this
## system's own Core-Rule-3 behavior for its own owned actions. Distinct from
## [TR-camera-input-027]'s "no branch on action identity" guarantee, which
## governs only the opaque re-emission of OTHER systems' actions (build_place
## et al.) -- Camera & Input interpreting its OWN rotation actions for its
## OWN camera state is the GDD's explicitly assigned behavior, not a
## violation of that passthrough contract. Step size is read from
## [member config] -- never a hardcoded literal [TR-camera-input-019].
func _apply_qe_rotation(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_rotate_left"):
		_yaw -= config.q_e_rotate_step
	elif event.is_action_pressed(&"camera_rotate_right"):
		_yaw += config.q_e_rotate_step


## Middle-mouse-drag rotation (GDD Core Rule 2) [TR-camera-input-022].
## Horizontal drag changes yaw, vertical drag changes pitch -- both
## proportional to `config.mouse_drag_sensitivity`, applied per motion
## event's [member InputEventMouseMotion.relative] pixel delta (never a
## manually-tracked previous-position diff, and never delta-time-scaled --
## the GDD's formula is purely per-pixel-of-drag, not per-frame). Pitch
## changes always route through [method set_pitch], inheriting its pole-
## safety clamp [TR-camera-input-037] silently, with no error, at either
## bound [TR-camera-input-040].
##
## Gated on `MOUSE_BUTTON_MASK_MIDDLE` in the motion event's own
## `button_mask` -- a self-describing per-event check, not a separately
## tracked press/release drag-state field: there is nothing to get "stuck"
## if a press or release event is ever swallowed elsewhere (e.g. by an HUD
## Control under ADR-0010's routing), because no state survives between
## events. Never sets `Input.mouse_mode = MOUSE_MODE_CAPTURED` -- the cursor
## stays visible and free, per the GDD/manifest.
func _apply_mouse_drag_rotation(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_yaw += event.relative.x * config.mouse_drag_sensitivity
		set_pitch(_pitch + event.relative.y * config.mouse_drag_sensitivity)


## Godot's per-frame engine callback -- this class's ONE sanctioned per-frame
## hook (story cam-005). [param delta] is Godot's own engine-provided frame
## delta, never a value read from this project's separate tick-warp/pause
## clock -- structurally, this class never reads that Autoload anywhere, so
## the raw-delta contract [TR-camera-input-030] holds the same way it does
## for rotation/zoom (both purely event-driven, this one purely frame-driven,
## neither ever touching the other clock).
##
## Reads [constant PAN_ACTIONS] via `Input.get_vector` every frame (a
## held-key, continuously-polled direction -- see [constant PAN_ACTIONS] for
## why this is distinct from the discrete [signal action_fired] passthrough)
## and forwards the resolved direction to [method _apply_pan]. This is
## deliberately the ONLY place this class reads the `Input` singleton for
## pan -- [method _apply_pan] takes the already-resolved direction as a
## parameter rather than querying `Input` itself, keeping the formula fully
## testable without depending on engine-level input dispatch (mirroring how
## [method _unhandled_input] takes a synthesizable [InputEvent] rather than
## reading global input state internally). `camera_pan_forward` is the
## `Input.get_vector` negative-Y parameter: at yaw=0 the camera sits at world
## +Z relative to the target (see [method derive_position]'s
## `distance*cos(yaw)` term), so "forward relative to view" -- the direction
## from camera to target -- is -Z before yaw rotation, matching `vec.y == -1`
## when the forward key is held.
func _process(delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector(
		&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back"
	)
	_apply_pan(delta, Vector3(input_vec.x, 0.0, input_vec.y))


## WASD ground-plane pan formula (GDD Core Rule 5) [TR-camera-input-025].
## [param input_dir] is the already-resolved, not-necessarily-normalized
## direction for this frame (see [method _process] for how it's read from
## [constant PAN_ACTIONS]) -- taking it as a parameter, rather than reading
## `Input` internally, is what makes this method exercisable directly in a
## headless test with an arbitrary direction, with no dependency on engine
## input dispatch.
##
## [param delta] is clamped to `config.max_delta_time` BEFORE entering the
## pan formula [TR-camera-input-043], preventing a large jump after a hitch/
## stall. The resulting delta vector is added to [member _target], then
## clamped to the world extent via [method clamp_target_to_bounds] --
## silently, with no error, and margin 0 (the config default) is a fully
## valid configuration, not an edge case [TR-camera-input-026]
## [TR-camera-input-049]. Input still registers at a bound; it simply
## produces zero further movement in that axis, never a blocked/ignored
## event.
func _apply_pan(delta: float, input_dir: Vector3) -> void:
	var clamped_delta: float = clampf(delta, 0.0, config.max_delta_time)
	var pan_delta: Vector3 = CameraInput.derive_pan_delta(
		input_dir, _yaw, _distance, clamped_delta, config.pan_speed_factor
	)
	_target = CameraInput.clamp_target_to_bounds(
		_target + pan_delta,
		config.world_width_cells, config.world_depth_cells, config.cell_size, config.pan_bound_margin
	)


## Pure pan-formula derivation (GDD Formulas section, Pan):
## `input_dir.normalized().rotated(UP, yaw) * delta * distance * pan_speed_factor`.
## Stateless -- exercisable directly with arbitrary values, without an
## instance or [method setup], mirroring [method derive_position]'s testable-
## pure-function shape. [param input_dir] need not be pre-normalized -- a
## [constant Vector3.ZERO] input (no keys held) normalizes to zero safely, no
## division-by-zero. [TR-camera-input-025] [TR-camera-input-043]
static func derive_pan_delta(
	input_dir: Vector3, yaw: float, distance: float, delta: float, pan_speed_factor: float
) -> Vector3:
	return input_dir.normalized().rotated(Vector3.UP, yaw) * delta * distance * pan_speed_factor


## Pure world-extent bound clamp for the pan target (GDD Formulas section,
## Pan): clamps X to `[margin, world_width_cells * cell_size - margin]` and Z
## to `[margin, world_depth_cells * cell_size - margin]`; `target.y` passes
## through untouched (the orbit target lives on the ground plane, Y is never
## part of this clamp). Stateless, mirroring [method derive_position]'s
## testable-pure-function shape. Margin 0 (the config default) is a fully
## valid configuration -- `clampf` degenerates gracefully to the raw extent
## bounds, no special-case needed. [TR-camera-input-026] [TR-camera-input-049]
static func clamp_target_to_bounds(
	target: Vector3, world_width_cells: int, world_depth_cells: int, cell_size: float, margin: float
) -> Vector3:
	return Vector3(
		clampf(target.x, margin, world_width_cells * cell_size - margin),
		target.y,
		clampf(target.z, margin, world_depth_cells * cell_size - margin)
	)
