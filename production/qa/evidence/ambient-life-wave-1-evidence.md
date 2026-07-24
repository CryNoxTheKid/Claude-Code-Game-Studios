# Evidence: Story presentation-001 Sub-scope A — Ambient Life Wave 1 (Environmental)

**Story**: `production/epics/presentation-experience/story-001-ambient-life-wave-1.md` (Sub-scope A only — environmental ambient motion; Sub-scope B villager idle behaviors is explicitly out of scope, gated on villager-ai-019)
**Date**: 2026-07-24
**Engine**: Godot 4.7.stable.official.5b4e0cb0f (local install, `C:/Users/Leo/Downloads/Godot_v4.7-stable_win64.exe/`)
**Evidence type**: Visual/Feel — ADVISORY (screenshots + automated logic tests). CD/art-director sign-off on the mood result happens in a separate pass, not part of this evidence doc.

---

## AC — Chimney/hearth smoke wisps, occupied/lit only [`ChimneySmokeEmitter`]

**Implementation**: `neues-spiel/src/presentation/chimney_smoke_emitter.gd`, config
`neues-spiel/src/presentation/ambient_life_config.gd`. Wraps a small `GPUParticles3D`
(art-bible §8.9.5 "Cheap — small GPUParticles3D"), gated exclusively by
`set_occupied_lit(bool)` — the seam a later Building-System/fixture wiring story
calls into (no building-occupancy/lit-state system exists yet in this codebase; this
class holds none of that logic itself, matching `LoopPayoffSignalSurface`'s
established "surface, not the real emitter" precedent).

**Automated coverage**: `tests/unit/presentation/chimney_smoke_emitter_test.gd` (5
tests) — headless setup, default "nobody home" (not emitting) state, `set_occupied_lit`
toggles both directions, particle count never exceeds the §8.9.5 ≤50-particle ambient
budget even given a deliberately out-of-range config, draw-pass mesh always assigned.

**Screenshot**: `presentation-001-suba-smoke-occupied-vs-empty-20260724-1.png` — two
placeholder huts side by side (no fixture-art pipeline exists yet — plain boxes stand
in). The left (occupied/lit) emitter shows a visible rising grey wisp trail; the right
(empty) emitter shows none. The "nobody home" tell reads correctly.

**Pass condition met.**

---

## AC — Grass/foliage sway via vertex-shader wind

**Implementation**: `neues-spiel/assets/shaders/foliage_sway.gdshader` — a SEPARATE
`ShaderMaterial` from `terrain_chunk.gdshader`, never applied to committed-block
terrain. Vertex-only sine displacement driven by engine `TIME`, phased by world
position so instances don't sway in lockstep. Placeholder-texture stub (per-vertex
`COLOR`) mirrors the terrain shader's own deferred-texturing precedent; culling left
at the explicit `cull_back` default (no `cull_disabled`).

**Automated coverage**: `tests/unit/presentation/foliage_sway_shader_contract_test.gd`
(6 tests) — shader loads/compiles headless, uniforms (`wind_speed`/`wind_strength`)
declared, vertex function displaces using `TIME`/`VERTEX`, is a genuinely separate
file from the terrain shader, and — the whole-story "static foundation untouched"
guard — `terrain_chunk.gdshader` contains no wind/sway text and still explicitly
culls back.

**Screenshot**: `presentation-001-suba-foliage-sway-20260724-{1,2}.png` — a 5×5 patch
of foliage_sway-shaded quads placed on the actual generated terrain surface (ground
height resolved per-cell via `VoxelWorldGrid.get_cell`, so blades sit on top of the
real contour, not floating/buried), captured at two different elapsed engine times.
Small dark blade shapes are visible scattered across the terrain crest, following its
contour.

**Pass condition met** (vertex-shader-driven displacement proven by the automated
contract test; screenshots are the companion visual confirmation — subtle at this
placeholder scale/lighting, expected until real vegetation art/mesh work lands).

---

## AC — Interior warm-detail clutter, static, no motion cost

