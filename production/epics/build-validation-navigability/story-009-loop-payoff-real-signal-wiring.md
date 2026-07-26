# Story 009: Loop-payoff surface receives real signals (milestone criterion #7)

> **Epic**: Build Validation & Navigability
> **Status**: Ready
> **Layer**: Feature (wiring into Presentation)
> **Type**: Integration
> **Estimate**: ~0.5 agent-day
> **Manifest Version**: 2026-07-23
> **Last Updated**: —

## Context

**GDD**: `design/gdd/build-validation-navigability.md` (Rule 10 signal contract) + `production/milestones/milestone-02-mvp-completion.md` criterion #7
**Requirement**: `TR-build-validation-navigability-039`, `TR-build-validation-navigability-040`, `TR-build-validation-navigability-036`, `TR-build-validation-navigability-045`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001 (Inter-System Reference & DI Pattern)
**ADR Decision Summary**: Injected-tier wiring only — the presentation surface binds to this module's signals through typed `@export` references wired in `GameWorld.tscn`, with all wiring in an explicitly-callable `setup()`. `LoopPayoffSignalSurface` is documented as *"the shared dependency later systems bind to"*; this story is that binding.

**Engine**: Godot 4.7-stable | **Risk**: MEDIUM
**Engine Notes**: Default (synchronous) connections preserve Rule 10's "one pass, one frame" reconciliation unit — do not add `CONNECT_DEFERRED` on this path.

**Control Manifest Rules (this layer)**:
- Required: injected-tier binding; `setup()` asserts the surface reference is wired; `_ready()` does nothing beyond optionally calling `setup()`.
- Forbidden: placeholder/stub emitters remaining anywhere on the payoff path; reshaping `LoopPayoffSignalSurface`'s parameter list (its own contract: a new payoff kind is a new `payoff_type` value, *"never a new signal or a reshaped parameter list"*).
- Guardrail: the wiring adds no analysis work — it is a pure adapter over emissions story 006/007 already produce.

**Open decision blocking this story** (Epic Known Conflict 5): the landed surface
exposes exactly `payoff_signaled(payoff_type: StringName, subject: StringName)`
and `emit_payoff(payoff_type, subject)`. That shape **cannot carry**
`room_recognized`'s `celebrate: bool` / `pass_group_id` pacing contract, which
criterion #7 names explicitly. Resolution options: (a) the adapter encodes pacing
into `payoff_type` (e.g. a distinct celebrating vs. quiet kind) and the consumer
re-queries this module for the group; (b) the surface gains a second, additive
contract. **Technical-director + creative-director decide** — the celebration is
a CD-protected beat (Art Bible §5.6). Do not pick unilaterally.

---

## Acceptance Criteria

*From milestone criterion #7 and GDD Rule 10's signal contract, scoped to this story:*

- [ ] The loop-payoff surface fires off the **genuine** `room_recognized` emission — including its `celebrate` / `pass_group_id` pacing contract, preserved through the adapter per the resolution of Known Conflict 5 — not a stub.
- [ ] The loop-payoff surface fires off the **genuine** `shelter_status_changed` emission (item id, `sheltered: bool`), not a stub.
- [ ] A **grep-guard proves no placeholder emitter remains on the payoff path** — the guard is part of the test suite, not a one-off manual check.
- [ ] Pacing survives the adapter: a same-pass group of recognitions reaches the surface as **one** celebration event (shared `pass_group_id`, all `celebrate = true`), and a later-pass recognition inside `room_cue_cooldown_ticks` reaches it as quiet status (`celebrate = false`) — never as a second celebration.
- [ ] `emit_payoff`'s existing idempotency holds under real emissions: re-emitting the same `(payoff_type, subject)` key refreshes in place and never grows `get_active_payoff_count()`.
- [ ] The binding is injected-tier: the surface reference is a typed `@export` wired in the scene, asserted in `setup()`, and the whole path is exercisable headless with a mocked surface.
- [ ] This story adds **no** analysis behavior — the adapter emits only in response to emissions stories 006/007 already produce, and the four-signal contract (TR-039) is unchanged.

---

## Implementation Notes

*Derived from ADR-0001 Implementation Guidelines:*

- The adapter is thin by design: subscribe to `room_recognized` and `shelter_status_changed`, translate to `emit_payoff(payoff_type, subject)`. `subject` is the item id for shelter and a stable region/group key for recognition.
- Building UI has ruled `room_recognized` has **no HUD surface** (its Rule 9d) — the celebration is exclusively the in-world highlight + chime. Do not route it to a HUD.
- The grep-guard should assert the absence of the scaffolding-era stub emitters in `neues-spiel/src/` on the payoff path, in the same style as the project's existing non-writer grep guards.
- Milestone evidence expects both a test and a written capture: `neues-spiel/tests/integration/presentation/loop_payoff_real_signal_test.gd` plus `production/qa/evidence/loop-payoff-wired-evidence-*.md`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Stories 006/007: the emissions themselves and their pacing logic.
- Story 008: the Warning/Info tiers (not part of criterion #7's payoff path).
- `presentation-001` / Art Bible: the highlight and chime treatment.

---

## QA Test Cases

- **Real `room_recognized`**: Given a region transitioning to Room, When the pass completes, Then the surface receives a payoff for it with the pacing contract intact.
- **Real `shelter_status_changed`**: Given a bed transitioning to sheltered, When the pass completes, Then the surface receives a payoff carrying that item id.
- **Grep-guard**: Given the source tree, When the guard runs, Then no placeholder/stub emitter is found on the payoff path.
- **Same-pass group**: Given two rooms recognized in one pass, When observed at the surface, Then it reads as ONE celebration event, not two.
- **Cooldown**: Given a recognition in a later pass inside the cooldown window, When observed, Then it arrives as quiet status, not a celebration.
- **Idempotency**: Given the same `(payoff_type, subject)` emitted twice, When measured, Then `get_active_payoff_count()` is unchanged.
- Edge cases: the load pass produces zero payoff emissions (transitions are silent there); a missing surface reference makes `setup()` assert rather than silently no-op.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `neues-spiel/tests/integration/presentation/loop_payoff_real_signal_test.gd` — must exist and pass. Companion capture: `production/qa/evidence/loop-payoff-wired-evidence-*.md`.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: 006 (`shelter_status_changed`), 007 (`room_recognized` + pacing). **External blocker**: the payoff-surface signal-shape decision (Epic Known Conflict 5).
- Unlocks: milestone criterion #7

