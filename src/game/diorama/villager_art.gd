class_name VillagerArt
extends RefCounted
## Builds villagers: Kenney's low-poly animated character (CC0, art/characters/kenney/) wearing
## skins painted by tools/paint_villager_skins.gd, toon-shaded with an ink outline. A person's
## DNA decides their skin tone, hair color, eye shape, height and build, so children look like a
## mix of their parents; their id picks the rest (face, beard, hair style); age and sex come from
## the simulation, and children grow a little every year.
## Walking plays a retargeted walk clip, sped up or slowed so one cycle covers the distance
## the villager actually moved. Idle and run stay in the library. Sitting and chopping play
## their own clips; other work still stoops and swings by bending bones (see set_tool, set_work).

const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
const IDLE_SOURCE := preload("res://art/characters/kenney/idle.fbx")
const RUN_SOURCE := preload("res://art/characters/kenney/run.fbx")
const WALK_SOURCE := preload("res://art/characters/quaternius/ual1_standard.glb")
const CHOP_SOURCE := preload("res://art/characters/quaternius/ual2_standard.glb")
const HUMANOID := preload("res://art/characters/kenney/humanoid.tres")
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
const PACE_MIN := 0.2
const PACE_MAX := 12.0 ## the retargeted cycle is short, so a toddler at a run still needs a high rate
const PACE_DT_MAX := 0.25 ## a longer gap is a hitch or the first sample, not a real speed

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
## Fashion (see wear()): the share of the tribe's own color in each class's clothes, so neighbors
## who chose the same palette still differ, and the shader's pattern numbers.
const FASHION_TINT := {"commoner": 0.18, "noble": 0.1, "guard": 0.08, "bonded": 0.0}
const PATTERNS := {"plain": 0.0, "stripes": 1.0, "hem": 2.0, "checks": 3.0, "sash": 4.0}
const GOLD := Color(0.98, 0.8, 0.36)

static var _materials: Dictionary = {} ## skin name -> ShaderMaterial
static var _library: AnimationLibrary
static var _tree: AnimationNodeBlendTree
static var _walk_stride := 0.0 ## one walk cycle, in skeleton units, along the facing axis
static var _walk_length := 1.0
static var _accessory_meshes: Dictionary = {} ## accessory part -> its mesh, shared by every figure


static func skin_name(face: String, narrow_eyes: bool, beard: bool) -> String:
	return "villager_%s%s%s" % [face, "_narrow" if narrow_eyes else "", "_beard" if beard else ""]


## What changes a person's figure over their life: growing up (yearly), becoming chief, and greying in steps.
static func looks_key(age: int, chief: bool) -> String:
	return "%s|%d|%d" % [chief, _grey_step(age), mini(age, 16)]


## How big a body is at an age, against an adult: babies are small and children grow each year.
static func growth(age: int) -> float:
	if age < 3:
		return 0.32 + 0.05 * age
	if age < 12:
		return 0.46 + (age - 3) * 0.033
	if age < 16:
		return 0.78 + (age - 12) * 0.05
	return 1.0


## How a person looks: DNA for skin, hair, eyes, height and build; their id for the face, beard and
## hair style; sex, age and rank from the simulation.
static func appearance_of(genome: PackedByteArray, id: int, female: bool, age: int, chief: bool, tunic: Color) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([id, "looks"])
	var elder := age >= ELDER_AGE
	var child := age < 16
	var narrow := Genetics.has_narrow_eyes(genome)
	var faces := FEMALE_FACES if female else MALE_FACES
	var face: String = faces[rng.randi_range(0, faces.size() - 1)]
	var beard := not female and not child and rng.randf() < (0.6 if elder else 0.35)
	var hair := _blend(HAIR_COLORS, Genetics.express(genome, "hair"))
	if elder:
		hair = hair.lerp(GREY_HAIR, _grey_step(age) / 4.0)
	var styles := CHILD_HAIR if age < 12 else (FEMALE_HAIR if female else MALE_HAIR)
	var build_gene := Genetics.express(genome, "build")
	var build := "slim" if build_gene < 0.42 else ("stout" if build_gene > 0.58 else "average")
	return {
		"tunic": tunic,
		"skin_tone": _blend(SKIN_TONES, Genetics.express(genome, "pigment")),
		"hair": hair,
		"narrow": narrow,
		"skin": skin_name(face, narrow, beard),
		"female": female, "child": child, "elder": elder, "chief": chief,
		"hair_style": styles[rng.randi_range(0, styles.size() - 1)],
		"build": build if age >= 12 else "average",
		"height": (0.94 if female else 1.0) * lerpf(0.9, 1.1, Genetics.express(genome, "height")) * (0.97 if elder else 1.0),
		"growth": growth(age),
	}


