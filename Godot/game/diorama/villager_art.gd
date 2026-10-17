class_name VillagerArt
extends RefCounted
## Builds villagers: Kenney's low-poly animated character (CC0, art/characters/kenney/) wearing
## skins painted by tools/paint_villager_skins.gd, toon-shaded with an ink outline. Every citizen
## looks like themselves for life: their id picks an ancestry (skin tone, hair color, eye shape),
## a face, a beard, a hair style, a build and a height; age and sex come from the simulation.
## Walking blends the idle and a slowed run, so one pair of clips covers standing and strolling.

const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
const IDLE_SOURCE := preload("res://art/characters/kenney/idle.fbx")
const RUN_SOURCE := preload("res://art/characters/kenney/run.fbx")
const SHADER := preload("res://art/shaders/villager.gdshader")
const MODEL_SCALE := 0.2 ## Kenney's character is 3.8 units tall; adults stand about two thirds of a tent
const CHILD_SCALE := 0.62
const HEAD_SCALE := 0.7 ## an adult's head, against Kenney's cartoon proportions
const CHILD_HEAD_SCALE := 0.9
const HEIGHT := 0.67 ## world units, for picking
const OUTLINE_WIDTH := 0.0005 ## in the model's own (tiny) units
const ELDER_AGE := 55
const WALK_BLEND := 0.4 ## how much of the run shows through while walking
const WALK_PACE := 0.7 ## run clip speed while walking
const CHILD_WALK_BLEND := 0.85 ## children run

const SKIN_TONES: Array[Color] = [
	Color(0.97, 0.82, 0.70), Color(0.93, 0.74, 0.60), Color(0.86, 0.65, 0.48), Color(0.76, 0.54, 0.38),
	Color(0.62, 0.42, 0.29), Color(0.48, 0.32, 0.22), Color(0.36, 0.24, 0.17),
]
const HAIR_COLORS: Array[Color] = [
	Color(0.10, 0.08, 0.08), Color(0.22, 0.14, 0.10), Color(0.38, 0.24, 0.15), Color(0.55, 0.27, 0.15),
	Color(0.70, 0.30, 0.14), Color(0.82, 0.66, 0.40), Color(0.90, 0.80, 0.56),
]
const GREY_HAIR := Color(0.80, 0.79, 0.82)
## Ancestries: which skin tones and hair colors (indexes above) go together, and how often eyes
## are narrow. Picked with equal odds, so every camp is mixed.
const ANCESTRIES: Array[Dictionary] = [
	{"skin": [0, 1], "hair": [1, 2, 3, 4, 5, 6], "narrow": 0.0},
	{"skin": [1, 2], "hair": [0, 1], "narrow": 1.0},
	{"skin": [2, 3, 4], "hair": [0, 1], "narrow": 0.0},
	{"skin": [4, 5, 6], "hair": [0], "narrow": 0.0},
	{"skin": [2, 3, 4], "hair": [0], "narrow": 0.5},
]
const MALE_FACES: Array[String] = ["m1", "m2", "m3"]
const FEMALE_FACES: Array[String] = ["f1"]
const MALE_HAIR: Array[String] = ["short", "short", "short", "topknot", "long"]
const FEMALE_HAIR: Array[String] = ["long", "long", "bun", "ponytail", "braid"]
const CHILD_HAIR: Array[String] = ["short", "short", "ponytail"]

static var _materials: Dictionary = {} ## skin name -> ShaderMaterial
static var _library: AnimationLibrary
static var _tree: AnimationNodeBlendTree


static func skin_name(face: String, narrow_eyes: bool, beard: bool) -> String:
	return "villager_%s%s%s" % [face, "_narrow" if narrow_eyes else "", "_beard" if beard else ""]


## What changes a citizen's figure over their life: becoming chief, and greying in steps.
static func looks_key(age: int, chief: bool) -> String:
	return "%s|%d" % [chief, _grey_step(age)]


## 0 before ELDER_AGE, then 1 to 4 as the hair greys.
static func _grey_step(age: int) -> int:
	if age < ELDER_AGE:
		return 0
	return clampi(roundi((age - ELDER_AGE + 10) / 25.0 * 4.0), 1, 4)