**Implementation**: `neues-spiel/src/presentation/interior_clutter_placer.gd`.
Data-driven `clutter_transforms` (scene-authored, analogous to `Valley.tscn`'s
structural-child wiring), spawns one static `MeshInstance3D` per transform with both
`set_process(false)`/`set_physics_process(false)` explicitly forced — the "no motion
cost" guarantee is structural, not just an absent override. Falls back to a
placeholder `BoxMesh` when no real prop mesh is assigned (no prop-art pipeline exists
yet).

**Automated coverage**: `tests/unit/presentation/interior_clutter_placer_test.gd` (7
tests) — headless setup, one prop per authored transform in order, determinism of
spawn pattern (same transforms in → same transforms out, two independent instances
compared), every spawned prop verified static, placeholder-mesh fallback.

**Screenshot**: `presentation-001-suba-interior-clutter-20260724-1.png` — four
placeholder clutter props (small boxes standing in for mugs/tools) visible against a
placeholder room's back wall and floor.

**Pass condition met.**

---

## AC — Torch/lantern flicker via light-energy noise, sub-3Hz (A5)

**Implementation**: `neues-spiel/src/presentation/torch_flicker.gd` +
`ambient_life_config.gd`. Drives an externally-assigned `Light3D`'s `light_energy`
from a small, deterministic sum-of-sines waveform (`compute_energy(time)`) — zero RNG
anywhere. Every configured component frequency is clamped strictly below 3.0 Hz
(`AmbientLifeConfig.TORCH_FLICKER_FREQUENCY_HZ_MAX = 2.9`) by `validate()`'s
single-field clamp+warn tier; an empty frequency list is a BLOCKING cross-value
invariant (no scalar to clamp to). Works identically for a fixed torch or a carried
lantern — the class does not own or create the light itself.

**THE binding sub-3Hz proof (asserted, not eyeballed)**:
`tests/unit/presentation/torch_flicker_test.gd`
`test_default_flicker_waveform_dominant_frequency_is_sub_3hz` and
`test_worst_case_all_components_at_clamp_ceiling_is_still_sub_3hz` numerically
estimate the combined waveform's oscillation rate via zero-crossing counting over a
10-second sampled window (200 Hz sample rate) and assert it is below 3.0 Hz — both for
the default config AND for a deliberately worst-case config (every component pinned
at the clamp ceiling, the fastest waveform this class can ever produce). A sum of
sine components each individually bounded below a frequency has no Fourier content
above that same bound (linearity), so bounding every component is sufficient to bound
the whole waveform, not merely necessary — see the test file's doc comment for the
full argument. 7 tests total in this file, also covering determinism, a hand-derived
ground-truth sample at t=0, non-negative energy across the sample window, and defense
in depth (an unvalidated above-cap config still gets caught the moment `validate()`
runs).

**Screenshot** (companion visual evidence only):
`presentation-001-suba-torch-flicker-20260724-{1,2}.png` — a fixed torch and a
carried-lantern stand-in (each an `OmniLight3D` driven by its own `TorchFlicker`,
plus a small emissive sphere visualizing the sampled `light_energy` as brightness,
since `Light3D` itself has no rendered geometry), captured at two elapsed times
logged as `fixed_energy=1.199…` / `fixed_energy=0.965…` (console log, ~20% swing
visible as a brighter/dimmer glow pool on the terrain beneath each light).

**Pass condition met** — sub-3Hz is a proven numeric property, not an eyeballed one.

---

## Whole-story AC — Committed-block materials untouched

**Verification**: `foliage_sway_shader_contract_test.gd`'s
`test_terrain_shader_contains_no_wind_sway_text` and
`test_terrain_shader_still_explicitly_culls_back` scan
`terrain_chunk.gdshader` directly and assert no wind/sway text was added and its
`cull_back` + non-`CULL_DISABLED` contract (vox-007) is unweakened. No file under
`src/voxel_world/` was modified by this story.

**Pass condition met.**

---

## Whole-story AC — Art-director / creative-director sign-off

**Status**: NOT part of this evidence pass — per task scope, CD sign-off happens in a
separate creative-director review after this implementation. This document and the
screenshots above are the input to that review.

---

## Sign-off

**Lead**: (awaiting art-director/creative-director review — evidence prepared for
that pass, not yet countersigned)
