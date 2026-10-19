# A whole planet: an open world that history changes

This is the plan for milestone M2.8 in the [roadmap](../ROADMAP.md). Today every run happens on one small floating island. After M2.8 every seed makes a whole planet, a flat open world that wraps east to west: continents and seas, many biomes, rivers, mountains and their own wildlife. Its peoples start out knowing only their valley and discover the rest. People and animals spread over it and change it. Forests fall, fields spread, overgrazed land turns to desert, towns leave ruins, and smoke from the late ages warms the climate.

The planet is far too big to simulate or draw all at once. It works the way No Man's Sky does: the land is a pure function of the seed and a place, made in detail only where it is needed, and only what has changed is saved (see "The open world" below).

It has seven parts:

- **W1 Generation:** a planet from a seed, in three layers (headless).
- **W2 A sim with a sense of place:** tribes, food, climate and animals live somewhere on the map, and the sim works only where life is.
- **W3 Discovery:** each people knows only what it has seen, and explores the rest.
- **W4 A living map:** the land changes with what people, animals and nature do.
- **W5 The view:** the world map and the close-up region, streamed in chunks.
- **W6 The player and the Oracle:** miracles, prophecies and dilemmas about places.
- **W7 Scale and balance.**

---

## Why the world feels tiny today

| # | Cause | Where |
|---|---|---|
| 1 | **One island, one biome.** Each seed rolls one of five biomes and an island of radius 9.4–12.2. Every tile of it is the same kind of land. | `WorldGen.generate`, `IslandShape` |
| 2 | **The sim has no geography.** Food, wood and stone rates are one set for the whole island (`world["rates"]`). Rain, droughts, disasters and smog (`rainfall`, `drought_months_left`, `pollution`) hit everyone at once. | `WorldState`, `ClimateSystem`, `EconomySystem` |
| 3 | **Tribes live nowhere.** A tribe has no position in the sim. The view gives each new tribe the next of 12 camp spots in the order it was founded. Buildings have a slot number, not a place. | `Diorama._next_slot`, `IslandShape.camp_slot`, `building_slots` |
| 4 | **Room is a formula.** The island feeds `2.6 × radius²` people (about 260) and has room for `0.32 × radius²` fields. | `WorldState.CAPACITY_PER_AREA`, `FIELDS_PER_AREA` |
| 5 | **The land never changes.** Trees and rocks are planted by the view from the seed. Cutting wood, farming, hunting and mining leave no mark on the land. Only buildings, fields and smog last. | `Props`, `WorkSites` |
| 6 | **Water is three spots.** A pond and a few springs that rain fills and drinking drains. No rivers, lakes or coast. | `water_*` in `WorldState` |
| 7 | **Animals share one pen.** All animals count against one cap of 240, with a room rule (twice the seeding) standing in for a forage grid that was never built. | `AnimalSystem.CAP`, `ROOM` |

So the map can't simply be made bigger. The sim needs to know where things are.

---

## The open world

Four rules keep a whole planet cheap, in memory, on the CPU and on disk.

1. **The land is a function, not a file.** The detail of any tile is worked out from the seed, its coordinates and the planet layer, the same way every time, on any thread, in any order. Nothing about untouched land is stored. It can be thrown away and made again, byte for byte.
2. **Only changes are saved.** A sparse layer of changes (a cut forest, a field, a town, a ruin, a discovery) sits on top of the generated land. A save grows with history, not with the size of the planet.
3. **Time is lazy where no one is.** Untouched land is never ticked. When a tribe, a herd or the camera reaches it, its state is worked out from how long it has been left alone: a forest cut 80 years ago has regrown by a formula, not by 80 years of monthly updates. World-wide numbers (warming, sea level) are applied when a tile is read.
4. **The sim works where life is.** Detailed simulation runs only in *active regions*: those a tribe lives in, works, or has passed through lately. Which regions are active follows sim rules only, never the camera, so the same seed and the same choices always give the same history.

