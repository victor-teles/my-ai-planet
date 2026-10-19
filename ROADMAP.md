# My AI Planet — Roadmap

A life simulation where you nurture a tiny hand-drawn planet from its first cell to floating cloud cities. An AI "Oracle" reads the state of your world, **predicts its future**, and you decide whether to let that future happen or bend it.

- **Platform:** PC (Steam) first: Windows, macOS, Linux
- **Engine:** Godot 4.7 (Forward+), typed GDScript only
- **Art:** Stylized 2.5D. Painted, toon-shaded diorama worlds (like the *Cloud City* reference) with low-poly 3D people
- **AI:** The player brings their own. Options: their own API key (Claude, OpenAI, Gemini…), a local model (Ollama, LM Studio), or an AI CLI already installed on their machine (Claude Code, Codex, Gemini CLI). There is no backend of ours, so we have no server costs.

---

## 1. The core idea in one loop

```
   ┌──────────────┐     ┌──────────────────┐     ┌───────────────────┐
   │  SIMULATE    │ ──▶ │  ORACLE PREDICTS │ ──▶ │  PLAYER INTERVENES │
   │ world ticks  │     │ "In 300 years the │     │ spend Influence,   │
   │ deterministic│     │  river tribes will│     │ answer dilemmas,   │
   │ systems      │     │  go to war"       │     │ place miracles     │
   └──────▲───────┘     └──────────────────┘     └─────────┬─────────┘
          │                                                │
          │            ┌──────────────────┐                │
          └─────────── │  REVEAL          │ ◀──────────────┘
                       │ prophecy came    │
                       │ true / was broken│
                       └──────────────────┘
```

The hook is **"the AI predicts the future, and you try to change it."** Every era opens with a prophecy, and you spend the era trying to make it happen or stop it. At the end, the game shows you what happened and why. This gives a clear goal on every run, makes the AI the visible star of the game, and makes your choices feel like they count.

### Design pillars

1. **Cause and effect you can read.** Every big outcome traces back to things you can see: a drought, a choice you made, a leader's personality. The AI explains them, but never invents them out of nothing.
2. **One planet, many scales.** You zoom from a puddle of cells to a creature, a village, a city, and finally the whole globe. The camera zoom is how you move through the game.
3. **A cozy look, real stakes.** Soft, painted, charming visuals on top of a simulation where civilizations can really collapse. **The tone is earned:** a gentle god gets a hopeful planet, and a cruel one gets a dark one (see §4).
4. **Every planet tells its own story.** Names, myths, leaders, and history are generated, so no two runs read the same.

---

## 2. Architecture: where the AI fits (and where it must not)

An LLM must **not** run the simulation tick by tick. That would be slow, expensive, non-deterministic, and impossible to balance. Instead, the work splits into two layers:

| Layer | Owns | Tech |
|---|---|---|
| **Simulation Core** | Population, resources, climate, genes, needs, relationships, buildings, tech. Runs every tick. | Deterministic, statically typed GDScript with a seeded RNG. Hot data lives in packed arrays (`PackedFloat32Array`, etc.), not one Node per citizen |
| **AI Director ("Oracle")** | Prophecies, narrative events, naming, myths, leader personalities, turning player choices into effects, era chronicles. Runs at **key moments only**. | Provider adapter (HTTP or local CLI process) → LLM, strict JSON schemas |

**The golden rule:** the AI only ever returns **structured proposals** (`{event, targets, effects: [{stat, delta}], text}`). The Simulation Core checks every proposal against the rules, clamps the numbers, and then applies it. The AI writes the story; the simulation owns the facts.

```
src/
  core/           # pure simulation, no rendering (testable headless)
    world_state.gd, tick_scheduler.gd, rng.gd
    systems/      # climate, biology, population, economy, culture, conflict
  ai/
    provider.gd           # interface
    providers/
      http/               # anthropic.gd, openai_compatible.gd (OpenAI, Ollama, LM Studio, OpenRouter…), gemini.gd
      cli/                # claude_code.gd, codex.gd, gemini_cli.gd (spawned processes)
      offline_templates.gd
    director.gd           # decides WHEN to call the AI
    schemas/              # JSON schemas for every request type
    prompt_library/       # versioned prompt templates
    cache.gd              # hash(state snapshot + prompt) → response
  game/           # scenes, UI, camera, input
  art/            # textures, sprites, shaders, palettes
  tests/          # GUT tests for core/ + golden-file tests for ai/ parsing
```

