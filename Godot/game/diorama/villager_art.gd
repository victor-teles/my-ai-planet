class_name VillagerArt
extends RefCounted
## Builds villagers: Kenney's low-poly animated character (CC0, art/characters/kenney/) wearing
## the skins painted by tools/paint_villager_skins.gd, toon-shaded with an ink outline. The head
## is scaled down from Kenney's cartoon proportions to an adult's. Walking blends the idle and
## a slowed run, so one pair of clips covers standing, strolling and hurrying.

const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
const IDLE_SOURCE := preload("res://art/characters/kenney/idle.fbx")
const RUN_SOURCE := preload("res://art/characters/kenney/run.fbx")
const SHADER := preload("res://art/shaders/villager.gdshader")
const LOOKS: Array[String] = ["male", "female"]
const MODEL_SCALE := 0.2 ## Kenney's character is 3.8 units tall; ours stand about two thirds of a hut
const HEAD_SCALE := 0.7
const HEIGHT := 0.67 ## world units, for picking
const OUTLINE_WIDTH := 0.0005 ## in the model's own (tiny) units
const HAIR_COLORS: Array[Color] = [
	Color(0.20, 0.13, 0.11), Color(0.36, 0.22, 0.14), Color(0.55, 0.30, 0.17), Color(0.72, 0.56, 0.34), Color(0.12, 0.10, 0.10),
]
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.78, 0.64), Color(0.88, 0.66, 0.50), Color(0.74, 0.52, 0.38), Color(0.56, 0.38, 0.27), Color(0.42, 0.29, 0.22),
]
const WALK_BLEND := 0.4 ## how much of the run shows through while walking
const WALK_PACE := 0.7 ## run clip speed while walking

static var _materials: Dictionary = {} ## look -> ShaderMaterial
static var _library: AnimationLibrary
static var _tree: AnimationNodeBlendTree


## A villager standing on its origin, facing +Z. Call set_walking() to animate it.
static func make(look: int, chief: bool, tunic: Color, hair: Color, skin_tone: Color) -> Node3D:
	var villager := Node3D.new()
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	villager.add_child(model)
	var skeleton := model.get_node("Root/Skeleton3D") as Skeleton3D
	var mesh := skeleton.get_node("characterMedium") as MeshInstance3D
	mesh.material_override = _material(LOOKS[look])
	mesh.set_instance_shader_parameter("tunic", tunic)
	mesh.set_instance_shader_parameter("hair", hair)
	mesh.set_instance_shader_parameter("skin_tone", skin_tone)
	var head := skeleton.find_bone("Head")
	skeleton.set_bone_pose_scale(head, Vector3.ONE * HEAD_SCALE)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", _animations())
	model.add_child(player)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = _blend_tree()
	tree.anim_player = NodePath("../AnimationPlayer")
	model.add_child(tree)
	tree.set("parameters/pace/scale", WALK_PACE)
	if chief:
		_add_headdress(skeleton, head)
	return villager


## Eases a villager between standing (0) and walking (1).
static func set_walking(villager: Node3D, amount: float) -> void:
	(villager.get_node("Model/AnimationTree") as AnimationTree).set("parameters/walk/blend_amount", amount * WALK_BLEND)


## Starts a villager's clips at their own point, so a crowd doesn't move in lockstep.
static func offset_time(villager: Node3D, seconds: float) -> void:
	(villager.get_node("Model/AnimationTree") as AnimationTree).advance(seconds)


static func _material(look: String) -> ShaderMaterial:
	if not _materials.has(look):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("skin", load("res://art/characters/villager_%s_skin.png" % look))
		material.set_shader_parameter("mask", load("res://art/characters/villager_%s_mask.png" % look))
		var outline := ShaderMaterial.new()
		outline.shader = ToonMaterials.OUTLINE_SHADER
		outline.set_shader_parameter("color", ToonMaterials.INK)
		outline.set_shader_parameter("width", OUTLINE_WIDTH)
		material.next_pass = outline
		_materials[look] = material
	return _materials[look]


static func _animations() -> AnimationLibrary:
	if _library == null:
		_library = AnimationLibrary.new()
		for source: Array in [[IDLE_SOURCE, "Root|Idle", "idle"], [RUN_SOURCE, "Root|Run", "run"]]:
			var scene := (source[0] as PackedScene).instantiate()
			var animation := (scene.get_node("AnimationPlayer") as AnimationPlayer).get_animation(source[1]).duplicate() as Animation
			animation.loop_mode = Animation.LOOP_LINEAR
			_library.add_animation(source[2], animation)
			scene.free()
	return _library


static func _blend_tree() -> AnimationNodeBlendTree:
	if _tree == null:
		_tree = AnimationNodeBlendTree.new()
		var idle := AnimationNodeAnimation.new()
		idle.animation = "idle"
		var run := AnimationNodeAnimation.new()
		run.animation = "run"
		_tree.add_node("idle", idle)
		_tree.add_node("run", run)
		_tree.add_node("pace", AnimationNodeTimeScale.new())
		_tree.add_node("walk", AnimationNodeBlend2.new())
		_tree.connect_node("pace", 0, "run")
		_tree.connect_node("walk", 0, "idle")
		_tree.connect_node("walk", 1, "pace")
		_tree.connect_node("output", 0, "walk")
	return _tree


## A leather band with three feathers, riding on the head bone.
static func _add_headdress(skeleton: Skeleton3D, head: int) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_idx = head
	skeleton.add_child(attachment)
	# The skeleton works in tiny units scaled up 100x by the model. Undo that (and the head's own
	# scale) so the sizes below read as world units on a model at scale 0.21; they grow and shrink with MODEL_SCALE.
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / (100.0 * 0.21 * HEAD_SCALE)
	attachment.add_child(holder)
	var band := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 0.068
	ring.bottom_radius = 0.07
	ring.height = 0.025
	band.mesh = ring
	band.material_override = ToonMaterials.get_material(Color(0.55, 0.22, 0.18), 0.008)
	band.position.y = 0.14
	holder.add_child(band)
	for i: int in 3:
		var feather := MeshInstance3D.new()
		var vane := SphereMesh.new()
		vane.radius = 0.022
		vane.height = 0.13
		feather.mesh = vane
		feather.material_override = ToonMaterials.get_material(Color(0.95, 0.75, 0.25) if i == 1 else Color(0.90, 0.33, 0.24), 0.006)
		feather.position = Vector3((i - 1) * 0.03, 0.195, -0.045)
		feather.rotation.z = (1 - i) * 0.35
		feather.scale = Vector3(1.0, 1.0, 0.35)
		holder.add_child(feather)
