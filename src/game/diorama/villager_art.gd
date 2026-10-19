class_name VillagerArt
extends RefCounted
## Builds villagers: Kenney's low-poly animated character (CC0, art/characters/kenney/) wearing
## skins painted by tools/paint_villager_skins.gd, toon-shaded with an ink outline. A person's
## DNA decides their skin tone, hair color, eye shape, height and build, so children look like a
## mix of their parents; their id picks the rest (face, beard, hair style); age and sex come from
## the simulation, and children grow a little every year.
## Motion is a set of retargeted clips (VillagerClips) in an AnimationTree that a VillagerAnimator
## plays: idle, walk, jog and run blended by the speed the figure really moves, so the feet keep
## pace with the ground, and actions (sitting, working by trade, talking, mourning, lying down...)
## that Settlement asks for by name. The API: play_action(), play_once(), set_locomotion_speed(),
## set_carry(), and work_action() / meet_action() / rest_action() to pick the clip for a trade,
## a meeting or a rest. VillagerPose still scales and bends bones on top of every clip.

const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
const SHADER := preload("res://art/shaders/villager.gdshader")
const MODEL_SCALE := 0.2 ## Kenney's character is 3.8 units tall; adults stand about two thirds of a tent
const CHILD_SCALE := 0.62
const HEAD_SCALE := 0.7 ## an adult's head, against Kenney's cartoon proportions
const CHILD_HEAD_SCALE := 0.9
const HEIGHT := 0.67 ## world units, for picking
const OUTLINE_WIDTH := 0.0005 ## in the model's own (tiny) units
const ELDER_AGE := 55
## The clip for each trade at work (see work_action). Trades not listed use DEFAULT_WORK.
const WORK_ACTIONS := {
	"woodcutter": "chop", "quarrier": "chop", "miner": "chop", "smith": "chop",
	"builder": "hammer", "toolmaker": "hammer", "potter": "kneel", "healer": "kneel",
	"forager": "gather", "farmer": "hoe", "hunter": "crouch", "fisher": "hold_up", "guard": "hold_up",
	"scholar": "interact", "factory_worker": "interact", "weaver": "sit_talk",
	"merchant": "talk", "official": "talk", "shaman": "pray",
}
const DEFAULT_WORK := "interact"
## The clip for each kind of meeting the sim reports (see meet_action).
const MEET_ACTIONS := {"chat": "talk", "love": "agree", "flirt": "talk", "quarrel": "argue", "fight": "fight"}
## The clip for a rest, by what the person is doing (see rest_action). Anything else sits.
const REST_ACTIONS := {"teaching": "sit_talk", "mourning": "mourn", "resting": "lie", "sick": "lie", "playing": "jump"}
## Extra bends (radians forward) an action adds on top of its clip, where the clip lacks them.
const ACTION_BENDS := {"mourn": {"Neck": 0.45, "Chest": 0.15}, "pray": {"Neck": 0.3}}

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


## A villager standing on its origin, facing +Z, animated by its VillagerAnimator (see animator()).
## seed_value spreads the animation updates of a crowd over frames (any number; ids work well).
static func make(looks: Dictionary, seed_value: int = 0) -> Node3D:
	var child: bool = looks["child"]
	var grown := float(looks.get("growth", CHILD_SCALE if child else 1.0))
	var villager := Node3D.new()
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
	player.add_animation_library("", VillagerClips.library())
	model.add_child(player)
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = VillagerClips.tree_root()
	tree.anim_player = NodePath("../AnimationPlayer")
	model.add_child(tree)
	var animator := VillagerAnimator.new()
	animator.name = "Animator"
	var size := float(looks["height"]) * grown
	animator.setup(tree, skeleton, size, VillagerClips.root_scale() * model.scale.y, seed_value)
	# Some fold their arms or stand easy while they wait; most stand plainly.
	animator.idle_kind = ["idle", "idle", "idle_arms", "idle_easy"][posmod(hash([seed_value, "idle"]), 4)]
	villager.add_child(animator)
	villager.set_meta("animator", animator)

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
	var idle := VillagerClips.library().get_animation("idle_easy")
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


## The villager's animator: its clips, gait and level of detail.
static func animator(villager: Node3D) -> VillagerAnimator:
	return villager.get_meta("animator") as VillagerAnimator


## How fast Settlement is moving the villager, in world units a second (0 when standing). In the
## scene the animator measures the real movement and uses that for the gait and the clip rate;
## this speed drives them when the figure is not moved (tools, stills: see VillagerAnimator.measure).
static func set_locomotion_speed(villager: Node3D, speed: float) -> void:
	animator(villager).speed = maxf(speed, 0.0)


## Starts an action (a looping state, one of VillagerClips.actions(): "sit", "chop", "talk",
## "mourn", "lie", "die"...) or "" to go back to standing and walking. While the figure is
## moving, the animator walks instead and resumes the action when it stops. Bends an action
## needs on top of its clip (a mourner's bowed head) come and go with it.
static func play_action(villager: Node3D, action: String) -> void:
	var player := animator(villager)
	if player.action == action:
		return
	if not action.is_empty() and not VillagerClips.has_action(action):
		push_error("VillagerArt: no action %s" % action)
		return
	var pose := villager.get_meta("pose") as VillagerPose
	for bone: String in ACTION_BENDS.get(player.action, {}):
		pose.set_extra(bone, 0.0)
	for bone: String in ACTION_BENDS.get(action, {}):
		pose.set_extra(bone, float(ACTION_BENDS[action][bone]))
	player.action = action


## The action playing (or asked for), "" when standing or walking.
static func current_action(villager: Node3D) -> String:
	return animator(villager).action


## A one-shot gesture of the upper body over whatever plays: "pick_up", "put_down", "nod" or "punch".
static func play_once(villager: Node3D, gesture: String) -> void:
	if not VillagerClips.has_gesture(gesture):
		push_error("VillagerArt: no gesture %s" % gesture)
		return
	animator(villager).fire(gesture)


## The action for a trade at work.
static func work_action(job: String) -> String:
	return String(WORK_ACTIONS.get(job, DEFAULT_WORK))


## The action for a meeting of a kind the sim reports ("chat", "love", "flirt", "quarrel", "fight").
static func meet_action(kind: String) -> String:
	return String(MEET_ACTIONS.get(kind, "talk"))


## The action for resting, by the person's activity: teachers talk sitting, mourners kneel with
## their heads bowed, the sick and the resting lie down, playing children jump; others sit.
static func rest_action(activity: String) -> String:
	return String(REST_ACTIONS.get(activity, "sit"))


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
	animator(villager).carrying = not what.is_empty()
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
	# A child carries a child-sized load, held where the carry pose puts the arms.
	model.scale *= grown
	model.position = Vector3(0.0, 0.3 * grown, 0.11 * grown)
	villager.add_child(model)


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
	animator(villager).update(seconds)


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