## How a citizen looks, from their id (fixed for life) plus sex, age and rank.
static func appearance(id: int, female: bool, age: int, chief: bool, tunic: Color) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, "looks"])
	var looks := _base_looks(rng, tunic)
	var elder := age >= ELDER_AGE
	var narrow: bool = looks["narrow"]
	var face: String = FEMALE_FACES[rng.randi_range(0, FEMALE_FACES.size() - 1)] if female else MALE_FACES[rng.randi_range(0, MALE_FACES.size() - 1)]
	var beard := not female and rng.randf() < (0.6 if elder else 0.35)
	var styles := FEMALE_HAIR if female else MALE_HAIR
	var builds := ["slim", "slim", "average", "average", "average", "stout", "stout"]
	var hair: Color = looks["hair"]
	if elder:
		# Greying comes in steps, so villagers share a few materials.
		hair = hair.lerp(GREY_HAIR, _grey_step(age) / 4.0)
	looks.merge({
		"skin": skin_name(face, narrow, beard),
		"female": female, "child": false, "elder": elder, "chief": chief,
		"hair": hair,
		"hair_style": styles[rng.randi_range(0, styles.size() - 1)],
		"build": builds[rng.randi_range(0, builds.size() - 1)],
		"height": (0.94 if female else 1.0) * rng.randf_range(0.94, 1.06) * (0.97 if elder else 1.0),
	}, true)
	return looks


## A child playing in the camp: not a citizen, just part of the scene.
static func child_appearance(seed_value: int, tunic: Color) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "child"])
	var looks := _base_looks(rng, tunic)
	var female := rng.randf() < 0.5
	var faces := FEMALE_FACES if female else MALE_FACES
	looks.merge({
		"skin": skin_name(faces[rng.randi_range(0, faces.size() - 1)], looks["narrow"], false),
		"female": female, "child": true, "elder": false, "chief": false,
		"hair_style": CHILD_HAIR[rng.randi_range(0, CHILD_HAIR.size() - 1)],
		"build": "average",
		"height": rng.randf_range(0.85, 1.1),
	}, true)
	return looks


static func _base_looks(rng: RandomNumberGenerator, tunic: Color) -> Dictionary:
	var ancestry := ANCESTRIES[rng.randi_range(0, ANCESTRIES.size() - 1)]
	var skins: Array = ancestry["skin"]
	var hairs: Array = ancestry["hair"]
	return {
		"tunic": tunic,
		"skin_tone": SKIN_TONES[int(skins[rng.randi_range(0, skins.size() - 1)])],
		"hair": HAIR_COLORS[int(hairs[rng.randi_range(0, hairs.size() - 1)])],
		"narrow": rng.randf() < float(ancestry["narrow"]),
	}


## A villager standing on its origin, facing +Z. Call set_walking() to animate it.
static func make(looks: Dictionary) -> Node3D:
	var child: bool = looks["child"]
	var villager := Node3D.new()
	villager.set_meta("walk_blend", CHILD_WALK_BLEND if child else WALK_BLEND)
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE * float(looks["height"]) * (CHILD_SCALE if child else 1.0)
	villager.add_child(model)
	var skeleton := model.get_node("Root/Skeleton3D") as Skeleton3D
	var mesh := skeleton.get_node("characterMedium") as MeshInstance3D
	mesh.material_override = _material(looks["skin"])
	mesh.set_instance_shader_parameter("tunic", looks["tunic"])
	mesh.set_instance_shader_parameter("hair", looks["hair"])
	mesh.set_instance_shader_parameter("skin_tone", looks["skin_tone"])
	var head_scale := CHILD_HEAD_SCALE if child else HEAD_SCALE
	skeleton.add_child(_pose(looks, head_scale))

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", _animations())
	model.add_child(player)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = _blend_tree()
	tree.anim_player = NodePath("../AnimationPlayer")
	model.add_child(tree)
	tree.set("parameters/pace/scale", WALK_PACE * (0.85 if looks["elder"] else 1.0))

	var head := _head_holder(skeleton, head_scale)
	_add_hair(head, looks["hair_style"], looks["hair"])
	if looks["chief"]:
		_add_headdress(head)
	return villager


## Eases a villager between standing (0) and walking (1).
static func set_walking(villager: Node3D, amount: float) -> void:
	var tree := villager.get_node("Model/AnimationTree") as AnimationTree
	tree.set("parameters/walk/blend_amount", amount * float(villager.get_meta("walk_blend")))


## Starts a villager's clips at their own point, so a crowd doesn't move in lockstep.
static func offset_time(villager: Node3D, seconds: float) -> void:
	(villager.get_node("Model/AnimationTree") as AnimationTree).advance(seconds)


