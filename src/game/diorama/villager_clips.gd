class_name VillagerClips
extends RefCounted
## The villagers' animation set and the AnimationTree that plays it (see docs/animations/CLIPS.md).
## Clips come from Quaternius' Universal Animation Library 1 and 2 (CC0), retargeted at load time
## onto Kenney's characterMedium skeleton: rotations into Kenney's rest axes and bone names, hip
## motion scaled by hip height. Kenney's own idle stays as a third idle (and the statues' pose).
##
## Locomotion (walk, jog, run) is baked into one-second cycles that all start with the left foot
## furthest forward, so a 1D blend space can mix them in step. Each gait's distance per cycle is
## measured from the planted foot, so the player can set the clip rate from the distance the
## villager really moved (see VillagerAnimator): the feet do not slide.
##
## The tree (shared by every villager; each AnimationTree keeps its own parameters):
##   gesture (OneShot)  <- state (Transition: "move" or an action) + gesture_kind (one-shot clips)
##   state "move"       <- carry (Blend2, arms only) <- moving (Blend2) <- idle_kind + pace(gait)
##   gait (BlendSpace1D, synced) keyed on speed against an adult's body: walk, jog, run

const UAL1 := preload("res://art/characters/quaternius/ual1_standard.glb")
const UAL2 := preload("res://art/characters/quaternius/ual2_standard.glb")
const KENNEY_IDLE := preload("res://art/characters/kenney/idle.fbx")
const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
const HUMANOID := preload("res://art/characters/kenney/humanoid.tres")
const CYCLE_KEYS := 48 ## keys per baked locomotion cycle
const MEASURE_STEPS := 96 ## samples when measuring a gait's planted foot
const CONTACT_BAND := 0.5 ## a foot moving back this low (share of its lift) counts as planted

## Gaits: [source, clip], named by GAIT_NAMES.
const GAITS: Array[Array] = [["ual1", "Walk"], ["ual1", "Jog_Fwd"], ["ual1", "Sprint"]]
const GAIT_NAMES: Array[String] = ["walk", "jog", "run"]
## The blend space's points: [gait, speed in world units a second on an adult]. Each gait holds a
## span on its own and hands over to the next in a short band, because gaits with different
## strides blended at one cadence slide a little. Below the first point the walk slows down and
## blends into an idle (see VillagerAnimator); above the last the run speeds up.
const GAIT_POINTS: Array[Array] = [[0, 0.30], [0, 0.52], [1, 0.66], [1, 1.15], [2, 1.35]]
## Standing idles; each villager keeps one (see VillagerAnimator.idle_kind).
const IDLES := {
	"idle": ["ual1", "Idle"],
	"idle_arms": ["ual2", "Idle_FoldArms"],
	"idle_easy": ["kenney", "Root|Idle"],
}
## Arms that hold a load in both hands, over any idle or gait.
const CARRY := ["ual2", "Walk_Carry"]
## States that VillagerArt.play_action() requests: [source, clip, loops]. Several stand in for
## something the library lacks (see CLIPS.md): hammering is the kneeling repair, a hoe is planting.
const ACTIONS := {
	"sit": ["ual1", "Sitting_Idle", true],
	"sit_talk": ["ual1", "Sitting_Talking", true],
	"kneel": ["ual1", "Fixing_Kneeling", true],
	"hammer": ["ual1", "Fixing_Kneeling", true],
	"gather": ["ual2", "Farm_Harvest", true],
	"chop": ["ual2", "TreeChopping", true],
	"hoe": ["ual2", "Farm_PlantSeed", true],
	"water": ["ual2", "Farm_Watering", true],
	"talk": ["ual1", "Idle_Talking", true],
	"argue": ["ual2", "Idle_No", true],
	"agree": ["ual2", "Yes", true],
	"cheer": ["ual1", "Dance", true],
	"mourn": ["ual1", "Crouch_Idle", true],
	"pray": ["ual1", "Spell_Simple_Idle", true],
	"crouch": ["ual1", "Crouch_Idle", true],
	"hold_up": ["ual1", "Idle_Torch", true],
	"interact": ["ual1", "Interact", true],
	"throw": ["ual2", "OverhandThrow", true],
	"push": ["ual1", "Push", true],
	"fight": ["ual1", "Punch_Jab", true],
	"jump": ["ual1", "Jump", true],
	"eat": ["ual2", "Consume", true],
	"lie": ["ual2", "LayToIdle", false], ## held on its first pose: flat on the back
	"die": ["ual1", "Death01", false], ## plays once and stays down
}
## A pose held still, from a clip's time: action -> seconds into the source clip.
const HELD := {"lie": 0.0}
## One-shot gestures over whatever plays (VillagerArt.play_once): [source, clip, backward].
## They move the upper body only (UPPER_BONES), so the legs keep walking or standing under them.
const GESTURES := {
	"pick_up": ["ual1", "PickUp_Table", false],
	"put_down": ["ual1", "PickUp_Table", true],
	"nod": ["ual2", "Yes", false],
	"punch": ["ual1", "Punch_Cross", false],
}
## Bones the carry pose takes over: the shoulders down to the fingers.
const CARRY_BONES: Array[String] = [
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandThumb1", "LeftHandThumb2",
	"RightHandIndex1", "RightHandIndex2", "RightHandIndex3", "RightHandThumb1", "RightHandThumb2",
]
## The spine up: what a gesture moves.
const UPPER_BONES: Array[String] = ["Spine", "Chest", "UpperChest", "Neck", "Head"]
const STATE_FADE := 0.3 ## seconds to cross-fade between actions
const IDLE_FADE := 0.5

