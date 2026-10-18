# A living world: villagers who move like people, and animals with DNA

This is the plan for milestone M2.6 in the [roadmap](../ROADMAP.md). It has two parts:

- **Part A:** villagers move and act like people, not robots. This part is view only: it never touches the simulation.
- **Part B:** animals, simulated with the same DNA rules as people (see [LIFE_SIM.md](LIFE_SIM.md)).

Part A's steering module (A2) is shared with Part B's herds (B5). Part B's core work (B1–B4) is headless, so it can run in parallel with Part A.

---

## Part A — Villagers who move like people

### Why the villagers look robotic today

| # | Cause | Where |
|---|---|---|
| 1 | **Two clips only.** A walk is 40% of a run blended with the idle at 70% speed, so the gait floats and the feet slide. Working, sitting, kneeling, talking and carrying are bone bends driven by sine waves. | `VillagerArt` (`WALK_BLEND`, `WALK_PACE`), `set_work` |
| 2 | **Everyone moves the same way.** One walk speed (0.42) for a child, a stout elder and a grieving widow. DNA, age, health and mood shape how people look but not how they move. | `Settlement.WALK_SPEED` |
| 3 | **Straight lines at a constant speed.** People slide straight to a random point. They walk through each other, through houses, walls and the fire, then stop dead. `_face()` snaps them to face a new direction in one frame. | `Settlement._step`, `_face` |
| 4 | **Work in lockstep.** Every woodcutter swings at the same rate (`sin(t * 5.0)`) with no strike, no pause and no result. Gatherers bob at a fixed rate. | `Settlement._step`, "Working motion" |
| 5 | **No intention.** Each step is a random target and a random timer. Any change from the sim (activity, job or home) clears the current plan, so at higher speeds people often turn around halfway through a walk. | `_sync_person` sets `walker.phase = ""` |
| 6 | **A dead idle.** Standing people play the same idle clip. They never glance at anyone, shift their weight or react to a birth, a death, rain or a war. A meeting is two people walking to a midpoint and standing still under a label. | `_plan`, `meet` |

### A1 — A real animation set (the biggest single win)

- Retarget the **Quaternius Universal Animation Library** (CC0, made for humanoid retargeting and Mixamo-style rigs) onto Kenney's `characterMedium` skeleton. Use Godot's import-time `BoneMap` with `SkeletonProfileHumanoid`. The painted skins, DNA looks and `VillagerPose` bone scales stay as they are.
  - First, make a small spike: retarget walk, sit and chop, then render close-ups of a slim woman, a stout man, an elder and a child. Check the hands, the feet and the scaled heads.
  - If the retarget fails, fall back to the library's own rig with our skins painted onto it. That costs a skin repaint, so it is the second choice.
- Clips needed: 2–3 idles, walk, jog, run, carry-walk (a load in both arms), sit on the ground, sit on a bench or log, kneel and gather, chop, hammer, hoe or dig, pick up and put down, talk gestures, wave, laugh or cheer, mourn, pray, lie or sleep, push or fight, and play for children (skip, jump, tag).
- Replace the two-clip `AnimationTree` with a state machine. Locomotion becomes a 1D blend space keyed on real speed, and the clip rate follows the distance moved, so **feet never slide**.
- Keep `VillagerPose` for build, stoop and the elder's bend. Hand-made bends stay only where no clip fits.
- Level of detail: villagers far from the camera or off screen update their animation every 2nd–4th frame and skip look-at. Target: 300 villagers at 60 fps (today it is about 65 fps with 170).

### A2 — Movement: steering, lanes and a gait from DNA

- **A shared steering module** (`game/diorama/steering.gd`, reused by animals in B5). It covers:
  - Acceleration, and an *arrive* behavior that eases into a stop.
  - A turn rate that slows people as they turn. A turn of more than 120° plays a turn in place.
  - Separation from nearby walkers, using a spatial hash per settlement.
  - Avoiding obstacles: building footprints (`BuildingArt.SIZES`), the fire and the wall.
- **Village lanes:** a small graph per camp (the ring streets, spokes between the rings and gates in the wall), with A* over about 20–40 nodes. People follow streets and use gates instead of cutting through houses. Paths into the wild are curved with 1–2 waypoints that avoid trees and rocks.
- **Gait from the person** (a profile computed once per walker and refreshed with `sync`):

  | Input | Effect |
  |---|---|
  | Age | Children skip and run. Elders walk slowly, stoop and sometimes pause. |
  | Height gene | A longer stride and a little more speed. |
  | Build | Stout people take heavier, slower steps. |
  | Health or sickness | A slower walk, and a limp for the sick and injured. |
  | Mood | Sad people walk slowly with the head down. Happy people walk with a bounce. |
  | Traits | Proud people walk upright, the shy keep their distance, and fierce or brave people walk briskly. |
  | Load | Stone is heavier than wood, and wood heavier than food. A load uses the carry-walk clip and slows the walk. |

- Per-walker noise (a seeded drift, not white noise) on speed, pauses and timing, so no two people move in step.

### A3 — Behavior: intentions, not random timers

