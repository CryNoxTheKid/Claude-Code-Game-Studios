# Epic: Resource & Item Database

> **Layer**: Foundation
> **GDD**: design/gdd/resource-item-database.md
> **Architecture Module**: Resource & Item Database (item/material definitions; boot-time validation; `missing_item` fallback; category/tier/material_family vocabulary)
> **Manifest Version**: 2026-07-23
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories resource-item-database`

## Overview

Resource & Item Database (RID) is the Foundation data-definition system: the
single source of truth for every material/item type (id, display name, category,
stack rules, material family, base properties). It is an Autoload (one of only
two), loads its definitions once at boot, and is the BLOCKING boot gate — its
`validation_complete(result)` signal is what `GameWorld` waits on before wiring
any injected-tier module; a Failed validation is a terminal halt. It exposes only
read-only queries (`get_by_id`, `list_ids_by_*`, `list_all_ids`) returning
getter-only immutable views, with a logged-once `missing_item` fallback. Other
systems store opaque string ids only.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0006: Data Definition Immutability & Reference Format | Two-type split — private `ItemDefinitionResource` (authoring) + public getter-only `ItemDefinition extends RefCounted` (fresh wrapper per call, wraps not copies); `visual_asset` is a typed `Mesh`, never a path string; never defensive-copy via `duplicate()`; multi-cell furniture adds a `footprint` field | MEDIUM |
| ADR-0005: Boot Sequencing & Initialization Gate | RID is the boot gate — `validation_complete` drives `GameWorld`'s Booting→Wiring transition; Failed = terminal halt (same severity model as config blocking-invariants) | MEDIUM |
| ADR-0002 / ADR-0001 | RID Autoload `load()`s its own config; definitions are `.tres`; validation once at boot | MEDIUM |

Engine-risk basis (4.7 policy): **MEDIUM** — the data/resources domain is flagged
MEDIUM. `FileAccess.store_*` return-type changed (4.4 — check it), and the
immutability pattern deliberately AVOIDS `duplicate_deep()` (4.5+) even though it
exists. LLM instinct is also wrong that Autoloads ready after the Main Scene (they
ready before, synchronously, in declared order — load-bearing for the boot gate)
and that `load()` on the same `.tres` returns a fresh object (it returns the
shared cached one). Cross-reference `docs/engine-reference/godot/` before any
FileAccess/Resource API is finalized.

## GDD Requirements

40 TRs registered (`TR-resource-item-database-*`). Coverage:

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-resource-item-database-010 / -023 | Immutable definition views; `visual_asset` typed reference; no setters | ADR-0006 ✅ |
| TR-resource-item-database-019 | `validation_complete` signal drives the boot gate | ADR-0005 ✅ |
| TR-resource-item-database-007 | Headless-mockable via DI | ADR-0001 ✅ |
| (validation) | Boot-time validation; `missing_item` fallback logged once/load | ADR-0006 + GDD ✅ |

**Coverage summary**: All ADR-worthy TRs trace to Accepted ADRs; remaining TRs
are GDD-specified. No untraced requirements.

**At-risk / deferred**: The `footprint` field for multi-cell furniture (ADR-0006
slice propagation) is added when the RID story lands — a known, scoped addition,
not an open decision.

## Milestone 01 Notes

- No tech-debt or CD-protected item lands here.
- M01 scope = full definitions + boot-time validation + immutable query API,
  serving as the boot gate the whole Foundation Spine waits on. It has no
  runtime dependencies and can be built first alongside the spine.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/resource-item-database.md` are verified
- A test proves getter-only immutability and the terminal-halt-on-Failed path
- Logic stories have passing test files in `tests/`

## Next Step

Run `/create-stories resource-item-database` to break this epic into implementable stories.