**When the AI is called (rough budget for each era):**

| Trigger | Model tier | Calls |
|---|---|---|
| Era prophecy and era chronicle | Large (e.g. Opus / Sonnet class) | 2 |
| Dilemma cards and narrative events | Medium | 5–15 |
| Naming, flavor text, citizen thoughts | Small (Haiku class) and batched | 20–50 |
| Turning free-text player "whispers" into effects | Medium | on demand, rate-limited |
| Style specs, banners, posters and slogans (see M3.5) | Small, prefetched | 3–8 |

**It must work offline.** `offline_templates.gd` is a full fallback built from hand-written templates, Markov name generators, and rule-based events. The game must stay playable with no network and no key. This also makes CI and automated tests possible.

### Bring your own AI

The game ships **without any AI access**. The player plugs in their own, in an **AI Settings** screen (shown in the first-run setup):

| Provider type | Examples | How it connects | Notes |
|---|---|---|---|
| **API key** | Anthropic, OpenAI, Gemini, OpenRouter | `HTTPRequest` / `HTTPClient` with streaming (SSE) | The key is saved in `user://` with `ConfigFile.save_encrypted_pass` (a machine-bound passphrase), never in logs or saves. A "Test connection" button checks it |
| **Local model** | Ollama, LM Studio, llama.cpp server | The same OpenAI-compatible HTTP adapter pointed at `localhost` | Free and private. Small models need stricter schemas and shorter prompts, so each tier has a "small-model prompt" variant |
| **Local CLI** | Claude Code (`claude -p --output-format json`), Codex (`codex exec`), Gemini CLI | `OS.execute_with_pipe()` runs it in the background; the game parses stdout | Uses the player's existing subscription. The game finds CLIs on PATH, warns about latency, and never passes shell-interpolated strings (args go in as an array) |
| **Offline** | Built-in templates | No AI at all | Always available, and used when anything else fails |

- **Per-task routing:** the player can choose a provider and model for each tier (big / medium / small), e.g. a local Ollama model for names and Claude for prophecies.
- **Capability probe:** on connect, the game runs a tiny JSON test so it knows whether the model can follow the schema, and turns down the AI's responsibilities for weak models.
- **Usage meter:** shows tokens used and an estimated cost per session, since it's the player's money.
- **Privacy note:** tell the player clearly what is sent (world state summaries only, nothing personal).

---

## 3. Eras (content arc)

Each era reuses the same loop but looks through a different lens: different verbs, a different camera scale, and a different art set.

| # | Era | Scale | You manage | Example prophecy |
|---|---|---|---|---|
| 1 | **Primordial Soup** | Micro (a tide pool) | Cell mutations, nutrients, temperature | "Life will die out in the warm vents" |
| 2 | **Bloom of Life** | Biome | Species traits, food webs, migrations | "The long-necks will out-eat the forest" |
| 3 | **First Fires** | Valley | Tribes, myths, first tools, family ties | "Two tribes will split over the sacred river" |
| 4 | **Kingdoms** | Region | Cities, trade, religion, rulers | "The salt empire will collapse within 3 kings" |
| 5 | **Smoke & Steam** | Continent | Industry, pollution, ideologies | "The sky will darken by the third generation" |
| 6 | **Cloud Age** | Planet and sky | Floating cities, AI citizens, leaving the planet | "Your people will leave the planet... or end it" |

Moving to the next era is a **cinematic zoom-out** with an AI-written chronicle of what happened ("The Book of Your Planet"), which the player keeps as a shareable artifact.

---

## 4. Player agency

- **Influence:** the main resource. You earn it when your people prosper, and when a prophecy comes true *or* is broken (both are dramatic).
- **Miracles (direct):** rain, a meteor, a fertile land, a plague, a muse who inspires an inventor. Each costs Influence and has visible effects on the map.
- **Dilemma cards (choices):** generated by the AI from the current state. *"The northern tribe found iron. Do you show them the forge, or hide it?"* Each choice is backed by validated effects, and the second-order effects are hinted at, never fully shown.
- **Whispers (free text, a stretch goal):** type an idea to a single citizen. The AI turns it into a bounded effect ("whisper 'boil the water' to the healer" → disease resistance +, and a new tradition is born).
- **Follow a life:** click any citizen to see their name, needs, relationships, and AI-written thoughts. Living moments at small scale keep the world feeling personal.

### Session shape: the player chooses

