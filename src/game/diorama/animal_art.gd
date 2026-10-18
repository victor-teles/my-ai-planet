class_name AnimalArt
extends RefCounted
## Wild and tame animals, from CC0 low-poly models (art/animals/, see CREDITS.txt there), restyled
## like the props: toon shading with brush strokes and an ink outline hull. An animal's genes
## decide its size, its coat (color and thickness), spots or stripes, the size of its antlers,
## horns or tusks, and the rare white coat that shows only with two copies.
## The view only reads the genome; nothing here touches the simulation.

const SHADER := preload("res://art/shaders/animal.gdshader")
const OUTLINE_WORLD := 0.007 ## ink line width in world units, for every animal
## Model -> file, its clip family (CLIPS), its head bone, and "ref", the height it usually stands
## at, which sets the width of its ink line.
const MODELS := {
	"deer": {"file": "res://art/animals/quaternius/deer.glb", "clips": "uaap", "head": "Head", "ref": 0.52},
	"stag": {"file": "res://art/animals/quaternius/stag.glb", "clips": "uaap", "head": "Head", "ref": 0.6},
	"wolf": {"file": "res://art/animals/quaternius/wolf.glb", "clips": "uaap", "head": "Head", "ref": 0.34},
	"horse": {"file": "res://art/animals/quaternius/horse.glb", "clips": "uaap", "head": "Head", "ref": 0.6},
	"cow": {"file": "res://art/animals/quaternius/cow.glb", "clips": "uaap", "head": "Head", "ref": 0.52},
	"bull": {"file": "res://art/animals/quaternius/bull.glb", "clips": "uaap", "head": "Head", "ref": 0.55},
	"fox": {"file": "res://art/animals/quaternius/fox.glb", "clips": "uaap", "head": "Head", "ref": 0.36},
	"shiba_inu": {"file": "res://art/animals/quaternius/shiba_inu.glb", "clips": "uaap", "head": "Head", "ref": 0.25},
	"boar": {"file": "res://art/animals/opengameart/boar.glb", "clips": "boar", "head": "head", "ref": 0.3, "turn": PI},
	"goat": {"file": "res://art/animals/opengameart/goat.glb", "clips": "goat", "head": "head", "ref": 0.32},
}
## What an animal does -> the clip each model family plays for it. Missing clips fall back to idle.
const CLIPS := {
	"uaap": {"idle": "Idle", "graze": "Eating", "walk": "Walk", "run": "Gallop", "death": "Death"},
	"goat": {"idle": "goat_idle", "graze": "goat_eat", "walk": "goat_walk", "run": "goat_run", "death": "goat_die"},
	"boar": {"idle": "default", "graze": "default", "walk": "walk", "run": "walk", "death": ""},
}
## Clip playback rates: a run that reuses the walk plays it faster.
const RATES := {"boar": {"run": 2.2, "walk": 1.1}}
## Material name -> role (0 keeps its color, 1 coat, 2 belly, 3 dark, 4 shaded coat). Unlisted
## names keep their color.
const ROLES := {
	"Main": 1, "Material": 1,
	"Main_Light": 2, "Material.003": 2, "Muzzle": 2,
	"Hair": 3, "Grey": 3,
	"Main_Dark": 4, "Material.010": 4,
}
## Model -> material names that are horn or hoof (they take the animal's horn color).
const HORN_PARTS := {"cow": ["Horns"], "bull": ["Horns"]}

