# Last Seal — Vertical Slice

> VERTICAL SLICE — NOT FOR PRODUCTION (reference only; production is rewritten from scratch)

## Hypothesis

A player, starting from nothing, draws a room, furnishes it with a bed, and
watches a villager move in and sleep there — experiencing "stewardship of a
place that feels alive" — within **5 minutes of unguided play**, with the
settlement staying cozy and readable inside the large world ("cozy at scale").
And: this loop is buildable at representative quality within **7 build days**.

## How to run

```
godot --path prototypes/last-seal-vertical-slice
```

Controls: WASD pan · Q/E + middle-drag rotate · wheel zoom · 1-5 tools ·
LMB place/commit · (Block tool) Ctrl+LMB remove · right-click/Esc cancel ·
R/F wall height · T/G material · B/V roof formation · Ctrl+Z/Y undo/redo ·
Space pause · +/- speed.

## Scope

All 11 MVP systems on a bounded settlement region (full 2000x2000x32 data
world, fixed view window, camera pan clamped, NO streaming). 1 villager.
Warmth-as-reward light + distance fog per the art bible.
OUT: save/load, doors/windows, combat, audio (beyond 2-3 cues), main menu,
multiple villagers, streaming.

## Status

**In progress** — Day 1 (2026-07-12): scaffold, contracts, core autoloads.

## Findings

(updated when the slice concludes — see REPORT.md)