The view follows its own rules (W5): chunks are built on worker threads around the camera, far land is drawn simpler, and the world is re-centered under the camera so large coordinates don't lose precision.

---

## The shape of the world

- **A flat map of a whole planet.** It wraps east to west, like a globe unrolled. The poles are at the top and bottom edges, so latitude sets the climate. Scrolling east never ends.
- **A grid of hex tiles**, grouped into square chunks (about 32 × 32 tiles) for generation, caching and drawing. Hexes give six equal neighbors for rivers, spread and borders.
- **One tile is about what one camp works.** A camp sits on a tile and works the tiles around it. Today's island is about 12 tiles.
- **Planet sizes** are a recipe number. With lazy land, a bigger planet costs almost nothing until people fill it. To confirm in W0:

  | Size | Tiles | Founding peoples | For |
  |---|---|---|---|
  | Island | about 40, one island in the sea | 1–3 | tests, balance baseline, a short run |
  | Normal | about 1024 × 512 | 3–6 | the default |
  | Vast | about 4096 × 2048 | 4–8 | long campaigns |

- **The Island preset rebuilds today's game** on the new map: one island in an ocean, same biomes and the same rates. The balance numbers in `LIFE_SIM.md`, `SOCIETY.md` and `LIVING_WORLD.md` are checked against it, so every later change can be compared with today.

---

## W1 — Generation: a planet in three layers

Pure, headless and deterministic (`core/planet_gen.gd`, using `SimRng` and seeded `FastNoiseLite`). Local noise alone can't make rain shadows or rivers that reach the sea, because those depend on land far away. So the world is made in layers, from coarse to fine.

### The planet layer (made once, saved)

A coarse grid of about 128 × 64 cells over the whole planet, made when the world is created, in well under a second.

1. **The planet's recipe.** The seed rolls a few big numbers. They make planets that feel different, not just maps that look different:

   | Number | Range | What it does |
   |---|---|---|
   | Ocean | 30–85% of the surface | Pangaea or water world |
   | Plates | 4–14 | One big continent, or many with long mountain ranges |
   | Warmth | −1 to +1 | Ice world or hothouse |
   | Wetness | −1 to +1 | Desert planet or swamp planet |
   | Tilt | 0–35° | How hard the seasons bite away from the equator |
   | Age | young to old | Sharp, high mountains and volcanoes, or worn-down hills |

   Planet types fall out of these numbers. A few names for the Oracle and the title card: *a frozen world*, *a world of sand*, *a world of a thousand islands*, *one great land*, *a green world*.
2. **Plates and height.** Voronoi plates, each moving one way. Where they push together, mountains rise; where they pull apart, rifts and seas open. Sea level is set by the ocean share. Volcanoes sit on plate edges.
3. **Temperature** from latitude, height (colder up high) and warmth.
4. **Wind and rain.** Wind bands by latitude (trade winds, westerlies, polar easterlies) carry wetness from the sea. Mountains wring it out, so the lee side is dry (a rain shadow).
5. **Great rivers and lakes.** Pits fill into lakes (priority flood). Water flows downhill and adds up; cells above a flow threshold carry a great river to the sea.
6. **Climate zones and provinces:** which biomes each cell leans to, and its ore provinces (copper and tin in mountains, iron in hills, coal in old lowland basins).
7. **Regions.** Cells are grouped into named regions (a valley, a coast, a plain), split by mountains, great rivers and coasts. Regions are the scale of weather, herds, discovery, prophecies and the map's names.
8. **Peoples.** Founding peoples land in good, spread-out regions (fresh water, food, wood, mild climate). Each brings its own culture and language as today, nudged by its homeland (steppe peoples more martial, as `WorldGen.BIOMES["culture"]` does now).

The planet layer is saved as packed arrays (a few hundred kilobytes at most), so a save never depends on the generator staying the same (the rule `WorldGen` already follows).