## Per species: the model for each sex (a young male uses "young" when given), an adult's height in
## world units (to the top of the head), the coat from thin to thick, the belly and dark colors,
## the markings, what grows on the head, and how much a thick coat fills out the body.
## Substitutes: the big cat is the fox model, the bear the boar model, sheep the goat model.
const LOOKS := {
	"deer": {"female": "deer", "male": "stag", "young": "deer", "height": 0.52,
		"coats": [Color(0.74, 0.50, 0.30), Color(0.58, 0.36, 0.22), Color(0.42, 0.28, 0.20)],
		"belly": Color(0.92, 0.84, 0.70), "dark": Color(0.30, 0.20, 0.14), "pattern": 1, "marks": 0.4, "head": "antlers"},
	"boar": {"female": "boar", "male": "boar", "height": 0.27,
		"coats": [Color(0.50, 0.40, 0.32), Color(0.38, 0.29, 0.24), Color(0.26, 0.21, 0.19)],
		"belly": Color(0.56, 0.46, 0.38), "dark": Color(0.16, 0.12, 0.11), "pattern": 2, "marks": 0.25, "head": "tusks"},
	"wolf": {"female": "wolf", "male": "wolf", "height": 0.34,
		"coats": [Color(0.70, 0.66, 0.60), Color(0.52, 0.50, 0.48), Color(0.34, 0.32, 0.32)],
		"belly": Color(0.88, 0.85, 0.80), "dark": Color(0.22, 0.20, 0.20), "pattern": 0, "head": ""},
	"horse": {"female": "horse", "male": "horse", "height": 0.6,
		"coats": [Color(0.80, 0.64, 0.42), Color(0.58, 0.36, 0.22), Color(0.36, 0.24, 0.18)],
		"belly": Color(0.80, 0.70, 0.58), "dark": Color(0.18, 0.14, 0.12), "pattern": 1, "marks": 0.35, "head": ""},
	"goat": {"female": "goat", "male": "goat", "height": 0.3,
		"coats": [Color(0.90, 0.86, 0.78), Color(0.66, 0.52, 0.38), Color(0.32, 0.26, 0.24)],
		"belly": Color(0.90, 0.86, 0.80), "dark": Color(0.22, 0.18, 0.16), "pattern": 1, "head": "horns", "female_head": true},
	"cat": {"female": "fox", "male": "fox", "height": 0.36,
		"coats": [Color(0.88, 0.70, 0.40), Color(0.80, 0.56, 0.26), Color(0.62, 0.42, 0.20)],
		"belly": Color(0.95, 0.90, 0.80), "dark": Color(0.22, 0.16, 0.12), "pattern": 1, "marks": 1.0, "head": ""},
	"bear": {"female": "boar", "male": "boar", "height": 0.46, "girth": 1.15,
		"coats": [Color(0.56, 0.40, 0.26), Color(0.42, 0.28, 0.18), Color(0.26, 0.19, 0.15)],
		"belly": Color(0.50, 0.36, 0.24), "dark": Color(0.18, 0.13, 0.10), "pattern": 0, "head": ""},
	"sheep": {"female": "goat", "male": "goat", "height": 0.33, "girth": 1.08,
		"coats": [Color(0.76, 0.58, 0.40), Color(0.62, 0.44, 0.30), Color(0.46, 0.33, 0.24)],
		"belly": Color(0.92, 0.88, 0.80), "dark": Color(0.30, 0.22, 0.17), "pattern": 0, "head": "horns", "female_head": true},
	"sheep_flock": {"female": "goat", "male": "goat", "height": 0.32, "girth": 1.3,
		"coats": [Color(0.96, 0.93, 0.86), Color(0.88, 0.84, 0.76), Color(0.74, 0.70, 0.64)],
		"belly": Color(0.95, 0.92, 0.86), "dark": Color(0.30, 0.26, 0.24), "pattern": 0, "head": ""},
	"goat_herd": {"female": "goat", "male": "goat", "height": 0.32,
		"coats": [Color(0.94, 0.92, 0.86), Color(0.70, 0.56, 0.42), Color(0.30, 0.25, 0.23)],
		"belly": Color(0.92, 0.88, 0.82), "dark": Color(0.20, 0.17, 0.15), "pattern": 1, "head": "horns", "female_head": true},
	"cattle": {"female": "cow", "male": "bull", "height": 0.52,
		"coats": [Color(0.86, 0.74, 0.58), Color(0.62, 0.38, 0.22), Color(0.26, 0.22, 0.20)],
		"belly": Color(0.94, 0.90, 0.84), "dark": Color(0.20, 0.16, 0.14), "pattern": 1, "head": ""},
	"pig": {"female": "boar", "male": "boar", "height": 0.26, "girth": 1.1,
		"coats": [Color(0.96, 0.78, 0.74), Color(0.90, 0.66, 0.62), Color(0.62, 0.46, 0.42)],
		"belly": Color(0.98, 0.84, 0.80), "dark": Color(0.40, 0.30, 0.28), "pattern": 1, "head": ""},
	"draft_horse": {"female": "horse", "male": "horse", "height": 0.68, "girth": 1.1,
		"coats": [Color(0.74, 0.58, 0.40), Color(0.50, 0.32, 0.20), Color(0.24, 0.20, 0.18)],
		"belly": Color(0.86, 0.80, 0.70), "dark": Color(0.16, 0.13, 0.12), "pattern": 1, "head": ""},
	"dog": {"female": "shiba_inu", "male": "shiba_inu", "height": 0.25,
		"coats": [Color(0.90, 0.74, 0.50), Color(0.74, 0.46, 0.24), Color(0.30, 0.24, 0.22)],
		"belly": Color(0.96, 0.92, 0.84), "dark": Color(0.20, 0.16, 0.14), "pattern": 0, "head": ""},
}
const WHITE_COAT := Color(0.96, 0.95, 0.90)
const WHITE_BELLY := Color(1.0, 0.98, 0.94)
const WHITE_DARK := Color(0.82, 0.80, 0.78)
const HORN := Color(0.86, 0.80, 0.66)
const YOUNG_SCALE := 0.45 ## a newborn's size against an adult's

