# The life simulation

Every person on the island is simulated. One tick is one day; a month is 30 days and a year is 12 months. Everything lives in `WorldState` as parallel packed arrays, so saving, loading and replaying stay exact (same seed, same world).

At normal speed (6 days a second) a year takes a minute. A prophecy spans 8–40 years; the whole arc, from the first fires to the Wired Age, is about 250–300 years.

Every seed makes a different island, with its own biome, ores and first peoples. The tribes climb through five ages, and their societies take their own shape on the way. Both are described in [SOCIETY.md](SOCIETY.md).

## Systems and when they run

| System | Runs | Does |
|---|---|---|
| `ClimateSystem` | monthly | Seasonal rain and droughts (scaled by the island's climate), the island's disaster, smog clearing |
| `WaterSystem` | monthly | The pond and springs fill and drain; thirsty tribes move to fuller water |
| `WorkSystem` | monthly | Discoveries and teaching between tribes; jobs; skills; the chief's next project; who lives where |
| `EconomySystem` | daily | Food, wood and stone come in; tools, clothes and jars are made and wear out; everyone eats; food spoils; builders build |
| `LifeSystem` | daily births, monthly the rest | Health, sickness, death, conception, coming of age, orphans, mood |
| `SocialSystem` | daily meetings, monthly the rest | Friendships, quarrels, love, proposals, arranged matches, separations, fights, the midsummer gathering |
| `RelationsSystem` | monthly chiefs and raids, yearly the rest | Tribe feelings, incidents, wars, vassals, revolts and annexations, gifts, merges, splits, chiefs stepping down |
| `SocietySystem` | monthly wealth and moods, yearly the rest | Income, taxes and tithes, loyalty, legitimacy, unrest, fear, faction power; nobles and bonded, laws, culture, elections, tribute |
| `CrisisSystem` | monthly | Protests, crackdowns, uprisings, revolutions, coups, captures, prophets, successions; arrests and exiles |
| `InfluenceSystem` | yearly | The god's Influence |
| `ProphecySystem` | monthly | Checks the prophecy |
| `EvolutionSystem` | yearly | Writes down the gene pool |
| `DestinySystem` | yearly | Checks whether the island has met its destiny |

## DNA (`core/genetics.gd`)

A genome holds two copies (0–255) of each of 14 genes: the first copy comes from the mother, the second from the father. A child gets one random copy of every gene from each parent. Each copy has a 1.5% chance to shift a little and a 0.2% chance to become something new.

| Gene | Shows as | Does |
|---|---|---|
| pigment, hair | Skin tone, hair color | Looks only; drifts |
| eyes | Narrow eyes, only with two copies (recessive) | Looks only |
| height, build | Height ±10%; slim, average or stout | Stout people lose less health in hunger |
| strength | | Hunting, building, woodcutting, quarrying, farming output; war |
| vitality | | Fewer fevers, less dying of them, higher top health |
| longevity | | Shifts the aging curve by ±8 years |
| fertility | | How easily a couple conceives |
| intellect | | Learning speed, discoveries, standing in the tribe |
| temper | | Quarrels; leans toward brave, fierce or proud |
| sociability | | Warmer meetings, boldness in love; leans toward cheerful and kind |
| curiosity | | Discoveries; leans toward curious; restless leaders found new tribes |
| frailty | Frail only with two copies (recessive) | Lower top health, shorter life, more sickness |

Natural selection is not scripted. Genes only nudge survival, work and attraction, and the plague kills the frail first. The evolution chart (E) shows the means of the tracked genes over the years.

## A life (`core/people.gd`, `core/systems/life_system.gd`)

| Stage | Ages | |
|---|---|---|
| Infant | 0–2 | Stays with the mother; mothers of babies under a year work at 60% |
| Child | 3–11 | Plays |
| Youth | 12–15 | Apprentices to a parent's job at half output and learns faster |
| Adult | 16–54 | Works; may marry; women may bear children until 45 |
| Elder | 55+ | Works at 75%, retires at 64 to teach the young |

- **Personality** forms at 15: two traits, weighted by genes (temper, sociability, curiosity, intellect, strength, vitality) and by the parents' traits.
- **Health** (0–100) recovers each month and falls with hunger, thirst, winter without a roof or warm clothes, and sickness. The young and the old are hit harder.
- **Sickness**: about 1–4% a month, more in winter, in crowded homes, for the frail and next to sick housemates. Healers make it less deadly.
- **Death**: an aging curve shifted by longevity, risks from sickness and weak health, and accidents by job (hunters most). Childbirth is risky without a healer.
- **Conception** needs a husband in the same tribe, about 13 months since the last birth, food, a roof and no deep grief. Large families want fewer children. Twins happen 1.5% of the time.
- **Babies** take the father's family name and sometimes a dead grandparent's given name.
- **Orphans** with no adult at home are taken in by a grandparent, an aunt or uncle, a grown sibling, or a kind family.
- **Mood** (0–100) follows the tribe's needs, a partner, children, friends, rivals, grief, sickness and health. It affects work and quarrels.

The dead stay in `state.dead` (the oldest are forgotten after 1,500), with their genome and their life story, so family trees and the feed can still show them.

## People together (`core/systems/social_system.gd`)

- Each day about 14% of the people meet someone: a housemate, a workmate or anyone in the tribe. Their traits (`SocialSystem.FIT`) and sociability decide whether the meeting warms or sours their bond (−100 to 100). Hot tempers and bad moods start quarrels.
- **Love** needs two single adults, close in age, drawn to each other's sex, not close kin (cousins may), and chemistry: a fixed spark per pair above 0.55. Singles spend a quarter of their meetings seeking someone. Love fades slowly unless they marry.
- At love 70 one proposes (the bolder one). The other says yes depending on their bond and love, or turns them down.
- Families arrange matches for singles from 24.
- Marriages between tribes move the partner from the smaller tribe, with their young children, and warm the two tribes.
- Couples who come to dislike each other may part. Bitter rivals sometimes come to blows.
- At midsummer the singles of friendly tribes meet at the gathering.

## Work (`core/jobs.gd`, `core/systems/work_system.gd`, `core/systems/economy_system.gd`)

Each month the tribe works out how many hands each job needs: specialists first (healers, toolmakers, potters, weavers, a shaman), then builders and woodcutters or quarriers for the current plan, then enough food workers to feed everyone through the year, with more when stores are low. People keep their job when they can; otherwise whoever suits a job best takes it. Suitability comes from skill, the gene the work needs, a parent's trade and personality.

Skills grow about 0.75 points a month (faster for the clever and for apprentices taught by elders), so mastering a trade takes about 12 years. Output depends on skill, genes, mood, health, age, the season, rain, tools and how crowded the wild woods are.

| Job | Needs | Makes |
|---|---|---|
| Forager, hunter | (start) | Food; wild food thins as the valley fills |
| Fisher | Fishing | Food, more when the water is full |
| Farmer | Farming and a field (3 farmers each) | Lots of food, most of it at harvest |
| Woodcutter | (start) | Wood |
| Quarrier | Stone tools | Stone |
| Builder | (start) | Builds the current project |
| Toolmaker | Stone tools | Tools (+35% output when the tribe is equipped) |
| Healer | Herbal lore | Care: fewer deaths from sickness and childbirth |
| Potter | Pottery | Jars: less spoilage, more storage |
| Weaver | Weaving | Warm clothes for winter |
| Shaman | Rites | Faith: mood and Influence |
| Miner | Copper working and a mine | Metal (iron once known); little where the island lacks the ore |
| Smith | Copper working and a smithy | Tools from metal, twice a toolmaker's |
| Scholar | Writing and a school | Research: faster discoveries |
| Merchant | Coinage and a market | Wealth, for themselves |
| Guard | Bronze, and a law or a worried ruler that wants guards | Order (control), strength in war; paid by the treasury |
| Official | Writing and taxation | Order; paid by the treasury |
| Factory worker | Steam power and a factory | Tools, cloth and jars by the cartload; profit for the owners; smoke |

## Discoveries (`core/knowledge.gd`)

Each month every adult has a small chance (higher with intellect, curiosity and the curious or wise trait) to discover something the tribe is ready for. Their job points them toward some discoveries (a forager finds herbal lore, a woodcutter carpentry). Friendly tribes teach each other.

Stone tools, fishing, herbal lore, rites and weaving need nothing. Pottery needs fire, carpentry needs stone tools, and farming needs herbal lore and pottery. After farming come the 21 techs of the four later ages (see [SOCIETY.md](SOCIETY.md)). Harder techs need more than one bright idea, and techs whose ore the island lacks rarely work out.

## Building (`core/buildings.gd`)

When nothing is being built, the chief chooses the next project:

1. Homes, if people lack beds: a tent, a hut once carpentry is known, or a longhouse for a big tribe.
2. A workshop.
3. A healer's hut.
4. A storehouse.
5. Fields.
6. A shrine.
7. The places of the later ages: a mine and a smithy, a school, a market, a temple; the great house, barracks, watchtowers, prison and statue that power builds for itself; factories, a broadcast tower and surveillance masts.
8. A palisade after a war (a stone wall once masonry is known).
9. The humblest home rebuilt as the best the tribe knows: tents become huts, then stone houses, row houses and apartment blocks.

Materials are set aside when work starts; until then woodcutters and quarriers gather what's missing. Builders put in their days. A tent takes about a month, a longhouse most of a year.

Couples get a home of their own when one frees up; crowded homes send out a young couple or a grown child. When a tribe has far more beds than people, an empty home comes down.

## Tribes (`core/systems/relations_system.gd`)

- **Chiefs** are chosen by standing: what the others think of them, age, intellect, lore, wealth, class and traits, tilted toward the strongest faction's kind. A chief who dies is replaced, and one past 74 steps down, except under hereditary rule, where the eldest of the ruling house inherits and rules for life. The chief's traits steer the tribe (`People.TRAITS`) and its laws (see [SOCIETY.md](SOCIETY.md)).
- **Feelings between tribes** fade each year. Shared full water warms them; shared failing water, envy, competing for the same woods, the valley filling up and the grudges between their people sour them. Marriages between them soften them.
- **Incidents** (a quarrel over a deer, trampled fields, an insult at the gathering) happen between tribes that aren't close friends. A starving tribe may **raid** a fed neighbor's stores.
- **War** comes to rivals at −45 or worse. Fighters are the able adults; strength, hunting skill, bravery, the chief and a palisade decide it. Named people fall, and the winner takes food.
- Kind or wise chiefs send **gifts** to mend feuds. A tiny tribe may **merge** into a friendly one.
- A tribe of 60, or 40 with too few roofs, may **split**: a restless young adult leads their household, siblings, friends and the unhappy to found a new tribe, carrying tents and their share of the stores.

## The view

`game/diorama/settlement.gd` draws each tribe. Every person walks to real work sites (`work_sites.gd`) with the tool of their job, works there, and brings food, wood or stone home. Children play, babies stay with their mothers, the sick lie by their door, mourners visit the graves, and elders sit by the fire. The sim's daily meetings (`state.meetings`, not saved) are acted out with a chat, love, quarrel or fight mark.

The UI panels live in `game/ui/`: the life feed, the person panel, the tribe panel and the evolution chart.

## Tuning

`tools/life_report.gd` prints one world year by year. `tools/balance_report.gd` runs several seeds with a kind bot.

The current balance over 100 years: about 40 people grow to about 120 in 4 tribes, with about 260 births, 160 deaths, 60 marriages, the whole tech tree, 1–2 wars, about 3 famines and 6 fevers.