## A color along a palette, 0 (first) to 1 (last), blending between neighbors.
static func _blend(palette: Array[Color], amount: float) -> Color:
	var at := clampf(amount, 0.0, 1.0) * (palette.size() - 1)
	var low := floori(at)
	var high := mini(low + 1, palette.size() - 1)
	# Quantized a little so neighbors share materials' instance values in steps, not a smear.
	return palette[low].lerp(palette[high], snappedf(at - low, 0.25))


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
	var grown := float(looks.get("growth", CHILD_SCALE if child else 1.0))
	var villager := Node3D.new()
	villager.set_meta("walk_blend", CHILD_WALK_BLEND if child else WALK_BLEND)
	villager.set_meta("growth", grown)
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE * float(looks["height"]) * grown
	villager.add_child(model)
	var skeleton := model.get_node("Root/Skeleton3D") as Skeleton3D
	var mesh := skeleton.get_node("characterMedium") as MeshInstance3D
	mesh.material_override = _material(looks["skin"])
	mesh.set_instance_shader_parameter("tunic", looks["tunic"])
	mesh.set_instance_shader_parameter("hair", looks["hair"])
	mesh.set_instance_shader_parameter("skin_tone", looks["skin_tone"])
	if looks.has("pattern"):
		mesh.set_instance_shader_parameter("trim", looks["trim"])
		mesh.set_instance_shader_parameter("pattern", PATTERNS.get(looks["pattern"], 0.0))
	var head_scale := lerpf(CHILD_HEAD_SCALE + 0.15, HEAD_SCALE, clampf(inverse_lerp(0.32, 1.0, grown), 0.0, 1.0)) if child else HEAD_SCALE
	var pose := _pose(looks, head_scale)
	skeleton.add_child(pose)
	villager.set_meta("pose", pose)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", _animations())
	model.add_child(player)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = _blend_tree()
	tree.anim_player = NodePath("../AnimationPlayer")
	model.add_child(tree)
	tree.set("parameters/pace/scale", 1.0)

	var head := _head_holder(skeleton, head_scale)
	villager.set_meta("head", head)
	_add_hair(head, looks["hair_style"], looks["hair"])
	if looks["chief"]:
		_add_headdress(head)
	elif looks.get("noble", false):
		_add_circlet(head, 0.016)
	if looks.get("noble", false):
		_add_cloak(skeleton, looks["tunic"])
	_add_accessory(head, String(looks.get("accessory", "none")), looks)
	return villager


## How rank shows: nobles wear a deeper, richer shade of the tribe's color (and a gold circlet
## and a cloak, see make), the bonded wear drab undyed cloth. status is "", "noble" or "bonded".
static func dress(looks: Dictionary, status: String) -> Dictionary:
	var tunic: Color = looks["tunic"]
	match status:
		"noble":
			looks["tunic"] = Color.from_hsv(tunic.h, minf(tunic.s * 1.25, 1.0), tunic.v * 0.62)
			looks["noble"] = true
		"bonded":
			looks["tunic"] = tunic.lerp(Color(0.62, 0.58, 0.52), 0.75)
	return looks


## Dresses a figure in its tribe's fashion (StyleKind's "fashion" spec) for its class: "commoner",
## "noble", "bonded" or "guard". Commoners wear the tribe's cloth, pattern and accessory; nobles
## their own finer color with a gold hem, the circlet and the cloak; the bonded plain drab; guards
## their uniform color with a sash in the trim. Without a fashion, dress() as before.
static func wear(looks: Dictionary, fashion: Dictionary, cls: String, tint: Color) -> Dictionary:
	if fashion.is_empty():
		return dress(looks, cls if cls in ["noble", "bonded"] else "")
	looks["tunic"] = ArtPalette.color(int(fashion.get(cls, 0))).lerp(tint, float(FASHION_TINT.get(cls, 0.0)))
	looks["trim"] = ArtPalette.color(int(fashion.get("trim", 17)))
	var pattern := String(fashion.get("pattern", "plain"))
	var accessory := String(fashion.get("accessory", "none"))
	match cls:
		"noble":
			looks["noble"] = true
			looks["trim"] = GOLD
			pattern = pattern if pattern != "plain" else "hem"
			accessory = "scarf" if accessory == "scarf" else "none"
		"bonded":
			pattern = "plain"
			accessory = "none"
		"guard":
			pattern = "sash"
			accessory = "none"
	looks["pattern"] = pattern
	looks["accessory"] = "none" if looks.get("child", false) or looks.get("chief", false) else accessory
	return looks


