# My AI Planet

A hand-drawn 2.5D life simulation. You nurture a tiny planet from its first cell to floating cloud cities, while an AI Oracle predicts its future and you try to change it. See [ROADMAP.md](ROADMAP.md).

## Run

Open `Godot/` in Godot 4.7, then press Play. The Oracle makes a prophecy, you nudge the world with miracles, and a chronicle tells you how it turned out.

Underneath, every person is simulated, one day at a time (see [docs/LIFE_SIM.md](docs/LIFE_SIM.md)):

- **DNA:** two copies of 14 genes, one from each parent, with mutations. Skin, hair, eye shape, height and build show on their body, so children look like their parents. Strength, vitality, longevity, fertility, intellect, temper, sociability and curiosity shape their lives, so the gene pool drifts and adapts.
- **A life:** birth, childhood, apprenticeship to a parent's trade, coming of age (personality from genes and upbringing), work, love, marriage, children, old age and death (of age, sickness, hunger, accidents, childbirth or war). Every life has a story you can read.
- **Relationships:** friends and rivals from daily meetings, sparks, proposals that can be refused, marriages within and between tribes, arranged matches, separations, widows, orphans taken in.
- **Work and building:** jobs assigned by need (food first), skills that grow over years, discoveries that open new jobs and buildings, chiefs who plan projects, builders who raise them over weeks. Tents become huts and longhouses; storehouses, workshops, healers' huts, shrines, fields and palisades follow.
- **Tribes:** chiefs chosen by respect, restless young adults who lead their families away to found new tribes, raids by the starving, quarrels, wars fought by named people, merges, gifts.

Every person is drawn on the island, walking out to real trees, rocks, bushes, shores and fields with the tool of their trade.

And around them, history moves (see [docs/SOCIETY.md](docs/SOCIETY.md)):

- **Every island is different:** each seed rolls a biome (green meadow, dry steppe, steaming jungle, cold taiga, rocky highland), its climate and its disaster (storms, locusts, blizzards, quakes), how rich its woods, game, fish, soil and stone are, which ores lie under it, its shape and waters, and one to three founding peoples with cultures of their own.
- **Five ages:** First Fires, the Age of Bronze, the Age of Iron, Smoke & Steam and the Wired Age, across 33 techs. An island without tin or iron struggles to leave its age. Villages grow from tents to apartment blocks, with mines, smithies, schools, markets, temples and factories, and the smoke that comes with them.
- **Societies that shape themselves:** wealth and inheritance, nobles and the bonded, loyal people and dissidents, five factions (the ruler, the free council, the priests, the warriors, the merchants), and 29 laws that rulers want, factions demand, councils block and revolutions tear up. The government is named after whoever holds power: Council of Elders, Kingdom, Theocracy, Military Junta, Corporate State, Total State...
- **Crises:** protests, crackdowns, uprisings and revolutions; coups; the merchants buying the state; prophets and schisms; wars of succession; arrests and exile; vassals, revolts and empires.
- **Destinies:** once the island reaches the age of steam, its greatest realm may become its destiny: the Panopticon, the Gilded Cage, the Perfect Bloodline, the Holy Order, the Iron Fist, the Free Commons, or Ashes. The Oracle writes the last chapter. Nudge it with miracles (smite a tyrant, awaken a people, sanctify a ruler) and dilemmas that pass or strike down laws.

| Key | Action |
|---|---|
| Space | Pause |
| Click a person | Inspect them: their life, family, DNA, bonds and life story (the dead too, from the feed or a family tree) |
| F | Follow the inspected person with the camera |
| Click a camp | Inspect the tribe (people, needs, stores, jobs, buildings, knowledge, gene pool; and on the Society tab, its government, rulers, factions, freedom and dystopia, culture, laws and crisis) and choose it for a miracle |
| Tab | Show or hide the life feed (filter by births, deaths, love, work, buildings, discoveries, tribes, politics, conflict) |
| E | Evolution chart: the gene pool over the years |
| H | Society chart: dystopia, freedom, control, inequality, fear, population and smog per tribe over the years |
| Esc | Close the panel |
| Enter | Continue after a reveal |
| 1 / 2 / 3 / 4 / 5 | Speed (2, 6, 20, 60 or 180 days a second), or pick a choice while a dilemma card is up |
| A | AI settings (or the "AI" button at the top right): provider, test connection, per-tier routing, budget, Gentle Mode, usage and cost. Time stops while they are open |
| S / L | Save / load |
| F1 | Debug panel |
| Drag / wheel | Orbit / zoom |

## AI providers

Choose the AI in the AI Settings screen (press A). Each model tier can use its own provider (for example thoughts on a local Ollama model and chronicles on Claude); the settings, API keys included, are saved encrypted (with a key tied to the machine) in `user://ai_settings.cfg`. Tiers left on "Automatic" use the first ready of: an API key, an installed AI CLI (Claude Code first), the offline templates.

Environment variables win over the saved settings: `MYAIPLANET_AI=offline|anthropic|openai|openrouter|gemini|ollama|lmstudio|claude_code|codex_cli|gemini_cli|grok_cli` (with `MYAIPLANET_MODEL`) picks the provider of every tier, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY` and `GEMINI_API_KEY` replace saved keys, `MYAIPLANET_AI_BUDGET` sets the spending cap and `MYAIPLANET_GENTLE=1` Gentle Mode. A typical prophecy plus chronicle costs about $0.04 with Claude Code and $0.13 with Grok CLI.

## Tests

```sh
scripts/test.sh                              # all tests, headless
scripts/test.sh determinism                  # only tests whose name matches
MYAIPLANET_LIVE_AI=1 scripts/test.sh live_ai # real AI calls (costs money)
```

Balance report (6 seeds, 100 years, offline AI, a bot that plays kindly), and a year-by-year report of one world:

```sh
godot --headless --path Godot -s res://tools/balance_report.gd -- years=100 seeds=6
godot --headless --path Godot -s res://tools/life_report.gd -- seed=42 years=80 every=5
```

The brush-stroke texture and the villager skins are painted by scripts: `tools/paint_textures.gd` and `tools/paint_villager_skins.gd` (run with `godot --headless --path Godot -s res://tools/<name>.gd`).

Art built on CC0 assets by Kenney: [Animated Characters](https://kenney.nl/assets/animated-characters-protagonists) and [Survivors](https://kenney.nl/assets/animated-characters-survivors) for the villagers, [Nature Kit](https://kenney.nl/assets/nature-kit) and [Survival Kit](https://kenney.nl/assets/survival-kit) for the props, tools, fences and workshop.

`scripts/test.sh` uses `godot` from your PATH, or `GODOT_PATH`, or `/Applications/Godot.app`.

## Screenshots

`scripts/screenshot.sh out.png [frames] -- --seed=42 --warmup-years=40 --distance=15 --pitch=-0.6 --yaw=3.8` renders a frame (it opens a window briefly). Add `--inspect=N [--tab=DNA] [--follow]` to open the N-th person, `--tribe[=N] [--tab=Society] [--scroll=PIXELS]` for a tribe, `--evolution` or `--society-chart[=measure]` for the charts, and `--age=N` to start every tribe with everything up to that age (0 to 4). For HUD checks: `--feed=off|full`, `--feed-filters`, `--prophecy=folded`, `--keys`, `--hover-miracle=harvest`, `--paused`, `--speed=1..5`.

![Village](docs/screenshots/m2-village.png)