| Mode | Length | What it is |
|---|---|---|
| **Genesis Campaign** | 4–6 h, saved between sessions | The full arc from cell to Cloud Age on one planet, with state carried across eras |
| **Era Run** | 30–60 min | Pick any unlocked era with a generated (or seeded) starting world and one prophecy, then play to the reveal. Replayable, roguelite style |
| **Sandbox** | Endless | No prophecy pressure, free Influence, every miracle unlocked. For people who just want to watch their world live |

All three run on the same systems. An Era Run is simply "one era of the campaign, started from a generated state", so this costs very little extra work. Era Runs unlock as the player reaches each era in the campaign (or all at once in an option, for players who don't want to unlock them).

### Tone grows from the player's choices

There is no fixed "dark" or "light" setting. The world's tone comes from **how you play**:

- The sim tracks a hidden **Disposition** for the player god: *benevolent ↔ wrathful* and *guiding ↔ hands-off*, built from the miracles cast and the dilemmas answered.
- Disposition and the world's state (famine, war, prosperity) feed into every AI prompt as a **tone level** (1 = fairy tale, 5 = grim chronicle). A gentle god's planet reads like a fable. A god who sends plagues gets darker events, darker myths, and people who fear them.
- Art and music follow the tone too: warmer palettes and lighter music when it's hopeful, desaturation and storms when it's grim.
- **The hard ceiling stays the same at every tone level:** consequences can be tragic (war, plague, extinction), but the writing is never graphic or gratuitous. This keeps the Steam rating predictable. An optional *Gentle Mode* caps the tone at 2 for players who want it.

---

## 5. Art direction: hand-drawn 2.5D in Godot

**Approach:** a 3D world with painted textures and toon shading, and low-poly 3D characters in the same style.

- **World:** low-poly meshes with **hand-painted albedo textures**, a custom toon or "painterly" shader (stepped lighting, colored shadows, soft rim light), and ink outlines from an inverted hull or a screen-space edge pass.
- **Characters:** low-poly 3D figures with adult proportions, toon-shaded and outlined like the world (the look of *Planitia* or *Kingdoms and Castles*). Hand-drawn billboards were tried and dropped: they read as stickers on a 3D world, and chibi proportions made adults look like children.
- **Props:** low-poly meshes with the same shading.
- **Diorama framing:** the planet is a **floating island / small globe** surrounded by clouds and sky gradients, like the *Cloud City* reference. A perspective camera with a narrow FOV gives a clean 2.5D look, and tilt-shift depth of field makes it feel like a miniature.
- **Mood by era:** each era gets a palette and lighting LUT. Era 1 is teal bioluminescence, Era 4 is warm parchment gold, Era 6 is neon magenta and purple.
- **Juice:** wobble on placement, puff particles, things popping in when they are built, and handwritten-style UI with ink-stamp icons.

**Hard rule:** pick an art bible early (a palette, line weight, and shading steps for each era) and test every asset against it. A consistent look matters more than raw detail.

**AI-generated art:** use it at most for concept exploration and reference. Final shipped assets should be drawn (or heavily painted over) so the style stays coherent and you avoid licensing risk. This is different from **AI-authored assets** (M3.5): there the AI writes a style spec, a vector emblem or a slogan, and the game builds the asset from its own kit and palette, so the art bible still holds.

---

## 6. Roadmap

Each milestone ends with a **playable build** and a clear exit criterion. Time estimates assume a solo developer or a very small team working part-time. Adjust them freely.

### M0 — Foundations (1–2 weeks)
- [x] CI running the headless tests (GitHub Actions on Linux, `.github/workflows/tests.yml`)
- [ ] Repo hygiene: Git LFS for art (the Kenney `.glb` props and textures have landed)
- [x] Folder structure from §2
- [x] `WorldState` + `TickScheduler` + seeded `SimRng` with save/load (JSON)
- [x] Typed GDScript enforced: untyped declarations are errors
- [x] `AIProvider` interface + offline templates + Anthropic API-key provider + Claude Code CLI provider
- [x] Debug overlay: tick rate, population, tribes, events, prophecy, AI calls and their cost
- [x] Headless test runner (`scripts/test.sh`, a small built-in runner instead of GUT for now)
- [ ] Live check of the Anthropic API-key provider (needs a key; the Claude Code path is verified)

**Exit:** a headless sim runs 10,000 ticks with the same result for the same seed, and one AI call returns schema-valid JSON. ✅ Both met.

### M1 — Art Bible & Look Prototype (2–3 weeks, can overlap M0)
- [x] Painterly toon shader, outline pass, dusk sky, tilt-shift, painted clouds, shore-foam water
- [x] One floating-island diorama as a target "beauty shot" (procedural placeholder geometry, see `docs/screenshots/`)
- [x] The live sim drawn on the island: camps, huts and hopping people grow with each tribe; drought turns the grass to straw; events pop up as floating text
- [x] Palette and lighting for Era 3, written down in `docs/ART_BIBLE.md`
- [x] Low-poly 3D villagers (Kenney's CC0 animated character with painted tribal skins): women and men, children, elders who grey and stoop, five ancestries, slim to stout builds, long hair, buns, braids and beards; chiefs wear a feathered headdress
- [x] Trees, undergrowth, rocks, tents and campfires from Kenney's CC0 Nature and Survival kits, restyled to the toon palette with ink outlines; a painted brush-stroke texture on every toon surface
- [ ] A real walk cycle (the walk is a slowed run blended with idle), work and sitting clips, and level of detail for villagers far from the camera (about 65 fps with 170 villagers today): moved to M2.6

**Exit:** one screenshot that looks good enough to post publicly.

### M2 — Vertical Slice: "First Fires" (Era 3) (6–8 weeks)
*Prove the whole loop on one era before building the other five.*
- [x] Systems: food, rain and droughts, population growth, famine, tribe splits (first-pass numbers)
- [x] Systems: water sources (a pond and two springs that rain fills and drinking drains), needs (food, water, room, safety → mood), relationships between tribes, wars and merging
- [x] **Every person simulated** (`docs/LIFE_SIM.md`), one day per tick: DNA (two copies of 14 genes, inherited and mutating), birth, growing up, apprenticeship, coming of age, work, love, marriage, children, old age and death with a cause; life stories, family trees, the dead remembered
- [x] Relationships between people: friendships and rivalries, chemistry, courtship, proposals and refusals, marriages across tribes, arranged matches, separations, fights, widows, orphans taken in
- [x] Jobs assigned by need with skills that grow over years; discoveries (stone tools, fishing, herbal lore, rites, pottery, weaving, carpentry, farming) open new jobs and buildings and spread between friends
- [x] Village building: chiefs plan, builders build over weeks; tents, huts, longhouses, workshop, healer's hut, storehouse, shrine, fields, palisade; homes for households
- [x] Tribes: chiefs chosen by respect, splits led by a restless young adult and their family and friends, raids, incidents, wars fought by named people, gifts, merges
- [x] **Oracle prophecy** at the start of each cycle → tracked as a measurable condition (population, tribes, largest tribe, buildings, discoveries), checked monthly by the sim
- [x] 5 miracles (Rain, Harvest, Drought, Plague that kills the frail first, Muse that inspires a discovery), Influence economy, kindness → tone of the AI's writing
- [x] AI-generated dilemma cards with sim-validated effects (with offline fallback), every 4–8 years or sooner after drama
- [x] End-of-prophecy **reveal + chronicle** screen: the AI explains what happened and why, citing the player's miracles
- [x] Time controls (pause and four speeds, 2 to 60 days a second), click a camp to inspect and choose a tribe
- [x] Every person drawn and going about their day: walking to real trees, rocks, bushes, shores and fields with the tool of their trade, carrying what they gathered home, acting out chats, quarrels and courtships, buried on the hill when they die
- [x] Life feed, person panel (life, family, DNA, bonds, story), tribe panel, evolution chart, follow camera
- [x] Balance pass with repeatable reports (`tools/balance_report.gd`, `tools/life_report.gd`): over 100 years about 40 people grow to about 125 in 3–4 tribes, with about 290 births, 65 marriages, a full tech tree, 1–2 wars and a handful of famines and fevers

**Exit:** 5 playtesters each finish a 30–45 min session, can explain *why* their prophecy came true or broke, and at least 3 of them want to play again.

### M2.5 — Living history: procedural islands, ages and societies
*Make every run its own story: a different island, a long climb through the ages, and a society that can end free or in a dystopia. See `docs/SOCIETY.md`.*
- [x] Procedural islands: biome (meadow, steppe, jungle, taiga, highland), climate, ores, a disaster each island is prone to, shape and waters, and 1 to 3 founding peoples with their own cultures
- [x] Five ages within one run: First Fires, Bronze, Iron, Smoke & Steam, Wired (33 techs; missing ores slow an island down), with new jobs (miner, smith, scholar, merchant, guard, official, factory worker) and buildings (denser homes; mines, schools, markets, temples, factories; the great house, watchtowers, prisons, statues and surveillance masts that power builds)
- [x] Emergent society: culture on four axes, wealth and inheritance, nobles and the bonded, loyalty and dissidents, five factions, a government named after whoever is on top, and 29 laws that rulers want, factions press for, councils block, revolutions tear up
- [x] Crisis chains: protests, crackdowns, uprisings, revolutions, coups, the merchants buying the state, prophets and schisms, wars of succession, arrests and exile, vassals, revolts and annexations
- [x] Destinies: the Panopticon, the Gilded Cage, the Perfect Bloodline, the Holy Order, the Iron Fist, the Free Commons or Ashes, with the Oracle's last chapter
- [x] Oracle: prophecies about ages, dystopia, inequality and vassals; dilemmas that pass or strike down laws and move unrest and legitimacy; political miracles (smite, awaken, sanctify)
- [x] Automated balance pass (`tools/society_report.sh`, 18 islands × 400 years × five bot gods, see `docs/SOCIETY.md` → Balance): untouched islands reach the Wired Age around year 214; the Free Commons and five dystopias all occur, none above 17%; a kind god raises the Free Commons from 11% to 33% and a meddling or sanctifying god darkens the island, so the god bends history without dictating it
- [ ] Balance pass with playtesters: pacing of the ages, how often dystopias win, how much the god can bend it
- [ ] Plague is too strong for small tribes (it kills about a quarter of a tribe, and a bot casting it whenever it can wipes out most islands): scale it to tribe size or raise its cost
- [ ] Era-specific camera scales and art sets (M4/M5) on top of the ages

### M2.6 — A living world: natural motion and animals with DNA (5–7 weeks)
*Villagers move like people, not robots, and animals live by the same DNA rules as people. See `docs/LIVING_WORLD.md`. Decisions locked 2026-10-18: retarget animations onto the Kenney rig, one genome per animal, hunters eat what they kill.*
- [ ] Real animation set: Quaternius' CC0 Universal Animation Library retargeted onto the Kenney rig (walk, jog, carry, sit, kneel, chop, hammer, hoe, talk, mourn, play…), locomotion blended by real speed so feet don't slide, animation level of detail (300 villagers at 60 fps). Replaces M1's "real walk cycle" item
- [ ] Steering shared with the animals: easing in and out, turn rates, separation, avoiding buildings, the fire and walls, village lanes with gates (A* on a small graph per camp)
- [ ] A gait from the person: age, height, build, health, mood, traits and load set speed, stride and posture; per-walker drift so no two move in step
- [ ] Intentions instead of random timers: a task queue that only urgent changes interrupt (no turning around at high speeds); work loops with a beginning, a middle and an end; groups at the fire, tag, look-at and idle details; reactions to births, deaths, rain, war and miracles; seasons change how people behave
- [ ] Gene tables in `Genetics` (people unchanged, saves byte-identical), a species table by biome, and wild animals as individuals with two copies of 12 genes (size, speed, coat, horns, temper, wariness…)
- [ ] `AnimalSystem`: forage, breeding seasons with herd sires, deaths from age, hunger, winter and predators (who take the slowest), hunting whose food follows herd fullness (each species' living count over its seeding, capped, weighted by its share; not a carcass worth 2.9; an empty valley pays nothing; a normal camp kills a handful a year; uncapped hunt work can wipe out a species and then its meat stops), three herds per species with room to grow to twice that, wolves following their prey. Done: seeding, room, breeding, deaths from age and winter, hunting and its tally. Still open: the forage grid, and predators that really catch prey (founders are all faster than `SLOW_PREY`, so wolves catch almost nothing)
- [ ] Taming and breeding: herders, pens, artificial selection shown in the evolution chart, dogs from wolves, draft animals and herds as wealth in the later ages
- [ ] Animals drawn (Quaternius' CC0 animal packs, looks from genes) with herds that flock, graze, watch and flee, hunts acted out, and an animal panel; animal prophecies, dilemmas and the Blessing of the Herds

**Exit:** follow any villager for a minute at any speed: they never walk through a house or a person, never turn around without a reason, and their feet don't slide. Same seed, same animals. Over 100 years a kind god keeps the herds alive and hunter food within 10% of today's balance. Overhunting can end a species and then lose that meat. Domestic herds visibly drift from wild ones.

### M2.7 — A screen you can read (2–3 weeks)
*The simulation stays. The first minute teaches the loop, and the dashboards wait until someone asks. See `docs/INTERFACE.md`. Can run beside M2.6.*
- [ ] The prophecy card leads with the plain goal, pauses time on each new prophecy, and teaches the loop once on a new world
- [ ] Speed buttons say how long a year takes. The feed opens on the big turns
- [ ] Feed, Genes, Society, and AI settings leave the top bar. The charts open from the person and tribe panels. AI settings open from the keys card. E, H, and A still work
- [ ] Miracles split into Bless and Strike. Smite, Awaken, and Sanctify appear once a tribe has laws or reaches the Bronze Age
- [ ] A person and a tribe open on a short card. Percentages, techs, laws, and allele grids stay one click down. DNA is renamed Blood
- [ ] The Influence purse shows Kind, Harsh, or Unpredictable from the god's existing disposition

**Exit:** after the opening and five minutes, a new player can say what the prophecy asks, how to cast a miracle on a tribe, and how fast a year passes. Shots in `docs/screenshots/`.

### M3 — The AI Director, done right (3–4 weeks)
- [x] Event pacing ("drama manager", `game/drama_manager.gd`): tension fed by weighted events with a 1.5-year half-life, a target curve that builds toward each prophecy's deadline and rests after a reveal, hard and per-category cooldowns (16–19 dilemmas a century, never closer than 2.5 years), a pacing hint in the prophecy and dilemma prompts; bursts of small events merged and rate-limited in the life feed and over the camps (`game/event_pacer.gd`)
- [x] Prompt library with versioning (`prompt_library/manifest.json`: version, tier, schema and size budget per task; old versions stay loadable) + golden tests (saved states → every task's real request, placeholders, size budget, offline and recorded replies pass schema, ceiling and sim)
- [x] Response cache (LRU, saved in `user://ai_cache/`), identical in-flight requests share one call, chronicles and the last chapter stream into the reveal as they are written (SSE for Anthropic and OpenAI-compatible)
- [ ] Batched thoughts (several people in one small call)
- [x] Cost guardrails: per-session budget ($0.10 and 200 calls by default) that drops each task a tier at 75% and goes offline when spent, one retry then offline, a circuit breaker per provider
- [x] Disposition tracking (mercy, wrath and how often the god meddles, saved) → tone level (1–5) and a disposition line in prompts; the hard content ceiling is enforced on every reply string (`ContentGuard`); Gentle Mode caps tone at 2 with a stricter list
- [x] Full provider lineup: OpenAI-compatible adapter (OpenAI, Ollama, LM Studio, OpenRouter; strict schema or JSON mode), Gemini, Codex CLI, Gemini CLI (only Codex and Claude Code checked live so far)
- [x] AI Settings screen (press A): provider and keys (saved encrypted), per-tier routing, test connection with the capability probe, local model list, budget, Gentle Mode, usage and cost meter; applies to the running game

**Exit:** a full Era Run works the same on (a) a cloud API key, (b) a 7–8B local model in Ollama, (c) Claude Code CLI, and (d) offline. An average cloud-key session costs the player less than a target we set (e.g. < $0.05), and the game never breaks when the provider fails mid-game.

**Status:** offline (d) runs end to end, and a failing provider falls back to offline mid-game in tests; Claude Code (c) passed the live prophecy and chronicle checks. Still to do: full Era Runs on (a) a cloud key, (b) a local 7–8B model in Ollama and (c), and measuring the average session cost.

### M3.5 — AI-authored assets (3–4 weeks)
*The player's AI writes the style and the words; the game builds the art. Every provider we support is a text model, so it can't paint a texture or model a mesh, but it can write a structured spec, simple SVG and lore-true text. Same golden rule as the Oracle: the AI proposes, the game validates, clamps and builds.*

```
sim facts ──► AI writes a spec ──► validate & clamp ──► engine builds it ──► saved with the world
(biome, culture,   (JSON or SVG,      (palette indices,   (BuildingArt,       (reloads look the
 age, government,   small model)       part limits, safe   villager skins,     same, and work
 laws, dystopia)                       SVG subset)         banner textures)    offline)
```

- [x] **Asset Director** (`ai/asset_director.gd`): asks for a spec when a tribe is founded and whenever it enters a new age, changes government or ruling house, or meets its destiny (each kind's *signature* changes); written in the background while the player plays, one small-model call each; asset calls may spend at most a tenth of the session budget (20 of the default 200 calls), after which the offline writers answer
- [x] Specs are saved in `WorldState.assets` (`core/asset_book.gd`), so a world looks the same after a reload and with the AI unplugged; every kind (`ai/assets/*_kind.gd`) has a seeded offline writer with the same schema, so offline worlds vary too; views read `AssetDirector.spec_or_offline()`, so nothing waits on the AI
- [x] The AI never picks raw colors or geometry: it picks art-bible palette indices (`core/art_palette.gd`) and modules from a grammar, and each kind clamps sizes and part counts; a rejected asset reply falls back offline without tripping the provider's circuit breaker
- [x] **Architectural style per tribe and age** (`style_kind.gd`, `game/diorama/styled_buildings.gd`): roofs (cone, gable, dome, stepped, flat, spire), wall materials no newer than the age, ornament, towers and proportions on homes, temple, great house, school and market. A Theocracy grows spires, a Total State goes grey and brutalist, a Free Commons stays colorful (`docs/screenshots/m35-styles.png`)
- [x] **Heraldry** (`heraldry_kind.gd`): a banner emblem, field and motto per ruling house, as SVG cleaned by `ai/svg_guard.gd` (whitelisted shapes, palette tokens only, no text, styles, links or entities; re-written from scratch) and rasterized with `Image.load_svg_from_string`; offline emblems from a grammar of 14 charges. Coups, revolutions and new houses replace the banner (`docs/screenshots/m35-heraldry.png`)
- [x] **Propaganda posters and slogans** (`poster_kind.gd`): one per dark law in force, on boards by the masts, towers, walls and fire; the Oracle sees the latest slogans and the motto in its world summary
- [x] **Fashion by culture and class**: colors per class, a woven pattern and an accessory (`VillagerArt.wear`); finer for nobles, drab for the bonded, uniforms for guards under a junta
- [x] **A people's own language** (`core/language.gd`): a phonology per founding people feeds `NameGen` (people, families, tribes, the island and its springs); dialects drift when tribes split; an AI-written language names everyone born after it
- [x] **Laws and places in their own words** (`names_kind.gd`, `LocalNames`): local names for laws and buildings in the feed and the tribe panel ("Watchful Eye of Piapusux" for the surveillance network); the sim keeps the ids
- [x] **Monuments** (`monument_kind.gd`): six statue poses from the ruler's vanity, plinth inscriptions, temple signs from prophets' doctrines
- [ ] Monuments: draw the plinth inscription on the statue (it shows in the tribe panel only); the pop-up text over the villages still uses the usual law and building names
- [ ] The buildings of control (barracks, prison, masts), tents, the healer's hut and the storehouse don't take the style yet
- [ ] Later, with M5: the illustrated "Book of Your Planet", laid out by the AI around screenshots, heraldry and chronicles

Not planned: image-model textures (they break style coherence and add licensing and disclosure questions; maybe as an opt-in extra), AI-written raw meshes (a module grammar gives creative control without wrecking the art bible), and 3D-generation services (slow, costly per asset, and off-style).

**Exit:** two runs on the same island seed with different providers, and one offline, all look coherent with the art bible, and their tribes, regimes and endings are visibly different from each other. Asset calls cost under a tenth of a session's AI budget, and a failed call never leaves a building unbuilt.

**Status:** `tests/test_assets_exit.gd` plays seed 42 for 60 years with two stand-in AIs and offline: every tribe gets its style, banner and names in all three, the two AIs' looks differ, asset calls stay within a tenth of the budget (20 AI-written specs, then 12 offline), and the looks never change the sim. Still to do: the same check with real providers (a cloud key, a local model and Claude Code), and a look at whether 20 asset calls are enough for a long run (later ages fall back to the offline writers once they are spent).

### M4 — Scale Up: Eras 2 & 4 (8–10 weeks)
- [ ] Era 4 Kingdoms: cities that grow building by building, trade routes, rulers with AI personalities, wars
- [ ] Era 2 Bloom of Life: species with gene traits, food-web simulation, evolution through mutation
- [ ] **Era transitions:** carry state forward (Era 2 species → Era 3 people's traits; Era 3 myths → Era 4 religions)
- [ ] Zoom-out transition cinematic

- [ ] Mode select: Genesis Campaign / Era Run / Sandbox, plus world seeds

**Exit:** a single campaign run that plays through three eras (2 → 3 → 4) and keeps the story consistent between them, and an Era Run of any of those eras can start from a generated world.

### M5 — Full Arc: Eras 1, 5, 6 (10–12 weeks)
- [ ] Era 1 cell sandbox (a short, tutorial-like opening)
- [ ] Era 5 industry, pollution, and ideologies
- [ ] Era 6 Cloud Age: floating cities (the reference image becomes real), multiple endings (exodus, harmony, collapse, transcendence)
- [ ] "The Book of Your Planet": an exportable illustrated chronicle (PNG or PDF), great for sharing on social media

**Exit:** a complete run from cell to ending in about 4–6 hours.

### M6 — Polish, Audio, Onboarding (6–8 weeks)
- [ ] Adaptive music layers for each era; ambience that grows with the population
- [ ] Tutorial given by the Oracle in its own voice: moved to M2.7 (the first prophecy card teaches the loop once)
- [ ] Accessibility: text scaling, colorblind-safe palettes, an option to pause on every event
- [ ] Performance: 10k+ simulated agents with level of detail (individuals up close, aggregate stats when zoomed out)
- [ ] Localization pipeline (EN + PT-BR first)

### M7 — Launch (Steam Early Access, then Full)
- [ ] Steam page with the beauty-shot trailer around M2–M4, to collect wishlists early
- [ ] First-run AI setup wizard ("Do you have an API key, a local model, or an AI CLI?" → guided setup, or "Play offline")
- [ ] Builds for Windows, macOS (signed and notarized), and Linux/Steam Deck; Steam achievements and cloud saves
- [ ] Steam store text that is upfront about it: "Bring your own AI, or play offline", plus Steam's AI-generated content disclosure
- [ ] Early Access with Eras 2–4, then the remaining eras added in updates
- [ ] Post-launch ideas: shared "seed" planets, a gallery of community planet chronicles, a mod API for prompts and events

---

## 7. Key risks and how to defuse them

| Risk | Mitigation |
|---|---|
| AI output breaks the sim or the story | Strict JSON schemas, validation and clamping, retry once, then fall back to offline templates |
| Setup friction: players without a key or local model bounce off | The offline mode must be genuinely fun on its own; the setup wizard has a one-click Ollama guide; Claude Code / Codex detection makes setup take zero steps for people who already have them |
| Results vary a lot between providers | A capability probe at connect time; small-model prompt variants; the sim validates every output, so a weak model gives a duller story, never a broken game |
| CLI providers are slow or change their flags | Prefetch while the player is busy; keep the CLI adapters small, with a version check and a clear error message when something changes |
| Player's AI spend | Call only at key moments, use model tiers, cache, show a usage meter, and let players set a per-session budget |
| AI makes the game "random", not meaningful | AI proposes, the sim decides; prophecies are measurable conditions; the reveal shows the causal chain |
| Scope explosion (six eras!) | The vertical slice (one era) must be fun before any other era begins. Every era reuses the same loop |
| Art too expensive for a small team | One strong art bible, modular kits per era, one shared CC0 character rig with painted skins per era instead of new models |
| Latency kills the pace | Request the next prophecy or dilemma *ahead of time*, while the player is busy; stream long text |
| Sim performance in GDScript | Data-oriented design (packed arrays, no Node per citizen), systems that update in batches at different rates, aggregate when zoomed out, and spread work across frames and threads (`WorkerThreadPool`). Profile at every milestone |

---

## 8. Decisions

| Topic | Decision | Consequences |
|---|---|---|
| **Platform** | PC / Steam first (Windows, macOS, Linux) | Forward+ renderer stays; no web build for now |
| **Session shape** | The player chooses: Genesis Campaign, Era Run, or Sandbox | Every era must be startable from a generated world state (§4) |
| **AI access** | Bring your own: API key, local model, or local AI CLI, plus offline | No backend to run; provider adapters and offline mode are core features, not extras (§2) |
| **Tone** | Comes from the player's decisions (Disposition → tone level), with a fixed content ceiling | Tone is a prompt parameter and an art/music parameter (§4) |
| **Language** | Typed GDScript only | Performance comes from data-oriented design and profiling, not from switching languages |

**Still open:** the price point, and whether to use a Steam demo (Era 3 Era Run, offline mode) as the wishlist driver.

---

## 9. Next 3 concrete steps

1. Commit the empty Godot project (`Godot/.gitignore` already keeps `.godot/` cache out of git).
2. Build `core/world_state.gd` + `tick_scheduler.gd` + a headless test proving determinism.
3. Paint the **first floating-island beauty shot** (M1) in parallel. It will drive motivation, the art bible, and the Steam page.