## Headgear for a trade, worn whenever they have the job: "helmet" (guards: a metal cap with a
## crest in the tribe's color), "cap" (officials: a dark felt cap), or "" for none.
static func set_headgear(villager: Node3D, kind: String, metal: Color, crest: Color) -> void:
	if String(villager.get_meta("headgear", "")) == kind:
		return
	villager.set_meta("headgear", kind)
	var head := villager.get_meta("head") as Node3D
	# A hat, hood or headband comes off under a helmet or cap; a scarf stays.
	var accessory := head.get_node_or_null("Accessory") as Node3D
	if accessory:
		accessory.visible = kind.is_empty() or bool(accessory.get_meta("neck", false))
	var old := head.get_node_or_null("Headgear")
	if old:
		old.queue_free()
	if kind.is_empty():
		return
	var gear := Node3D.new()
	gear.name = "Headgear"
	match kind:
		"helmet":
			var dome := SphereMesh.new()
			dome.radius = 0.082
			dome.height = 0.082
			dome.is_hemisphere = true
			dome.radial_segments = 10
			dome.rings = 3
			var material := ToonMaterials.get_material(metal, 0.006)
			gear.add_child(_hair_part(dome, material, Vector3(0.0, 0.12, -0.005), Vector3(1.0, 1.15, 1.08)))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.088
			rim.bottom_radius = 0.092
			rim.height = 0.016
			rim.radial_segments = 10
			gear.add_child(_hair_part(rim, material, Vector3(0.0, 0.12, -0.005)))
			var crest_box := BoxMesh.new()
			crest_box.size = Vector3(0.018, 0.05, 0.13)
			gear.add_child(_hair_part(crest_box, ToonMaterials.get_material(crest, 0.006), Vector3(0.0, 0.225, -0.01)))
		"cap":
			var cap := CylinderMesh.new()
			cap.top_radius = 0.07
			cap.bottom_radius = 0.084
			cap.height = 0.07
			cap.radial_segments = 10
			gear.add_child(_hair_part(cap, ToonMaterials.get_material(Color(0.22, 0.2, 0.28), 0.006), Vector3(0.0, 0.17, -0.005)))
	head.add_child(gear)


## A still figure in the idle clip's first pose with the right arm raised (radians above level), carved from
## one material, crowned and cloaked: the ruler, for statues. Adult proportions, like every villager.
## pose is one of STATUE_POSES: "raised_fist" (the arm raised by raise), "sword" (a blade held high),
## "pointing" (the way forward), "open_arms" (embracing the people), "scroll" (holding out the law)
## or "staff" (leaning on a tall staff).
static func statue(material: Material, raise: float, cloak: Color, pose: String = "raised_fist") -> Node3D:
	var figure := Node3D.new()
	var model := MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_SCALE
	figure.add_child(model)
	var skeleton := model.get_node("Root/Skeleton3D") as Skeleton3D
	(skeleton.get_node("characterMedium") as MeshInstance3D).material_override = material
	var idle := _animations().get_animation("idle")
	for track: int in idle.get_track_count():
		var bone := skeleton.find_bone(String(idle.track_get_path(track).get_concatenated_subnames()))
		if bone == -1:
			continue
		match idle.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, idle.rotation_track_interpolate(track, 0.0))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, idle.position_track_interpolate(track, 0.0))
	skeleton.set_bone_pose_scale(skeleton.find_bone("Head"), Vector3.ONE * HEAD_SCALE)
	# Arms are aimed as (out to the side, forward, up).
	match pose:
		"sword":
			_aim_arm(skeleton, "Right", Vector3(0.25, 0.3, 1.0))
			_statue_prop(skeleton, material, "sword")
		"pointing":
			_aim_arm(skeleton, "Right", Vector3(0.3, 1.0, 0.3))
		"open_arms":
			_aim_arm(skeleton, "Right", Vector3(1.0, 0.5, 0.45))
			_aim_arm(skeleton, "Left", Vector3(1.0, 0.5, 0.45))
		"scroll":
			_aim_arm(skeleton, "Right", Vector3(0.25, 0.9, -0.1))
			_statue_prop(skeleton, material, "scroll")
		"staff":
			_aim_arm(skeleton, "Right", Vector3(0.3, 0.3, -1.0))
			_statue_prop(skeleton, material, "staff")
		_:
			_aim_arm(skeleton, "Right", Vector3(cos(raise) * 0.55, 0.4, sin(raise)))
	var head := _head_holder(skeleton, HEAD_SCALE)
	_add_circlet(head, 0.04)
	_add_cloak(skeleton, cloak)
	return figure


