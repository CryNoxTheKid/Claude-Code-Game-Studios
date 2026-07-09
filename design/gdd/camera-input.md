# Camera & Input

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: None directly — Foundation infrastructure enabling Pillar 1 (building) and Pillar 4 (clarity)

## Summary

Camera & Input owns the game's raw input pipeline (InputMap actions,
mouse/keyboard events) and the single free-orbit camera through which the
player views and navigates the valley — bounded to stay within/near the
Voxel World's extent. It exposes camera state and the current mouse
world-ray to every other system, but does not interpret what a click means
(that's each consuming system's job, e.g. the Building System).

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `None`

## Overview

Camera & Input is the system the player touches every second of play — an
orbit camera (drag to rotate, wheel to zoom, WASD to pan), bounded to the
valley so the player never drifts into empty void, plus the raw input
pipeline (InputMap actions, mouse/keyboard capture) that every other system
builds on. This system owns HOW input is captured and HOW the camera moves;
it does NOT decide WHAT an input means gameplay-wise — a left-click reaching
the Building System still has to be interpreted there as "place a block."
MVP needs exactly one camera mode: free orbit. Additional modes (e.g., a
future combat-focus camera) are deliberately out of scope until a system
actually needs one.

## Player Fantasy

Unlike Scene/World Management or Voxel World, the player feels this system
directly and continuously — every rotation, zoom, and pan is immediate
feedback. The camera fantasy is still one of *invisibility through quality*:
it should feel smooth, predictable, and responsive enough that all of the
player's attention stays on what's being built, not on the camera itself.
The building prototype already confirmed this — camera/orbit/snapping never
became the friction the concept doc feared. Success here doesn't mean "the
player never notices the camera," it means "the player never notices it
*because* it's good" — a subtle but important distinction from the purely
invisible Foundation systems.

*(`creative-director` not consulted — Lean mode skips non-high-risk sections.)*

## Detailed Design

*(No specialist consulted — Lean mode skips non-high-risk sections. Drafted
using the building prototype's validated camera values as reference. Review
manually before production.)*

### Core Rules

1. The camera orbits a target point (a look-at point in world space) at a
   configurable distance, yaw, and pitch — position is derived from
   target + spherical offset, not stored independently.
2. Middle-mouse-drag rotates the camera: horizontal drag changes yaw,
   vertical drag changes pitch (within the pitch clamp bounds).
3. Q/E keys rotate yaw by a fixed step per press (an alternative to mouse
   drag).
4. The mouse wheel zooms by scaling distance **multiplicatively** (not
   additively), clamped to a min/max distance range.
5. WASD pans the orbit target along the ground plane, direction relative to
   the camera's current yaw ("W" always means "forward relative to view"),
   scaled by delta-time and current distance (panning feels proportionally
   faster when zoomed out).
6. The orbit target is clamped to the Voxel World's horizontal bounds (plus
   a small margin) so panning cannot drift into the void beyond the valley.
7. This system owns the InputMap action definitions (e.g., `build_place`,
   `build_remove`, `camera_rotate_left`) but does NOT interpret what an
   action means — it only reports "this action fired" via signal; the
   consuming system (Building System, etc.) owns interpretation.