### The detail layer (made on demand, never saved)

Per chunk, a pure function of the seed, the chunk's coordinates and the planet layer:

- Height with local hills and valleys, kept true to the planet layer's height at the cell centers.
- Small rivers and streams that run into the great rivers, lakes, beaches and shallows.
- **Biomes** from temperature × rain (a Whittaker table), then height and water: ocean, shallows, beach, ice, tundra, taiga, temperate forest, meadow, steppe, savanna, desert, jungle, swamp, highland, mountain. Today's five biomes keep their numbers in `WorldGen.BIOMES`, and the new ones get their own rows.
- **What the land holds,** per tile: soil, forest cover, game, fish, stone and the four ores from the province. One region can lack tin while the next has plenty, which gives trade and conquest a reason.
- Seeds for the props (trees, rocks, bushes) the view plants.

Chunks live in a cache (least recently used goes first). Generating a chunk twice, in any order or on any thread, gives the same bytes; a test checks it.

### The change layer (saved)

A sparse map from tile to what is different there: forest cover, soil, game, what is built, who owns it, ruins, roads, and the tick of the last change (for lazy time). Plus each people's discovered land (W3). Only tiles that have changed have an entry.

---

## W2 — A sim with a sense of place

The biggest change, and the one that needs the most care. Everything stays deterministic and every number lands on the save grid (`FLOAT_STEP`).

- **Tribes have a home and a territory.** New fields: `tribe_home` (a tile) and the tiles it works (owner per tile, in the change layer). A territory grows with population and shrinks when work is short. Buildings stand on tiles, so a town can spread over several.
- **Food comes from the land it works.** Each job's rate comes from the tribe's tiles instead of `world["rates"]`: forage from grass and forest cover, hunting from the herds in its region, fishing from coast, river and lake tiles, farming from soil × rain × fields, wood from forest cover, stone and ore from what lies under its tiles. The tribe's crowding, tools, chief, laws and techs multiply them as today.
- **Room comes from the land.** What a territory can feed replaces `CAPACITY_PER_AREA`, and fields need suitable tiles, not a share of the radius.
- **Water** is rivers, lakes and the coast (fishing, not drinking). A tribe far from fresh water needs wells (a tech) or suffers. The pond and springs stay only on the Island preset.
- **Climate by place.** Rain per region by latitude and season. A drought is a dry spell over a few regions that moves and ends, not over the whole world. Each hazard strikes where it belongs: storms on coasts, blizzards in the cold, quakes and eruptions on plate edges, locusts on dry plains, floods on rivers. Weather is worked out only for active regions; elsewhere it is drawn from the seed when someone looks.
- **Spreading out.** A tribe that splits (`RelationsSystem`) founds its new camp on a free, good, *known* tile within reach, scored by soil, water, wood, game and distance from rivals. Hungry or beaten tribes can move their home. Peoples cross the sea once they know boats (a fishing-age tech, then sailing).
- **Meeting.** Tribes only know tribes they have met. Two tribes meet when their territories or their explorers touch (W3). Until then they have no relation at all, so a people that grew apart for 200 years meets the rest with its own culture, tongue and laws. Distance weakens trade, raids and rule: an empire across a sea is harder to hold.
- **Animals live in regions.** The cap moves from the whole world to each region's forage (this is the forage grid that M2.6 B3 left open). In active regions every animal is an individual, as today: herds graze down a region and move on, follow the seasons, and wolves follow their prey. In quiet regions each species is a head count kept near what the land feeds. When a region becomes active, its animals are made as individuals from the seed, the region and that day, so the same history makes the same herds. A species can die out in one region and live in another.

### Distant peoples

With lazy land, the people are the main cost (W7). The default, to check against W0's numbers:

- Every tribe is simulated person by person while the world is under a population budget (about 1,500, set in W0).
- Above the budget, peoples that have met no person-by-person tribe are simulated as groups: head counts by age and sex, culture, techs, laws, a few named rulers and a short history. They grow, split, starve and discover by the same rules, at the group's scale.
- On first contact, a group becomes people again: individuals are made from its counts, culture and history, with the seed, the people and the day, so it is deterministic.
- If every tribe has met another and the world is still over budget, the person tick has to get cheaper (profile first), not the rules looser.

---

## W3 — Discovery

Each people knows only what it has seen. The rest of the planet is unknown to it, to the Oracle and, on the map, to the player.

- **Known land** is kept per people as a bit per tile, by chunk, in the change layer. It never shrinks.
- **How land is discovered:**

  | Who | How far | When |
  |---|---|---|
  | Everyone | The tribe's territory and a ring around it | Always |
  | Foragers and hunters | A few tiles past the territory | While they work |
  | Scouts | Far, along rivers, coasts and passes | A new job, more often in curious people (the curiosity gene) and open cultures |
  | Migrants | The way to their new home | When a tribe splits or moves |
  | Traders, raiders, armies | The road to the other tribe | Once two tribes have met |
  | Sailors | Along coasts, then across seas | Boats, then sailing and navigation techs |

- **Knowledge spreads.** Friends and kin share what they have seen, as techs spread today. Tribes that trade or are at peace share their maps; a cartography tech makes it faster. Conquest takes the loser's map.
- **First sight is history.** The first to see a sea, a mountain range or a new continent gets a line in their life story and the world feed ("Ana the scout saw the eastern sea"), and their people names the place in its own tongue (`Language`). Two peoples can call the same river by two names until one rules both banks.
- **It costs nothing.** Land no one has discovered is never generated in detail and never ticked.
- **On the map,** the player sees the land that any people has discovered; the rest lies under painted cloud, with only the faint shape of the planet layer beneath (W5).
- **The Oracle** only speaks of known land, and can prophesy discoveries: "within 30 years the river people will find the sea".

---

## W4 — A living map

The change layer holds what is different per tile: forest cover, soil, game and fish stocks, what is built on it, and smoke. Active regions update monthly or yearly, in batches; quiet land catches up by formula when it is read (lazy time). A tile's biome is worked out again each year from its temperature, rain, cover and soil, with a margin so it doesn't flicker between two biomes.

| Cause | What it does to the land | Can it come back? |
|---|---|---|
| Woodcutting | Forest cover falls. A cleared tile becomes grassland. | Regrows slowly if left alone |
| Clearing slopes | Soil washes away on hills without cover. | Very slowly |
| Farming | Fields spread over the best tiles. Farming the same field without rest drains the soil. Rotation and irrigation (techs) keep or raise it. | Fallow fields recover |
| Herding (M2.6 B4) | Pastures. Too many animals on dry land: grassland → steppe → desert. | Slowly, in wet climates only |
| Hunting | Herds thin out in a region; a species can be lost there. Without grazers forests regrow; without wolves grazers boom and eat the young trees. | Animals can return from next door |
| Mines and quarries | The ore and stone of a tile run out. Spoil heaps. | No |
| Towns and roads | Towns spread over tiles. Roads form where people go back and forth (trade, tribute, war). | Abandoned towns become ruins |
| War | Burned fields and forests, razed towns. | Ruins stay on the map |
| Fire | Wildfires in dry forests and grass, in droughts or wars. | Regrows, sometimes richer |
| Industry | Smoke drifts downwind and dirties the tiles below it. The world's smoke builds up a warming that raises temperatures slowly. Ice melts, deserts spread, and in the Wired Age the sea can rise and drown low coasts. | Very slowly, if the smoke stops |
| Nature | Eruptions cover land in ash (barren, then very rich), quakes, floods on rivers. | Yes |

Every recovery has a closed form (how far it gets back in N years), so lazy time and monthly updates agree. A test checks that a region left alone for 100 years reads the same either way.