static var _library: AnimationLibrary
static var _tree: AnimationNodeBlendTree
static var _cycle_lengths: PackedFloat32Array = [] ## skeleton units travelled per cycle, by gait
static var _root_scale := 1.0 ## Kenney's Root node scale: skeleton units to model units
static var _bone_path := ""


## Every clip, baked once and shared.
static func library() -> AnimationLibrary:
	if _library == null:
		_bake()
	return _library


## The animation tree root, shared by every villager.
static func tree_root() -> AnimationNodeBlendTree:
	if _tree == null:
		_tree = _build_tree()
	return _tree


## Skeleton units the body travels in one cycle of each gait (walk, jog, run).
static func cycle_lengths() -> PackedFloat32Array:
	library()
	return _cycle_lengths


## Skeleton units to the model's own units (multiply by the model's scale for world units).
static func root_scale() -> float:
	library()
	return _root_scale


## Skeleton units per cycle where the gait blend space sits at position (adult speed): the two
## neighboring points mix linearly, as the blend space mixes them.
static func cycle_length_at(position: float) -> float:
	var lengths := cycle_lengths()
	var first: Array = GAIT_POINTS[0]
	if position <= float(first[1]):
		return lengths[int(first[0])]
	for i: int in range(1, GAIT_POINTS.size()):
		var point: Array = GAIT_POINTS[i]
		var at := float(point[1])
		if position <= at:
			var before: Array = GAIT_POINTS[i - 1]
			var t := (position - float(before[1])) / (at - float(before[1]))
			return lerpf(lengths[int(before[0])], lengths[int(point[0])], t)
	return lengths[int(GAIT_POINTS[GAIT_POINTS.size() - 1][0])]


## Speeds (world units a second, on an adult) at which each gait plays at its authored rate.
static func natural_speeds() -> PackedFloat32Array:
	var lengths := cycle_lengths()
	var speeds := PackedFloat32Array()
	var sources := _sources()
	for i: int in GAITS.size():
		var source := _clip(sources, String(GAITS[i][0]), String(GAITS[i][1]))
		speeds.append(lengths[i] * _root_scale * VillagerArt.MODEL_SCALE / source.length)
	for scene: Node in sources.values():
		scene.free()
	return speeds


## Every name play_action() accepts.
static func actions() -> Array:
	return ACTIONS.keys()


static func has_action(action: String) -> bool:
	return ACTIONS.has(action)


static func has_gesture(gesture: String) -> bool:
	return GESTURES.has(gesture)


# --- Baking -------------------------------------------------------------------------