- **A task queue per walker** (still visual only). A task is *go → do → come back*. The walker commits to the current task. A change from the sim queues the next plan instead of clearing the current one. Only urgent changes interrupt: death, falling sick, arrest, a fight or the call to war. This fixes the turning-around at high speeds.
- **Work loops with a beginning, a middle and an end:**
  - *Woodcutter:* walks to the tree, squares up to it, makes 3–6 strokes with an uneven rhythm, then pauses or wipes their brow. The tree shakes and chips fly. They pick up a log and carry it home.
  - *Builder:* carries materials from the store to the site, kneels, hammers and steps back to look.
  - *Farmer:* walks along the rows and hoes, with the season shown (sowing, tending, harvest).
  - *Hunter:* leaves in a pair or a group and crouches to stalk. With Part B, hunters track a real animal.
  - *Forager, healer, scholar, merchant, guard:* each gets 2–3 distinct actions instead of one bend.
- **Life between work:**
  - Groups of 3–5 form at the fire and sit in a circle. They take turns to talk with gestures and laugh.
  - Friends walk together. Couples sit close.
  - Children play tag (one child is "it").
  - Parents pick up their toddlers.
  - Elders teach a ring of youths.
- **Idle details:** look-at (the head bone turns toward a nearby walker, the fire or the person the player is inspecting), weight shifts, stretches and yawns. These are staggered so they never sync.
- **Reactions to what the sim reports:**

  | Event | Reaction |
  |---|---|
  | A birth | The family gathers. |
  | A death | People nearby turn. Mourners kneel at the grave. |
  | Rain | People look up and hurry under a roof. |
  | Drought | Shoulders slump. |
  | War | Fighters gather at the fire, then march out together. |
  | Midsummer gathering | A dance around the fire. |
  | A miracle | Everyone turns toward it. |

- **Seasons instead of a day-night cycle:** a sim day lasts under a second, so a day-night cycle would only flicker. In winter people huddle by the fire, walk faster and fewer go out. In summer they linger outside.

### A4 — Polish

- Dust puffs when people run, a sway on held tools, small anticipation and settle at the start and end of a move. Footstep and work-sound hooks are ready for M6 audio.
- A follow-camera check: following any villager for a minute should feel like watching a person.

### Exit for Part A

Follow any villager for 60 seconds at each speed. They never walk through a house or another person, never turn around without a reason, and their feet never slide. Two people with the same job never move in step. The motion shows that elders, children, the sick and the grieving are different people. Before and after recordings go in `docs/screenshots/`.

**Tests:**
- Headless planner tests: a non-urgent sim change does not cancel a walk, and an urgent one does.
- Steering tests: in a scripted crowd of 40, no two walkers overlap for more than a moment and nobody ends up inside a building footprint.
- An fps benchmark with 300 villagers.

---

## Part B — Animals with the same DNA rules

**The same principles as people.**
- Every animal is simulated in `core/`, in packed arrays in `WorldState`, drawn from the seeded `SimRng` and saved.
- Each gene has two copies (one from each parent), inheritance and mutation work the same way, and some genes are recessive.
- **Genes only nudge.** Natural selection is never scripted.
- The view only draws.

### B1 — General genetics

`Genetics` hard-codes the human gene list today. Change its functions to take a **gene table** (genes, recessive rules, mutation chances). The people table is the current list, unchanged, so **existing saves, genomes and the determinism test stay byte-identical**. A golden test checks this: the same seed gives the same world hash as before the change.

### B2 — Species (`core/species.gd`)

A data table, designed to grow into Era 2 *Bloom of Life* (species with gene traits and food webs). Per species, it records:

- Diet (grazer, browser, predator or omnivore), size, herd or pack size, and home biomes.
- Breeding season and litter size, and lifespan.
- What the species gives (meat, hide, wool, milk, draft power), how dangerous it is, and whether it can be tamed.

**Starter wild species by biome:**

| Biome | Species |
|---|---|
| Meadow | Deer, boar, wolf |
| Steppe | Wild horse, goat, wolf |
| Jungle | Boar, a big cat |
| Taiga | Deer, wolf, bear |
| Highland | Goat, wild sheep |

**Domestic species, which come from taming:** sheep, goat, cattle, pig, horse, and dog (from the wolf).

**Animal genes** (two copies each):

| Gene | Shows as | Does |
|---|---|---|
| size | Body scale | Meat yield, strength, food needed |
| speed | | Escaping predators and hunters; chasing for predators |
| coat | Coat thickness and color | Surviving winter (taiga) and heat (jungle) |
| pattern | Spots and stripes | Looks only; drifts |
| horns | Antler or horn size | Defense, winning mates |
| fertility | | Litter size and how often |
| longevity | | Aging curve |
| hardiness | | Disease, hunger |
| temper | | Wild ↔ tame. The key to taming. |
| wariness | | How far away it flees (flight distance) from people |
| yield | | Wool, milk, eggs (domestic lines) |
| white | A white coat, only with two copies (recessive) | Looks only. A rare "white stag" the Oracle can notice. |

### B3 — The animal system (`core/systems/animal_system.gd`)