static var _templates: Dictionary = {} ## model -> PackedScene, restyled and stripped
static var _measures: Dictionary = {} ## model -> {"height", "length", "unit"}
static var _materials: Dictionary = {} ## "model|surface name" -> ShaderMaterial
static var _hulls: Dictionary = {} ## Mesh -> skinned outline hull


## The model ids every species can use, so tests can check they all exist.
static func models_of(species_id: String) -> Array[String]:
	var look: Dictionary = LOOKS.get(species_id, {})
	var found: Array[String] = []
	for key: String in ["female", "male", "young"]:
		if look.has(key) and String(look[key]) not in found:
			found.append(String(look[key]))
	return found


## How an animal looks: genes for size, coat, markings, horns and the white coat; its id only
## for tiny variations that no gene covers. age_days and sex come from the simulation.
static func appearance_of(species_id: String, genome: PackedByteArray, id: int, female: bool, age_days: int) -> Dictionary:
	var table := Species.animal_table()
	var look: Dictionary = LOOKS.get(species_id, LOOKS["deer"])
	var years := float(age_days) / float(WorldState.DAYS_PER_YEAR)
	var adult := years >= float(AnimalSystem.ADULT_YEARS)
	var grown := clampf(lerpf(YOUNG_SCALE, 1.0, years / 1.5), YOUNG_SCALE, 1.0)
	var size := Genetics.express(genome, "size", table)
	var coat_gene := Genetics.express(genome, "coat", table)
	var white := table.shows(genome, "white")
	var model := String(look["female"] if female else look["male"])
	if not female and not adult and look.has("young"):
		model = String(look["young"])
	var coats: Array = look["coats"]
	var coat := _blend(coats, coat_gene)
	var belly: Color = look["belly"]
	var dark: Color = look["dark"]
	# A sliver of per-animal shade so a herd of the same genes still reads as individuals.
	var shade := (float(hash([id, "coat"]) % 1000) / 1000.0 - 0.5) * 0.06
	coat = coat.lightened(shade) if shade > 0.0 else coat.darkened(-shade)
	if white:
		coat = WHITE_COAT
		belly = WHITE_BELLY
		dark = WHITE_DARK
	var head := String(look.get("head", ""))
	var horns := Genetics.express(genome, "horns", table)
	var horn_size := 0.0
	if not head.is_empty() and (not female or bool(look.get("female_head", false))):
		horn_size = lerpf(0.55, 1.3, horns) * (1.0 if not female else 0.55)
		if not adult:
			horn_size *= clampf((years - 0.4) / 0.6, 0.0, 1.0)
	# Markings stay faint on most adults and bold only at the top of the gene.
	var pattern := pow(Genetics.express(genome, "pattern", table), 1.6) * float(look.get("marks", 0.6))
	# Fawns and piglets are marked more strongly than their parents.
	if not adult and int(look["pattern"]) != 0:
		pattern = maxf(pattern, 0.65)
	return {
		"species": species_id,
		"model": model,
		"female": female,
		"adult": adult,
		"white": white,
		"height": float(look["height"]) * lerpf(0.86, 1.14, size) * grown,
		"girth": float(look.get("girth", 1.0)) * lerpf(0.97, 1.08, coat_gene),
		"coat": coat,
		"belly": belly,
		"dark": dark,
		"pattern": pattern if int(look["pattern"]) != 0 else 0.0,
		"pattern_kind": float(look["pattern"]),
		"head": head,
		"horns": horn_size,
		"grown": grown,
	}


## A color along a palette, 0 (first) to 1 (last).
static func _blend(palette: Array, amount: float) -> Color:
	var spot := clampf(amount, 0.0, 1.0) * (palette.size() - 1)
	var low := mini(floori(spot), palette.size() - 2)
	return (palette[low] as Color).lerp(palette[low + 1] as Color, spot - low)


