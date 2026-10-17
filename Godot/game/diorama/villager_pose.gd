class_name VillagerPose
extends SkeletonModifier3D
## Shapes one villager's body on top of the animation, every frame: bone scales for build and
## proportions (slim or stout, a woman's narrower shoulders, an adult's or a child's head) and
## extra bends (an elder's stoop). The clips don't animate scale, so scales simply stick;
## bends are added after the clip's own rotation.

var scales: Dictionary = {} ## bone name -> Vector3
var bends: Dictionary = {} ## bone name -> radians of forward bend

var _scale_bones: Dictionary = {} ## bone index -> Vector3
var _bend_bones: Dictionary = {} ## bone index -> Quaternion


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _scale_bones.is_empty() and _bend_bones.is_empty():
		for bone: String in scales:
			_scale_bones[skeleton.find_bone(bone)] = scales[bone]
		for bone: String in bends:
			_bend_bones[skeleton.find_bone(bone)] = Quaternion(Vector3.RIGHT, float(bends[bone]))
	for index: int in _scale_bones:
		skeleton.set_bone_pose_scale(index, _scale_bones[index])
	for index: int in _bend_bones:
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * (_bend_bones[index] as Quaternion))