## Straightens an arm ("Right" or "Left") and turns it to point along aim: how far out to its
## own side, forward and up. The skeleton is Z-up and faces -Y; poses are worked out along the
## bone chain, since its cache isn't fresh yet.
static func _aim_arm(skeleton: Skeleton3D, side_name: String, aim: Vector3) -> void:
	var arm := skeleton.find_bone(side_name + "Arm")
	var forearm := skeleton.find_bone(side_name + "ForeArm")
	skeleton.set_bone_pose_rotation(forearm, Quaternion.IDENTITY)
	var parent := _bone_global(skeleton, skeleton.get_bone_parent(arm))
	var local := skeleton.get_bone_pose(arm)
	var pointing := ((parent * local).basis * skeleton.get_bone_pose_position(forearm)).normalized()
	var side := signf((parent * local).origin.x)
	var wanted := Vector3(side * aim.x, -aim.y, aim.z).normalized()
	var turn := Basis(Quaternion(pointing, wanted))
	skeleton.set_bone_pose_rotation(arm, (parent.basis.inverse() * turn * parent.basis * local.basis).get_rotation_quaternion())


## Something a statue holds in its right hand, carved from its stone: "sword", "scroll" or "staff".
static func _statue_prop(skeleton: Skeleton3D, material: Material, prop: String) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "RightHand"
	skeleton.add_child(attachment)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / (100.0 * MODEL_SCALE)
	attachment.add_child(holder)
	# The props are in world-sized units, so they take an outline of their own size.
	var tint: Color = (material as ShaderMaterial).get_shader_parameter("tint") if material is ShaderMaterial else Color(0.7, 0.7, 0.75)
	var stone := ToonMaterials.get_material(tint, 0.004)
	var model: Node3D
	match prop:
		"sword":
			# The hand bone runs toward the fingertips (+Y): the blade rises out of the fist.
			model = Node3D.new()
			model.add_child(_hair_part(_box(Vector3(0.03, 0.26, 0.01)), stone, Vector3(0.0, 0.19, 0.0)))
			model.add_child(_hair_part(_box(Vector3(0.11, 0.02, 0.024)), stone, Vector3(0.0, 0.055, 0.0)))
			model.add_child(_hair_part(_sphere(0.018), stone, Vector3(0.0, -0.035, 0.0)))
		"staff":
			# Held like a guard's pike: most of it rises above the hand.
			model = Node3D.new()
			model.add_child(_hair_part(_rod(0.011, 0.86), stone, Vector3(0.0, -0.2, 0.0)))
			model.add_child(_hair_part(_sphere(0.03), stone, Vector3(0.0, -0.64, 0.0)))
		_:
			model = _tool_model(prop)
			for part: Node in model.find_children("*", "MeshInstance3D", true, false):
				(part as MeshInstance3D).material_override = stone
	holder.add_child(model)


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Eases a villager between standing (0) and the walk clip (1). The clip speeds up with the
## distance covered since the previous call, so the feet keep pace with the body.
static func set_walking(villager: Node3D, amount: float) -> void:
	var tree := villager.get_node("Model/AnimationTree") as AnimationTree
	tree.set("parameters/walk/blend_amount", amount)
	var now := Time.get_ticks_msec()
	var pos := villager.global_position if villager.is_inside_tree() else villager.position
	if amount > 0.001 and villager.has_meta("walk_sample_pos") and _walk_stride > 0.0:
		var dt := (now - int(villager.get_meta("walk_sample_at"))) / 1000.0
		if dt > 0.0 and dt <= PACE_DT_MAX:
			var previous: Vector3 = villager.get_meta("walk_sample_pos")
			var delta := pos - previous
			var speed := Vector2(delta.x, delta.z).length() / dt
			var model := villager.get_node("Model") as Node3D
			var root := model.get_node("Root") as Node3D
			var world_stride := _walk_stride * absf(root.transform.basis.get_scale().y) * model.scale.y
			if world_stride > 0.00001:
				tree.set("parameters/pace/scale", clampf(speed * _walk_length / world_stride, PACE_MIN, PACE_MAX))
	villager.set_meta("walk_sample_at", now)
	villager.set_meta("walk_sample_pos", pos)


## Puts a tool (or nothing, "") in a villager's right hand: "axe", "hammer", "hoe", "pickaxe",
## "spear", "rod", "basket", "bowl", and from the later ages "pike" (a guard's upright spear),
## "book", "scroll", "purse" and "wrench".
static func set_tool(villager: Node3D, tool: String) -> void:
	if String(villager.get_meta("tool", "")) == tool:
		return
	villager.set_meta("tool", tool)
	var holder: Node3D = villager.get_meta("hand") if villager.has_meta("hand") else null
	if holder == null:
		var skeleton := villager.get_node("Model/Root/Skeleton3D") as Skeleton3D
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "RightHand"
		skeleton.add_child(attachment)
		holder = Node3D.new()
		holder.scale = Vector3.ONE / (100.0 * MODEL_SCALE)
		attachment.add_child(holder)
		villager.set_meta("hand", holder)
	for old: Node in holder.get_children():
		old.queue_free()
	if tool:
		holder.add_child(_tool_model(tool))


