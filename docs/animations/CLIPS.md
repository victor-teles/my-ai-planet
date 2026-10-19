# Villager animation set (M2.6 A1)

This page lists the clips villagers play, where each comes from, and what the library lacks. It also describes the tree that plays them, the API Settlement uses, and the level of detail.

Reader: someone adding a clip, mapping a new activity to a clip, or checking performance.

## Sources

Two files from Quaternius' Universal Animation Library (CC0), in `src/art/characters/quaternius/`:

- `ual1_standard.glb`, 46 clips: A_TPose, Crouch_Fwd, Crouch_Idle, Dance, Death01, Driving, Fixing_Kneeling, Hit_Chest, Hit_Head, Idle, Idle_Talking, Idle_Torch, Interact, Jog_Fwd, Jump, Jump_Land, Jump_Start, PickUp_Table, Pistol_* (6), Punch_Cross, Punch_Enter, Punch_Jab, Push, Roll, Roll_RM, Sitting_Enter, Sitting_Exit, Sitting_Idle, Sitting_Talking, Spell_Simple_* (4), Sprint, Swim_Fwd, Swim_Idle, Sword_Attack, Sword_Attack_RM, Sword_Idle, Walk, Walk_Formal.
- `ual2_standard.glb`, 43 clips: A_TPose, Chest_Open, ClimbUp_1m_RM, Consume, Farm_Harvest, Farm_PlantSeed, Farm_Watering, Hit_Knockback(_RM), Idle_FoldArms, Idle_Lantern, Idle_No, Idle_Rail, Idle_Rail_Call, Idle_Shield, Idle_Shield_Break, Idle_TalkingPhone, LayToIdle, Melee_Hook(_Rec), NinjaJump_* (3), OverhandThrow, Shield_Dash_RM, Shield_OneShot, Slide, Slide_Exit, Slide_Start, Sword_Block, Sword_Dash_RM, Sword_Regular_* (6), TreeChopping, Walk_Carry, Yes, Zombie_Idle, Zombie_Scratch, Zombie_Walk_Fwd.

`src/tools/clip_inventory.gd` prints this list with clip lengths. Kenney's own `idle.fbx` stays in the set as a third idle and as the statues' pose.

## The set

All clips are retargeted at load time onto Kenney's `characterMedium` skeleton (see [SPIKE.md](SPIKE.md) for the bone map and the rest-space conversion). `src/game/diorama/villager_clips.gd` holds the table.

| Needed | Name in the set | Source clip | Notes |
|---|---|---|---|
| Idles (3) | `idle`, `idle_arms`, `idle_easy` | Idle, Idle_FoldArms, Kenney idle | Each villager keeps one: half plain, a quarter arms folded, a quarter Kenney's |
| Walk | `walk` | Walk | Gait |
| Jog | `jog` | Jog_Fwd | Gait |
| Run | `run` | Sprint | Gait |
| Carry-walk | `carry` | Walk_Carry | Arms only, over any idle or gait, while `set_carry` holds a load |
| Sit on the ground | `sit` | Sitting_Idle | A low sit with both feet flat, hips about 0.14 above the ground |
| Sit and talk | `sit_talk` | Sitting_Talking | Teachers, weavers |
| Kneel, gather | `kneel`, `gather` | Fixing_Kneeling, Farm_Harvest | Gather bends to the ground |
| Chop | `chop` | TreeChopping | Woodcutters, quarriers, miners, smiths |
| Hammer | `hammer` | Fixing_Kneeling | Stand-in: kneeling repair work. Builders, toolmakers |
| Hoe, dig | `hoe`, `water` | Farm_PlantSeed, Farm_Watering | Stand-in: planting. No hoe or dig swing |
| Pick up, put down | `pick_up`, `put_down` (one-shot) | PickUp_Table, played forward and backward | Upper body only, at the end of work and at the store |
| Talk | `talk`, `argue`, `agree` | Idle_Talking, Idle_No, Yes | Meetings: chat, quarrel, love |
| Cheer | `cheer` | Dance | Stand-in |
| Mourn | `mourn` | Crouch_Idle + a bowed head | The bow is a `VillagerPose` bend added with the action |
| Pray | `pray` | Spell_Simple_Idle + a bowed head | Stand-in: one arm held out. Shamans |
| Lie, sleep | `lie` | LayToIdle, first pose held | Sick and resting people |
| Die | `die` | Death01, once, then held | Replaces the old 90 degree tip-over |
| Push, fight | `push`, `fight`, `punch` (one-shot) | Push, Punch_Jab, Punch_Cross | Fights between villagers |
| Children's play | `jump` | Jump | Children who stop while playing |
| Other trades | `crouch`, `hold_up`, `interact`, `throw`, `eat` | Crouch_Idle, Idle_Torch, Interact, OverhandThrow, Consume | Hunters crouch, fishers and guards hold up their rod or pike, scholars and factory hands work at a bench |

### Missing from the library

- **Sit on a bench or log.** Sitting_Idle is a low sit, not a seat at knee height. A raised seat needs either a new clip or a log prop placed under the low sit.
- **Hammer standing (an anvil), hoe and dig swings.** Builders kneel with Fixing_Kneeling, smiths use the chop swing, and farmers use the planting clip.
- **Wave, laugh, cheer.** `cheer` is Dance. No wave or laugh exists.
- **Mourn and pray.** Both are stand-ins (a crouch with a bowed head, and a spell pose). Neither is a real kneeling grief or hands together.
- **Sleep.** `lie` holds the first pose of LayToIdle (flat on the back). No sleeping on the side.
- **Children's skip and tag.** Children run with the adult jog and run, at the child's size, and jump. No skip.
- **Turn in place.** Turning in place shows the idle.

