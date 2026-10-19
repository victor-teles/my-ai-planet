extends SceneTree
## Every species side by side (male, female, young, and a white-coated one), toon-shaded, for
## checking the animal models and their looks from genes.
## Usage: godot --path src --resolution 1600x900 -s res://tools/animal_gallery.gd -- --out=<file.png>
##   [--what=graze|walk|run|idle] [--species=deer,wolf] [--zoom=1.0]

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")

var _out := ""
var _what := "idle"
var _frames := 0
var _ink := true
var _pan := 0.0
var _animals: Array[Node3D] = []


func _initialize() -> void:
	var species: Array[String] = []
	species.assign(Species.WILD + Species.DOMESTIC)
	var zoom := 1.0
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() < 2:
			continue
		match pair[0]:
			"out":
				_out = pair[1]
			"what":
				_what = pair[1]
			"species":
				species.assign(pair[1].split(","))
			"zoom":
				zoom = float(pair[1])
			"pan":
				_pan = float(pair[1])
			"ink":
				_ink = pair[1] != "off"
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://").path_join("../docs/screenshots/animals/gallery.png")
	var world := Node3D.new()
	root.add_child(world)
	_environment(world)
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40.0, 0.1, 40.0)
	ground.mesh = plane
	ground.position.y = -0.05
	ground.material_override = ToonMaterials.get_material(Color(0.46, 0.70, 0.38), 0.0, true)
	world.add_child(ground)
	var row := 0
	for species_id: String in species:
		var variants: Array[Dictionary] = [
			{"female": false, "age": 4, "genes": 0.5, "white": false},
			{"female": true, "age": 4, "genes": 0.5, "white": false},
			{"female": false, "age": 0, "genes": 0.5, "white": false},
			{"female": false, "age": 6, "genes": 0.95, "white": false},
			{"female": true, "age": 3, "genes": 0.1, "white": true},
		]
		for v: int in variants.size():
			var variant := variants[v]
			var genome := _genome(float(variant["genes"]), bool(variant["white"]))
			var days := int(variant["age"]) * WorldState.DAYS_PER_YEAR + 120
			var looks := AnimalArt.appearance_of(species_id, genome, row * 10 + v, bool(variant["female"]), days)
			var animal := AnimalArt.make(looks)
			animal.position = Vector3((v - 2) * 0.9, 0.0, -row * 0.9)
			animal.rotation.y = -1.1
			world.add_child(animal)
			if not _ink:
				for ink: Node in animal.find_children("*Ink", "MeshInstance3D", true, false):
					(ink as Node3D).visible = false
			AnimalArt.play(animal, _what)
			AnimalArt.advance(animal, 0.4 + v * 0.13, 1.0 if _what == "graze" else 0.0)
			_animals.append(animal)
		row += 1
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	var depth := row * 0.9
	var center := Vector3(_pan, 0.2, -depth * 0.5 + 0.45)
	var distance := (depth * 1.25 + 3.0) / zoom
	camera.look_at_from_position(center + Vector3(0.0, distance * 0.62, distance * 0.78), center)


func _genome(level: float, white: bool) -> PackedByteArray:
	var genome := PackedByteArray()
	for gene: String in Species.GENES:
		var value := roundi(level * 255.0)
		if gene == "white":
			value = 240 if white else 10
		genome.append(value)
		genome.append(value)
	return genome


func _environment(world: Node3D) -> void:
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
	world.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.80, 0.62)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0.0)
	world.add_child(sun)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	print("saved ", _out, " ", image.save_png(_out))
	return true