## Something carried against the chest on the way back from work: "wood", "stone", "food",
## "fish", "planks", "goods" (a crate from the factory), or "" for empty hands.
static func set_carry(villager: Node3D, what: String) -> void:
	if String(villager.get_meta("carry", "")) == what:
		return
	villager.set_meta("carry", what)
	var old := villager.get_node_or_null("Carry")
	if old:
		old.queue_free()
	if what.is_empty():
		return
	var model: Node3D
	match what:
		"wood":
			model = Kit.prop("resource-wood", 0.12)
		"stone":
			model = Kit.prop("resource-stone", 0.1)
		"planks":
			model = Kit.prop("resource-planks", 0.08)
		"fish":
			model = Kit.prop("fish", 0.1)
		"goods":
			model = Kit.prop("box", 0.11)
		_:
			model = Kit.prop("pot_small", 0.12)
	var grown := float(villager.get_meta("growth", 1.0))
	model.name = "Carry"
	model.position = Vector3(0.0, 0.3 * grown, 0.11 * grown)
	villager.add_child(model)


## Working motion. stoop and swing still bend the spine and the right arm when no clip fits
## (gathering, farming, a scholar's lean). A swing above zero latches the chop clip until both
## amounts return to zero, so a woodcutter's downbeat does not snap back to idle. action "sit"
## plays the ground-sit clip. Pass "" to leave the choice to stoop and swing.
static func set_work(villager: Node3D, stoop: float, swing: float = 0.0, action: String = "") -> void:
	var pose := villager.get_meta("pose") as VillagerPose
	var tree := villager.get_node("Model/AnimationTree") as AnimationTree
	if action == "sit":
		villager.set_meta("chopping", false)
		tree.set("parameters/work_kind/blend_amount", 0.0)
		tree.set("parameters/action/blend_amount", 1.0)
		_work_bend(pose, 0.0, 0.0)
		return
	var chopping := bool(villager.get_meta("chopping", false))
	if swing > 0.001:
		chopping = true
	elif is_zero_approx(stoop) and is_zero_approx(swing):
		chopping = false
	villager.set_meta("chopping", chopping)
	if chopping:
		tree.set("parameters/work_kind/blend_amount", 1.0)
		tree.set("parameters/action/blend_amount", 1.0)
		_work_bend(pose, 0.0, 0.0)
	else:
		tree.set("parameters/action/blend_amount", 0.0)
		_work_bend(pose, stoop, swing)


static func _work_bend(pose: VillagerPose, stoop: float, swing: float) -> void:
	pose.set_extra("Spine", stoop * 0.5)
	pose.set_extra("Chest", stoop * 0.25)
	pose.set_extra("RightArm", -swing * 1.4)
	pose.set_extra("RightForeArm", -swing * 0.5)


## Lying down (sick, or falling at death): 0 standing, 1 flat on the ground.
static func set_lying(villager: Node3D, amount: float) -> void:
	var model := villager.get_node("Model") as Node3D
	model.rotation.x = -PI / 2.0 * amount
	model.position.y = 0.05 * amount * float(villager.get_meta("growth", 1.0))


