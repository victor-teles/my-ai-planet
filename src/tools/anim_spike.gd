extends SceneTree
## Close-ups of the villager animation set (VillagerClips) on Kenney villagers, through the same
## API Settlement uses (play_action, set_locomotion_speed, set_carry).
## Usage: godot --path src --resolution 1000x1200 -s res://tools/anim_spike.gd -- [--out=<dir>]
##   [--who=slim-woman,stout-man,elder,child] [--actions=walk,jog,run,carry,sit,chop,...]
##   [--frames=N --step=0.1]: N stills per action, step seconds apart (to compare feet frame to frame)
##   [--sheet]: every action of one figure in one image, a grid of cells, instead of one file each
## "walk", "jog" and "run" are locomotion at that gait's blend position; "carry" is a walk with a
## load; anything else is an action name.

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")
const DEFAULT_ACTIONS: Array[String] = ["walk", "jog", "run", "carry", "sit", "chop", "hammer", "hoe", "gather", "kneel", "talk", "mourn", "lie"]
const SPEEDS := {"walk": 0.42, "jog": 0.9, "run": 1.6, "carry": 0.36}

var _out := ""
var _camera: Camera3D
var _label: Label
var _world: Node3D
var _shots: Array[Dictionary] = []
var _index := -1
var _hold := 0
var _current: Node3D
var _frames := 1
var _step := 0.1
var _sheet := false
var _cells: Array[Image] = []
var _cell_names: PackedStringArray = []


func _initialize() -> void:
	var who: Array[String] = ["slim-woman", "stout-man", "elder", "child"]
	var actions: Array[String] = DEFAULT_ACTIONS.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		var value := pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"out":
				_out = value
			"who":
				who.assign(value.split(","))
			"actions":
				actions.assign(value.split(","))
			"frames":
				_frames = maxi(int(value), 1)
			"step":
				_step = float(value)
			"sheet":
				_sheet = true
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/anim-set")
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
	var people := {
		"slim-woman": _adult(11, true, 28, "slim", Color(0.86, 0.38, 0.52)),
		"stout-man": _adult(23, false, 34, "stout", Color(0.25, 0.42, 0.72)),
		"elder": _adult(41, false, 72, "average", Color(0.55, 0.40, 0.28)),
		"child": VillagerArt.child_appearance(7, Color(0.95, 0.72, 0.28)),
	}
	for name: String in who:
		for action: String in actions:
			for frame: int in _frames:
				_shots.append({"who": name, "action": action, "looks": people[name], "frame": frame})


func _adult(id: int, female: bool, age: int, build: String, tunic: Color) -> Dictionary:
	var looks := VillagerArt.appearance(id, female, age, false, tunic)
	looks["build"] = build
	looks["female"] = female
	return looks


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
	if _hold > 0:
		_hold -= 1
		if _hold > 0:
			return false
		var shot: Dictionary = _shots[_index]
		var image := root.get_texture().get_image()
		if _sheet:
			_cells.append(image)
			_cell_names.append(String(shot["action"]))
		else:
			var suffix := "" if _frames == 1 else "-%02d" % int(shot["frame"])
			var path := _out.path_join("%s-%s%s.png" % [shot["who"], shot["action"], suffix])
			print("saved ", path, " ", image.save_png(path))
		_dump(String(shot["action"]))
		_current.queue_free()
		_current = null
		var last := _index + 1 >= _shots.size()
		if _sheet and (last or _shots[_index + 1]["who"] != shot["who"]):
			_save_sheet(String(shot["who"]))
		if last:
			return true
	_index += 1
	_show(_shots[_index])
	_hold = 3
	return false


func _show(shot: Dictionary) -> void:
	var looks: Dictionary = shot["looks"]
	var villager := VillagerArt.make(looks, 5)
	_world.add_child(villager)
	var animator := VillagerArt.animator(villager)
	animator.measure = false
	animator.idle_kind = "idle"
	var action := String(shot["action"])
	var at := 0.0
	if SPEEDS.has(action):
		VillagerArt.set_locomotion_speed(villager, float(SPEEDS[action]) * animator.body)
		if action == "carry":
			VillagerArt.set_carry(villager, "wood")
		# Settle the smoothed speed, then land on a stride with the feet far apart.
		for i: int in 30:
			animator.update(1.0 / 30.0)
		at = _stride_time(villager) + float(shot["frame"]) * _step
	else:
		VillagerArt.play_action(villager, action)
		if action == "chop" or action == "hammer":
			VillagerArt.set_tool(villager, "axe" if action == "chop" else "hammer")
		elif action == "hoe":
			VillagerArt.set_tool(villager, "hoe")
		animator.update(0.0)
		at = 0.6 + float(shot["frame"]) * _step
	animator.update(at)
	animator.set_process(false)
	var grown := float(villager.get_meta("growth", 1.0))
	var top := 0.78 * float(looks["height"]) * grown
	var center := Vector3(0.0, top * 0.46, 0.0)
	var yaw := -0.62 if action != "lie" else -1.2
	var pitch := -0.16 if action != "lie" else -0.5
	var distance := top * (1.85 if action != "lie" else 2.2)
	_camera.position = center + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	_camera.look_at_from_position(_camera.position, center)
	_label.text = "%s  %s%s" % [shot["who"], action, "" if _frames == 1 else "  +%.2fs" % (float(shot["frame"]) * _step)]
	_current = villager


## Seconds to advance a gait from here to where the feet are furthest apart along the walk.
func _stride_time(villager: Node3D) -> float:
	var animator := VillagerArt.animator(villager)
	var scale := float(animator.tree.get("parameters/pace/scale"))
	if scale <= 0.0:
		return 0.0
	var skeleton := animator.skeleton
	var best := 0.0
	var best_spread := -1.0
	var steps := 16
	for step: int in steps:
		animator.update(1.0 / (scale * steps))
		var left := VillagerArt._bone_global(skeleton, skeleton.find_bone("LeftFoot")).origin
		var right := VillagerArt._bone_global(skeleton, skeleton.find_bone("RightFoot")).origin
		var spread := absf(left.y - right.y)
		if spread > best_spread:
			best_spread = spread
			best = float(step + 1) / (scale * steps)
	# The loop above went one whole cycle, so best from here lands on the widest stride.
	return best


func _save_sheet(who: String) -> void:
	if _cells.is_empty():
		return
	var cell_w := _cells[0].get_width() / 2
	var cell_h := _cells[0].get_height() / 2
	var cols := mini(_cells.size(), 5)
	var rows := ceili(_cells.size() / float(cols))
	var sheet := Image.create(cell_w * cols, cell_h * rows, false, _cells[0].get_format())
	for i: int in _cells.size():
		var cell := _cells[i]
		cell.resize(cell_w, cell_h)
		sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i((i % cols) * cell_w, (i / cols) * cell_h))
	var path := _out.path_join("%s-sheet.png" % who)
	print("saved ", path, " ", sheet.save_png(path), " ", ",".join(_cell_names))
	_cells.clear()
	_cell_names.clear()


func _dump(action: String) -> void:
	var skeleton := _current.get_node("Model/Root/Skeleton3D") as Skeleton3D
	var line := PackedStringArray()
	for bone_name: String in ["Head", "Hips", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var idx := skeleton.find_bone(bone_name)
		var world: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin
		line.append("%s %.3f,%.3f,%.3f" % [bone_name, world.x, world.y, world.z])
	print("  ", action, ": ", "  ".join(line))