static func _bake() -> void:
	var library := AnimationLibrary.new()
	var sources := _sources()
	var kenney := MODEL.instantiate()
	var skeleton := kenney.get_node("Root/Skeleton3D") as Skeleton3D
	_root_scale = absf((kenney.get_node("Root") as Node3D).transform.basis.get_scale().y)
	var kenney_idle := _clip(sources, "kenney", "Root|Idle").duplicate() as Animation
	kenney_idle.loop_mode = Animation.LOOP_LINEAR
	_bone_path = kenney_idle.track_get_path(0).get_concatenated_names()
	var names := _humanoid_names()
	var baked: Dictionary = {} ## "source|clip" -> retargeted clip, so shared clips bake once
	var bake := func(source: String, clip: String) -> Animation:
		var key := source + "|" + clip
		if not baked.has(key):
			if source == "kenney":
				baked[key] = kenney_idle
			else:
				var scene: Node = sources[source]
				var source_skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
				baked[key] = _retarget(source_skeleton, skeleton, _clip(sources, source, clip), names, _bone_path)
		return baked[key]
	_cycle_lengths = PackedFloat32Array()
	for i: int in GAITS.size():
		var walk: Animation = bake.call(String(GAITS[i][0]), String(GAITS[i][1]))
		var gait := _measure_gait(skeleton, walk)
		_cycle_lengths.append(float(gait["cycle"]))
		library.add_animation(GAIT_NAMES[i], _cycle(walk, float(gait["phase"])))
	for idle: String in IDLES:
		library.add_animation(idle, bake.call(String(IDLES[idle][0]), String(IDLES[idle][1])))
	library.add_animation("carry", bake.call(String(CARRY[0]), String(CARRY[1])))
	for action: String in ACTIONS:
		var entry: Array = ACTIONS[action]
		var clip: Animation = bake.call(String(entry[0]), String(entry[1]))
		if HELD.has(action):
			clip = _held(clip, float(HELD[action]))
		elif not bool(entry[2]):
			clip = clip.duplicate() as Animation
			clip.loop_mode = Animation.LOOP_NONE
		library.add_animation(action, clip)
	for gesture: String in GESTURES:
		var entry: Array = GESTURES[gesture]
		var once := (bake.call(String(entry[0]), String(entry[1])) as Animation).duplicate() as Animation
		once.loop_mode = Animation.LOOP_NONE
		library.add_animation("once_" + gesture, once)
	kenney.free()
	for scene: Node in sources.values():
		scene.free()
	_library = library


static func _sources() -> Dictionary:
	return {"ual1": UAL1.instantiate(), "ual2": UAL2.instantiate(), "kenney": KENNEY_IDLE.instantiate()}


static func _clip(sources: Dictionary, source: String, clip: String) -> Animation:
	var player := (sources[source] as Node).find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	# Import drops a trailing _Loop from some names. Try the bare name, then the name on the file.
	for name: String in [clip, clip + "_Loop"]:
		if player.has_animation(name):
			return player.get_animation(name)
	push_error("VillagerClips missing %s in %s; it has %s" % [clip, source, player.get_animation_list()])
	return Animation.new()


## A clip cut to one pose at time, held still.
static func _held(anim: Animation, time: float) -> Animation:
	var out := Animation.new()
	out.length = 0.5
	out.loop_mode = Animation.LOOP_LINEAR
	for track: int in anim.get_track_count():
		var type := anim.track_get_type(track)
		var copy := out.add_track(type)
		out.track_set_path(copy, anim.track_get_path(track))
		if type == Animation.TYPE_ROTATION_3D:
			out.rotation_track_insert_key(copy, 0.0, anim.rotation_track_interpolate(track, time))
		elif type == Animation.TYPE_POSITION_3D:
			out.position_track_insert_key(copy, 0.0, anim.position_track_interpolate(track, time))
	return out