static func _tool_model(tool: String) -> Node3D:
	var model: Node3D
	match tool:
		"axe":
			model = Kit.prop("tool-axe", 0.26)
		"hammer":
			model = Kit.prop("tool-hammer", 0.2)
		"hoe":
			model = Kit.prop("tool-hoe", 0.36)
		"pickaxe":
			model = Kit.prop("tool-pickaxe", 0.28)
		"pike":
			# Held upright along the arm, the point well above the head.
			model = Node3D.new()
			var pole := MeshInstance3D.new()
			pole.mesh = _rod(0.009, 0.82)
			pole.material_override = ToonMaterials.get_material(Color(0.42, 0.30, 0.22), 0.004)
			model.add_child(pole)
			var blade := MeshInstance3D.new()
			var point := CylinderMesh.new()
			point.top_radius = 0.0
			point.bottom_radius = 0.022
			point.height = 0.09
			point.radial_segments = 4
			blade.mesh = point
			blade.rotation.x = PI
			blade.position.y = -0.455
			blade.material_override = ToonMaterials.get_material(Color(0.78, 0.78, 0.84), 0.004)
			model.add_child(blade)
			model.position = Vector3(0.0, -0.22, 0.0)
			return model
		"book", "scroll":
			model = Node3D.new()
			if tool == "book":
				var cover := BoxMesh.new()
				cover.size = Vector3(0.11, 0.14, 0.03)
				model.add_child(_hair_part(cover, ToonMaterials.get_material(Color(0.55, 0.22, 0.2), 0.004), Vector3.ZERO))
				var pages := BoxMesh.new()
				pages.size = Vector3(0.1, 0.13, 0.034)
				model.add_child(_hair_part(pages, ToonMaterials.get_material(Color(0.95, 0.9, 0.78), 0.0), Vector3(0.008, 0.0, 0.0)))
			else:
				var roll := _rod(0.02, 0.17)
				model.add_child(_hair_part(roll, ToonMaterials.get_material(Color(0.93, 0.86, 0.68), 0.004), Vector3.ZERO))
				var seal := SphereMesh.new()
				seal.radius = 0.016
				seal.height = 0.032
				model.add_child(_hair_part(seal, ToonMaterials.get_material(Color(0.75, 0.15, 0.15), 0.0), Vector3(0.0, 0.0, 0.02)))
				model.rotation = Vector3(0.0, 0.0, PI / 2.0)
			model.position = Vector3(0.0, -0.06, 0.02)
			return model
		"purse":
			model = Node3D.new()
			var sack := SphereMesh.new()
			sack.radius = 0.045
			sack.height = 0.08
			sack.radial_segments = 8
			sack.rings = 4
			model.add_child(_hair_part(sack, ToonMaterials.get_material(Color(0.55, 0.36, 0.22), 0.004), Vector3.ZERO))
			var knot := SphereMesh.new()
			knot.radius = 0.012
			knot.height = 0.024
			model.add_child(_hair_part(knot, ToonMaterials.get_material(Color(0.98, 0.8, 0.36), 0.0), Vector3(0.0, -0.032, 0.0)))
			model.position = Vector3(0.0, -0.06, 0.0)
			return model
		"wrench":
			model = Node3D.new()
			var steel := ToonMaterials.get_material(Color(0.6, 0.62, 0.7), 0.004)
			var handle := BoxMesh.new()
			handle.size = Vector3(0.02, 0.26, 0.012)
			model.add_child(_hair_part(handle, steel, Vector3.ZERO))
			var jaw := BoxMesh.new()
			jaw.size = Vector3(0.02, 0.05, 0.012)
			for side: float in [-0.03, 0.03]:
				model.add_child(_hair_part(jaw, steel, Vector3(side, 0.145, 0.0)))
			var bridge := BoxMesh.new()
			bridge.size = Vector3(0.08, 0.02, 0.012)
			model.add_child(_hair_part(bridge, steel, Vector3(0.0, 0.12, 0.0)))
		"basket":
			model = Kit.prop("bucket", 0.1)
			model.position = Vector3(0.0, -0.06, 0.0)
			return model
		"bowl":
			model = Kit.prop("pot_small", 0.08)
			model.position = Vector3(0.0, -0.05, 0.0)
			return model
		"spear", "rod":
			model = Node3D.new()
			var length := 0.6 if tool == "spear" else 0.7
			var wood := ToonMaterials.get_material(Color(0.55, 0.38, 0.24), 0.004)
			var shaft := MeshInstance3D.new()
			var stick := CylinderMesh.new()
			stick.top_radius = 0.008
			stick.bottom_radius = 0.01
			stick.height = length
			stick.radial_segments = 5
			shaft.mesh = stick
			shaft.material_override = wood
			model.add_child(shaft)
			if tool == "spear":
				var tip := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.02
				cone.height = 0.07
				cone.radial_segments = 4
				tip.mesh = cone
				tip.material_override = ToonMaterials.get_material(Color(0.55, 0.52, 0.58), 0.004)
				tip.position.y = length / 2.0 + 0.03
				model.add_child(tip)
	# The bone runs down the hand; a gripped handle crosses it.
	model.rotation = Vector3(0.0, 0.0, PI / 2.0)
	return model


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
	if _library != null:
		return _library
	var library := AnimationLibrary.new()
	for source: Array in [[IDLE_SOURCE, "Root|Idle", "idle"], [RUN_SOURCE, "Root|Run", "run"]]:
		var scene := (source[0] as PackedScene).instantiate()
		var animation := (scene.get_node("AnimationPlayer") as AnimationPlayer).get_animation(source[1]).duplicate() as Animation
		animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(source[2], animation)
		scene.free()
	var kenney := MODEL.instantiate()
	var kenney_skeleton := kenney.get_node("Root/Skeleton3D") as Skeleton3D
	var bone_path := library.get_animation("idle").track_get_path(0).get_concatenated_names()
	var names := _humanoid_names()
	var walk_scene := WALK_SOURCE.instantiate()
	var walk_skeleton := walk_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var walk_player := _animation_player(walk_scene)
	var baked_walk := _retarget(walk_skeleton, kenney_skeleton, walk_player.get_animation("Walk"), names, bone_path)
	var baked_sit := _retarget(walk_skeleton, kenney_skeleton, walk_player.get_animation("Sitting_Idle"), names, bone_path)
	walk_scene.free()
	var chop_scene := CHOP_SOURCE.instantiate()
	var chop_skeleton := chop_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var chop_player := _animation_player(chop_scene)
	var baked_chop := _retarget(chop_skeleton, kenney_skeleton, chop_player.get_animation("TreeChopping"), names, bone_path)
	chop_scene.free()
	library.add_animation("walk", baked_walk)
	library.add_animation("sit", baked_sit)
	library.add_animation("chop", baked_chop)
	_walk_length = baked_walk.length
	_walk_stride = _measure_stride(kenney_skeleton, baked_walk)
	kenney.free()
	_library = library
	return library


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


