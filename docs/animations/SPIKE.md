# A1 animation spike

The retarget onto Kenney's `characterMedium` works. Walk, sit, and chop play on that skeleton. Idle and run still play. The bake copies clips only. The Quaternius mesh stays out of the scene, and this spike does not repaint skins.

Reader: someone deciding whether the rest of the clip list can use this rig. After reading, they can see which bones mapped, and what the stills show for hands, feet, and heads.

## Bones

Godot renamed the Quaternius rigs to `SkeletonProfileHumanoid` and overwrote their rest axes at import. A runtime bake then writes those clips into Kenney bone names and Kenney rest space. A rest pose maps back to the Kenney rest within 0.04 degrees on every mapped bone.

The bone map assigns the arms. `LeftUpperArm` is `LeftArm`, `LeftLowerArm` is `LeftForeArm`, and `LeftHand` is `LeftHand`. The right side matches. The map also assigns shoulders, index fingers (`LeftHandIndex1` through `3`), and the two thumb bones (`LeftHandThumb1`, `LeftHandThumb2`). Legs map `LeftUpperLeg` to `LeftUpLeg` and `LeftLowerLeg` to `LeftLeg`.

These profile bones have no Kenney deform bone. The bake drops their tracks:

- `Root`. `HipsCtrl` is an IK parent of the hips.
- `Jaw`, `LeftEye`, `RightEye`.
- `LeftThumbDistal` and `RightThumbDistal`. The Kenney thumb stops at `LeftHandThumb2`.
- Every middle, ring, and little finger bone.
- UAL2 leaf bones (`thumb_04_leaf_l` and the other fingertip leaves).

The bake skips foot IK helpers (`FootCtrl`, `HeelRoll`, `ToeRoll`, `KneeCtrl`, `HipsCtrl`, and the `*_end` tips). Skin weights use the deform bones in the bone map, and they skip those helpers.

Kenney's skeleton is Z-up and faces -Y. The source clips are Y-up and face +Z. The bake turns source model space onto that skeleton before it applies the pose. The bake divides each hip position key by the source motion scale. It then multiplies that delta by the hip-height ratio: Kenney hip height along +Z, over the source hip height along Y.

## Playback

Superseded by the full set: see [CLIPS.md](CLIPS.md). The spike's `set_walking` took the clip rate from the left foot's peak-to-peak travel against the hips (0.17 world units a cycle). The planted foot's speed gives 0.26, so the spike's walk played about 1.7 times too fast. `set_walking`, `set_work` and `set_lying` were replaced by `play_action`, `play_once` and `set_locomotion_speed`.

## What the stills show

Stills are in `docs/screenshots/anim-spike/`. Each frame is one villager from `VillagerArt.make`, posed in walk, sit, or chop. Adult head scale on the bone is 0.7. The child's head scale is 0.90. Neither head scale explodes.

**Walk.** `slim-woman-walk.png`, `stout-man-walk.png`, `elder-walk.png`, and `child-walk.png`. One foot is forward and flat. The other foot is back and just off the ground. Arms hang and swing, with the hands at hip height, clear of the chest and the face. On the slim woman and the child, the rear fist meets the thigh. On the stout man, the forward fist crosses in front of the wide belly. The elder stoops (the existing `VillagerPose` bend) and the forward fist meets the thigh. Feet stay on the stride. Heads keep their usual size. The child's head is larger than an adult's, and the elder's hair is grey.

**Sit.** `slim-woman-sit.png`, `stout-man-sit.png`, `elder-sit.png`, and `child-sit.png`. This is `Sitting_Idle` from Universal Animation Library 1. On this body it is a deep squat with both feet flat. It is a ground sit, and the hips do not rest on a chair. Hips drop to about 0.14 world units on the slim woman (0.23 while she stands). Hands meet in front of the shins. The hands stay outside the torso. The elder's stoop carries the head forward and the hands down to the shins. The child's head stays at the child scale.

**Chop.** `slim-woman-chop.png`, `stout-man-chop.png`, `elder-chop.png`, and `child-chop.png`. The raised fist holds the existing axe beside the head. The blade crosses the fist. The tool mount expects the idle grip, so the blade does not follow a lumberjack line. The other fist rests at the hip. On the stout man that fist presses the wide belly. The feet plant in a wide stance, with the soles on the ground. The axe stays outside the head. On the child, the larger head leaves a small gap beside the blade.

## Files

The clip files are `src/art/characters/quaternius/ual1_standard.glb`, `ual2_standard.glb`, `CREDITS.txt`, and the two humanoid bone maps. The Kenney map is `src/art/characters/kenney/humanoid.tres`. The Kenney FBX import files stay as they were. The bake is in `src/game/diorama/villager_clips.gd` and the playback in `villager_animator.gd`. The still tool is `src/tools/anim_spike.gd`. It now renders any clip of the set, and its spike stills are kept in `docs/screenshots/anim-spike/`.
