extends SceneTree
## Close-ups of the retargeted walk, sit and chop on four Kenney villagers.
## Usage: godot --path src --resolution 1000x1200 -s res://tools/anim_spike.gd -- --out=<dir>

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")

var _out := ""
var _camera: Camera3D
var _label: Label
var _world: Node3D
var _shots: Array[Dictionary] = []
var _index := -1
var _hold := 0
var _current: Node3D


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair[0] == "out" and pair.size() > 1:
			_out = pair[1]
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/anim-spike")
	DirAccess.make_dir_recursive_absolute(_out)
	_world = Node3D.new()
	root.add_child(_world)
	_environment()
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(6.0, 0.1, 6.0)
	ground.mesh = plane
	ground.position.y = -0.05
	ground.material_override = ToonMaterials.get_material(Color(0.46, 0.70, 0.38), 0.0, true)
	_world.add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	_world.add_child(_camera)
	_label = Label.new()
	_label.position = Vector2(20, 14)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_label.add_theme_constant_override("outline_size", 8)
	root.add_child(_label)
	_queue("slim-woman", _adult(11, true, 28, "slim", Color(0.86, 0.38, 0.52)))
	_queue("stout-man", _adult(23, false, 34, "stout", Color(0.25, 0.42, 0.72)))
	_queue("elder", _adult(41, false, 72, "average", Color(0.55, 0.40, 0.28)))
	_queue("child", VillagerArt.child_appearance(7, Color(0.95, 0.72, 0.28)))


func _adult(id: int, female: bool, age: int, build: String, tunic: Color) -> Dictionary:
	var looks := VillagerArt.appearance(id, female, age, false, tunic)
	looks["build"] = build
	looks["female"] = female
	return looks


func _queue(who: String, looks: Dictionary) -> void:
	for action: String in ["walk", "sit", "chop"]:
		_shots.append({"who": who, "action": action, "looks": looks})


func _environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.50, 0.36, 0.70)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.80, 0.62)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0.0)
	_world.add_child(sun)


func _process(_delta: float) -> bool:
	if _current:
		_shape(_current)
	if _hold > 0:
		_hold -= 1
		if _hold > 0:
			return false
		var shot: Dictionary = _shots[_index]
		var path := _out.path_join("%s-%s.png" % [shot["who"], shot["action"]])
		var image := root.get_texture().get_image()
		var err := image.save_png(path)
		print("saved ", path, " ", err, " ", image.get_width(), "x", image.get_height())
		_dump()
		_current.queue_free()
		_current = null
		if _index + 1 >= _shots.size():
			return true
	_index += 1
	_show(_shots[_index])
	_hold = 3
	return false


func _show(shot: Dictionary) -> void:
	var looks: Dictionary = shot["looks"]
	var villager := VillagerArt.make(looks)
	var tree := villager.get_node("Model/AnimationTree") as AnimationTree
	tree.active = false
	_world.add_child(villager)
	var action := String(shot["action"])
	if action == "walk":
		VillagerArt.set_walking(villager, 1.0)
		VillagerArt.set_work(villager, 0.0)
	elif action == "sit":
		VillagerArt.set_walking(villager, 0.0)
		VillagerArt.set_work(villager, 0.0, 0.0, "sit")
	else:
		VillagerArt.set_walking(villager, 0.0)
		VillagerArt.set_tool(villager, "axe")
		VillagerArt.set_work(villager, 0.15, 1.0)
	var at := _pose_time(villager, action)
	tree.advance(at)
	_shape(villager)
	print("pose ", shot["who"], " ", action, " at ", snappedf(at, 0.001))
	var grown := float(villager.get_meta("growth", 1.0))
	var top := 0.78 * float(looks["height"]) * grown
	var center := Vector3(0.0, top * 0.46, 0.0)
	var yaw := -0.62
	var pitch := -0.16
	var distance := top * 1.85
	_camera.position = center + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	_camera.look_at_from_position(_camera.position, center)
	_label.text = "%s  %s" % [shot["who"], action]
	_current = villager


func _pose_time(villager: Node3D, action: String) -> float:
	var skeleton := villager.get_node("Model/Root/Skeleton3D") as Skeleton3D
	var player := villager.get_node("Model/AnimationPlayer") as AnimationPlayer
	var anim := player.get_animation(action)
	var best_time := anim.length * 0.35
	var best := -999.0
	var steps := 24
	for step: int in steps:
		var time := anim.length * step / float(steps)
		_apply(skeleton, anim, time)
		var score := 0.0
		if action == "walk":
			var left := VillagerArt._bone_global(skeleton, skeleton.find_bone("LeftFoot")).origin
			var right := VillagerArt._bone_global(skeleton, skeleton.find_bone("RightFoot")).origin
			score = absf(left.y - right.y)
		elif action == "sit":
			score = -VillagerArt._bone_global(skeleton, skeleton.find_bone("Hips")).origin.z
		else:
			score = VillagerArt._bone_global(skeleton, skeleton.find_bone("RightHand")).origin.z
		if score > best:
			best = score
			best_time = time
	skeleton.reset_bone_poses()
	return best_time


func _apply(skeleton: Skeleton3D, anim: Animation, time: float) -> void:
	skeleton.reset_bone_poses()
	for track: int in anim.get_track_count():
		var bone := skeleton.find_bone(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(track, time))
		elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
			skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(track, time))


func _shape(villager: Node3D) -> void:
	var pose := villager.get_meta("pose") as VillagerPose
	pose._process_modification_with_delta(0.0)


func _dump() -> void:
	var skeleton := _current.get_node("Model/Root/Skeleton3D") as Skeleton3D
	var head := skeleton.find_bone("Head")
	print("  head scale ", skeleton.get_bone_pose_scale(head))
	for bone_name: String in ["Head", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var idx := skeleton.find_bone(bone_name)
		var world: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin
		print("  ", bone_name, " world ", world)
