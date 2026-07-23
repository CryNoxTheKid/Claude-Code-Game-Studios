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
## Out of scope for this class as authored here (later stories extend this
## same class, not new ones): InputMap action registration/passthrough
## (story cam-002), mouse-drag/Q-E rotation and WASD pan/zoom input handling
## (stories cam-003/004/005), the mouse world-ray query (story cam-006), and
## the Active/Suspended state machine (story cam-007).
class_name CameraInput
extends Node

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
	_is_set_up = true


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
