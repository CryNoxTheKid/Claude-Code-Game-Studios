# Resource & Item Database

> **Status**: Draft
> **Author**: user + Claude Code Game Studios agents
> **Last Updated**: 2026-07-09
> **Last Verified**: 2026-07-09
> **Implements Pillar**: None directly — Foundation infrastructure for Pillar 1 (building materials) and Pillar 2 (settlement economy)

## Summary

Resource & Item Database is the Foundation-layer data definition system for
every material, item, and resource type in the game — a single source of
truth for what a "thing" is (id, display name, category, stack rules,
material family, base properties) that Building System, Township Progression,
and future economy/inventory systems query rather than duplicate.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `None`

## Overview

Resource & Item Database owns the static, data-driven definition of every
resource and item in the game world — not their placement, ownership, or
behavior, only their *definition*. Per the project's coding standard that
gameplay values must be data-driven, it is authored as a set of external
data resources rather than hardcoded values, and exposed through a lookup
API that other systems query by id.

It exists because multiple systems need to agree on the same facts about a
given resource or item: the Building System needs to know a material is
valid for placement and which visual material family it belongs to; future
Storage & Inventory needs to know whether an item stacks and can be hauled;
Gathering & Production Chains needs to know what a recipe's inputs and
outputs refer to. Without one authoritative database, these facts would be
duplicated across systems and drift out of sync.

**Explicitly out of scope**: this system does not track where resources are
(Storage & Inventory, Alpha), who carries them to a build or craft site
(Villager AI hauling behavior), what they cost to place (Building System),
or how they are produced (Gathering & Production Chains). It defines the
nouns those systems act on — including the definition fields they will need
later (stackability, haulability, storage category) so the database does
not need a breaking rework when those Alpha systems arrive.

This system has no player-facing behavior of its own — no UI, no on-screen
representation. Players experience it exclusively through the systems built
on top of it: choosing a material in the Building System's placement tools,
or watching villagers gather and consume resources over time.

## Player Fantasy

None directly — this is pure infrastructure. Players never see or touch the
database itself; they feel what it enables through other systems:

- **Building System (Pillar 1)**: the fantasy of choosing *this* wood, *this*
  stone for a wall lives in the building tools — but the palette of materials
  they choose from is defined here.
- **Township Progression / economy (Pillar 2)**: the fantasy of a settlement
  that grows richer — new materials and items appearing over time — is
  delivered by unlock systems, but every unlockable thing is defined here.

