# A screen you can read

This is the plan for milestone M2.7 in the [roadmap](../ROADMAP.md). It changes what the player sees. The simulation stays as it is.

The aim: a person who has never played can say, after the opening, what they are trying to do, how they touch a tribe, and how fast time is moving.

## Why it feels confusing now

The pieces exist. They all arrive at once, and several of them speak in the sim's own words.

| # | What the player meets | Where |
|---|---|---|
| 1 | The full dashboard is up in the first minute. Top bar: pause, five speeds labeled 1× to 90×, the island, then Feed, Genes, Society, Oracle, and the keys. Left: the prophecy and a feed of every birth and job. Bottom: Influence and eight miracles, including Smite, Awaken, and Sanctify. | `main.gd` layout, `TopBar.NAV`, `MiracleBar` |
| 2 | Time starts the instant the prophecy arrives, at 6 days a second, about a year a minute. The goal is on screen while the years pass. | `main.gd` `_process`, `speed_index` starts at 1 |
| 3 | The prophecy leads with the Oracle's poetry. The plain goal is the line under it. "Make it happen, or break it" is a faint caption. The reason both endings pay Influence is a tooltip. | `ProphecyCard` |
| 4 | Eight miracles share one tile. A blessing and a curse look the same. Political miracles are there before anyone has a law. | `Miracles.ORDER` |
| 5 | A person opens on percentages: health, mood, skill, loyalty, wealth, then the tribe's needs again. Two allele squares per gene, and the word "frailty allele", live on the DNA tab. The life story is the last tab. | `PersonPanel` |
| 6 | A camp opens a long scroll: ages, needs, stores, jobs, buildings, every tech, neighbors, blood, then a Society tab with seven measures. One tooltip calls inequality a Gini coefficient. | `TribePanel` |
| 7 | The Genes and Society buttons open year-by-year charts. The Oracle button opens provider, budget, and model routing. | `EvolutionPanel`, `SocietyPanel`, `AISettingsPanel` |
| 8 | Kindness changes how the chronicle speaks. Nothing on screen says so. | `WorldState.disposition_text`, used in prompts |
| 9 | Nothing teaches the loop. The keys card, behind ?, is the manual. | `KeysCard`. M6 still lists a tutorial |

The dilemma card can stay. Time already waits, the situation is a paragraph, and each choice is a row. The chronicle can stay. The camp already draws a selection ring (`Settlement.set_selected`).

The paper-and-ink look in [ART_BIBLE.md](ART_BIBLE.md) stays. When this ships, that doc's layout table is updated to match.

## The resting screen

With nothing else open, the player sees four things.

- The island.
- The prophecy card.
- Time controls, and the ? button.
- The miracle bar, and a short feed of the big turns.

Feed, Genes, and Society leave the top bar. The feed is already the left column. The gene chart opens from a person's Blood tab, with the words "See the valley". The society chart opens from a tribe's Society tab, with the words "See the island". Both keys, E and H, still work.

The Oracle button leaves the play bar. AI settings open from one row on the keys card: "Who the Oracle speaks through". The A key still opens them. The prophecy card remains the Oracle's voice.

## The prophecy

`ProphecyCard` leads with the plain goal, in the strong face: "Grow to 77 people or more before year 140." The Oracle's sentence sits under it, in italic, shorter. Then the meter, then the years left.

The faint caption becomes one line: "Bring this about, or break it. Either way the Chronicler tells the story, and you gain Influence."

These goals get plainer words in `goal_what`. The meter still shows the number.

| Metric | Goal line |
|---|---|
| max_dystopia | A tribe falls under a hard rule |
| max_inequality | In one tribe, the rich pull far ahead of the rest |
| vassal_count | One tribe rules N others |

When the meter moves, add one clause from the latest event that touched that count: "Up 12. A good harvest." If no event explains it, show the numbers alone.

A new prophecy pauses time. The card grows a button, "Let the years run". The chronicle already waits for Continue. This matches it. Later prophecies do the same: one click, then the speed the player already chose. Loading a save does not pause again.

The first prophecy of a new world adds three lines under the goal, and never shows them again:

1. You watch this island.
2. This is what must happen.
3. Bless or strike a people with the bar below. Click a camp to choose who.

