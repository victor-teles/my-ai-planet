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

One walk cycle moves the left foot 0.0086 skeleton units along the facing axis. At adult scale that is 0.17 world units in 1.333 seconds. `set_walking` sets the clip rate from the distance moved since the previous call, so the feet keep up with the body. `set_walking` clamps the rate between 0.2 and 12. A settlement walk at 0.42 world units per second plays the clip at about 3.2 times. A shorter villager takes faster steps because the stride scales with the model.

`set_walking` still takes a 0 to 1 blend. The blend mixes the walk clip with idle. Run stays in the library and out of this blend. `set_work` plays chop once the swing is greater than zero, and holds that clip until both amounts return to zero. A stoop with no swing still bends the spine. `set_work(villager, stoop, swing, "sit")` plays the sit clip. Settlement never passes the `"sit"` action.

## What the stills show

Stills are in `docs/screenshots/anim-spike/`. Each frame is one villager from `VillagerArt.make`, posed in walk, sit, or chop. Adult head scale on the bone is 0.7. The child's head scale is 0.90. Neither head scale explodes.

**Walk.** `slim-woman-walk.png`, `stout-man-walk.png`, `elder-walk.png`, and `child-walk.png`. One foot is forward and flat. The other foot is back and just off the ground. Arms hang and swing, with the hands at hip height, clear of the chest and the face. On the slim woman and the child, the rear fist meets the thigh. On the stout man, the forward fist crosses in front of the wide belly. The elder stoops (the existing `VillagerPose` bend) and the forward fist meets the thigh. Feet stay on the stride. Heads keep their usual size. The child's head is larger than an adult's, and the elder's hair is grey.

**Sit.** `slim-woman-sit.png`, `stout-man-sit.png`, `elder-sit.png`, and `child-sit.png`. This is `Sitting_Idle` from Universal Animation Library 1. On this body it is a deep squat with both feet flat. It is a ground sit, and the hips do not rest on a chair. Hips drop to about 0.14 world units on the slim woman (0.23 while she stands). Hands meet in front of the shins. The hands stay outside the torso. The elder's stoop carries the head forward and the hands down to the shins. The child's head stays at the child scale.

**Chop.** `slim-woman-chop.png`, `stout-man-chop.png`, `elder-chop.png`, and `child-chop.png`. The raised fist holds the existing axe beside the head. The blade crosses the fist. The tool mount expects the idle grip, so the blade does not follow a lumberjack line. The other fist rests at the hip. On the stout man that fist presses the wide belly. The feet plant in a wide stance, with the soles on the ground. The axe stays outside the head. On the child, the larger head leaves a small gap beside the blade.

## Files

The clip files are `src/art/characters/quaternius/ual1_standard.glb`, `ual2_standard.glb`, `CREDITS.txt`, and the two humanoid bone maps. The Kenney map is `src/art/characters/kenney/humanoid.tres`. The Kenney FBX import files stay as they were. The bake and the playback are in `src/game/diorama/villager_art.gd`. The still tool is `src/tools/anim_spike.gd`.
