# My AI Planet — Roadmap

A life simulation where you nurture a tiny hand-drawn planet from its first cell to floating cloud cities. An AI "Oracle" reads the state of your world, **predicts its future**, and you decide whether to let that future happen or bend it.

- **Platform:** PC (Steam) first: Windows, macOS, Linux
- **Engine:** Godot 4.7 (Forward+), typed GDScript only
- **Art:** Hand-drawn 2.5D. Painted diorama worlds (like the *Cloud City* reference) with expressive 2D characters (like *Monster Boy*)
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
Godot/
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

**It must work offline.** `offline_templates.gd` is a full fallback built from hand-written templates, Markov name generators, and rule-based events. The game must stay playable with no network and no key. This also makes CI and automated tests possible.

### Bring your own AI

The game ships **without any AI access**. The player plugs in their own, in an **AI Settings** screen (shown in the first-run setup):

| Provider type | Examples | How it connects | Notes |
|---|---|---|---|
| **API key** | Anthropic, OpenAI, Gemini, OpenRouter | `HTTPRequest` / `HTTPClient` with streaming (SSE) | The key is saved in `user://` with `ConfigFile.save_encrypted_pass`, never in logs or saves. A "Test connection" button checks it |
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

**Recommended approach:** a 3D world with painted textures, plus 2D characters as billboards.

- **World:** low-poly meshes with **hand-painted albedo textures**, a custom toon or "painterly" shader (stepped lighting, colored shadows, soft rim light), and ink outlines from an inverted hull or a screen-space edge pass.
- **Characters and props:** hand-drawn `Sprite3D` / `AnimatedSprite3D` billboards (in the *Monster Boy* style: bold outlines, squash and stretch).
- **Diorama framing:** the planet is a **floating island / small globe** surrounded by clouds and sky gradients, like the *Cloud City* reference. A perspective camera with a narrow FOV gives a clean 2.5D look, and tilt-shift depth of field makes it feel like a miniature.
- **Mood by era:** each era gets a palette and lighting LUT. Era 1 is teal bioluminescence, Era 4 is warm parchment gold, Era 6 is neon magenta and purple.
- **Juice:** wobble on placement, puff particles, things popping in when they are built, and handwritten-style UI with ink-stamp icons.

**Hard rule:** pick an art bible early (a palette, line weight, and shading steps for each era) and test every asset against it. A consistent look matters more than raw detail.

**AI-generated art:** use it at most for concept exploration and reference. Final shipped assets should be drawn (or heavily painted over) so the style stays coherent and you avoid licensing risk.

---

## 6. Roadmap

Each milestone ends with a **playable build** and a clear exit criterion. Time estimates assume a solo developer or a very small team working part-time. Adjust them freely.

### M0 — Foundations (1–2 weeks)
- [ ] Repo hygiene: Git LFS for art (when the first art lands), CI running the headless tests
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
- [ ] Hand-painted textures and 2D billboard characters to replace the primitive placeholders

**Exit:** one screenshot that looks good enough to post publicly.

### M2 — Vertical Slice: "First Fires" (Era 3) (6–8 weeks)
*Prove the whole loop on one era before building the other five.*
- [x] Systems: food, rain and droughts, population growth, famine, tribe splits (first-pass numbers)
- [ ] Systems: water sources, needs, relationships between tribes, conflict and merging
- [ ] Citizens with names, traits, and an inspector panel
- [x] **Oracle prophecy** at the start of each cycle → tracked as a measurable condition, checked yearly by the sim
- [x] 4 miracles (Rain, Harvest, Drought, Plague), Influence economy, kindness → tone of the AI's writing
- [x] AI-generated dilemma cards with sim-validated effects (with offline fallback), every ~20 years or sooner after drama
- [x] End-of-prophecy **reveal + chronicle** screen: the AI explains what happened and why, citing the player's miracles
- [x] Time controls (pause and three speeds), click a camp to choose a tribe
- [x] First balance pass with a repeatable report (`Godot/tools/balance_report.gd`): a drought every ~20 years, about 3 miracles per prophecy, offline prophecies about 50/50

**Exit:** 5 playtesters each finish a 30–45 min session, can explain *why* their prophecy came true or broke, and at least 3 of them want to play again.

### M3 — The AI Director, done right (3–4 weeks)
- [ ] Event pacing ("drama manager"): tension curve, cooldowns, no event spam
- [ ] Prompt library with versioning + golden tests (saved state → expected schema and constraints)
- [ ] Response cache, batching, streaming text for chronicles
- [ ] Cost guardrails: per-session budget, model-tier routing, graceful drop to offline
- [ ] Disposition tracking → tone level (1–5) in prompts; the hard content ceiling is enforced on the output; Gentle Mode
- [ ] Full provider lineup: OpenAI-compatible adapter (OpenAI, Ollama, LM Studio, OpenRouter), Gemini, Codex CLI, Gemini CLI
- [ ] AI Settings screen: per-tier routing, test connection, capability probe, usage and cost meter

**Exit:** a full Era Run works the same on (a) a cloud API key, (b) a 7–8B local model in Ollama, (c) Claude Code CLI, and (d) offline. An average cloud-key session costs the player less than a target we set (e.g. < $0.05), and the game never breaks when the provider fails mid-game.

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
- [ ] Tutorial given by the Oracle in its own voice
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
| Art too expensive for a small team | One strong art bible, modular kits per era, billboards instead of rigged 3D characters |
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
