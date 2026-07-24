# Milestone Review: 01 — Foundation + Core (Playable Integrated Build)

**Generated**: 2026-07-24 · **Producer** · Review mode: **lean** (PR-MILESTONE gate skipped — Go/No-Go presented without a spawned producer sub-verdict; I am the producer of record here).

## Overview

- **Target**: ~22 expected working days / ~3 sprints (optimistic 18 / pessimistic 29)
- **Elapsed**: 7 sprints closed (S1–S7), all single-session, **zero carryover, zero unplanned rework across every sprint**
- **Suite**: 843/843 blocking + 5 advisory perf, 0 orphans, green on every commit
- **The milestone's true spine is DONE**: the integrated build-and-inhabit loop assembles, runs headless in the commit gate, and now closes end-to-end (villagers build what the player draws). That was the milestone's highest-risk deliverable and it landed clean.

> **Numbering note**: criteria are numbered 1–13 in the milestone-file checkbox order (the numbering S6's notes used). Sprint-7's prose labels the closed job loop "criterion #2" — that is a labeling slip; milestone-file #2 is "Foundation systems integrated." The closed loop deepens #6/#7/#8. No status changes from this — flagged only to keep the record clean.

## Per-Criterion Status

| # | Criterion | Status | Evidence / Gap |
|---|-----------|--------|----------------|
| 1 | Boot + DI + config spine (headless boot test) | **MET** | `spine-001..004` (S1–S2), `scene-002` boot-gate, ADR-0005 gate; `spine-004` headless boot integration test green |
| 2 | Foundation systems integrated (5 systems, per-system tests, one scene) | **MET** | Scene/World closed S3, Camera closed S4, Time&Tick/RID/Voxel all green; `scene-004` crown (S6) runs all five in one scene |
| 3 | Mesher CW-winding rewrite + culling RE-ENABLED | **MET** | `vox-007` (S4) — CW winding + backface culling ENABLED, TECH DEBT 1 retired |
| 4 | Per-tick re-tuning pass (recorded config change) | **OPEN** | Blocked **solely** on a systems-designer/game-designer VALUE DECISION (deferred S5/S6/S7). Measurement basis now exists (`villager-ai-025`: worst 3.02ms @30 villagers, 5.5× under budget; chronically-full-queue finding). Stories `villager-ai-022` + `tick-007` exist, un-run |
| 5 | ADR-0015 C1/C4 residency tuning (stories w/ measured values) | **PARTIAL** | Invariants **fully certified** via `vox-013/014` (S6) — ADR-0015 Accepted. BUT the criterion names *tuning stories with measured values*: `vox-016` (C1 async-cap/gen-cost) + `vox-017` (C4 drain) exist un-run. **Producer decision needed: does #5 close on certification, or does it require vox-016/017's measured values?** |
| 6 | Building System playable (full lifecycle) | **PARTIAL** | Happy path IN: draft→release→build→done, generic block placement, plan-only undo core (`019/020/021/022/029/002/004/030/005/032/033/003`). **NOT built**: room/roof/house **tools** (`024/025/026/027`), change orders (`007`), worker-executed demolition (`009/031/017`), pause/resume (`006`), click-selection (`008`) — all exist as unscheduled story files. Criterion as written names change orders + demolition + tools → not fully met |
| 7 | Villager AI playable (incl. anti-stuck watchdog + seal prevention + F3 telemetry) | **PARTIAL** | Core IN: FSM, AStar3D, occupancy, deterministic ordering (ADR-0009), threading (ADR-0008) — `001..012` green. **NOT built**: the entire anti-stuck/seal-prevention safety layer — `013` nudge-aside (F4), `014` rescue-BFS (F5), `015` unstuck-watchdog + F3 telemetry, `016` seal-prevention/livelock. Criterion explicitly requires watchdog + seal prevention + F3 telemetry → not met. (Milestone goal itself: "live inside the world **without getting stuck**") |
| 8 | Integrated playable build (E2E LOOP on every commit) | **MET** | `scene-004` crown (S6) — assembled GameWorld E2E: real-pipeline block placement AND a villager walks; in the commit gate. Deepened by `villager-ai-012` (S7) closed loop |
| 9 | Ambient-life wave 1 (CD-protected) | **PARTIAL** | Sub-A CD-**APPROVED WITH ADVISORIES** (2026-07-24): smoke/sway/clutter/flicker, sub-3Hz proven numerically. **CD ruling: do NOT mark "world lacks life" closed — finding stays OPEN until Sub-B lands.** Sub-B (`villager-ai-019` idle behaviors) unscheduled; Valley golden-hour re-shoot owed (CD advisory #2) |
| 10 | Loop-payoff communication scaffolding (CD-protected) | **MET** | `presentation-002` (S5) CD-approved — scaffolding half; the recovery *mechanic* is M02 by design |
| 11 | All S1/S2 bugs resolved | **MET** | 0 open S1/S2. One S7 process incident (presentation-001 GPUParticles orphans, exit-code mismatch) root-caused + fixed same-day; caught by parent verification |
| 12 | Performance: 60 FPS on production window, culling RE-ENABLED | **OPEN** | **NO STORY FILE EXISTS.** `vox-015` (S6) landed the streaming *machinery*; `villager-ai-025` measured the *CPU/AI* frame budget (PASS, 3.02ms). Neither measures the *rendering/culling 60-FPS* target on the live Valley. Must `/create-stories` (suggested `voxel-world/story-018-live-view-window-valley-wiring-and-60fps-measurement`) |
| 13 | Build stable (E2E green) for the pre-milestone review window | **PARTIAL** | E2E LOOP in the commit gate since S6, green on every commit. But **"the review window" is undefined** — no agreed observation duration was set. Define the window (e.g., N green commits / sessions) and confirm it elapses |

**Tally**: MET 6 (#1,2,3,8,10,11) · PARTIAL 5 (#5,6,7,9,13) · OPEN 2 (#4,12)

## Honest Go/No-Go Assessment

**Recommendation: CONDITIONAL — NOT complete; NO-GO to declare M01 done today; GO to a closing plan gated on two scope decisions + the long-blocked designer decision.**

The good news is the load-bearing news: the milestone's *reason to exist* — proving the build-and-inhabit loop on the production codebase, integrated and green — is **MET and durable**. The two crowns (assembled E2E, then the closed job loop) landed with zero carryover across seven clean sprints. The highest-risk, most-uncertain work is behind us.

The honest problem: the milestone's **acceptance wording for #6 and #7 is broader than what the crowns delivered.** The sprints built the *spine* of Building and Villager AI; the *breadth* the criteria name — building tools, change orders, demolition, and the entire villager anti-stuck/seal-prevention ladder — is unbuilt (though fully storyed). Two criteria (#4 re-tune, #12 60-FPS) are genuinely OPEN, and #12 has no story and carries the one real unknown (rendering could surface remediation).

Sized strictly as written, remaining work is **~18–22 agent-days ≈ 2 more sprints**, not 1. That number collapses toward **~1 sprint** if the #6/#7 breadth is trimmed by scope decision to the loop-critical subset. **That scope decision — not capacity — is what determines whether M01 closes in S8 or S9.** This is the fork to put in front of the CD/game-designer before S8 planning.

## Critical Path to Close (sized in agent-days)

Ordered by leverage. Decisions first — two of them gate everything downstream.

1. **[DECISION, day 0] Scope ruling on #6 + #7 breadth** — producer-facilitated, CD + game-designer. *Does M01 require building tools (`024/025/026/027`) + change orders (`007`) + demolition (`009/031`), and the full anti-stuck ladder (`013/014/015/016`) — or does the happy-path loop + a minimal watchdog satisfy the milestone goal ("live inside the world without getting stuck")?* This ruling sets total remaining scope (1 vs 2 sprints). **~0.5 ad facilitation.**
2. **[DECISION, day 0] The re-tune value decision (#4)** — 4th time on the block (deferred S5/S6/S7). Measurement basis now exists. Once numbers land: `villager-ai-022` + `tick-007` as one coordinated config change. **~1.5 ad after decision.**
3. **[#12, early] Create + run the 60-FPS measurement story** — new `voxel-world/story-018`: wire the view-window stream into the live Valley, profile 60 FPS with culling on the production window. Do this early — it is the one unretired unknown. **~2–3 ad + unknown remediation risk.**
4. **[#7 minimum] Anti-stuck watchdog + seal prevention** — at minimum `villager-ai-015` (watchdog + F3 telemetry) + `016` (seal/livelock). Core to the milestone goal. Nudge-aside (`013`) / rescue-BFS (`014`) escalation tiers can follow if the base suffices. **~2–3 ad base, ~4–5 ad full ladder.**
5. **[#5 close] Confirm closure basis** — certification (done) vs run `vox-016/017` measured-value tuning stories. **0 ad if certification accepted; ~2 ad if stories required.**
6. **[#9 close] CD ruling + Sub-B** — does #9 close on Sub-A-present, or require `villager-ai-019` + presentation Sub-B + Valley re-shoot? **~2.5 ad if Sub-B required (CD-protected).**
7. **[#6 breadth] Only if scope ruling holds it** — tools + change orders + demolition. **~6–8 ad.**
8. **[#13] Define + observe the stability window** — minimal dev; a producer definition + green-commit observation. **~0 ad dev.**

## Sprint 8: Must vs. Defer

**MUST (unblock decisions + retire unknowns + close the safety-critical gap):**
- **Facilitate the two scope decisions (#6/#7 breadth) + surface the #4 re-tune decision** — top producer action, day 0. Nothing sizes correctly until these land.
- **`villager-ai-022` + `tick-007`** — the coordinated re-tune, the moment numbers exist (#4).
- **Create + run `voxel-world/story-018`** — the missing 60-FPS measurement (#12); retire the unknown early.
- **`villager-ai-015` + `016`** — watchdog + telemetry + seal prevention (#7 core; directly serves "without getting stuck").
- **Define the #13 stability window** and start the green-commit observation clock.
- **Resolve #5 closure basis** (certification vs `vox-016/017`).

**CAN DEFER (with reasons):**
- **#9 Sub-B** (`villager-ai-019` + presentation Sub-B + golden-hour re-shoot) — CD-protected, but CD framed it as a later wave; if #9 closes on Sub-A-present, defer to M02. Bundle the Valley re-shoot with #12's Valley-wiring if both run. **CD ruling required — do not silently drop.**
- **Building lifecycle breadth not loop-critical** — pause/resume (`006`), click-selection (`008`), furniture (`016/017/028`), dig/mining (`013/014`), tool-batch (`018`) — M02 unless the scope ruling pulls them.
- **Anti-stuck escalation tiers** — nudge-aside (`013`, F4) + rescue-BFS (`014`, F5) can follow the base watchdog if `015/016` satisfy the goal.

## Flagged Gaps in Epic Story Coverage
- **Criterion #12 has NO story file** — the only true missing story. `/create-stories` before it can be scheduled.
- **Criterion #4** — stories exist (`villager-ai-022`, `tick-007`); blocker is a decision, not a file.
- **Criteria #5/#6/#7/#9** — all remaining work has story files; the gap is scheduling + (for #6/#7) a scope ruling, not authoring.

## Action Items
| # | Action | Owner | When |
|---|--------|-------|------|
| 1 | Facilitate CD/game-designer scope ruling on #6 (tools/change-orders/demolition) + #7 (anti-stuck ladder depth) | producer | S8 day 0 |
| 2 | Surface the #4 re-tune value decision to systems-designer/game-designer (4th ask) | producer | S8 day 0 |
| 3 | `/create-stories` for the #12 60-FPS-with-culling measurement story | producer | before S8 planning |
| 4 | Define the #13 stability observation window | producer | S8 |
| 5 | Confirm #5 closure basis (certification vs vox-016/017) | producer + TD | S8 |
| 6 | Re-baseline the M01 calendar estimate now the loop has landed (S6 action item) | producer | S8 |