## A new animal node. Its "Model" child faces +Z and stands on y = 0. Meta: "player" (the
## AnimationPlayer, advanced by hand), "clips" (what -> clip name), "skeleton", "height".
static func make(looks: Dictionary) -> Node3D:
	var model_id := String(looks["model"])
	var animal := Node3D.new()
	var model := _template(model_id).instantiate() as Node3D
	model.name = "Model"
	var measure: Dictionary = _measures[model_id]
	var scale := float(looks["height"]) / float(measure["height"])
	var girth := float(looks.get("girth", 1.0))
	model.scale = Vector3(scale * girth, scale, scale)
	model.position.y = -float(measure["bottom"]) * scale
	model.rotation.y = float(MODELS[model_id].get("turn", 0.0))
	animal.add_child(model)
	var body := model.get_node(String(measure["body"])) as MeshInstance3D
	body.set_instance_shader_parameter("coat", looks["coat"])
	body.set_instance_shader_parameter("belly", looks["belly"])
	body.set_instance_shader_parameter("dark", looks["dark"])
	body.set_instance_shader_parameter("pattern", looks["pattern"])
	body.set_instance_shader_parameter("pattern_kind", looks["pattern_kind"])
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var info: Dictionary = MODELS[model_id]
	animal.set_meta("player", player)
	animal.set_meta("skeleton", skeleton)
	animal.set_meta("family", info["clips"])
	animal.set_meta("height", float(looks["height"]))
	animal.set_meta("head_bone", skeleton.find_bone(String(info["head"])))
	_dress_head(model, looks)
	return animal


## Plays what the animal is doing ("idle", "graze", "walk", "run", "death") at a rate. Blends
## from the clip before. Does nothing if that clip is already playing.
static func play(animal: Node3D, what: String, rate: float = 1.0) -> void:
	var player := animal.get_meta("player") as AnimationPlayer
	var family := String(animal.get_meta("family"))
	var clips: Dictionary = CLIPS[family]
	var clip := String(clips.get(what, clips["idle"]))
	if clip.is_empty():
		clip = String(clips["idle"])
	var rates: Dictionary = RATES.get(family, {})
	player.speed_scale = rate * float(rates.get(what, 1.0))
	if player.current_animation == clip:
		return
	var anim := player.get_animation(clip)
	if anim and what != "death":
		anim.loop_mode = Animation.LOOP_LINEAR
	player.play(clip, 0.25)


## Moves the animation on by delta. With head_down > 0, models with no eating clip bow the head.
static func advance(animal: Node3D, delta: float, head_down: float = 0.0) -> void:
	var player := animal.get_meta("player") as AnimationPlayer
	player.advance(delta)
	if head_down > 0.0 and String(animal.get_meta("family")) == "boar":
		var skeleton := animal.get_meta("skeleton") as Skeleton3D
		var bone := int(animal.get_meta("head_bone"))
		if bone >= 0:
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion(Vector3.RIGHT, 0.55 * head_down))


## Whether a model family has its own clip for a thing (the boar has no death or eating clip).
static func has_clip(animal: Node3D, what: String) -> bool:
	var clips: Dictionary = CLIPS[String(animal.get_meta("family"))]
	return not String(clips.get(what, "")).is_empty() and String(clips.get(what, "")) != String(clips["idle"])


# --- Building the models ------------------------------------------------------------

static func _template(model_id: String) -> PackedScene:
	if _templates.has(model_id):
		return _templates[model_id]
	var info: Dictionary = MODELS[model_id]
	var root := (load(String(info["file"])) as PackedScene).instantiate() as Node3D
	_strip(root, root)
	var measure := _measure(root)
	_measures[model_id] = measure
	# World size of one mesh unit once the model stands at its usual height.
	var unit := float(measure["unit"]) * float(info["ref"]) / float(measure["height"])
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		_restyle(model_id, instance, measure)
		var hull := MeshInstance3D.new()
		hull.name = instance.name + "Ink"
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if instance.skin:
			hull.mesh = _hull(instance.mesh)
			hull.skin = instance.skin
			instance.get_parent().add_child(hull)
			hull.skeleton = hull.get_path_to(instance.get_node(instance.skeleton))
		else:
			hull.mesh = _hull(instance.mesh)
			instance.add_child(hull)
		# Antlers and horns are thin: a full-width line would swallow them.
		var thin := 1.0 if instance.skin else 0.6
		hull.material_override = ToonMaterials.outline(OUTLINE_WORLD / unit * thin)
		hull.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	_templates[model_id] = packed
	return packed