## A looping gait resampled to one second, starting phase seconds into the source.
static func _cycle(anim: Animation, phase: float) -> Animation:
	var out := Animation.new()
	out.length = 1.0
	out.loop_mode = Animation.LOOP_LINEAR
	for track: int in anim.get_track_count():
		var type := anim.track_get_type(track)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var copy := out.add_track(type)
		out.track_set_path(copy, anim.track_get_path(track))
		out.track_set_interpolation_type(copy, Animation.INTERPOLATION_LINEAR)
		out.track_set_interpolation_loop_wrap(copy, true)
		var previous := Quaternion.IDENTITY
		for key: int in CYCLE_KEYS:
			var at := float(key) / CYCLE_KEYS
			var source_time := fposmod(phase + at * anim.length, anim.length)
			if type == Animation.TYPE_ROTATION_3D:
				var turn := anim.rotation_track_interpolate(track, source_time)
				if key > 0 and previous.dot(turn) < 0.0:
					turn = -turn
				previous = turn
				out.rotation_track_insert_key(copy, at, turn)
			else:
				out.position_track_insert_key(copy, at, anim.position_track_interpolate(track, source_time))
	return out


## How far one cycle carries the body, and where the cycle starts. While a foot is planted it
## moves backward in skeleton space exactly as fast as the body moves forward, so the planted
## foot's speed times the clip length is the distance per cycle. A foot is planted while it moves
## backward in the lower half of its lift (the ankle is lowest at heel strike and rises as the heel
## rolls off, so height alone is not enough). The cycle starts where the left foot is furthest
## forward. The skeleton is Z-up and faces -Y.
static func _measure_gait(skeleton: Skeleton3D, anim: Animation) -> Dictionary:
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var forward: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var height: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var tracks := _bone_tracks(skeleton, anim)
	for step: int in MEASURE_STEPS:
		_apply_pose(skeleton, tracks, anim, anim.length * step / MEASURE_STEPS)
		for side: int in 2:
			var foot := VillagerArt._bone_global(skeleton, int(feet[side])).origin
			forward[side].append(-foot.y)
			height[side].append(foot.z)
	skeleton.reset_bone_poses()
	var dt := anim.length / MEASURE_STEPS
	var speed_sum := 0.0
	var samples := 0
	for side: int in 2:
		var low := 999.0
		var high := -999.0
		for h: float in height[side]:
			low = minf(low, h)
			high = maxf(high, h)
		var band := low + (high - low) * CONTACT_BAND
		for step: int in MEASURE_STEPS:
			if height[side][step] > band:
				continue
			var ahead := forward[side][(step + 1) % MEASURE_STEPS]
			var behind := forward[side][(step - 1 + MEASURE_STEPS) % MEASURE_STEPS]
			if ahead >= behind:
				continue
			speed_sum += (behind - ahead) / (2.0 * dt)
			samples += 1
	var planted_speed := speed_sum / maxi(samples, 1)
	var front := 0
	for step: int in MEASURE_STEPS:
		if forward[0][step] > forward[0][front]:
			front = step
	return {"cycle": maxf(planted_speed * anim.length, 0.0001), "phase": anim.length * front / MEASURE_STEPS}