static func _animation_player(scene: Node) -> AnimationPlayer:
	return scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer


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
	for profile_name: String in names:
		var src_id := source.find_bone(profile_name)
		var tgt_name := String(names[profile_name])
		var tgt_id := target.find_bone(tgt_name)
		if src_id < 0 or tgt_id < 0:
			push_error("VillagerArt retarget missing %s -> %s" % [profile_name, tgt_name])
			continue
		var src_parent := _parent_global_rest(source, src_id)
		var tgt_parent := _parent_global_rest(target, tgt_id)
		var src_rest := source.get_bone_rest(src_id)
		var tgt_rest := target.get_bone_rest(tgt_id)
		# RetargetModifier3D treats both global rests as one model space. Kenney is Z-up, so
		# rotate source model space (Y-up, facing +Z) onto the skeleton (Z-up, facing -Y) first.
		var align := _model_basis()
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
		push_error("VillagerArt retarget rest error %.2f deg on %s" % [worst, worst_bone])
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


## Peak-to-peak travel of the left foot against the hips, along the skeleton's facing axis (-Y).
static func _measure_stride(skeleton: Skeleton3D, anim: Animation) -> float:
	var hips := skeleton.find_bone("Hips")
	var foot := skeleton.find_bone("LeftFoot")
	var tracks: Dictionary = {}
	for track: int in anim.get_track_count():
		var bone := skeleton.find_bone(String(anim.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		if not tracks.has(bone):
			tracks[bone] = {}
		var slot: Dictionary = tracks[bone]
		if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			slot["rot"] = track
		elif anim.track_get_type(track) == Animation.TYPE_POSITION_3D:
			slot["pos"] = track
	var lo := Vector3(999.0, 999.0, 999.0)
	var hi := Vector3(-999.0, -999.0, -999.0)
	var steps := 32
	for step: int in steps:
		var time := anim.length * step / float(steps)
		skeleton.reset_bone_poses()
		for bone: int in tracks:
			var info: Dictionary = tracks[bone]
			if info.has("rot"):
				skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(int(info["rot"]), time))
			if info.has("pos"):
				skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(int(info["pos"]), time))
		# Global pose is stale until the skeleton is in the tree, so walk the chain from the poses just set.
		var rel := _bone_global(skeleton, foot).origin - _bone_global(skeleton, hips).origin
		lo = lo.min(rel)
		hi = hi.max(rel)
	skeleton.reset_bone_poses()
	return (hi - lo).y


static func _blend_tree() -> AnimationNodeBlendTree:
	if _tree == null:
		_tree = AnimationNodeBlendTree.new()
		var idle := AnimationNodeAnimation.new()
		idle.animation = "idle"
		var walk_clip := AnimationNodeAnimation.new()
		walk_clip.animation = "walk"
		var sit := AnimationNodeAnimation.new()
		sit.animation = "sit"
		var chop := AnimationNodeAnimation.new()
		chop.animation = "chop"
		_tree.add_node("idle", idle)
		_tree.add_node("walk_clip", walk_clip)
		_tree.add_node("sit", sit)
		_tree.add_node("chop", chop)
		_tree.add_node("pace", AnimationNodeTimeScale.new())
		_tree.add_node("walk", AnimationNodeBlend2.new())
		_tree.add_node("work_kind", AnimationNodeBlend2.new())
		_tree.add_node("action", AnimationNodeBlend2.new())
		_tree.connect_node("pace", 0, "walk_clip")
		_tree.connect_node("walk", 0, "idle")
		_tree.connect_node("walk", 1, "pace")
		_tree.connect_node("work_kind", 0, "sit")
		_tree.connect_node("work_kind", 1, "chop")
		_tree.connect_node("action", 0, "walk")
		_tree.connect_node("action", 1, "work_kind")
		_tree.connect_node("output", 0, "action")
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