**History you can see.** Graves, ruins, old roads and battlefields stay on the map, so the land tells the run's story. The world feed and the Oracle can point at them.

---

## W5 — The view

- **World map** (zoomed out). The map painted in the toon style: biome colors from `BiomeLook`, relief shading, rivers, coasts with foam, ice, clouds drifting on the wind. Towns are small models that grow with their tribe, and borders show who owns what. It scrolls east and west for ever. Undiscovered land lies under painted cloud. The map is drawn from the planet layer and the change layer in texture tiles, so it never needs the detail layer.
- **Overlays:** biome, territory, forest, soil, temperature, rain, smoke, herds, what each people knows, and the regions a prophecy is about.
- **Region view** (zoomed in). Continuous 3D ground, with today's villagers, animals, buildings and props. Only the land around the camera is drawn, in rings:

  | Ring | What is drawn |
  |---|---|
  | Near | Full ground mesh, props, buildings, villagers and animals (today's level of detail rules) |
  | Middle | A simpler ground mesh, trees as low models, towns as blocks, no people |
  | Far | The map texture on a low mesh, fading into the painted sky |

- **No lag from streaming:**
  - Chunks are generated and meshed on worker threads (`WorkerThreadPool`). The main thread only adds the finished ones, a few per frame, within a time budget.
  - Chunks ahead of the camera are made before it gets there. Old ones go back to a pool and are reused.
  - The world is re-centered under the camera (a floating origin), so far coordinates don't jitter.
  - A changed tile repaints its pixels in the map texture and rebuilds its chunk only if it is in view.
- **One zoom** goes from the map to the ground. The camera tilts as it comes down, so the region view keeps the diorama look (tilt-shift, painted sky).
- **The eras' scales** in `ROADMAP.md` §3 (valley, region, continent, planet) become where the camera rests by default as the ages pass, on the same map.
- **The floating island.** The region view no longer floats; the land runs to the horizon. The floating-island look stays the Era 6 ending in `ROADMAP.md` §3 (Cloud Age: land lifted into the sky). `ART_BIBLE.md` gets a section for the world map and for the new biomes.
- **Art needed:** props and palettes for desert, savanna, tundra, ice, swamp, mountains and coasts, all from CC0 low-poly packs with adult proportions, like the current Kenney and Quaternius sets. No hand-drawn or chibi art.

---

## W6 — The player and the Oracle

- **Miracles land on a known place.** Rain and Drought fall on a region, Harvest on a tribe's fields. Their cost grows with the area.
- **New miracles that shape the land:** raise or sink land, plant a forest, turn a river, wake a volcano (ash, then rich soil), heal the land (soil and cover back). Healing counts as kind and flooding as wrathful in the god's disposition, as today.
- **A vision.** A miracle that shows a people a far land (a scout's dream), so the god can steer discovery.
- **Prophecies about places**, measured by the sim like every prophecy (`Prophecy.METRICS`): the forest of a named region, the tiles a tribe rules, a species alive in a region, a desert reaching a town, the sea rising, a people reaching another continent, two peoples meeting, a discovery.
- **Dilemmas about land:** clear the old forest for fields? dam the river? let the herds graze the sacred hill? send the young across the sea?
- **The reveal shows the map** before and after, with the places that mattered marked, so the chronicle's causes can be seen.

---

## W7 — Scale and balance

**What a person costs.** On the dev machine, a 100-year headless run of seed 42 (about 40 people growing to 116) took 43 seconds: about 12 µs per person-day, including start-up and the report. At speed 5 (180 days a second), 500 people would take a whole core. At speed 3 (20 days a second), about 4,000 would. Bonds and romance grow faster than the head count. The land is cheap with the open-world rules; the people are not.

- **Measure first (W0):** profile `LifeSystem`, `SocialSystem` and `RelationsSystem`, make the person tick cheaper where it is easy, and set the population budget for distant peoples (W2).
- **Spread the sim over frames.** Systems that run monthly or yearly are split across the days of the month, so no single frame does a month's work. Heavy yearly work (biomes, lazy catch-up of a region) runs on worker threads and joins at a fixed tick, so threads never change the result.
- **Budgets the game checks:** frame time for the view, sim time per in-game day, chunks in memory, change-layer size per century.
- **The headless reports** (`balance_report.gd`, `life_report.gd`, `society_report.sh`) get a `map=` option and print map stats: forest cover, soil, desert tiles, ruins, discovered share, the area each tribe holds, species per region, active regions, sim time per year.

---

## Order of work

```
W0 spike ─► W1 generation ─► W2 spatial sim ─► W3 discovery ─► W4 living map ─► W7 balance
                  └────────► W5 world map view ─► W5 region view (streaming)
                                       W2 + W3 + W5 ─────► W6 player and Oracle
```

- **W0 (about 1 week).** Profile the person tick. A first planet layer, and `tools/map_report.gd` writes a PNG of it for 20 seeds, so the generator can be judged by eye before any 3D work. A chunk-streaming spike: fly a camera over generated land and check frame times.
- **W1 and the world map view (W5)** can run side by side: W1 is headless, and the map view only needs the planet and change layers.
- **W2 goes behind the Island preset first.** The sim reads the tiles, but the Island preset must keep today's balance. Then the Normal planet is turned on.
- **W3** needs W2's territories. **W4** needs W2. **W6** needs W2, W3 and the map view.

This milestone takes over M2.6's open forage grid (in W2), feeds M2.7's panels (overlays and region cards), and gives M4 its trade routes (roads) and its food web (species per region).

---

## Exit

- 20 seeds give 20 worlds that look and play differently: at least four planet types, and at least six biomes on every Normal planet. Every founding people starts in a livable region.
- Same seed, same map, same history: a determinism test over 10,000 ticks covers the map's changes, discovery and distant peoples. Chunks made in any order, on any thread, are identical.
- The Island preset stays within 10% of today's balance (population at year 100, hunger deaths, techs).
- Over 400 years on a Normal planet with no god: tribes spread over several regions and discover a growing share of the planet; forest falls around towns and fields and roads spread; abandoned towns leave ruins; in some seeds at least one region turns to desert or loses its soil; in seeds that reach the Wired Age, smoke visibly warms the map.
- Peoples who meet after 200 years apart differ in culture, tongue and laws.
- A god's miracle on the land can still be seen on the map 50 years later.
- No hitches: the world map and a camera flying over the region view hold 60 fps, with no frame over 33 ms from streaming. The region view is as fast as today's island. A 400-year headless run of a Normal planet takes no more than ten times the island's. A save after 400 years is under 10 MB.

---

## Decisions

Locked 2026-10-18.

**Shape.** A flat open world that wraps east to west, not a round globe. The close-up region view keeps the diorama look.

**Plan first.** This plan comes before any prototype. W0 is the first code.

**Open world, the No Man's Sky way.** The land is generated from the seed where it is needed and never stored; only changes are saved; quiet land catches up by formula; the sim works only in active regions, chosen by sim rules and never by the camera. The view streams chunks on worker threads in rings of detail.

**Discovery.** Each people sees only what it has discovered, and so do the map and the Oracle. Peoples discover by working, scouting, migrating, trading and sailing, and share their maps.

**Old saves.** `SAVE_VERSION` goes to 6. Version 5 saves stop loading (the loader already refuses other versions).

**When.** The rest of M2.6 is finished first. M2.6 B4 (taming and breeding) waits for W2, because herders and pastures need regions.

**Distant peoples, a default for now.** Every tribe is simulated person by person under a population budget; above it, peoples no detailed tribe has met become groups until first contact (W2). Revisit with W0's numbers.

Still open, to settle in W0: the planet sizes and the population budget.