## Drops the glTF's helper nodes: bone attachments with nothing on them and bone-end markers.
static func _strip(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		_strip(child, root)
	if node == root:
		return
	if node is BoneAttachment3D and node.find_children("*", "MeshInstance3D", true, false).is_empty():
		node.get_parent().remove_child(node)
		node.free()
	elif node.get_class() == "Node3D" and String(node.name).ends_with("_end") and node.get_child_count() == 0:
		node.get_parent().remove_child(node)
		node.free()


## Height, length and bottom of the model at rest in the scene's own space, the skinned body's
## path, and the world size of one mesh unit once the model is scaled to its species' height.
static func _measure(root: Node3D) -> Dictionary:
	var box := AABB()
	var first := true
	var body := ""
	var body_size := -1.0
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var b := _to_root(instance, root) * instance.get_aabb()
		box = b if first else box.merge(b)
		first = false
		if instance.skin and b.size.length() > body_size:
			body_size = b.size.length()
			body = String(root.get_path_to(instance))
	var body_node := root.get_node(body) as MeshInstance3D
	var mesh_height := body_node.get_aabb().size.length()
	var scene_height := (_to_root(body_node, root) * body_node.get_aabb()).size.length()
	var unit := scene_height / maxf(mesh_height, 0.000001) # scene units per mesh unit
	return {"height": box.size.y, "length": box.size.z, "bottom": box.position.y, "body": body, "unit": unit}


## Product of the node's ancestors' transforms up to root (global_transform needs a tree).
static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var at: Node = node
	while at != root and at is Node3D:
		transform = (at as Node3D).transform * transform
		at = at.get_parent()
	return transform


static func _restyle(model_id: String, instance: MeshInstance3D, measure: Dictionary) -> void:
	var mesh := instance.mesh
	var horn_parts: Array = HORN_PARTS.get(model_id, [])
	var antlers := String(instance.name).contains("Horns")
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface) as BaseMaterial3D
		var surface_name := source.resource_name if source else ""
		var key := "%s|%s|%d" % [model_id, surface_name, int(antlers)]
		if not _materials.has(key):
			var material := ShaderMaterial.new()
			material.shader = SHADER
			material.set_shader_parameter("brush_strokes", ToonMaterials.BRUSH_STROKES)
			var role := int(ROLES.get(surface_name, 0))
			var tint := source.albedo_color if source else Color.WHITE
			# glTF colors are linear; the toon palette is written in sRGB.
			tint = tint.linear_to_srgb()
			if antlers or surface_name in horn_parts:
				role = 0
				tint = HORN
			material.set_shader_parameter("role", role)
			material.set_shader_parameter("tint", tint)
			var length := maxf(instance.get_aabb().size.z, maxf(instance.get_aabb().size.y, instance.get_aabb().size.x))
			material.set_shader_parameter("pattern_scale", 9.0 / maxf(length, 0.000001))
			_materials[key] = material
		instance.set_surface_override_material(surface, _materials[key])


## The same triangles with every corner's normal averaged over the faces that meet there, so the
## ink hull pushes out evenly instead of splitting along the model's hard edges. A skinned mesh
## keeps its bones and weights, so the hull bends with the body.
static func _hull(mesh: Mesh) -> ArrayMesh:
	if _hulls.has(mesh):
		return _hulls[mesh]
	var smooth := ArrayMesh.new()
	var snap := mesh.get_aabb().size.length() * 0.0001
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var sums := {}
		for v: int in vertices.size():
			var key := vertices[v].snappedf(snap)
			sums[key] = sums.get(key, Vector3.ZERO) + normals[v]
		var averaged := PackedVector3Array()
		averaged.resize(vertices.size())
		for v: int in vertices.size():
			averaged[v] = (sums[vertices[v].snappedf(snap)] as Vector3).normalized()
		var hull_arrays := []
		hull_arrays.resize(Mesh.ARRAY_MAX)
		hull_arrays[Mesh.ARRAY_VERTEX] = vertices
		hull_arrays[Mesh.ARRAY_NORMAL] = averaged
		hull_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		var flags := 0
		if arrays[Mesh.ARRAY_BONES] != null:
			hull_arrays[Mesh.ARRAY_BONES] = arrays[Mesh.ARRAY_BONES]
			hull_arrays[Mesh.ARRAY_WEIGHTS] = arrays[Mesh.ARRAY_WEIGHTS]
			flags = mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		smooth.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hull_arrays, [], {}, flags)
	_hulls[mesh] = smooth
	return smooth


## Antlers, horns and tusks are the models' own (a mesh named *Horns* pinned to the head bone):
## they grow with the horns gene and are hidden on animals that have none (does, young males,
## and the species that borrow a horned model).
static func _dress_head(model: Node3D, looks: Dictionary) -> void:
	var size := float(looks["horns"])
	for node: Node in model.find_children("*Horns", "MeshInstance3D", true, false):
		var horns := node as Node3D
		var holder := horns.get_parent() as Node3D
		holder.visible = size > 0.05
		horns.scale = Vector3.ONE * maxf(size, 0.05)
