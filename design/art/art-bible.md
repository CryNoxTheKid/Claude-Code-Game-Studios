# Art Bible — The Last Seal (Voxel)

> **Status**: Sections 1–4 APPROVED (2026-07-11 — all four taste-level choices confirmed by user: distance-keyed fog + silhouettes, flat sharp HUD, amber/gold palette, 3 launch biomes); 5–9 to follow in Pre-Production
> **Author**: art-director agent + user (autonomous draft 2026-07-11, taste-level choices flagged for user check)
> **Last Updated**: 2026-07-11
> **Foundation**: `design/art/visual-direction-note.md` (2026-07-09 interim anchor — this bible supersedes it as the production reference; the note's rules carry forward unless explicitly revised here)
> **World scale**: LARGE (2000×2000×32, ADR-0014) — all sections must hold at expedition distance, not just settlement-camera distance
> **AD-ART-BIBLE sign-off**: skipped — Lean mode (required before the Pre-Production → Production gate, not before Pre-Production entry)

---

## 1. Visual Identity Statement

**The One-Line Rule** *(sharpened from `visual-direction-note.md`, extended for scale)*:

> **A built, lived-in space must always read warmer and more alive than anything around or threatening it — from the doorway to the horizon.**

The addition of "to the horizon" is deliberate: at 2000×2000 scale the player's home is frequently a small warm cluster seen from far away, not a frame-filling subject. The rule has to survive that view, not just the close-up.

### Supporting Principles

**1. Warmth-as-Reward.** Interior/fixture light (hearth, windows, lanterns) is warm and grows more saturated as build quality rises; ambient, exterior, and terrain light stays a cooler, desaturated neutral by comparison.
*Design test:* If an unbuilt, raw cell ever reads as warm or inviting as a furnished room, the palette has failed — warmth must be earned by building, never given for free.
*Serves:* Pillar 1 (*the building IS the game*) — warmth is the visible receipt for mechanical investment, not decoration layered on top.

**2. Blocky Honesty.** Structural geometry is flush, axis-aligned, and hard-edged (1m cells, no bevels, no gaps); readability comes from texture, per-face shading, and corner ambient occlusion, never from rounding or spacing the forms.
*Design test:* If a shape needs a rounded corner or a physical gap between blocks to read clearly, the fix is texture/lighting, not geometry.
*Serves:* Pillar 4 (*clarity over complexity*) — this is the visual half of that pillar's contract: legible forms at a glance.

**3. Stakes as Weather.** Threat intrudes on the existing palette — cool rim-light and desaturated fog creeping in from the threat's approach vector — rather than replacing it; the settlement's own warm lights get *locally brighter and more prominent* during an encounter.
*Design test:* If danger ever makes home look colder or less alive than the danger itself, the scene is off-model — pull back immediately.
*Serves:* Pillar 3 (*cozy, but with stakes*) — this is that pillar's entire visual contract in one sentence.

**4. The Horizon Test — NEW, large-world.** Principles 1–3 must resolve not just in a close establishing shot but at the edge of the streamed view radius (~380m), through the fog band, and in silhouette. Distance is not a rendering afterthought here — the core fantasy explicitly includes "the pull of the horizon" (`game-concept.md`), so the identity has to be legible *as* that pull, not just survive it.
*Design test:* Silhouette-and-screenshot the scene from expedition distance, in fog, at dusk. Without reading any UI, can you still tell "this is home," "this is wilderness," and "this is danger" apart?
*Serves:* Pillar 3 + the horizon-pull fantasy beat — at this world scale, distance itself carries meaning and must be tuned like any other visual signal, not left to whatever the mesher happens to output.

---

## 2. Mood & Atmosphere

### 2.1 Settlement Building (default state)

| | |
|---|---|
| **Emotional target** | Quiet pride, unhurried competence — "I am tending something that is mine." |
| **Lighting** | Warm-neutral daylight base with a permanent golden-hour bias (never harsh/neutral-white, even at "midday"); soft, high-ambient-fill shadows, not dramatic ones. Day/night cycle skews warmer at dusk/dawn as a bonus coziness window. Interior hearth/window light is always the warmest, most saturated point in any frame. |
| **Adjectives** | unhurried, tactile, sun-warmed, handmade, settled |
| **Energy level** | Low–mid, steady — no camera motion, no flicker; visual pacing matches the HUD's own "instant swap, no slide" calm (`interaction-patterns.md`). |
| **Carrying element** | The lit window/hearth glow — the single warmest, most saturated pixel cluster in the frame, legible from orbit-camera distance as the settlement's "we're okay" beacon. |

### 2.2 Expedition / Exploration — NEW, large-world

| | |
|---|---|
| **Emotional target** | The pull of "what's over that ridge" — anticipation and scale, with a little deliberate solitude (you've left the warmth behind, on purpose). |
| **Lighting** | Cooler and higher-contrast than the settlement's (extends `visual-direction-note.md` §2a's "terrain/sky stay cooler neutral" further outward): open-sky directional light, longer shadows, a wider value range. This is *not* the threat's cool rim-light (2.4) — it's exposed, not hostile. |
| **Adjectives** | vast, exposed, quiet, distant, wind-scoured |
| **Energy level** | Low but wide — unhurried pacing, visually big framing (horizon and skybox given real weight in composition). |
| **Carrying element** | The silhouetted landmark on the horizon (a distant seal-dungeon spire, a distinctive peak) — always the highest-contrast, most legible shape against sky/fog, working as a wayfinding beacon that pulls the player forward the way hearth-glow pulls them home. |

### 2.3 Distress / Warning States (villager trapped, unmet need, etc.)

| | |
|---|---|
| **Emotional target** | "Something needs me, but it's not catastrophic yet" — a nudge, not an alarm. Stays inside Pillar 3's cozy-is-the-resting-state default. |
| **Lighting** | No scene-wide change. Material never carries state (Section 4 rule) and accessibility A5 forbids flashing/shake — distress is communicated entirely through the UI/overlay layer. |
| **Adjectives** | pointed, legible, calm-urgent, contained |
| **Energy level** | Low–mid — a static or gently-pulsing icon (sub-3Hz, per A5), never a flash, never a shake. |
| **Carrying element** | The existing billboarded shape+label icon above the affected villager/room (`interaction-patterns.md`'s "shape+label, never hue" convention) — small, localized, dismissable, never full-screen. |

### 2.4 Scene Transition / Dungeon Approach (VS+)

| | |
|---|---|
| **Emotional target** | Threshold-crossing — "I am choosing to leave safety." A held breath, not fear yet. |
| **Lighting** | This is where `visual-direction-note.md` §2c ("stakes as weather") begins literally: cool rim-light and desaturated fog creep in from the approach vector; any light the player carries (torch, lantern) becomes locally brighter — the beacon-in-the-dark read starts at the threshold, not inside the dungeon. |
| **Adjectives** | hushed, cooling, narrowing, charged |
| **Energy level** | Mid, rising — the one state allowed a deliberate pacing shift (existing transition overlay, `scene-world-management.md`), but still obeys A5 (no screen shake, no >3Hz flicker). |
| **Carrying element** | The fog gradient itself, keyed to **Threshold Cool** `#6B8593` (a desaturated slate distinct from State Blue — AD re-review fix 2026-07-11: fog is world-space atmosphere and must never borrow a UI state hue; State Blue means SAFE and only lives in UI chrome). |

### 2.5 Menus / Pause

| | |
|---|---|
| **Emotional target** | Neutral competence — a tool, not a mood. Get in, decide, get out. |
| **Lighting** | N/A — flat UI-space. Background is a dimmed/blurred freeze of the last world frame ("paused, not left"), not a separately lit environment. |
| **Adjectives** | quiet, flat, immediate, unadorned |
| **Energy level** | Minimal — zero ambient motion (no parallax, per A5), instant open/close. |
| **Carrying element** | The dimmed world freeze-frame behind the menu — keeps the player anchored to "their" settlement at zero extra cost. |

### 2.6 Fog / Horizon Treatment for the Streaming Boundary

**Proposal:** fog color is a function of *distance from the settlement core*, not only distance from camera.

- Near the settlement core, atmospheric falloff stays **warm-neutral** (an extension of Valley Ochre, §4.3) — the world doesn't visually go cold right at the edge of home turf.
- Past expedition range, falloff shifts to the **Threshold Cool fog** (`#6B8593`, see 2.4) — signaling "you are now away from home" before any UI does.
- **Silhouetted landmarks** (dungeon spires, distinctive peaks) are placed to poke through the fog band at the streamed view-radius edge as low-detail silhouette proxies, giving the player a next-goal read before that chunk streams in at full detail (this also gives the ~2.6s initial-window-build a visual anchor to hold onto, per ADR-0014's measured load time).

> **CONFIRMED (user decision 2026-07-11):** the recommended option below is now the committed rule. Original note: recommended — warm-to-cool distance-keyed fog + silhouette landmarks, because it does double duty (depth cue *and* narrative "leaving home" signal) at no extra render cost beyond a color ramp. **Alternative:** a single flat neutral-grey fog color regardless of distance (simpler, cheaper to implement, but loses the "leaving home" read and does nothing for Principle 4's Horizon Test).

---

## 3. Shape Language

### 3.1 Character Silhouette Philosophy (Villagers & Squad)

Villagers use **chunky, exaggerated block silhouettes** (oversized head-to-body ratio, in the Minecraft/Stonehearth family) so the silhouette alone — no texture required — reads at small screen size. This serves two distance regimes at once:

- **Settlement-camera distance:** silhouette + Function-gold trim on profession tools/gear reads role at a glance, extending Villager Info UI's existing "shape, never hue" icon convention from the UI layer down into the character model itself.
- **Expedition distance:** villagers themselves rarely appear this far out (they live in the settlement core, per `game-concept.md`), but squad members on dungeon delves do. Same rule applies, with one addition: squad members carry a visible **warm accent** (trim, cape, banner-color) against the cooler expedition/dungeon palette, so "this is mine" reads even off-camera from the settlement — Principle 1 (Warmth-as-Reward) extended to *who*, not just *where*.

### 3.2 Environment Geometry Rules

| Element | Rule |
|---|---|
| **Structural blocks** (wall/floor/roof/foundation) | Strict 1m grid, flush, axis-aligned. Non-negotiable — this is Principle 2 (Blocky Honesty) itself. |
| **Furniture/fixtures** (bed, table, hearth, door) | Grid-cell-based for placement logic, but may use sub-cell silhouette detail within their cell bounding box (a bed can *read* as bed-shaped, not a plain cube) — placement stays on-grid, the model inside the cell is where craft happens. |
| **Vegetation** (grass, bushes, trees) | The one deliberate exception — may deviate from strict block silhouettes (billboard/small non-cubic clusters) for a softer "alive" read against blocky architecture, provided hue never leaves the Material/terrain family and never encroaches on Function-gold. |
| **Distant terrain** (chunked mesher, height-band vertex colors) | Pure blocky/faceted at every distance by construction — the mesher only emits axis-aligned faces (ADR-0014). No separate art ruling needed; this is already structurally locked. |

The vegetation exception is intentional, not a gap: it creates a **built-vs-wild distinction at the silhouette level**, not just the color level — hard edges mean "made," slightly softer edges mean "grown."

### 3.3 Hero vs. Supporting Shapes

- **Hero shapes** = Function-tier fixtures (hearth, bed, table, door — the Unique Hook objects). These get the most silhouette investment: distinct outlines, gold trim, the strongest read in any frame. They're both gameplay-critical and the emotional payoff objects (Principle 1).
- **Supporting shapes** = plain Material blocks (wall/floor/roof segments) stay deliberately plain and repetitive. Gestalt figure-ground: if every block carried equal detail, nothing would pop — Function fixtures need to win that visual contest for Principle 1 to work at all.

### 3.4 UI Shape Grammar

**Position: clean, flat, sharp-cornered HUD — echoes the world's squareness, not its texture.**

The HUD borrows exactly one thing from the voxel world's shape language: **hard, square corners, no rounding** (consistent with Principle 2). It does *not* otherwise mimic voxel texture or depth — no faux-block bevels, no gradient chrome, no skeuomorphism. This is a deliberate two-level grammar:

- **Macro level** (panels, toasts, chips): sharp square corners, flat fills — matches the world's edge language and serves the existing "speed over ornament" / instant-swap HUD feel (`building-ui.md` Game Feel, `interaction-patterns.md`).
- **Micro level** (status/state icons): deliberately *varied* shapes (triangle, circle, diamond) — this is where colorblind differentiation lives (Section 4.6, A1), and variety here is required, not decorative.

> **CONFIRMED (user decision 2026-07-11):** the recommended option below is now the committed rule. Original note: recommended — flat/sharp HUD with world-echoing corners only. **Alternative:** a fully skeuomorphic blocky HUD (chunky pixel-art inventory slots, Minecraft-inventory-style). Rejected as primary because it fights the already-committed "speed over ornament" feel and adds asset/render cost with no gameplay payoff — but it's a viable alternate identity if the team wants a stronger retro-voxel HUD signature later.

---

## 4. Color System

### 4.1 Primary Palette

| Swatch | Name | Hex | Family | Role |
|---|---|---|---|---|
| 🟫 | Timber Brown | `#8B5E3C` | Material | Wood structure — walls, beams, framing |
| ⬜ | Hearth-stone Grey | `#8A8D8F` | Material | Stone structure — foundations, floors |
| 🟧 | Thatch Umber | `#A8642F` | Material | Thatch/roofing — warm red-brown |
| 🟡 | Hearth Gold | `#F5A83C` | Function | Fixtures that carry function (bed, table, hearth, door) — the "this block does something" tell; always the most saturated warm in a built frame |
| 🟨 | Valley Ochre | `#C2AD7C` | Ambient | Terrain/sky base neutral — muted, warm-leaning, recedes near the settlement core |
| 🔵 | State Blue | `#4A90C4` | State | Safe / positive / calm signal — UI and overlay only |
| 🟠 | State Orange | `#E1752E` | State | Danger / alert / warning signal — UI and overlay only |
| 🔲 | Threshold Cool | `#6B8593` | Atmosphere | Distance/dungeon-approach fog ONLY — world-space atmosphere, deliberately distinct from State Blue (which means SAFE and never leaves UI chrome) |

**Deliberate separation note:** Hearth Gold (Function) and State Orange (State) are both warm hues by necessity — the note's own philosophy makes warmth the reward signal, and orange is the safer danger-hue for colorblind accessibility. They stay distinguishable *structurally*, not just by eye: Hearth Gold **only ever appears on static geometry** (fixtures), State Orange **only ever appears in the UI/overlay layer** (Section 4 rule from `visual-direction-note.md` §3, carried forward verbatim) — they are never candidates for confusion in the same visual channel, and both still carry mandatory shape/label pairing regardless (§4.6).

> **CONFIRMED (user decision 2026-07-11):** the recommended option below is now the committed rule. Original note: recommended — amber/gold-leaning warm family (as above), cooler slate-blue state axis. **Alternative:** lean the warm family more toward true orange-red (e.g., Hearth Gold → `#E8873A`-adjacent) for a punchier "campfire" read — rejected as primary because it narrows the gap to State Orange further; worth a swatch-comparison pass once real assets exist.

### 4.2 Semantic Color Vocabulary

| Meaning | Color | Notes |
|---|---|---|
| Structure — recedes | Material family (Timber/Stone/Thatch) | Differentiate by value/texture, not saturation |
| "This does something" | Hearth Gold | Function tier only — never used for plain structure |
| Safe / positive / confirm | State Blue | UI/overlay only |
| Danger / warning / alert | State Orange | UI/overlay only |
| Neutral / info / ambient | Valley Ochre (or a desaturated grey derivative) | Terrain base, non-alert UI chrome |

### 4.3 Per-Height-Band Terrain Color Mapping (ADR-0014)

Bands ramp from warm-neutral (low) to cool-pale (high) — this does double duty as material logic (grass → earth → stone → snow) **and** an atmospheric-perspective depth cue that blends directly into the horizon fog (§2.6):

| Band | Elevation (of 32) | Name | Hex | Read |
|---|---|---|---|---|
| 1 | 0–8 | Lowland | `#9CAD6E` | Grass/valley floor — warm-neutral, welcoming near the settlement |
| 2 | 8–16 | Midland | `#A98F5E` | Earth/hills — warmer transitional brown |
| 3 | 16–24 | Highland | `#7C818A` | Stone/rock — cooler slate grey |
| 4 | 24–32 | Peak | `#C9D3D8` | Snow/frost — cool pale, blends directly into the expedition fog color (§2.6) |

### 4.4 Biome / Area Temperature Rules (2000×2000 world — 3 launch biomes max)

1. **Home Valley** (settlement core & immediate surrounds) — the note's original warm-neutral palette (§2.1), highest warmth ceiling for structures, Valley Ochre base.
2. **Expedition Highlands** (mid-distance, seal-dungeon approach terrain) — cooler, more desaturated, rockier; literalizes Principle 3 (Stakes as Weather) at the terrain level, not just the encounter level.
3. **Deep Threshold** (distant, dungeon-adjacent) — coldest, near-monochrome blue-grey; maximum contrast against any warm light the player carries, so the beacon-in-the-dark read (§2.4) starts working the moment this biome comes into view.

> **CONFIRMED (user decision 2026-07-11):** the recommended option below is now the committed rule. Original note: recommended — the 3 biomes above, chosen because each one maps to an existing narrative/gameplay distance ring (home / expedition / dungeon-threshold) rather than adding new geography for its own sake. **Alternative:** a 2-biome launch (merge Expedition Highlands + Deep Threshold into one "Wilds" biome) — simpler to build/texture for Vertical Slice, at the cost of a less gradual cool-down curve toward dungeons.

### 4.5 UI Palette Divergence

The HUD deliberately does **not** use the full material/terrain palette — it runs a reduced, low-key neutral shell so it never visually competes with the world:

- **Panel/chrome fill:** near-black warm-neutral, `#262220` — low-key enough to recede behind world color.
- **Functional highlight (active/focused state):** Hearth Gold `#F5A83C`.
- **Status only:** State Blue / State Orange, exclusively.
- **Text:** off-white `#EDE6DA` (warm-tinted white, not clinical `#FFFFFF`, to stay in-family) — sized per `accessibility-requirements.md` A4 (16px+ body, 18px+ labels).

### 4.6 Colorblind Backup Table

Per `accessibility-requirements.md` A1: no gameplay-critical state may rely on hue alone. Blue–orange is the safer axis for the most common types (protanopia/deuteranopia), but no axis is fully safe for every type — table below names the residual risk pairs and their backups.

| Pair | Colorblind type at risk | Failure mode | Backup mechanism |
|---|---|---|---|
| State Blue vs. Valley Ochre/terrain neutrals | Tritanopia | Blue can read muddier/greener, may blend into cool terrain neutrals at distance | State color never appears on world terrain (structural rule, §3) — it only ever sits inside UI chrome with icon shape + label |
| Hearth Gold (Function) vs. State Orange (Danger) | Protanopia/deuteranopia (mild), tritanopia (moderate) | Both warm/yellow-orange; saturation is the only differentiator at low contrast | Structurally prevented from co-occurring (Gold = geometry only, Orange = UI only, §4.1); UI additionally pairs distinct icon shape (e.g., triangle-exclaim vs. star-glow) + label, per A1 |
| State Blue vs. State Orange (the core axis) | Verified safe for protanopia/deuteranopia (primary target); mild compression under tritanopia | Edge case only | Every instance ships with a paired shape (square/round/etc. per existing Villager Info UI + Building UI icon conventions) + text label — mandatory day-one, not deferred |

**QA hook:** grayscale pass is the MVP gate (A1); a tritanopia-specific simulator pass is scoped to Vertical Slice QA per `accessibility-requirements.md`'s existing "Colorblind simulation testing beyond grayscale" gap — this table is the checklist for that pass when it runs.

---

## 5. Character Design Direction

[To be designed — Pre-Production]

---

## 6. Environment Design Language

[To be designed — Pre-Production]

---

## 7. UI/HUD Visual Direction

[To be designed — Pre-Production; must align with design/ux/interaction-patterns.md]

---

## 8. Asset Standards

[To be designed — Pre-Production; MagicaVoxel .vox → Blender → Godot pipeline, technical-artist constraints]

---

## 9. Style Prohibitions

[To be designed — Pre-Production]