static func _bone_tracks(skeleton: Skeleton3D, anim: Animation) -> Array[Vector3i]:
	var found: Array[Vector3i] = [] ## (bone, track, type)
	for track: int in anim.get_track_count():
		var bone := skeleton.find_bone(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0:
			found.append(Vector3i(bone, track, anim.track_get_type(track)))
	return found


static func _apply_pose(skeleton: Skeleton3D, tracks: Array[Vector3i], anim: Animation, time: float) -> void:
	skeleton.reset_bone_poses()
	for entry: Vector3i in tracks:
		if entry.z == Animation.TYPE_ROTATION_3D:
			skeleton.set_bone_pose_rotation(entry.x, anim.rotation_track_interpolate(entry.y, time))
		elif entry.z == Animation.TYPE_POSITION_3D:
			skeleton.set_bone_pose_position(entry.x, anim.position_track_interpolate(entry.y, time))


## Profile bone name to the Kenney deform bone. Empty map entries (no counterpart) are left out.
static func _humanoid_names() -> Dictionary:
	var map := HUMANOID as BoneMap
	var profile := map.profile
	var names: Dictionary = {}
	for i: int in profile.bone_size:
		var profile_name := String(profile.get_bone_name(i))
		var skeleton_name := String(map.get_skeleton_bone_name(profile_name))
		if not skeleton_name.is_empty():
			names[profile_name] = skeleton_name
	return names


## Copies one Quaternius clip onto Kenney bone names and Kenney rest axes. Rotations follow
## RetargetModifier3D's local-pose conversion, then a fixed turn from the source's Y-up model
## space onto Kenney's Z-up skeleton. Position keys are stored divided by the source motion
## scale; only the hips keep one, scaled by the ratio of hip heights.
static func _retarget(source: Skeleton3D, target: Skeleton3D, anim: Animation, names: Dictionary, bone_path: String) -> Animation:
	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = Animation.LOOP_LINEAR
	var ratio := _hip_ratio(source, target)
	var motion := source.motion_scale if not is_zero_approx(source.motion_scale) else 1.0
	var prepared: Dictionary = {}
	var worst := 0.0
	var worst_bone := ""
	var align := _model_basis()
	for profile_name: String in names:
		var src_id := source.find_bone(profile_name)
		var tgt_name := String(names[profile_name])
		var tgt_id := target.find_bone(tgt_name)
		if src_id < 0 or tgt_id < 0:
			push_error("VillagerClips retarget missing %s -> %s" % [profile_name, tgt_name])
			continue
		var src_parent := _parent_global_rest(source, src_id)
		var tgt_parent := _parent_global_rest(target, tgt_id)
		var src_rest := source.get_bone_rest(src_id)
		var tgt_rest := target.get_bone_rest(tgt_id)
		# RetargetModifier3D treats both global rests as one model space. Kenney is Z-up, so
		# rotate source model space (Y-up, facing +Z) onto the skeleton (Z-up, facing -Y) first.
		var pre := tgt_parent.basis.inverse() * align * src_parent.basis
		var post := src_rest.basis.inverse() * src_parent.basis.inverse() * align.inverse() * tgt_parent.basis * tgt_rest.basis
		var rest_error := rad_to_deg((pre * src_rest.basis * post).get_rotation_quaternion().angle_to(tgt_rest.basis.get_rotation_quaternion()))
		if rest_error > worst:
			worst = rest_error
			worst_bone = profile_name
		prepared[profile_name] = {
			"name": tgt_name, "pre": pre, "post": post,
			"src_origin": src_rest.origin, "tgt_origin": tgt_rest.origin,
		}
	for track: int in anim.get_track_count():
		var profile_name := String(anim.track_get_path(track).get_concatenated_subnames())
		if not prepared.has(profile_name):
			continue
		var info: Dictionary = prepared[profile_name]
		var type := anim.track_get_type(track)
		var path := NodePath(bone_path + ":" + String(info["name"]))
		var pre: Basis = info["pre"]
		var post: Basis = info["post"]
		if type == Animation.TYPE_ROTATION_3D:
			var rot_track := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(rot_track, path)
			out.track_set_interpolation_type(rot_track, anim.track_get_interpolation_type(track))
			var previous := Quaternion.IDENTITY
			var started := false
			for key: int in anim.track_get_key_count(track):
				var src_q := anim.track_get_key_value(track, key) as Quaternion
				var turned := (pre * Basis(src_q) * post).get_rotation_quaternion()
				if started and previous.dot(turned) < 0.0:
					turned = -turned
				started = true
				previous = turned
				out.rotation_track_insert_key(rot_track, anim.track_get_key_time(track, key), turned)
		elif type == Animation.TYPE_POSITION_3D and profile_name == "Hips":
			var pos_track := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pos_track, path)
			out.track_set_interpolation_type(pos_track, anim.track_get_interpolation_type(track))
			var src_origin: Vector3 = info["src_origin"]
			var tgt_origin: Vector3 = info["tgt_origin"]
			for key: int in anim.track_get_key_count(track):
				var played := (anim.track_get_key_value(track, key) as Vector3) * motion
				var origin := pre * ((played - src_origin) * ratio) + tgt_origin
				out.position_track_insert_key(pos_track, anim.track_get_key_time(track, key), origin)
	if worst > 1.0:
		push_error("VillagerClips retarget rest error %.2f deg on %s" % [worst, worst_bone])
	return out