8. This system exposes a "current mouse world-ray" query (derived from the
   camera's projection and the mouse's screen position), so any system
   (e.g., the Building System, which forwards it to Voxel World's raycast)
   can convert the mouse position into a world-space ray without
   recomputing the camera projection itself.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|-----------------|-----------------|----------|
| Active | Default; also entered from Suspended once a scene finishes loading | A scene transition begins (see Scene/World Management) | Full camera control (rotate/zoom/pan) and input dispatch are enabled |
| Suspended | A scene transition begins (Scene/World Management's Transitioning state) | Scene transition completes | Camera position freezes; no rotate/zoom/pan; input events are not dispatched to gameplay systems |

*(Directly implements Scene/World Management's Core Rule 6 — "neither scene
receives input" during a transition.)*

### Interactions with Other Systems

- **Scene/World Management** (Foundation sibling): this system suspends
  itself during the Transitioning state (see that GDD's Core Rule 6); its
  own root also lives under the loaded scene.
- **Voxel World** (Foundation sibling): **no direct connection.** This
  system only provides the mouse world-ray; the Building System fetches
  that ray and forwards it to Voxel World's raycast API. Camera & Input
  never calls Voxel World itself.
- **Building System** (MVP, downstream): consumes InputMap action signals
  (e.g., `build_place`) and the mouse-world-ray query to interpret player
  input and perform picking (via Voxel World).

## Formulas

*(`systems-designer` and `godot-specialist` consulted — mandatory for this
high-risk section even in Lean mode. Formalizes the concept prototype's
already-proven values rather than inventing new ones.)*

### Camera Position from Spherical Coordinates

`camera_position = target + Vector3(distance * sin(yaw) * cos(pitch), distance * sin(pitch), distance * cos(yaw) * cos(pitch))`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| target | `target` | Vector3 | see Pan formula | Orbit target point (ground plane) |
| distance | `distance` | float | 4.0–60.0 | Spherical radius |
| yaw | `yaw` | float (rad) | unbounded, wraps | Horizontal orbit angle |
| pitch | `pitch` | float (rad) | **0.15–1.5** (safety margin from the poles, see note below) | Vertical orbit angle |
| camera_position | `camera_position` | Vector3 | derived | Resulting camera world position |

**Example**: `target=(32,0,32), distance=18.0, yaw=0.7, pitch=0.95` →
`camera_position ≈ (38.75, 14.63, 40.02)`. Recomputed every frame, never
stored independently.

**Important Godot note**: `pitch` must never approach the poles (±90°) — the
spherical-to-Cartesian derivation degenerates there (the yaw axis becomes
undefined). The 0.15–1.5 rad range (≈8.6°–86°) is exactly this safety
margin, not an arbitrary choice.

### Zoom (multiplicative)

`distance' = clamp(distance * zoom_factor, 4.0, 60.0)`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| distance | `distance` | float | 4.0–60.0 | Current orbit distance |
| zoom_factor | `zoom_factor` | float | {0.9 in, 1.1 out} | Factor **per wheel event** (not per frame — the wheel fires discretely) |

**Example**: `distance=18.0`, zoom in → `18.0 * 0.9 = 16.2`.

### Pan (yaw-relative, distance-scaled)

`target' = clamp_to_bounds(target + input_dir.normalized().rotated(UP, yaw) * delta * distance * 0.7)`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| input_dir | `input_dir` | Vector3 | WASD combination | Raw direction before yaw rotation |
| delta | `delta` | float | ~0–0.05 | Frame delta-time |
| distance | `distance` | float | 4.0–60.0 | Faster pan when zoomed out |
| target' | `target'` | Vector3 | clamped to `[0, world_width_cells*cell_size] × [0, world_depth_cells*cell_size]` | New orbit target |

### Mouse World-Ray — deliberately NOT a Formula

`origin = camera.project_ray_origin(mouse_screen_pos)`,
`direction = camera.project_ray_normal(mouse_screen_pos)` — native Godot 4.7
API (unchanged since 4.3), no tunable value of our own. **Important**: both
must be computed from the same screen point in the same frame (don't cache
one and recompute the other later, or Suspended-state freezes could desync
them).

### Godot 4.7 clarification: device ID is irrelevant here

The 4.7 change (`DEVICE_ID_MOUSE`/`DEVICE_ID_KEYBOARD` replacing hardcoded
`0`) only concerns which physical device generated an event. Nothing in this
system branches on device identity (actions route through named InputMap
actions and typed event checks) — deliberately a non-issue, so no one adds
unnecessary device-ID logic here later.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-------------------|-----------|
| Mouse-drag would push `pitch` beyond its bounds (0.15/1.5) | Silently clamps to the boundary, no error | Standard clamp behavior, prevents pole degeneration |
| WASD held while the target is already at the world bound | Target stays clamped, no further movement in that direction, no error | Prevents drifting into the void without blocking input |
| A scene transition begins while the rotate mouse button is held | Camera immediately enters Suspended; the held button is ignored until released and re-pressed | Prevents a "stuck" drag state from surviving the transition |
| Camera returns from Suspended to Active | Resumes with the exact same yaw/pitch/distance/target it had when frozen — no snap, no catching up on queued input | Prevents disorientation after a scene transition |
| Very large delta-time in one frame (e.g., a hitch, or the window was minimized) | Delta-time is clamped to a maximum before entering the Pan formula | Prevents a huge camera jump after a stall |
| Mouse wheel fires very rapidly (fast scrolling) | Each event independently applies the zoom factor; the clamp (4.0–60.0) prevents overshoot regardless of event count | No compounding issue from the multiplicative formula |
| The mouse world-ray query is called while Suspended | Remains technically computable (camera transform is frozen but valid) — consuming systems shouldn't act on it anyway, since input dispatch is disabled during the transition | No special case needed in the ray calculation itself; consistency comes from input suspension |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|----------------------|
| Scene/World Management | This system depends on | Listens for the transition-begin/-complete signal to enter/exit Suspended state |
| Voxel World | (indirect only, via Building System) | See Interactions — no direct call |
| Building System | Depended on by | Consumes InputMap action signals and the mouse-world-ray query |
| Building UI | Depended on by | Registers its bindings (`tool_select_1..5`, `time_pause`, `time_speed_up/down`) under this system's action ownership (its Rule 12); follows Suspended (added 2026-07-10, cross-review bidirectional fix) |
| Villager Info UI | Depended on by | Consumes the mouse-world-ray + click action in Idle for villager selection; follows Suspended (added 2026-07-10, cross-review bidirectional fix) |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------------|------------|---------------------|---------------------|
| `start_distance` | 18.0 | 4.0–60.0 | Starts more zoomed out | Starts closer in |
| `start_yaw` | 0.7 rad | any | — | — |
| `start_pitch` | 0.95 rad | 0.15–1.5 | Steeper starting top-down angle | Flatter starting view angle |
| `distance_min` / `distance_max` | 4.0 / 60.0 | — | Larger zoom range, more load at very far distances | Tighter zoom range, may feel restrictive |
| `zoom_factor_in` / `zoom_factor_out` | 0.9 / 1.1 | 0.8–0.95 / 1.05–1.2 | Snappier zoom steps | Smoother but slower zoom |
| `pitch_min` / `pitch_max` | 0.15 / 1.5 rad | fixed (pole safety margin, see Formulas) | — | — |
| `q_e_rotate_step` | 0.12 rad | 0.05–0.3 | Faster key-based rotation | Finer, slower key-based rotation |
| `mouse_drag_sensitivity` | 0.008 | 0.003–0.02 | More sensitive mouse rotation | Less responsive mouse rotation |
| `pan_speed_factor` | 0.7 | 0.3–1.5 | Faster panning | Slower panning |
| `max_delta_time` | 0.1s | 0.05–0.2s | Larger possible camera jumps after a hitch | Camera visibly "lags" through a hitch instead of jumping |

*(All values except `pitch_min`/`pitch_max` and `max_delta_time` come directly
from the playtested building prototype — no invented numbers.)*

## Visual/Audio Requirements

This system has almost no dedicated visual/audio events of its own — its
"feedback" IS the camera motion itself. Two light touches are worth
specifying: (1) the mouse cursor should change during an active rotate-drag
(e.g., to a grab/orbit icon) to signal the drag is engaged; (2) reaching a
pan boundary is deliberately silent — no additional VFX/audio cue — matching
Pillar 4 (clarity over complexity) and avoiding noise during normal building
flow.

## Game Feel

### Feel Reference

Should feel like a smooth colony-sim orbit camera (Stonehearth/Cities:
Skylines-adjacent) — buttery, no perceptible lag on rotate, but panning
carries a touch of glide rather than a robotic snap. NOT like a flight-sim
free camera (too many degrees of freedom, disorienting), NOT like a rigid
grid-locked RTS camera (too stiff for an "orbit around your creation" feel).

### Input Responsiveness

| Action | Max Input-to-Response Latency (ms) | Frame Budget (at 60fps) | Notes |
|--------|-------------------------------------|--------------------------|-------|
| Mouse-drag rotate | ~16ms (1 frame) | 1 frame | Must feel 1:1, zero perceptible lag |
| Zoom (wheel) | ~16ms | 1 frame | Instant response to the wheel event |
| WASD pan | ~16ms | 1 frame | Input registers the same frame it's pressed |

### Animation Feel Targets / Impact Moments

N/A — no keyframed animation, only continuous formula-driven movement; no
combat-hit equivalent for this system.

### Weight and Responsiveness Profile

Light and reactive, not heavy/deliberate — the camera should feel like an
extension of the mouse, not a vehicle with momentum. High player control at
all times (no forced inertia beyond the input itself). Smooth/analog, not
stepped. Instant start/stop on rotate/pan (arcade feel, no ease-in/out) —
matching the already-validated prototype feel. Hitting a boundary
(pan/pitch) should read as a gentle stop, not a jarring bounce.

### Feel Acceptance Criteria

- [ ] Playtesters describe the camera as "smooth"/"responsive" unprompted,
      never "laggy" or "floaty"
- [ ] No playtester reports disorientation from rotation or zoom
- [ ] Reaching a boundary is described as a "gentle stop," not jarring

## UI Requirements

Minimal — only the mouse cursor state (see Visual/Audio). No dedicated HUD
element. Camera settings (e.g., sensitivity) belong to Main Menu & Settings
(Alpha tier) later, not here.

## Cross-References

| This Document References | Target GDD | Specific Element Referenced | Nature |
|---------------------------|-----------|-------------------------------|--------|
| "Listens for the transition-begin/-complete signal" | `design/gdd/scene-world-management.md` | Transition signal (already defined there for Save/Load) | State trigger |
| "Suspended state directly implements 'neither scene receives input'" | `design/gdd/scene-world-management.md` | Core Rule 6 | Rule dependency |
| "world_width_cells, world_depth_cells, cell_size bound the pan target" | `design/gdd/voxel-world.md` | Tuning Knobs + `cell_size` constant | Data dependency |
| "InputMap action results feed the Building System's interpretation" | `design/gdd/building-system.md` (not yet authored) | Action signal consumption | Data dependency |

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Verdict: GAPS on first draft → 2 missing criteria added (mouse-ray
during Suspended, rapid-zoom clamp), 2 reworded for testability (bound-pan
behavior, InputMap non-interpretation as a positive checkable contract).)*

1. **GIVEN** the camera is active, **WHEN** position is computed, **THEN** it
   always equals target + spherical offset (never independently stored).
   *[Logic]*
2. **GIVEN** middle-mouse-drag, **WHEN** dragged horizontally, **THEN** yaw
   changes proportionally by `mouse_drag_sensitivity`; vertical drag changes
   pitch, clamped to `[pitch_min, pitch_max]`. *[Logic]*
3. **GIVEN** Q or E is pressed, **WHEN** the press registers, **THEN** yaw
   changes by ±`q_e_rotate_step`. *[Logic]*
4. **GIVEN** a single mouse wheel event, **WHEN** it fires, **THEN** distance
   is multiplied by `zoom_factor_in`/`out` and clamped to
   `[distance_min, distance_max]`. *[Logic]*
5. **GIVEN** N sequential zoom-in wheel events (rapid scrolling), **WHEN**
   each fires, **THEN** distance still respects the clamp regardless of N.
   *[Logic]*
6. **GIVEN** WASD input, **WHEN** held, **THEN** the target moves in the
   yaw-rotated input direction, scaled by delta-time and current distance.
   *[Logic]*
7. **GIVEN** the target is already at a world bound and WASD keeps pushing
   outward, **WHEN** pan is applied repeatedly, **THEN** it produces zero
   further delta in that direction with no exception raised (input is not
   blocked, it simply has no further effect). *[Logic]*
8. **GIVEN** pitch would exceed its bounds, **WHEN** rotation input is
   applied, **THEN** it clamps silently without error. *[Logic]*
9. **GIVEN** a scene transition begins, **WHEN** the signal fires, **THEN**
   the camera immediately enters Suspended (no rotate/zoom/pan, no input
   dispatch). *[Integration]*
10. **GIVEN** the camera is Suspended, **WHEN** the transition completes,
    **THEN** it returns to Active with the exact same yaw/pitch/distance/
    target it had when suspended. *[Integration]*
11. **GIVEN** the rotate mouse button is held when a transition begins,
    **WHEN** suspended, **THEN** the held button is ignored until released
    and re-pressed. *[Integration]*
12. **GIVEN** the camera is Suspended, **WHEN** the mouse world-ray is
    queried, **THEN** it returns a valid ray from the frozen transform — no
    error, no special-case branch. *[Logic]*
13. **GIVEN** a very large delta-time (e.g., after a stall), **WHEN** the pan
    formula runs, **THEN** delta-time is clamped to `max_delta_time` first.
    *[Logic]*
14. **GIVEN** the mouse world-ray query is called, **WHEN** invoked, **THEN**
    origin and direction are computed from the same screen point in the same
    frame. *[Logic]*
15. **GIVEN** an InputMap action fires (e.g. `build_place`), **WHEN** this
    system processes it, **THEN** the emitted signal payload contains only
    the action name string, and the emitting code path contains no branch on
    that string's value. *[Logic]*
16. **Performance**: camera position recomputation and input processing
    complete within budget every frame. *[DEFERRED — requires full build +
    profiling]*
17. No hardcoded values — all tuning knob values are read from config/
    exported vars, verified by code review. *[Config/Data, Advisory]*

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Exact cursor icon/asset for the rotate-drag state? | art-director | At the art bible | — |
| Exact margin value for the pan-bound clamp ("plus a small margin," Core Rule 6)? | game-designer | Alongside the Building System GDD (depends on how close to the edge building must reach) | **RESOLVED 2026-07-09**: no building-driven extra margin needed — building must reach the world edge, and the world-extent clamp already permits that (building-system.md, Interactions). Any small aesthetic margin is a pure camera-feel value; keep default 0 until playtest says otherwise |
| Is gamepad camera control needed at MVP, or only later (per technical-preferences.md "partial... later")? | game-designer | Before Alpha | — |
| Is `max_delta_time` = 0.1s the right value, or does it need adjusting during the performance spike (see Voxel World GDD)? | technical-director | At the performance spike before Vertical Slice | — |