No spotlight tour and no second tutorial mode. M6's "tutorial given by the Oracle" is this card.

## Miracles

The bar has two groups. Bless holds Rain, Harvest, and Muse. Strike holds Drought and Plague. Each group has a small label.

Smite, Awaken, and Sanctify are a third group, Rule. They appear once any tribe has a chief and at least one law, or any tribe has reached the Age of Bronze. Before that they are absent. A faded tile is reserved for a miracle the player already knows but cannot cast, and the existing reason stays ("Choose a tribe first", "Not enough Influence").

The target chip says "Choose a people on the island" until a camp is selected, then the tribe's name. The selection ring on the camp stays.

After a cast, the notice says the result in the world's terms. Harvest: "The Oru's stores hold four more months of food." Plague: "A sickness is in the Oru. N people died." The notice widget already exists (`NOTICE_SECONDS`).

## A person

Clicking someone still opens `PersonPanel`. The Life tab starts with four lines under the name.

- What they are doing, and their job.
- One worry, if health, mood, or loyalty is low. Otherwise this line is absent.
- Their thought, as now.
- A follow button, as now.

Health, mood, skill, loyalty, and wealth stay, under a closed section titled "How they fare". The tribe's needs leave this panel.

The tabs stay, with DNA renamed Blood. Family, Bonds, and Story stay as they are. The allele grid stays on Blood.

## A tribe

The Life tab of `TribePanel` opens with one sentence, picked in this order: hungry, short of water, at war, raising a building, or "The Oru are well. Nara leads them." Under that, food in days, then the four needs as words: Fine, Low, or Bad. The percent shows on hover.

Jobs, buildings, knowledge, neighbors, and blood stay, each closed until opened. Knowledge shows what they know and the next discovery within reach. The locked remainder of the tree stays behind "Show the rest".

The Society tab opens with the government, the ruler, and one sentence for the measure that is most wrong: "People are afraid of their rulers." The bars, factions, culture, laws, slogans, and monuments stay below, each group closed. The inequality tooltip says "How unevenly savings are spread." The words "Gini coefficient" go away.

## The feed and the speeds

The feed starts with `_only_major` on, and the title reads "The big turns". The filter still reveals daily work, apprentices, and small gifts.

Speed buttons say how long a year takes: "3 min", "1 min", "18 s", "6 s", "2 s". The tooltip keeps the exact rate, "6 days a second". The default stays the current one, about a minute a year. While time is paused, or a card is waiting, the date plaque says "Time is stopped".

## How the god seems

The Influence purse gains one word from `WorldState.disposition()`, once the god has acted enough for a leaning. Benevolent reads "Kind". Wrathful reads "Harsh". Capricious reads "Unpredictable". Unknown shows nothing. The tooltip uses `disposition_text()` without the mercy and wrath totals. No new sim value.

## Animals, when they arrive

The animal panel in [LIVING_WORLD.md](LIVING_WORLD.md) follows the person card. The first view is the species, the age, what it is doing, and one line of its story. Genes open under Blood.

## Order of work

```
C1 prophecy leads with the goal, pauses, and teaches once
C2 speeds in words, feed starts on the big turns
C3 top bar loses Feed, Genes, Society, and AI settings
C4 miracle groups, Rule waits for laws or the Bronze Age
C5 person card and tribe card open short
C6 the god's leaning on the purse
```

C1 and C2 are copy and a pause. They can ship before the layout work.

## Exit

A new world, no one explaining the keys. After "Let the years run" and five minutes, a new player can answer three questions: what the prophecy is asking for, how to cast a miracle on a tribe, and how fast a year is passing.

Before and after shots of the resting screen go in `docs/screenshots/`.

Tests in `test_hud.gd`:

- In year 0 of the First Fires, with no laws, the bar shows Rain, Harvest, Muse, Drought, and Plague, and hides Smite, Awaken, and Sanctify.
- The prophecy card's first text line is `goal_text`, and a new prophecy leaves time paused until "Let the years run".
- The feed starts on the big turns.
- The top bar's play buttons are pause, the five speeds, and the keys.
- A person's Life tab does not list the tribe's needs.
- Inequality's tooltip does not say Gini.