## Source clips are Y-up and face +Z. Kenney's skeleton is Z-up and faces -Y. X is the character's left on both.
static func _model_basis() -> Basis:
	var align := Basis()
	align.x = Vector3(1.0, 0.0, 0.0)
	align.y = Vector3(0.0, 0.0, 1.0)
	align.z = Vector3(0.0, -1.0, 0.0)
	return align


## Hip height on the source is its Y (Y-up). On Kenney it is +Z, because the skeleton is Z-up.
static func _hip_ratio(source: Skeleton3D, target: Skeleton3D) -> float:
	var src_height := absf(source.get_bone_global_rest(source.find_bone("Hips")).origin.y)
	var tgt_height := absf(target.get_bone_global_rest(target.find_bone("Hips")).origin.z)
	if src_height < 0.00001:
		return 1.0
	return tgt_height / src_height


static func _parent_global_rest(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var parent := skeleton.get_bone_parent(bone)
	if parent < 0:
		return Transform3D.IDENTITY
	return skeleton.get_bone_global_rest(parent)


# --- The tree -----------------------------------------------------------------------

static func _build_tree() -> AnimationNodeBlendTree:
	library()
	var tree := AnimationNodeBlendTree.new()
	var idle_kind := AnimationNodeTransition.new()
	idle_kind.xfade_time = IDLE_FADE
	tree.add_node("idle_kind", idle_kind)
	var i := 0
	for idle: String in IDLES:
		idle_kind.add_input(idle)
		tree.add_node(idle, _play(idle))
		tree.connect_node("idle_kind", i, idle)
		i += 1
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = 4.0
	gait.sync = true
	for p: int in GAIT_POINTS.size():
		var point: Array = GAIT_POINTS[p]
		gait.add_blend_point(_play(GAIT_NAMES[int(point[0])]), float(point[1]), -1, "%s_%d" % [GAIT_NAMES[int(point[0])], p])
	tree.add_node("gait", gait)
	tree.add_node("pace", AnimationNodeTimeScale.new())
	tree.connect_node("pace", 0, "gait")
	tree.add_node("moving", AnimationNodeBlend2.new())
	tree.connect_node("moving", 0, "idle_kind")
	tree.connect_node("moving", 1, "pace")
	var carry := AnimationNodeBlend2.new()
	carry.filter_enabled = true
	for bone: String in CARRY_BONES:
		carry.set_filter_path(NodePath(_bone_path + ":" + bone), true)
	tree.add_node("carry_clip", _play("carry"))
	tree.add_node("carry", carry)
	tree.connect_node("carry", 0, "moving")
	tree.connect_node("carry", 1, "carry_clip")
	var state := AnimationNodeTransition.new()
	state.xfade_time = STATE_FADE
	tree.add_node("state", state)
	state.add_input("move")
	tree.connect_node("state", 0, "carry")
	i = 1
	for action: String in ACTIONS:
		state.add_input(action)
		tree.add_node("act_" + action, _play(action))
		tree.connect_node("state", i, "act_" + action)
		i += 1
	var gesture_kind := AnimationNodeTransition.new()
	gesture_kind.xfade_time = 0.0
	tree.add_node("gesture_kind", gesture_kind)
	i = 0
	for gesture: String in GESTURES:
		gesture_kind.add_input(gesture)
		var once := _play("once_" + gesture)
		if bool(GESTURES[gesture][2]):
			once.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		tree.add_node("once_" + gesture, once)
		tree.connect_node("gesture_kind", i, "once_" + gesture)
		i += 1
	var gesture := AnimationNodeOneShot.new()
	gesture.fadein_time = 0.15
	gesture.fadeout_time = 0.25
	gesture.filter_enabled = true
	for bone: String in UPPER_BONES + CARRY_BONES:
		gesture.set_filter_path(NodePath(_bone_path + ":" + bone), true)
	tree.add_node("gesture", gesture)
	tree.connect_node("gesture", 0, "state")
	tree.connect_node("gesture", 1, "gesture_kind")
	tree.connect_node("output", 0, "gesture")
	return tree


static func _play(animation: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	return node