## Build and proportions as bone scales, the elder's stoop as bends. Widening the spine is
## undone on the chest and neck (bones in one vertical chain, so nothing shears), leaving a belly
## or a slim waist without stretching the head and arms.
static func _pose(looks: Dictionary, head_scale: float) -> VillagerPose:
	var pose := VillagerPose.new()
	var hips := Vector3.ONE
	var spine := Vector3.ONE
	var chest := Vector3.ONE
	match String(looks["build"]):
		"slim":
			hips = Vector3(0.9, 1.0, 0.9)
			spine = Vector3(0.88, 1.0, 0.86)
		"stout":
			hips = Vector3(1.12, 1.0, 1.12)
			spine = Vector3(1.2, 1.0, 1.3)
	if looks["female"] and not looks["child"]:
		hips *= Vector3(1.06, 1.0, 1.0)
		chest = Vector3(0.9, 1.0, 0.95)
	# The chest keeps a little of the spine's width, so stout people are broad, not just bellied.
	var chest_scale := chest * Vector3(lerpf(1.0, spine.x, 0.4), 1.0, lerpf(1.0, spine.z, 0.4)) / spine
	var torso := hips * spine * chest_scale
	pose.scales = {
		"Hips": hips, "Spine": spine, "Chest": chest_scale,
		"Neck": Vector3(1.0 / torso.x, 1.0, 1.0 / torso.z),
		"Head": Vector3.ONE * head_scale,
	}
	if looks["elder"]:
		pose.bends = {"Spine": 0.12, "Chest": 0.1, "Neck": -0.16}
	return pose


static func _material(skin: String) -> ShaderMaterial:
	if not _materials.has(skin):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("skin", load("res://art/characters/%s_skin.png" % skin))
		material.set_shader_parameter("mask", load("res://art/characters/%s_mask.png" % skin))
		var outline := ShaderMaterial.new()
		outline.shader = ToonMaterials.OUTLINE_SHADER
		outline.set_shader_parameter("color", ToonMaterials.INK)
		outline.set_shader_parameter("width", OUTLINE_WIDTH)
		material.next_pass = outline
		_materials[skin] = material
	return _materials[skin]


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


## A node riding on the head bone whose units are world units on an adult-sized model (they grow
## and shrink with the model's scale): the skeleton works in tiny units scaled up 100x.
static func _head_holder(skeleton: Skeleton3D, head_scale: float) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / (100.0 * 0.21 * head_scale)
	attachment.add_child(holder)
	return holder


## Hair beyond the short crop painted on the skin: long hair, a bun, a ponytail, a braid or a topknot.
static func _add_hair(head: Node3D, style: String, color: Color) -> void:
	var material := ToonMaterials.get_material(color, 0.006)
	match style:
		"long":
			head.add_child(_hair_part(_capsule(0.07, 0.25), material, Vector3(0.0, 0.05, -0.075), Vector3(1.05, 1.0, 0.45)))
		"bun":
			head.add_child(_hair_part(_sphere(0.045), material, Vector3(0.0, 0.15, -0.075)))
		"ponytail":
			head.add_child(_hair_part(_sphere(0.032), material, Vector3(0.0, 0.13, -0.085)))
			var tail := _hair_part(_capsule(0.026, 0.16), material, Vector3(0.0, 0.05, -0.105))
			tail.rotation.x = 0.25
			head.add_child(tail)
		"braid":
			for i: int in 4:
				head.add_child(_hair_part(_sphere(0.028), material, Vector3(0.0, 0.1 - i * 0.045, -0.085 - i * 0.008)))
		"topknot":
			head.add_child(_hair_part(_sphere(0.035), material, Vector3(0.0, 0.185, -0.02)))


## A leather band with three feathers.
static func _add_headdress(head: Node3D) -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 0.068
	ring.bottom_radius = 0.07
	ring.height = 0.025
	head.add_child(_hair_part(ring, ToonMaterials.get_material(Color(0.55, 0.22, 0.18), 0.008), Vector3(0.0, 0.14, 0.0)))
	for i: int in 3:
		var vane := SphereMesh.new()
		vane.radius = 0.022
		vane.height = 0.13
		var color := Color(0.95, 0.75, 0.25) if i == 1 else Color(0.90, 0.33, 0.24)
		var feather := _hair_part(vane, ToonMaterials.get_material(color, 0.006), Vector3((i - 1) * 0.03, 0.195, -0.045), Vector3(1.0, 1.0, 0.35))
		feather.rotation.z = (1 - i) * 0.35
		head.add_child(feather)


static func _hair_part(mesh: Mesh, material: Material, position: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position
	part.scale = scale
	return part


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 2
	return mesh
