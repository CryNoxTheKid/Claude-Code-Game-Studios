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
## Out of scope for this class as authored here (later stories extend this
## same class, not new ones): mouse-drag/Q-E rotation and WASD pan/zoom input
## handling (stories cam-003/004/005), the mouse world-ray query (story
## cam-006), and the Active/Suspended state machine (story cam-007).
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

## Tuning config dependency (ADR-0002). Wired via a scene file's Inspector in
## production, or assigned directly in a headless test. Never read inside
## `_ready()` -- see [method setup].
@export var config: CameraInputConfig

## Orbit target point (ground-plane look-at). Mutated by the pan formula
## (story cam-005, out of scope here); starts at the world origin.
## [TR-camera-input-021]
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
func _unhandled_input(event: InputEvent) -> void:
	var fired: Array[StringName] = OWNED_ACTIONS.filter(
		func(action_name: StringName) -> bool: return event.is_action_pressed(action_name)
	)
	for action_name: StringName in fired:
		action_fired.emit(action_name)