## The tree

One `AnimationNodeBlendTree` is built once and shared. Each villager's `AnimationTree` keeps its own parameters.

- `state` is an `AnimationNodeTransition` that acts as the state machine. Its states are `move` and every action, fully connected, with a 0.3 second cross-fade.
- `move` is `carry` (a `Blend2` filtered to the shoulders, arms and hands) over `moving` (a `Blend2` of the idle and the gait).
- `gait` is an `AnimationNodeBlendSpace1D` with `sync` on, keyed on speed against an adult's body: walk from 0.30 to 0.52 world units a second, jog from 0.66 to 1.15, and run from 1.35. A short band between two points mixes both gaits. A `TimeScale` (`pace`) sits over it.
- `gesture` is a `OneShot` over everything, filtered to the spine and arms, so the legs keep walking under a pick-up.

The gaits are baked into one-second cycles that start with the left foot furthest forward, so the blend space mixes them in step. At load time, `VillagerClips` measures each gait's distance per cycle from the planted foot. A foot counts as planted while it moves backward in the lower half of its lift. The results on an adult: walk 0.26, jog 0.86 and run 0.59 world units per cycle.

## Feet that do not slide

`VillagerAnimator` (`src/game/diorama/villager_animator.gd`) measures how far the figure really moved since its last update. The speed against the body's size (height times growth) sets the gait. The clip rate is that distance over the gait's distance per cycle. A child at a playing pace runs where an adult at the same speed would walk.

While the figure moves faster than 0.16 (adult units a second), any action gives way to walking and comes back when it stops. That way nobody slides along sitting or chopping.

`test_villager_anim::test_feet_do_not_slide` checks the planted foot over the ground. The foot drifts 5% of the body's travel at a walk (0.30 and 0.42), 4% in the walk-to-jog band (0.6), 3% at a jog (0.9) and at a run (1.6), and 6% for a running child (1.1). The spike took the rate from the foot's peak-to-peak travel against the hips. That is about 0.6 of the distance per cycle, so the walk played about 1.7 times too fast. `docs/screenshots/anim-set/walk-by-consecutive-frames.png` shows six frames in a row from `src/tools/walk_by.gd`. In it the walker's rear foot holds its stripe on the floor while the body moves on.

## API (`VillagerArt`)

- `set_locomotion_speed(villager, speed)`: the speed Settlement moves the figure at. In the scene the animator measures the real movement. This value drives tools and stills (`VillagerAnimator.measure = false`).
- `play_action(villager, name)`: starts an action, or `""` for standing and walking.
- `play_once(villager, gesture)`: `pick_up`, `put_down`, `nod` or `punch`.
- `set_carry(villager, what)`: the prop plus the carry arms.
- `work_action(job)`, `meet_action(kind)`, `rest_action(activity)`: the clip for a trade, a meeting, or a rest.
- `animator(villager)`: the `VillagerAnimator`, for its rate and state.

`set_walking`, `set_work` and `set_lying` are gone. `VillagerPose` still scales and bends bones on top of every clip: build, head size, and the elder's stoop.

## Level of detail

The tree (`AnimationMixer` callback mode manual) and the skeleton's modifiers (`Skeleton3D` modifier callback mode manual) run only when the animator updates. The animator updates as follows:

| Where the villager is | Update every |
|---|---|
| On screen, nearer than 10 units to the camera (the follow camera sits at 9) | frame |
| On screen, nearer than 22 units | 2nd frame |
| On screen, further | 3rd frame |
| Off screen | 4th frame |

Each update passes the frames' time added up. The first countdown is staggered by id, so 40 villagers made on one frame update 10 per frame (`test_lod_updates_are_staggered`). Settlement runs a walker's behavior step (planning, steering, timers, clip requests) on the frames its animator updates, with the time since the last step. A far walker therefore moves and animates at one cadence, each update measures exactly one step, and the camp's per-frame cost falls with the walkers' rates. Tree parameters are set only when they change. The camera frustum is read once a frame for all villagers.

Steering also got cheaper. The camp builds one neighbor grid a frame (`Steering.neighbor_grid`) instead of one per walker, so the cost is no longer O(n²). The pair loops read packed arrays, and obstacles out of reach are dropped before the per-obstacle math. All of these give the same results (`test_shared_grid_matches`, `test_steering`).

## Benchmark

`scripts/fps_bench.sh` (`src/tools/fps_bench.gd`) opens a 1600x1000 window with vsync off. It builds seed 42 after 30 years (three camps) and fills the camps with exactly 300 villagers: working at every trade, idling, resting, teaching, mourning and playing. It then prints the average fps, the slowest second, the 1% low, and the milliseconds spent in the camps' behavior, the sync, and the render. Use `--probe=nosettle` to stop behavior and `--probe=noanim` to stop animation.

Results with 300 villagers, on an M3 shared with other Godot jobs (load average 8 to 20, so runs vary a lot):

| | Default view (distance 30) | Close-up of one camp (`--focus --distance=12`) |
|---|---|---|
| Before (4306eb9) | 13.5 to 14.7 fps average, slowest second 9.6 to 13.4 | 13.6 to 15.0 |
| After | 51 to 96 fps average (best: 96, slowest second 94) | 40 to 75 |

Before the change, the camps' behavior step took 52 to 65 ms a frame (the per-walker neighbor hash) and the animation about 9 ms. After it, the behavior step takes 8 to 10 ms and animation with rendering about 5 ms.