The indirect design obligation this creates: material and item definitions
must carry enough identity (name, family, visual hookup per the Visual
Direction Note's material↔meaning color language) that the systems built on
top can make each material feel distinct rather than interchangeable.

> `creative-director` not consulted — Lean mode (non-high-risk section).

## Detailed Design

### Core Rules

1. **One definition per thing.** Every resource, material, and item in the
   game has exactly one definition in this database, identified by a unique,
   stable `snake_case` string id (e.g. `wood_block`). An id, once shipped in
   a save file, is never renamed or reused for a different thing (see Edge
   Cases for handling retired ids).
2. **Definitions are static data.** Definitions are authored as external
   data resources (per the project coding standard: gameplay values are
   data-driven, never hardcoded). The database loads once at boot,
   validates, and is immutable for the rest of the session. Nothing in the
   game ever modifies a definition at runtime.
3. **Definition ≠ availability.** Whether a player can currently use an item
   is not stored here. Unlock/availability state is owned by Recipe &
   Blueprint Unlocks / Township Progression (Alpha); the database only
   provides the `tier` field those systems key off.
4. **Definition schema.** Every entry carries these fields:

   | Field | Type | Required in MVP | Notes |
   |-------|------|-----------------|-------|
   | `id` | string (snake_case) | Yes | Unique, stable, never reused |
   | `display_name` | string | Yes | Player-facing name (localizable later) |
   | `category` | enum | Yes | See Rule 5 |
   | `material_family` | enum or none | Yes for building materials | `wood` / `stone` / `thatch` per the Visual Direction Note; none for non-material items |
   | `tier` | int ≥ 0 | Yes | `0` = free bootstrap material (see Rule 6); higher tiers gated by future unlock systems |
   | `visual_asset` | asset reference | Yes | Mesh/material hookup — the single place art assets bind to game data |
   | `stackable` | bool | Authored, unused until Alpha | Pre-provisioned for Storage & Inventory |
   | `max_stack_size` | int ≥ 1 | Authored, unused until Alpha | Only meaningful when `stackable` |
   | `haulable` | bool | Authored, unused until Alpha | Pre-provisioned for Villager AI hauling |
   | `storage_category` | enum | Authored, unused until Alpha | Which stockpile type accepts this item |

   Fields marked "Authored, unused until Alpha" are required-present in MVP
   data files (boot validation enforces presence); only their *consumption*
   is deferred to Alpha.

5. **Fixed category set.** The schema defines five categories from day one;
   MVP fills only the first two with content:
   `building_material` (MVP), `furniture_fixture` (MVP),
   `raw_resource` (Alpha), `consumable` (Alpha), `equipment` (Alpha).
   Adding a category is a schema change (design decision), not a data edit.
6. **The tier-0 bootstrap set.** Exactly three building materials ship at
   tier 0 — `wood_block`, `stone_block`, `thatch_block` — one per material
   family in the Visual Direction Note. Tier 0 means: the Building System
   treats them as always available and free of resource cost in the MVP.
   This implements the systems-index resolution of the Building ↔ Township
   Progression circular dependency: building is usable before any economy
   system exists.
7. **MVP furniture content.** The `furniture_fixture` category is populated
   in MVP, but the exact entry list (which furniture, doors, windows) is
   owned by the Building System GDD — entries are authored here once that
   GDD names them. This GDD owns the schema, not the furniture list.
8. **Read-only lookup API.** Other systems query: get definition by id,
   list ids by category, list ids by material family, list all ids. There
   is no write API. The database performs no gameplay logic — it never
   computes costs, validates placement, or spawns anything.

### States and Transitions

*(System lifecycle — individual definitions have no state; they are
immutable data.)*

| State | Entry Condition | Exit Condition | Behavior |
|-------|-----------------|-----------------|----------|
| Unloaded | Before boot loading runs | Loading begins | No query is valid |
| Validating | Data files read | Validation passes or fails | Checks: id uniqueness, id format, known category, known material family, required fields present, `max_stack_size ≥ 1` where stackable |
| Ready | Validation passes | Never (persists for the session) | All queries valid; contents immutable |
| Failed | Validation fails | Session ends | Boot halts with an error naming every invalid entry (fail loudly at boot — never launch with a partially valid database) |

### Interactions with Other Systems

- **Building System** (MVP, downstream, primary consumer): queries
  `building_material` and `furniture_fixture` entries to populate its
  placement palette; reads `tier` to determine the free tier-0 set; reads
  `material_family` + `visual_asset` to render placed blocks. Building
  System owns costs and placement rules; this database owns what exists.
- **Voxel World** (Foundation sibling, shared vocabulary): Voxel World cells
  store "a block-type identifier and a material identifier" (its Core Rule
  2) — those identifiers are ids defined here. Voxel World treats them as
  opaque values and never queries this database; consumers that need meaning
  (Building System, rendering) resolve the ids here. No runtime dependency
  in either direction.
- **Storage & Inventory** (Alpha, downstream): will read `stackable`,
  `max_stack_size`, `haulable`, `storage_category`. Fields are authored now
  so no schema rework is needed then.
- **Gathering & Production Chains** (Alpha, downstream): recipe inputs and
  outputs will reference ids from this database.
- **Township Progression / Recipe & Blueprint Unlocks** (Alpha, downstream):
  unlock state references ids; `tier` provides the gating scaffold.
- **Save/Load & World Persistence** (Vertical Slice, downstream): save files
  store ids only — never definition contents. On load, stored ids are
  resolved against the current database (see Edge Cases for missing ids).
- **UI systems** (Building UI et al., downstream): read `display_name` and
  `visual_asset` for player-facing presentation.

## Formulas

*(`systems-designer` consulted — mandatory for this high-risk section even in
Lean mode. Verdict: this system owns no formulas.)*

**None.** This system stores authored configuration values (`tier`,
`max_stack_size`, etc.) — it computes nothing from them. A formula transforms
variable inputs into a derived output; this database only returns what was
written at authoring time, unchanged. All math that *consumes* these values —
build costs, stack-overflow handling, tier-gated unlock checks — is owned by
the downstream systems that query this database (Building System, Storage &
Inventory, Recipe & Blueprint Unlocks), consistent with the same verdict
reached for Scene/World Management.

Deliberately NOT formulas (and why):
- **Id lookup** — a native dictionary get-by-key; no tunable variables, no
  designer-authored curve, no output range. Engine mechanics, not game math.
- **Boot validation checks** — boolean pass/fail invariants against static
  schema rules (see States and Transitions), not value computations.
- **Tier → availability mapping** — a gating function needing inputs this
  system doesn't have (player progress, unlocked-tier state); owned by
  Recipe & Blueprint Unlocks / Township Progression per Core Rule 3.

## Edge Cases

1. **Save file references a retired id.** The database resolves any unknown
   id to a reserved built-in `missing_item` definition: category
   `building_material`, a deliberately conspicuous error visual (magenta
   placeholder material), display name "Missing Item". Player-built
   structures are preserved cell-for-cell — nothing is silently deleted —
   and each distinct missing id is logged once on load. (Same approach as
   Minecraft's missing-texture handling.)
2. **Runtime query for an unknown id.** The lookup API returns an explicit
   not-found result and logs the id; callers that must render *something*
   (world loading, above) resolve to `missing_item`. An unknown id reaching
   the API in normal play is a programming error, not a player-caused state.
3. **`missing_item` is reserved.** Boot validation rejects any authored
   entry using the id `missing_item` — it can never be overridden by data.
4. **Duplicate ids across data files.** Boot validation fails (Failed state)
   naming both files. The game never launches with an ambiguous database.
5. **Unknown category or material_family value in an entry.** Boot
   validation fails naming the entry — categories and families are fixed
   enums (Core Rule 5), not free text.
6. **Retired ids are never reused.** A retired-ids ledger is kept in the
   data set; boot validation rejects any new entry whose id appears in it.
   This protects old save files from resolving an id to the *wrong* thing —
   worse than resolving to nothing (case 1).
7. **`max_stack_size` authored on a non-stackable entry.** Ignored, with a
   validation warning (not a failure) — the field is only meaningful when
   `stackable` is true.
8. **Query for a category with no entries** (e.g. `raw_resource` in MVP).
   Returns an empty list — a valid result, not an error. Consuming systems
   must handle empty palettes.
9. **Entries with `tier > 0` exist while no unlock system does (MVP).**
   Consuming systems must treat any non-tier-0 entry as unavailable by
   default. The Building System's MVP palette therefore shows exactly the
   tier-0 set plus the MVP furniture list — a tier-3 item authored early
   must never leak into the palette just because it exists in the database.

## Dependencies

### Upstream (systems this one depends on)

**None.** This is a Foundation-layer leaf: it reads its own authored data
files at boot and depends on no other game system. (Boot sequencing — the
database must reach Ready before dependent systems initialize — is an
architecture concern for the future boot-order ADR, not a design dependency.)

### Downstream (systems that depend on this one)

| System | Tier | GDD Status | What it consumes |
|--------|------|-----------|------------------|
| Building System | MVP | Next in design order | Palette contents (`building_material`, `furniture_fixture`), `tier` for the free set, `material_family` + `visual_asset` for rendering |
| Voxel World | MVP | Designed | *Shared vocabulary only, not a runtime dependency*: the "material identifier" its cells store (its Core Rule 2) is an id defined here, treated opaquely |
| Storage & Inventory | Alpha | Undesigned | `stackable`, `max_stack_size`, `haulable`, `storage_category` *(provisional — fields pre-authored per this GDD's Overview)* |
| Gathering & Production Chains | Alpha | Undesigned | Recipe inputs/outputs reference ids *(provisional)* |
| Township Progression / Recipe & Blueprint Unlocks | Alpha | Undesigned | Unlock state references ids; `tier` is the gating scaffold *(provisional)* |
| Save/Load & World Persistence | Vertical Slice | Undesigned | Saves store ids only; load resolves ids via the lookup API incl. `missing_item` fallback (Edge Case 1) *(provisional)* |
| Building UI / Economy UI | MVP / Alpha | Undesigned | `display_name`, `visual_asset` for player-facing presentation *(provisional)* |

All "provisional" rows describe expected contracts with undesigned systems —
those GDDs must confirm or renegotiate these interfaces when authored.

## Tuning Knobs

This system is itself the game's primary tuning surface: every definition
field is authored external data (Core Rule 2), so "tuning" here means
editing entries, not code. The knobs below define the safe ranges those
edits must stay within.

| Knob | Default | Safe Range | Affects |
|------|---------|-----------|---------|
| `tier` (per entry) | 0 (bootstrap set) | 0–9 | Availability gating once unlock systems exist (Alpha). Raising a tier-0 material above 0 breaks the MVP bootstrap guarantee (Core Rule 6) — the tier-0 set must always contain at least one entry per material family |
| `max_stack_size` (per entry) | 50 | 1–999 | Storage density and hauling trip counts (Alpha). Values above ~200 risk trivializing storage as a constraint |
| `stackable` / `haulable` (per entry) | true | — | Whether Storage & Inventory / Villager AI hauling can interact with the item at all (Alpha) |
| Tier-0 set composition | `wood_block`, `stone_block`, `thatch_block` | ≥ 1 entry per material family | What players can build with for free in the MVP — changing this changes the entire early-game building experience and must stay aligned with the Visual Direction Note's three material families |

Not tuning knobs (and why): `id` (immutable contract — see Edge Case 6),
`category` / `material_family` enums (schema changes, design decisions per
Core Rule 5), `display_name` / `visual_asset` (content, not balance).

## Visual/Audio Requirements

The database has no visuals of its own, but it is the binding point where
art assets attach to game data (`visual_asset`, Core Rule 4):

- Every authored entry must reference a valid visual asset — boot validation
  treats a missing reference as a failure.
- The three tier-0 materials must visually match the Visual Direction Note's
  material↔meaning language: wood = warm brown, stone = cool grey,
  thatch = warm red-brown.
- **New asset required**: the `missing_item` placeholder needs a deliberately
  conspicuous error material (magenta, per Edge Case 1) — an actual asset to
  produce, not just a convention.
- Audio: none in MVP. If per-material sounds are wanted later (placement
  thunk per family), that becomes an additional schema field — see Open
  Questions.

## Game Feel

Not applicable — pure infrastructure with no player-facing interaction,
motion, or timing. Feel obligations live in the consuming systems (e.g. the
Building System's placement feedback). The database's only "feel" contribution
is indirect: distinct material identity (Player Fantasy section).

## UI Requirements

None owned by this system — it renders nothing. It supplies the fields UI
systems present: `display_name` (must be built localization-ready, even
though MVP ships English-only) and `visual_asset` (palette icons/previews
are derived from it by Building UI). Any UI for browsing the database
(debug item browser) is a development tool, not a player-facing requirement.

## Cross-References

- `design/gdd/game-concept.md` — Pillars 1 (building materials) and 2
  (settlement economy) that this Foundation system serves
- `design/art/visual-direction-note.md` — material families (wood/stone/
  thatch) and the material↔meaning color language the tier-0 set implements
- `design/gdd/systems-index.md` — Building ↔ Township Progression circular
  dependency resolution that Core Rule 6 (tier-0 set) implements
- `design/gdd/voxel-world.md` — Core Rule 2 (cells store this database's ids
  as opaque values; shared vocabulary, no runtime dependency)
- `.claude/docs/coding-standards.md` — "gameplay values must be data-driven"
  standard that Core Rule 2 implements
- `design/registry/entities.yaml` — registry entries for `wood_block`,
  `stone_block`, `thatch_block` (registered at this GDD's completion)

## Acceptance Criteria

*(`qa-lead` consulted — mandatory for this high-risk section even in Lean
mode. Review found 2 rewrites and 6 missing criteria; all incorporated.)*

1. **GIVEN** valid data files, **WHEN** the game boots, **THEN** the database reaches Ready and every authored entry is queryable by id.
2. **GIVEN** any authored entry, **WHEN** queried by id, **THEN** every returned field matches the authored data exactly.
3. **GIVEN** two entries with the same id, **WHEN** the game boots, **THEN** boot halts in Failed state with an error naming both entries.
4. **GIVEN** an entry with an unknown category or material_family value, **WHEN** the game boots, **THEN** boot halts naming the entry.
5. **GIVEN** an entry missing a required field, **WHEN** the game boots, **THEN** boot halts naming the entry and the field.
6. **GIVEN** an entry whose id is not valid snake_case (e.g. contains uppercase, spaces, or hyphens), **WHEN** the game boots, **THEN** boot halts naming the entry.
7. **GIVEN** a data set with two independent invalid entries (e.g. one missing a required field, one with an unknown category), **WHEN** the game boots, **THEN** boot halts and the error names both entries, not just the first encountered.
8. **GIVEN** a runtime query for an id not in the database, **WHEN** the lookup API is called, **THEN** it returns an explicit not-found result, logs the id, and does not crash.
9. **GIVEN** a save file containing an id not in the current database, **WHEN** the save loads, **THEN** all cells are preserved, the id resolves to `missing_item` (magenta visual), and each distinct missing id is logged exactly once per load.
10. **GIVEN** an authored entry with id `missing_item`, **WHEN** the game boots, **THEN** boot halts (reserved id).
11. **GIVEN** a new entry whose id appears in the retired-ids ledger, **WHEN** the game boots, **THEN** boot halts naming the entry and the ledger conflict.
12. **GIVEN** a category with zero entries (e.g. `raw_resource` in MVP), **WHEN** queried by category, **THEN** an empty list is returned without error.
13. **GIVEN** the MVP data set, **WHEN** querying by category `building_material`, **THEN** exactly the authored building-material ids are returned, and no `furniture_fixture` ids leak in.
14. **GIVEN** the MVP data set, **WHEN** querying all tier-0 building materials, **THEN** exactly `wood_block`, `stone_block`, `thatch_block` are returned.
15. **GIVEN** entries of multiple material families, **WHEN** queried by one family, **THEN** all and only entries of that family are returned.
16. **GIVEN** the MVP data set, **WHEN** "list all ids" is called, **THEN** every authored entry's id is present exactly once and no unauthored id appears.
17. **GIVEN** the database has not yet reached Ready, **WHEN** any lookup API is called, **THEN** the call fails/errors rather than returning data (no partial reads).
18. **GIVEN** a definition queried at boot, **WHEN** the same id is queried again after intervening queries for other ids, **THEN** the returned values are equal to the boot-time values.
19. **GIVEN** a definition object returned by a query, **WHEN** the caller mutates the returned object, **THEN** a subsequent query for the same id returns the original, unmutated authored values.
20. **GIVEN** a stackable entry with `max_stack_size < 1`, **WHEN** the game boots, **THEN** boot halts naming the entry.
21. **GIVEN** a non-stackable entry with `max_stack_size` authored, **WHEN** the game boots, **THEN** boot succeeds with a validation warning.
22. **GIVEN** an entry whose `visual_asset` reference does not resolve to an existing asset, **WHEN** the game boots, **THEN** boot halts naming the entry.

## Open Questions

1. **MVP furniture list** — which furniture/door/window entries exist in MVP
   is owned by the Building System GDD (Core Rule 7). → *Building System GDD*
   **RESOLVED 2026-07-09**: the MVP `furniture_fixture` list is exactly
   `bed` (building-system.md Core Rule 8, per the concept's "1 room + 1 bed
   + 1 villager" MVP). Doors/windows and the ~6 furniture types arrive at
   Vertical Slice.
2. **Provisional `storage_category` enum values** — the field is
   required-present in MVP but its real value set belongs to Storage &
   Inventory (Alpha). MVP needs a provisional enum (e.g. `materials`,
   `furniture`) that Storage & Inventory may later extend — extend, not
   rename, or MVP data files break. → *Storage & Inventory GDD*
3. **Does tier granularity (0–9) match Township Progression's unlock
   structure?** The `tier` int is a scaffold guess; the unlock GDD may want
   named stages instead of numbers. Validate before Alpha data is authored
   at scale. → *Township Progression / Recipe & Blueprint Unlocks GDD*
4. **Per-material placement audio** — if each material family gets its own
   placement sound (wood thunk vs stone clack), that's a new schema field.
   Decide when Building System's feel work lands. → *audio-director /
   Building System GDD*
5. **Data file format and organization** (one resource file per entry vs.
   consolidated tables; hot-reload in editor) — implementation, not design.
   → *future data-architecture ADR via `/create-architecture`*
6. **Localization pipeline for `display_name`** — MVP ships English-only but
   localization-ready (UI Requirements). The actual string-extraction
   workflow is unowned. → *localization-lead, pre-Alpha*