- **Forage:** a coarse grid of the island's grazing, which rain regrows. Herds eat it, and fields, camps and felled woods shrink it. Grazing sets each animal's condition.
- **Births:** in the breeding season, the mother is paired with a herd sire. The sire is the strongest by size and horns, so sexual selection happens on its own. Inheritance and mutation use B1's code.
- **Deaths:** from age, starvation, winter (where coat matters), disease, predators and hunters.
- **Predators:** they take the slowest and weakest (by speed, health and age), which drives natural selection. Wolves follow the prey, so their numbers rise and fall with it.
- **Movement:** herds move between grazing grounds and keep away from camps, as far as their wariness gene says.
- **Every animal is an individual** (so each one keeps its own DNA). Totals are capped at about 150–300 animals per island, and most work runs monthly.
- **Hunting becomes real:** a hunter's food comes from the animals actually killed. This replaces `wild_yield` for hunters in `EconomySystem`, and foragers stay abstract. Success depends on skill, strength, tools, and the prey's speed and wariness. Boars and bears can injure hunters. **Overhunting can wipe a species out of the valley**, which gives the feed an event and the Oracle a prophecy.
- **Wolves** take livestock and, rarely, attack a person. Hunters and guards drive them off.

### B4 — Taming and breeding

- New techs: *animal taming* in the First Fires age, and *husbandry* together with farming. They unlock the **herder** job, pens and pastures.
- **Taming** captures the calmest animals of a wild herd (the ones with a low temper gene). **Breeding** picks parents toward the tribe's goal: calmer, bigger, more wool or more milk. That is **artificial selection the player can watch** in a new animal tab of the evolution chart (E), as domestic sheep drift away from wild ones over the decades.
- **Dogs:** wolves that hang around a camp and have a low temper gene become dogs. They follow their owners and help hunters.
- **The later ages:**
  - Oxen and horses speed up farming and building.
  - Horses add riders in war.
  - Herds are wealth and pass down to heirs, linking to `SocietySystem`, nobles and the bonded.
  - Optional law hooks: a sacred animal under a theocracy, a hunting ban for commoners.

### B5 — The view

- **Models:** Quaternius' CC0 low-poly animal packs, which include an animated farm-animal pack (cow, pig, horse, llama, sheep, dog) and a wild pack with a wolf. Before building on them, check which species and clips (idle, walk, run, eat, death) the downloads really contain. A deer or stag still has to be found. All models are restyled with the toon shader and ink outline, like the Kenney props.
- **Looks from genes,** as with `VillagerArt.appearance_of`: size, coat color and pattern, antlers and horns, and the white coat.
- **Herd behavior:** flocking (cohesion, separation, alignment) on the shared steering module from A2.
  - Grazing with the head down.
  - Alert with the head up when a hunter is within the wariness distance.
  - Fleeing at a run.
  - The young following their mothers.
  - Wolves trotting in a pack and chasing.
- **Hunts acted out:** hunters stalk, throw, the animal falls, and they carry it home. A herder leads the livestock to pasture and back. Dogs trot beside their owners.
- **An animal panel** when you click an animal: its species, age, mother, genes and a short story ("born in the spring of year 42, outran the wolves twice"). Only notable animals get names, such as the white stag or a chief's horse. The small-model naming that M3.5 uses can write them, with an offline fallback.

### B6 — The Oracle and the player

- **Prophecies:** "the deer will be gone from the valley within 30 years", "the herds will outnumber the people".
- **Dilemmas:** wolves are taking the sheep: cull them or live with them? A white stag was seen: hunt it, or call it sacred?
- **Miracles:** *Blessing of the Herds* (fertility). The plague can now strike the livestock.
- The world summary sent to the AI gains a short line about the animals.

### Exit for Part B

Same seed, same animals: the determinism and save/load round-trip tests pass with animals in the world.

**Over 100 years with the kind bot:**
- Wild herds survive.
- Overhunting can still wipe out a species when a bot overhunts.
- Hunters' food stays within ±10% of today's balance, so the numbers in LIFE_SIM and SOCIETY don't shift.
- Domestic lines visibly drift from wild ones in at least two genes.

`tools/life_report.gd` and `tools/balance_report.gd` print the animal stats. The game holds 60 fps with 300 villagers and 300 animals.

---

## Order of work

```
A1 animation spike ─► A1 full set ─► A3 behavior ─► A4 polish
        A2 steering + lanes ─┘            │
B1 gene tables ─► B2 species ─► B3 system ─► B4 taming
                                 └──────────► B5 view (needs A2) ─► B6 Oracle
```

Part A goes first because the player sees it every second. B1–B3 can run in parallel because they are headless and testable on their own.

## Decisions to confirm

| Topic | Recommendation | Alternative |
|---|---|---|
| Animation source | Retarget Quaternius UAL onto the current Kenney rig, which keeps today's looks | Move to the UAL rig and repaint the skins |
| Animal individuals | Every animal is an individual with its own genome, with a cap per island | Herds with one shared gene pool (cheaper, but the DNA story is weaker) |
| Hunting balance | Hunting food comes from real animals, then rebalance to match today | Keep hunting abstract and make animals only visual (loses overhunting and selection by hunters) |
