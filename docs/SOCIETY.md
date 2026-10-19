# Worlds, ages and societies

Every seed makes a different island, and every island's people climb through five ages, from the first fires to a wired world. On the way, each tribe's society takes its own shape. Nothing about it is scripted: who holds power, which laws pass, who is rich, who is watched, and whether it ends free or in a dystopia all grow out of the simulation. You can push it with miracles and dilemmas, but you can't fully control it.

## The island (`core/world_gen.gd`)

`WorldGen.generate(seed)` makes a recipe, saved in `state.world`:

| Key | What it is |
|---|---|
| `name`, `biome` | `meadow`, `steppe`, `jungle`, `taiga` or `highland` |
| `rain`, `drought`, `winter`, `sickness` | Climate: rain multiplier, drought chance per year, harm of winter (0 to 1.35), fevers |
| `rates` | Multipliers for `forage`, `hunt`, `fish`, `farm`, `wood`, `stone` |
| `ores` | `copper`, `tin`, `iron`, `coal`: 0 means none (that tech's bright ideas work out a fifth as often, `Knowledge.NO_ORE`), up to about 1.8 |
| `hazard` | `storms` (buildings fall), `locusts` (stores eaten), `blizzards` (food and wood lost), `quakes` (stone falls) |
| `island` | `radius` (8.6 to 11.6), `roughness`, `hills`, `pond` ([x, z]), `pond_radius`, `springs` (1 to 4) |
| `trees`, `rocks` | How thickly the view plants them (about 0.4 to 2) |
| `peoples` | 1 to 3 founding bands: `name`, `couples`, `culture` |

Every number in the recipe is a float, so it survives a save and load bit for bit. `WorldGen.describe(world)` gives one line: "Soulanaash, a dry, windswept steppe: rich in tin and coal."

## The ages (`core/knowledge.gd`)

| Age | Gate tech | Brings |
|---|---|---|
| 0 First Fires | | The 12 Stone Age techs |
| 1 Age of Bronze | `bronze` (needs tin) | Copper working (needs copper), writing, masonry, the wheel, irrigation |
| 2 Age of Iron | `iron_working` (needs iron) | Mathematics, coinage, philosophy, medicine |
| 3 Smoke & Steam | `steam_power` (needs coal) | Printing, gunpowder, telegraph, vaccines |
| 4 Wired Age | `electricity` | Radio, computing, genetics, networks |

`state.age_of(t)` is a tribe's age. Hard techs need several bright ideas: discovery succeeds with probability `(1.6 / difficulty)^3.5`. Every adult may have the idea, but above 40 adults a tribe thinks only as fast as the square root of its size (`WorkSystem.CROWD_THINKS`). Scholars, writing, mathematics, philosophy, printing, computing and networks speed the search; taboos, a state religion and censorship slow it. Techs carry bonuses (`Knowledge.BONUSES`), read with `state.tech_bonus(t, effect)`.

New jobs: miner (mine, digs ore), smith (smithy, makes tools from metal), scholar (school, research), merchant (market, wealth), guard (bronze and a law that wants guards, keeps order and fights), official (a law that wants officials), factory worker (factory, makes tools, cloth and jars, and smoke). Tools matter more in each age (`EconomySystem.TOOL_POWER`).

New buildings: homes get denser (`tent` → `hut` / `longhouse` → `stone_house` → `rowhouse` → `apartment`), and the humblest home is rebuilt as the best the tribe knows. Also `mine`, `smithy`, `school`, `market`, `temple`, `factory`, `broadcast_tower`. Power builds for itself: `great_house` (a strong ruler), `barracks` (3+ guards), `watchtower` (control 35+), `prison` (arrests), `statue` (a proud or greedy ruler with power 60+), `surveillance_mast` (the surveillance network) and `stone_wall` (after a war; it replaces the palisade).

## A tribe's society (`core/society.gd`, `core/laws.gd`)

**Culture:** four axes, -100 to 100, in `state.tribe_culture[t]`: `hierarchy`, `piety`, `martial`, `openness`. Each founding people starts with its own culture, leaned by the biome. Culture drifts every year with the ruler's traits, the laws in force and what the tribe went through. A tribe that splits off carries its culture with some noise, a little more open and less ranked.

**Wealth and class:** everyone has savings (`person_wealth`). Work earns them (merchants and smiths most). The chief's share, the temple tithe and taxes take a cut. The treasury pays guards and officials, and the ruler skims it (greedy rulers most). Factories make their owners rich. Inheritance passes wealth to children, so inequality (a Gini, `Society.inequality`) builds over generations. Where there are ranks, the ruling house and the richest families are `noble`. A child is born noble when both parents are, or when one is and the child carries the ruling house's name. Under bonded labor, those with nothing fall into bondage, and so do their grown children.

**Loyalty:** each adult (0 to 100) follows the rulers' legitimacy, their own mood, their class, propaganda, custody and their pride. Below 25 they are dissidents.

**Tribe measures:** stateful ones are `legitimacy`, `unrest` and `fear`. Derived ones are `freedom`, `control` (laws, plus guards and officials on duty, times surveillance), `inequality` and `dystopia`.

**Factions:** `ruler`, `council` (the free), `priests`, `warriors`, `merchants`. Each holds power from 0 to 100 (`state.tribe_power[t]`), built from laws, jobs, buildings, who owns the wealth, culture and reign length. The government is named after the strongest faction, in the words of its age:

| Strongest | Names |
|---|---|
| none above 25 | Band of equals, Free tribe |
| council | Council of Elders, Council, Assembly, Republic, Democracy |
| ruler | Chiefdom, Despotate, Kingdom, Monarchy, Autocracy, Empire (2+ vassals), Police State, Total State |
| priests | Rule of Shamans, Theocracy |
| warriors | Warband, Military Junta |
| merchants | Merchant Council, Merchant Oligarchy, Plutocracy, Corporate State |

`Society.scale(t)`: Band, Tribe, Chiefdom, City-state, Kingdom, Nation, Empire.

**Laws:** there are 29, from the council of elders to birth permits; see `Laws.LAWS`. Each year the ruler puts forward the law they want most. The score adds their traits, the situation (famine, war, dissent and so on), the culture's fit, the strongest faction, and what the law does for the ruler's own power. A strong council blocks laws that take its freedoms, except in an emergency. The ruler may strike down a law they dislike, unless it keeps them in power. Emergency powers outlast their emergency unless a gentle ruler or a strong council gives them back. Then the strongest other faction presses for its own law: a weaker, gentle or discredited ruler gives way; otherwise they refuse, and the council remembers it. Some laws replace others (the assembly replaces the council of elders).

**Succession:** under hereditary rule the eldest of the ruling house inherits, and rules for life. Otherwise the tribe chooses, tilted toward the strongest faction's kind: a general, a priest or the rich. Where there are elections, the tribe votes every 8 years. Where the radio and the score say who to love, the ruler always wins.

## Crises (`core/systems/crisis_system.gd`)

At most one runs in a tribe at a time (`state.tribe_crisis[t]`):

- **Protests** (unrest 55+). The ruler gives way (a hated law falls), cracks down (arrests, fear, emergency powers) or waits. If anger keeps rising, protests become an **uprising**: rebels against guards, nobles and the loyal. Win, and it's a **revolution**: the ruler is driven out, nobility abolished, the treasury shared out and the dark laws torn up, and the rebels' leader rules, for better or worse. Lose, and the uprising is **crushed**: the rebels are jailed, or flee to found their own tribe, and secret police or emergency powers follow.
- **Coup:** the warriors outgrow a ruler nobody believes in, and their general takes the seat.
- **Capture** (Smoke & Steam on): the merchants outgrow the state, and the richest buys it, often with a corporate charter.
- **Prophet:** a holy outsider preaches. Under a state faith they are silenced and become a martyr. Otherwise their followers split off (a **schism**), or the old priests lose their hold (**reform**).
- **Succession:** under hereditary rule, a rival with more standing contests the heir. It is settled, the rival leads their supporters away, or it becomes a war of succession.

Where a law allows detention, dissidents are arrested every month; the more control and surveillance, the more get caught. Their families turn against the rulers. Where exile is the law, a troublemaker is driven out each year. Wars from the Age of Bronze on can make the loser a **vassal** that pays tribute. Bitter vassals revolt, and loyal old vassals are **annexed**.

## Destinies (`core/systems/destiny_system.gd`)

From Smoke & Steam on, each year the sim asks what the island's greatest realm has become. When one answer holds for 12 years (`DestinySystem.HOLD_YEARS`), that is the island's destiny (`state.destiny`). The `destiny` event fires, and the Oracle writes the last chronicle.

| Destiny | Needs |
|---|---|
| The Panopticon | Surveillance net or social credit, control 75+, freedom 25 or less (Wired) |
| The Gilded Cage | A corporate charter or merchants on top, inequality 55+ (Wired) |
| The Perfect Bloodline | Birth permits, dystopia 50+ (Wired) |
| The Holy Order | Priests on top with a state religion, freedom 30 or less (Steam) |
| The Iron Fist | Warriors on top (Steam), or in the Wired Age a ruler on top with a standing army; fear 40+ |
| The Free Commons | Freedom 75+, inequality 40 or less, dystopia 20 or less, elections (Wired) |
| Ashes | Everyone dead, or smog 85+ and fewer than 40 people |

## Reading it from the view and the UI

All read-only, and cheap enough for a panel; cache per second for anything per-frame:

- `Society.metrics(state, t)`: age, government, scale, freedom, control, inequality, fear, legitimacy, unrest, dystopia, nobles, bonded, detained, dissidents.
- `Society.gloom(state)`: 0 to 1, population-weighted dystopia, so the view can darken.
- `Society.laws_of(state, t)`, `Laws.LAWS[law]["name"]` and `["description"]`, plus `state.tribe_laws[t][law]` (the tick it passed).
- `state.tribe_power[t]`, `Society.top_faction()`, `state.tribe_culture[t]`, `state.tribe_crisis[t]`, `state.tribe_dynasty[t]`, `state.tribe_overlord[t]`, `Society.vassals_of()`.
- Per person: `person_wealth`, `person_status` (`""`, `"noble"` or `"bonded"`), `person_loyalty`, `person_detained` (months left).
- `state.pollution` (0 to 100), `state.society_history` (yearly), `state.destiny` and `DestinySystem.progress()`.
- New event types are in `EventText` under the `politics` category, plus `new_age`, `disaster` and `destiny`.

In the game: the tribe panel's Society tab shows all of it, the person panel shows class, wealth, loyalty and custody, H opens the society chart, and the top bar shows the island, the highest age, the smog, and an omen once a destiny has held for 5 years.

## Balance

The M2.5 balance pass, the automated half (playtesters come later). Two headless reports, both with the offline Oracle (no AI calls):

```sh
# The long arc: 18 islands (every biome, 1 to 3 founding peoples) for 400 years, under five bot gods.
# One Godot process per run, 6 at a time; rows land in the folder and are merged at the end.
src/tools/society_report.sh /tmp/arc years=400 gods=none,benevolent,wrathful,meddler,kingmaker jobs=6
# Or in one process (slow): godot --headless --path src -s res://tools/society_report.gd -- seeds=1-6 years=300 gods=none
# The First Fires century (M2): 6 islands, 100 years, a kind bot.
godot --headless --path src -s res://tools/balance_report.gd [-- seeds=12]
```

A 400-year run takes 3 to 5 minutes (people meeting every day is most of the time), so the full five-god report is 90 runs and about an hour and a half on 8 cores. A run stops when the island meets its destiny. Set `GODOT_LOCK=/some/dir` to have the script take a `mkdir` lock around each batch when other processes share the import cache.

The bot gods play by the rules: they cast once a month at most, only what their Influence pays for, and answer every dilemma.

| God | Casts | Dilemmas |
|---|---|---|
| none | nothing | the mildest choice |
| benevolent | Awaken on the darkest society (dystopia 30+ or a dark law, each tribe at most every 3 years), Rain in a drought, Harvest for the hungry, a Muse near the Influence cap | the kindest, freest choice |
| wrathful | Drought, Smite, Plague on the greatest realm in turn (Plague only on a realm of 60+) | the cruelest choice |
| meddler | Sanctify, Smite, Awaken on the greatest realm in turn | down the list |
| kingmaker | Sanctify the greatest realm's ruler; Smite them if they are kind or wise | the darkest choice |

`liberator` (Awaken the darkest, Smite harsh rulers) is in the tool too, but not in the tables.

### Targets (first pass)

- A good run reaches the Wired Age in about 200 to 350 years; a missing ore slows an island but doesn't stop it.
- Left alone, destinies vary: none above about 40% of runs, the Free Commons and at least 3 dystopias all turn up, Ashes is rare.
- A kind, awakening god raises the odds of the Free Commons; a wrathful or sanctifying one raises dystopia. The god bends the story; it doesn't dictate it.
- No island dies out in its first century on its own.
- The First Fires century stays as M2 left it: about 40 people grow to about 120 in 4 tribes, about 260 births and 60 marriages, the full early tree, 1 to 2 wars, a handful of famines and fevers.

### Results

Before is the code as M2.5 left it, after is this pass; both with the same five bots, 18 islands and 400 years. Runs are chaotic (one changed number reshuffles every history), so read the shares as rough: one run is 6%.

**Left alone** (`none`):

| | Before | After |
|---|---|---|
| Bronze, Iron, Steam, Wired: median year (runs that got there) | 96, 107, 179, 210 (12 of 18 Wired) | 107, 151, 183, 214 (15 of 18 Wired) |
| Fastest and slowest Wired | 181 and 315 | 143 and 382 |
| Dystopia: peak, island mean | 70, 24.8 | 71, 20.2 |
| Inequality: peak, island mean | 54, 27.0 | 61, 27.4 |
| Revolutions, coups, captures, uprisings crushed (per run) | 0.1, 3.9, 0.4, 0.1 | 1.3, 4.9, 1.5, 0.4 |
| Wars, famines, fevers (per run) | 14.3, 22.4, 34.0 | 17.3, 36.5, 31.8 |
| People at year 100, at year 200, at the peak | 124, 286, 328 | 128, 235, 299 |
| Islands dead in their first century, at all | 2, 3 | 0, 2 |

**Destinies** (share of runs, after; before in brackets):

| God | Panopticon | Gilded Cage | Bloodline | Holy Order | Iron Fist | Free Commons | Ashes | None yet | Dark (with Ashes) |
|---|---|---|---|---|---|---|---|---|---|
| none | 0 (22) | 17 (11) | 11 (6) | 11 (22) | 11 (0) | 11 (6) | 11 (17) | 28 (17) | 61 (78) |
| benevolent | 0 (17) | 0 (11) | 0 (11) | 22 (22) | 11 (6) | **33** (6) | 0 (6) | 33 (22) | 33 (72) |
| wrathful | 6 (6) | 0 (0) | 0 (0) | 11 (6) | 17 (0) | 0 (0) | 17 (39) | 50 (50) | 50 (50) |
| meddler | 0 (11) | 6 (0) | 0 (6) | **44** (28) | 0 (0) | 6 (0) | 0 (33) | 44 (22) | 50 (78) |
| kingmaker | 6 (17) | 6 (11) | 0 (6) | 28 (33) | 17 (0) | 6 (0) | 0 (17) | 39 (17) | 56 (83) |

**How far the god bends it** (after): mean island dystopia is 17.6 under the benevolent god, 20.2 left alone, 24.0 under wrath, 25.0 under the meddler and 27.3 under the kingmaker. Revolutions per run: 4.0 benevolent, 1.3 alone, 0.6 kingmaker, 0.1 wrath. The benevolent god triples the Free Commons (11% to 33%) and halves the dark endings (61% to 33%), but a third of its islands still end dark (two in three of those in a Holy Order). Sanctifying a ruler all game (kingmaker) or meddling with every lever (meddler) all but rules out the Free Commons and tips the realm toward the priests (Sanctify adds piety) and the army. Wrath mostly stalls history: famines and fevers pile up, only 12 of 18 islands reach the Wired Age (median year 304), half never meet a destiny in 400 years, and a sixth die out within 60 years: droughts and lightning on bands of 25 to 55 people.

Before this pass the god couldn't bend it: the benevolent god's islands ended as dark as the untouched ones (72% against 78%), because nothing it did could start a revolution (0.1 a run, for every god).

**The First Fires century** (`balance_report.gd`, 6 islands, 100 years; after on 12 islands in brackets):

| | Before | After |
|---|---|---|
| People at year 25, 50, 100 | 46, 76, 106 | 46, 79, 124 (44, 76, 125) |
| Tribes | 3.2 | 3.5 (3.7) |
| Births, deaths, marriages | 297, 218, 58 | 291, 194, 66 (289, 190, 67) |
| Discoveries, buildings | 14.8, 59 | 14.8, 68 (14.5, 70) |
| Droughts, famines, fevers | 2.8, 4.3, 9.5 | 2.7, 4.5, 5.8 (3.3, 4.8, 7.9) |
| Wars, splits | 2.0, 4.8 | 1.7, 3.5 (1.8, 4.2) |
| Influence a year | 0.47 | 0.46 (0.47) |

### What was wrong, and the tuning

Before: every tribe that got past a few dozen people ended as a hereditary kingdom with bonded labor; freedom fell to 0 and control to 100, yet unrest stayed at 0 for centuries, so nothing ever overturned it. About five revolutions in 90 runs, whatever the god did; one Free Commons among 18 untouched islands; Awaken bounced off. Three islands starved to the last person, one in its third year and two more within 112 years.

| Where | Constant | Before | After | Why |
|---|---|---|---|---|
| `economy_system.gd` | hungry days (`HUNGER_SHORTFALL`) | any day the stores ran dry was a full day of starvation | the share of the day's food missing is the chance it counts | A band that gathered nine tenths of its food still starved like one that gathered none; whole islands died in a bad winter |
| `life_system.gd` | `CONCEPTION_CHANCE` | 0.2 | 0.18 | Fewer famine deaths would have grown the First Fires century to about 160 people |
| `life_system.gd` | `FULL_FAMILIES` (was the literal 1.3) | 1.3 | 1.1 | Families shrink from about 26 people on an average island, not 78, so small bands still grow freely but the century lands near 120 |
| `life_system.gd` | noble births | one noble parent made a noble child | both parents, or one and the ruling house's name | Nobility spread to whole tribes (175 nobles of 175); nobles get +20 loyalty, so nobody ever dissented |
| `society_system.gd` | `PASS_AT` | 3.0 | 3.5 | Any ruler who wasn't kind or wise passed hereditary rule and bonded labor within a few years |
| `society_system.gd` | `POWER_APPEAL` (was the literal 8) | power / 8 | power / 12 | Same: the power a law gave the ruler outweighed everything else in its appeal |
| `laws.gd` | `push` of `hereditary_rule`, `bonded_labor` | hierarchy +2 a year each | +1 | Together they made the culture welcome them within 20 years, so they cost no legitimacy |
| `society_system.gd` | `UNFREE_LOYALTY` (was 0.3) | 0.3 | 0.45 | Loyalty lost per point of freedom below 40 |
| `society_system.gd` | `DARK_LAW_LEGITIMACY` (new) | 0 | 3 per dark law | People know a cage whatever their culture says |
| `society_system.gd` | `CONTROL_CALMS` (was 0.15) | 0.15 | 0.1 | Control 100 alone held unrest down by 15 |
| `society_system.gd` | `DETAINED_UNREST` (new) | 0 | 60 × share of adults in custody | Arrests removed the dissidents from the count, so full jails made a quiet tribe |
| `crisis_system.gd` | `UPRISING_AT` | 70 | 65 | After a crackdown (unrest -15) anger seldom climbed back to 70 within the six tense months |
| `knowledge.gd` | `iron_working` difficulty | 3.0 | 3.5 | The Age of Bronze often lasted under 10 years |
| `knowledge.gd` | `electricity` difficulty | 4.8 | 5.3 | Great realms went from Steam to Wired in 5 to 30 years |
| `work_system.gd` | `CROWD_THINKS` (new) | | 40 | Above 40 adults a tribe thinks as the square root of its size: a big realm reached the Wired Age by year 137 |
| `knowledge.gd` | `NO_ORE` | 0.12 | 0.2 | An island without coal could sit in the Age of Iron for 250 years |
| `laws.gd` | `surveillance_net` "when" | dissent, unrest, fights | + big | With the higher bar no ruler wanted it any more, and the Panopticon vanished (it is still the rarest ending) |
| `destiny_system.gd` | `HOLD_YEARS` | 15 | 12 | Most destinies came after year 330, or not at all |
| `destiny_system.gd` | `FREE_INEQUALITY` | 35 | 40 | The freest Wired democracies sit at inequality 31 to 41 (merchants and factories make some rich), so they flickered in and out |
| `destiny_system.gd` | `GILDED_INEQUALITY` | 60 | 55 | Corporate states sat at 53 to 61 |
| `destiny_system.gd` | `IRON_FIST_FEAR`, who counts as the army | 55, warriors on top | 40, or in the Wired Age a ruler on top with a standing army | Juntas never reached fear 55; and the Wired police states that leaned on an army had no destiny at all |

The bots' first tries taught two things about the god's own tools, which live in files this pass didn't touch: Plague (`Miracles.PLAGUE_DEATH` 0.1 + `PLAGUE_FRAILTY` 0.35) kills about a quarter of a tribe, so a god who casts it whenever they can afford it (every 6 years or so) wipes out three islands in four; and the offline dilemmas' first choice often takes food from a starving tribe, so the M2 bot (which always takes it) is harsher than a hands-off player.

Still open for the playtesters: Ashes comes from slow declines (a small, war-torn, famine-struck island that never leaves the First Fires), not from smog; the Holy Order is the commonest dark ending under any god who blesses rulers; and three in ten untouched islands haven't met a destiny by year 400.