## What a tribe's fashion puts on ordinary people: "headband" (in the trim), "hat" (felt, banded
## in the trim), "hood" (in the tunic's color), "scarf" (round the neck, in the trim), "feather"
## (one, in the trim, from a leather band) or "none". Meshes are shared; materials by color.
static func _add_accessory(head: Node3D, kind: String, looks: Dictionary) -> void:
	if kind == "none" or kind.is_empty():
		return
	if _accessory_meshes.is_empty():
		_accessory_meshes = {
			"band": _ring(0.075, 0.073, 0.02), "brim": _ring(0.13, 0.13, 0.012), "crown": _ring(0.068, 0.076, 0.065),
			"hood": _hood(), "scarf": _ring(0.062, 0.07, 0.045), "tail": _box(Vector3(0.04, 0.09, 0.015)), "vane": _vane(),
		}
	var trim := ToonMaterials.get_material(looks.get("trim", GOLD), 0.006)
	var gear := Node3D.new()
	gear.name = "Accessory"
	match kind:
		"headband":
			gear.add_child(_hair_part(_accessory_meshes["band"], trim, Vector3(0.0, 0.125, -0.005)))
		"hat":
			var felt := ToonMaterials.get_material((looks["tunic"] as Color).darkened(0.35), 0.006)
			gear.add_child(_hair_part(_accessory_meshes["brim"], felt, Vector3(0.0, 0.16, -0.005)))
			gear.add_child(_hair_part(_accessory_meshes["crown"], felt, Vector3(0.0, 0.198, -0.005)))
			gear.add_child(_hair_part(_accessory_meshes["band"], trim, Vector3(0.0, 0.175, -0.005), Vector3(0.95, 0.9, 0.95)))
		"hood":
			var cloth := ToonMaterials.get_material((looks["tunic"] as Color).darkened(0.1), 0.006)
			gear.add_child(_hair_part(_accessory_meshes["hood"], cloth, Vector3(0.0, 0.1, -0.018), Vector3(1.08, 1.15, 1.15)))
		"scarf":
			gear.set_meta("neck", true)
			gear.add_child(_hair_part(_accessory_meshes["scarf"], trim, Vector3(0.0, -0.005, 0.0)))
			var tail := _hair_part(_accessory_meshes["tail"], trim, Vector3(0.025, -0.05, 0.06))
			tail.rotation.x = -0.3
			gear.add_child(tail)
		"feather":
			var leather := ToonMaterials.get_material(Color(0.42, 0.27, 0.19), 0.006)
			gear.add_child(_hair_part(_accessory_meshes["band"], leather, Vector3(0.0, 0.125, -0.005)))
			var feather := _hair_part(_accessory_meshes["vane"], trim, Vector3(0.03, 0.19, -0.06), Vector3(1.0, 1.0, 0.35))
			feather.rotation.z = -0.3
			gear.add_child(feather)
	head.add_child(gear)


static func _ring(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


static func _hood() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.09
	mesh.is_hemisphere = true
	mesh.radial_segments = 10
	mesh.rings = 3
	return mesh


static func _vane() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.022
	mesh.height = 0.13
	mesh.radial_segments = 6
	mesh.rings = 3
	return mesh


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


## A bone's pose in skeleton space, multiplied up its chain.
static func _bone_global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var pose := Transform3D.IDENTITY
	while bone != -1:
		pose = skeleton.get_bone_pose(bone) * pose
		bone = skeleton.get_bone_parent(bone)
	return pose


## A gold band round the head; thick ones (a statue's crown) get points.
static func _add_circlet(head: Node3D, height: float) -> void:
	var gold := ToonMaterials.get_material(Color(0.98, 0.8, 0.36), 0.006)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.074
	ring.bottom_radius = 0.072
	ring.height = height
	ring.radial_segments = 10
	head.add_child(_hair_part(ring, gold, Vector3(0.0, 0.135, -0.005)))
	if height < 0.03:
		return
	var point := CylinderMesh.new()
	point.top_radius = 0.0
	point.bottom_radius = 0.016
	point.height = 0.04
	point.radial_segments = 4
	for i: int in 5:
		var angle := TAU * i / 5.0
		head.add_child(_hair_part(point, gold, Vector3(sin(angle) * 0.07, 0.135 + height / 2.0 + 0.018, cos(angle) * 0.07 - 0.005)))


## A cloak hanging from the shoulders down the back, in the tunic's rich color with gold at the collar.
static func _add_cloak(skeleton: Skeleton3D, color: Color) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "Chest"
	skeleton.add_child(attachment)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / (100.0 * MODEL_SCALE)
	attachment.add_child(holder)
	var cape := BoxMesh.new()
	cape.size = Vector3(0.2, 0.36, 0.02)
	var cloak := _hair_part(cape, ToonMaterials.get_material(color.darkened(0.15), 0.004), Vector3(0.0, -0.08, -0.075))
	cloak.rotation.x = 0.12
	holder.add_child(cloak)
	var collar := BoxMesh.new()
	collar.size = Vector3(0.22, 0.03, 0.03)
	holder.add_child(_hair_part(collar, ToonMaterials.get_material(Color(0.98, 0.8, 0.36), 0.004), Vector3(0.0, 0.09, -0.06)))


static func _rod(radius: float, length: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 5
	return mesh


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
