extends SceneTree
## Writes the three SkeletonProfileHumanoid bone maps used to retarget walk, sit and chop.
## Run once: godot --headless --path src --script res://tools/make_bone_maps.gd

func _initialize() -> void:
	var profile := SkeletonProfileHumanoid.new()
	print("PROFILE ", profile.bone_size)
	for i: int in profile.bone_size:
		print("  ", profile.get_bone_name(i), " parent ", profile.get_bone_parent(i))
	_save("res://art/characters/kenney/humanoid.tres", _kenney())
	_save("res://art/characters/quaternius/ual1_humanoid.tres", _ual1())
	_save("res://art/characters/quaternius/ual2_humanoid.tres", _ual2())
	_rest("res://art/characters/kenney/characterMedium.fbx")
	quit()


func _save(path: String, bones: Dictionary) -> void:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	for profile_bone: String in bones:
		map.set_skeleton_bone_name(profile_bone, bones[profile_bone])
	var err := ResourceSaver.save(map, path)
	print("saved ", path, " ", err, " mapped ", bones.size())


func _mirror(bones: Dictionary) -> Dictionary:
	var mirrored := {}
	for profile_bone: String in bones:
		if not profile_bone.begins_with("Left"):
			continue
		var skeleton_bone: String = bones[profile_bone]
		var right := skeleton_bone.replace(".L", ".R").replace("_l", "_r").replace("Left", "Right")
		mirrored["Right" + profile_bone.substr(4)] = right
	return mirrored


func _kenney() -> Dictionary:
	# No Root, jaw, eyes, middle/ring/little fingers, or third thumb bone on this rig.
	# HipsCtrl and the foot-IK helpers are not humanoid bones and stay unmapped.
	var bones := {
		"Hips": "Hips",
		"Spine": "Spine",
		"Chest": "Chest",
		"UpperChest": "UpperChest",
		"Neck": "Neck",
		"Head": "Head",
		"LeftShoulder": "LeftShoulder",
		"LeftUpperArm": "LeftArm",
		"LeftLowerArm": "LeftForeArm",
		"LeftHand": "LeftHand",
		"LeftThumbMetacarpal": "LeftHandThumb1",
		"LeftThumbProximal": "LeftHandThumb2",
		"LeftIndexProximal": "LeftHandIndex1",
		"LeftIndexIntermediate": "LeftHandIndex2",
		"LeftIndexDistal": "LeftHandIndex3",
		"LeftUpperLeg": "LeftUpLeg",
		"LeftLowerLeg": "LeftLeg",
		"LeftFoot": "LeftFoot",
		"LeftToes": "LeftToes",
	}
	bones.merge(_mirror(bones))
	return bones


func _ual1() -> Dictionary:
	var bones := {
		"Root": "root",
		"Hips": "DEF-hips",
		"Spine": "DEF-spine.001",
		"Chest": "DEF-spine.002",
		"UpperChest": "DEF-spine.003",
		"Neck": "DEF-neck",
		"Head": "DEF-head",
		"LeftShoulder": "DEF-shoulder.L",
		"LeftUpperArm": "DEF-upper_arm.L",
		"LeftLowerArm": "DEF-forearm.L",
		"LeftHand": "DEF-hand.L",
		"LeftThumbMetacarpal": "DEF-thumb.01.L",
		"LeftThumbProximal": "DEF-thumb.02.L",
		"LeftThumbDistal": "DEF-thumb.03.L",
		"LeftIndexProximal": "DEF-f_index.01.L",
		"LeftIndexIntermediate": "DEF-f_index.02.L",
		"LeftIndexDistal": "DEF-f_index.03.L",
		"LeftMiddleProximal": "DEF-f_middle.01.L",
		"LeftMiddleIntermediate": "DEF-f_middle.02.L",
		"LeftMiddleDistal": "DEF-f_middle.03.L",
		"LeftRingProximal": "DEF-f_ring.01.L",
		"LeftRingIntermediate": "DEF-f_ring.02.L",
		"LeftRingDistal": "DEF-f_ring.03.L",
		"LeftLittleProximal": "DEF-f_pinky.01.L",
		"LeftLittleIntermediate": "DEF-f_pinky.02.L",
		"LeftLittleDistal": "DEF-f_pinky.03.L",
		"LeftUpperLeg": "DEF-thigh.L",
		"LeftLowerLeg": "DEF-shin.L",
		"LeftFoot": "DEF-foot.L",
		"LeftToes": "DEF-toe.L",
	}
	bones.merge(_mirror(bones))
	return bones


func _ual2() -> Dictionary:
	var bones := {
		"Root": "root",
		"Hips": "pelvis",
		"Spine": "spine_01",
		"Chest": "spine_02",
		"UpperChest": "spine_03",
		"Neck": "neck_01",
		"Head": "Head",
		"LeftShoulder": "clavicle_l",
		"LeftUpperArm": "upperarm_l",
		"LeftLowerArm": "lowerarm_l",
		"LeftHand": "hand_l",
		"LeftThumbMetacarpal": "thumb_01_l",
		"LeftThumbProximal": "thumb_02_l",
		"LeftThumbDistal": "thumb_03_l",
		"LeftIndexProximal": "index_01_l",
		"LeftIndexIntermediate": "index_02_l",
		"LeftIndexDistal": "index_03_l",
		"LeftMiddleProximal": "middle_01_l",
		"LeftMiddleIntermediate": "middle_02_l",
		"LeftMiddleDistal": "middle_03_l",
		"LeftRingProximal": "ring_01_l",
		"LeftRingIntermediate": "ring_02_l",
		"LeftRingDistal": "ring_03_l",
		"LeftLittleProximal": "pinky_01_l",
		"LeftLittleIntermediate": "pinky_02_l",
		"LeftLittleDistal": "pinky_03_l",
		"LeftUpperLeg": "thigh_l",
		"LeftLowerLeg": "calf_l",
		"LeftFoot": "foot_l",
		"LeftToes": "ball_l",
	}
	bones.merge(_mirror(bones))
	return bones


func _rest(path: String) -> void:
	var scene := (load(path) as PackedScene).instantiate()
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	print("REST ", path, " bones ", skeleton.get_bone_count())
	var mesh := scene.find_child("characterMedium", true, false) as MeshInstance3D
	if mesh:
		print("  aabb ", mesh.get_aabb())
		var skin := mesh.skin
		if skin:
			var names: PackedStringArray = []
			for i: int in skin.get_bind_count():
				names.append(String(skin.get_bind_name(i)))
			print("  skin binds ", names.size(), " ", " ".join(names))
	for bone_name: String in ["Hips", "Spine", "Head", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightArm"]:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			print("  missing ", bone_name)
			continue
		var rest := skeleton.get_bone_global_rest(idx)
		var y := rest.basis.y.normalized()
		print("  ", bone_name, " origin ", rest.origin, " +Y ", y)
	var root := scene.find_child("Root", true, false) as Node3D
	if root:
		print("  Root xform ", root.transform)
	scene.free()
