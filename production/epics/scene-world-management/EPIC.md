# Epic: Scene/World Management

> **Layer**: Foundation
> **GDD**: design/gdd/scene-world-management.md
> **Architecture Module**: Scene/World Management (World Root lifecycle; the 3-signal transition contract; scene attach/detach topology)
> **Manifest Version**: 2026-07-23
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories scene-world-management`

## Overview

Scene/World Management owns the World Root node and is the single legal entry
point for scene topology change. It exposes the transition state machine
(Booting / Active / Transitioning) and the `transition_begun()` /
`transition_ended(success)` contract that Camera & Input (Suspended), Building
System (undo-clear on COMPLETE), and the UI systems key off. At MVP it manages
the single always-loaded Valley scene; the two-live-scenes Valley+Dungeon model
is Vertical-Slice-tier and enters via ADR-0013. It consumes the Foundation Spine
epic's boot gate (it does not own the gate) and guarantees the World Root is
never freed and `change_scene_to_file`/`current_scene` are never used.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: Boot Sequencing & Initialization Gate | Scene/World Management's Booting state is the boot-gate host; Valley attaches only after RID Ready (gate mechanism owned by `foundation-spine`) | MEDIUM |
| ADR-0013: Multi-Scene Concurrency Model | ONE shared `World3D`, Dungeon at `100_000`-unit offset; exactly one `WorldEnvironment`; per-scene toggles for `Camera3D.current`/`AudioListener3D`/`DirectionalLight3D.visible`, centralized in `_activate_scene`/`_deactivate_scene` — **VS-tier** (no Dungeon at MVP) | MEDIUM |
| ADR-0012: Save/Load Serialization Strategy | Savepoints fire exclusively on `transition_ended(success=true)`; Scene/World Management triggers, never owns, save data — **VS-tier** | MEDIUM |
| ADR-0001: Inter-System Reference & DI Pattern | Injected-tier module; wired in `GameWorld.tscn`; logic in `setup()` | MEDIUM |

Engine-risk basis (4.7 policy): MEDIUM. MVP is single-scene and LOW-risk on its
own, but the Accepted multi-scene decision (ADR-0013) touches post-cutoff engine
facts the LLM does not know: `_input`/`_unhandled_input` dispatch is SceneTree-
global (not per-Viewport), `DirectionalLight3D` affects the whole `World3D`, and
float32 ULP scales with magnitude (why the offset is kept at `100_000`). Verify
against `docs/engine-reference/godot/` before any scene-concurrency API is used.
The banned APIs (`change_scene_to_file`/`reload_current_scene`/direct
`current_scene`) are a code-review-blocking guardrail.

## GDD Requirements

34 TRs registered (`TR-scene-world-management-*`). Coverage:

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-scene-world-management-004 | Boot gate: RID Ready before Valley attaches; DB failure → terminal halt | ADR-0005 ✅ (host here) |
| TR-scene-world-management-010 | Exactly one scene has control; neither receives input mid-transition | GDD-specified ✅ |
| TR-scene-world-management-013 / -024 | Savepoint binds to transition-COMPLETE only, never begin/abort | ADR-0012 ✅ (VS-tier) |
| TR-scene-world-management-033 | Two-live-scenes partitioning (shared World3D, offset, per-scene toggles) | ADR-0013 ✅ (VS-tier) |
| TR-scene-world-management-030 | All transition tunables from config | ADR-0002 ✅ |

**Coverage summary**: All ADR-worthy TRs trace to Accepted ADRs; remaining TRs
are GDD-specified (traced to the GDD + architecture.md Module Ownership). No
untraced requirements.

**At-risk / deferred**: TR-033 (multi-scene) and TR-013/-024 (savepoint binding)
are Accepted but **VS-tier** — out of Milestone 01 scope. MVP builds only the
single-Valley lifecycle + the transition-signal contract stubs the boot path
needs. Do not build Dungeon scene concurrency in M01.

## Milestone 01 Notes

- No tech-debt or CD-protected item lands here.
- M01 scope = World Root + boot-gate integration + single-Valley attach + the
  transition-signal contract (Foundation systems must "run together in one scene"
  per the milestone success criteria). Multi-scene is M02+/VS.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/scene-world-management.md` are verified
- Logic/Integration stories have passing test files in `tests/`
- A headless test proves World Root persistence and the one-begin→one-complete/abort invariant

## Next Step

Run `/create-stories scene-world-management` to break this epic into implementable stories.
