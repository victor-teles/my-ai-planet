extends SceneTree
## Lines up every later-age building, or the villagers at the later jobs, or the two village walls,
## under the game's dusk light, renders a few frames and saves one, so the art can be checked at a
## glance. Opens a window briefly.
## Usage: Godot --path Godot --resolution 1600x900 -s res://tools/building_gallery.gd --
##   --out=/tmp/gallery.png [--show=buildings|people|walls|styles|heraldry|<building type>] [--age=4]
##   [--island=meadow] [--seed=3] [--row=0|1|2] (styles: a Theocracy, a Total State and a Free Commons,
##   or one of them)
##   [--site] (a building site instead) [--look-height=1.0] [--yaw=0.5] [--pitch=-0.45] [--distance=16] [--frames=40]

const SKY_SHADER := preload("res://art/shaders/sky_dusk.gdshader")
const BUILDINGS: Array[String] = [
	"stone_house", "rowhouse", "apartment", "great_house", "statue",
	"smithy", "school", "temple", "market", "barracks",
	"mine", "watchtower", "prison", "factory", "broadcast_tower", "surveillance_mast",
]
## job -> [tool, headgear, status]
const PEOPLE := {
	"miner": ["pickaxe", "", ""], "smith": ["hammer", "", ""], "scholar": ["book", "", ""],
	"merchant": ["purse", "", ""], "guard": ["pike", "helmet", ""], "official": ["scroll", "cap", ""],
	"factory_worker": ["wrench", "", ""], "noble": ["", "", "noble"], "bonded": ["", "", "bonded"],
}
const TINT := Color(0.85, 0.42, 0.38)

var _options := {}
var _frames := 0
var _wanted := 40


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		_options[pair[0]] = pair[1] if pair.size() > 1 else ""
	_wanted = int(_options.get("frames", 40))
	var world := Node3D.new()
	root.add_child(world)
	_environment(world)
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40.0, 0.2, 40.0)
	ground.mesh = plane
	ground.position.y = -0.1
	ground.material_override = ToonMaterials.get_material(Color(0.46, 0.70, 0.38), 0.0, true)
	world.add_child(ground)
	var show := String(_options.get("show", "buildings"))
	var age := int(_options.get("age", 4))
	var center := Vector3.ZERO
	match show:
		"buildings":
			for i: int in BUILDINGS.size():
				var model := BuildingArt.make(BUILDINGS[i], TINT, age)
				model.position = Vector3((i % 6) * 1.9 - 4.75, 0.0, (i / 6) * 2.1 - 2.1)
				world.add_child(model)
		"people":
			var jobs := PEOPLE.keys()
			for i: int in jobs.size():
				var job: String = jobs[i]
				var setup: Array = PEOPLE[job]
				var looks := VillagerArt.appearance(i * 7 + 3, i % 3 == 2, 30, false, TINT)
				VillagerArt.dress(looks, setup[2])
				var figure := VillagerArt.make(looks)
				figure.position = Vector3(i * 0.42 - jobs.size() * 0.21, 0.0, 0.0)
				world.add_child(figure)
				VillagerArt.set_tool(figure, setup[0])
				VillagerArt.set_headgear(figure, setup[1], Color(0.66, 0.66, 0.72), TINT)
				var label := Label3D.new()
				label.text = job
				label.pixel_size = 0.0025
				label.position = Vector3(0.0, 0.85, 0.0)
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				figure.add_child(label)
			center = Vector3(0.0, 0.4, 0.0)
		"styles":
			_styles(world, age)
			center = Vector3(0.0, 0.3, 0.0)
		"walls":
			for k: int in 2:
				var ring := BuildingArt.wall(["palisade", "stone_wall"][k], 2.68, TINT)
				ring.position.x = k * 6.0 - 3.0
				world.add_child(ring)
		"heraldry":
			_heraldry(world)
			center = Vector3(0.0, 0.45, 0.0)
		_:
			var site := _options.has("site")
			var model := BuildingArt.building_site(show) if site else BuildingArt.make(show, TINT, age)
			world.add_child(model)
			var size: Vector3 = BuildingArt.SIZES.get(show, Vector3(0.5, 0.5, 1.0))
			center = Vector3(0.0, float(_options.get("look-height", size.z * 0.4)), 0.0)
	var camera := Camera3D.new()
	camera.fov = 32.0
	world.add_child(camera)
	var yaw := float(_options.get("yaw", 0.5))
	var pitch := float(_options.get("pitch", -0.45))
	var distance := float(_options.get("distance", 16.0))
	camera.position = center + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at_from_position(camera.position, center)


## One row per society, each in its offline style (StyleKind): its homes and civic buildings, and
## in front of them a commoner, a noble, one of the bonded and a guard in its fashion.
func _styles(world: Node3D, age: int) -> void:
	var kind := StyleKind.new()
	var rows: Array[Dictionary] = [
		{"government": "Theocracy", "culture": {"piety": 60}, "tint": Color(0.85, 0.62, 0.38)},
		{"government": "Total State", "dystopia": 80, "dystopia_kind": "surveillance", "culture": {"martial": 30}, "tint": Color(0.62, 0.42, 0.62)},
		{"government": "Democracy", "destiny_id": "free_commons", "culture": {"openness": 50}, "tint": Color(0.38, 0.66, 0.78)},
	]
	var types: Array[String] = ["hut", "stone_house", "rowhouse", "apartment", "temple", "great_house", "school", "market"]
	var only := int(_options.get("row", -1))
	for r: int in rows.size():
		if only != -1 and r != only:
			continue
		var facts: Dictionary = rows[r].duplicate()
		facts.merge({"age_level": age, "island": String(_options.get("island", "meadow"))})
		var style: Dictionary = kind.accept(kind.offline(facts, int(_options.get("seed", 3)) + r), facts)
		print(facts["government"], " ", style)
		var tint: Color = facts["tint"]
		var z := (r - 1) * 3.4 if only == -1 else 0.0
		for i: int in types.size():
			var model := BuildingArt.make(types[i], tint, age, style)
			model.position = Vector3(i * 1.45 - 5.1, 0.0, z - 0.55)
			world.add_child(model)
		var classes: Array[String] = ["commoner", "commoner", "noble", "bonded", "guard"]
		for k: int in classes.size():
			var looks := VillagerArt.wear(VillagerArt.appearance(r * 11 + k * 5 + 1, k % 2 == 1, 30, false, tint), style["fashion"], classes[k], tint)
			var figure := VillagerArt.make(looks)
			figure.position = Vector3(k * 0.42 - 0.9, 0.0, z + 0.75)
			world.add_child(figure)
			if classes[k] == "guard":
				VillagerArt.set_tool(figure, "pike")
				VillagerArt.set_headgear(figure, "helmet", Color(0.66, 0.66, 0.72), tint)
		if only != -1:
			continue
		var label := Label3D.new()
		label.text = String(facts["government"]) + ("" if not facts.has("destiny_id") else " (Free Commons)")
		label.pixel_size = 0.006
		label.position = Vector3(-6.4, 0.5, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)


## The AI-authored look of a tribe, written offline: banners at the back, a statue in every pose
## and a temple with its holy sign in the middle, propaganda posters in front.
func _heraldry(world: Node3D) -> void:
	var heraldry := HeraldryKind.new()
	var cultures: Array[Dictionary] = [
		{"piety": 60}, {"martial": 70, "hierarchy": 40}, {"openness": 60, "hierarchy": -50},
		{"hierarchy": 70, "piety": 30}, {"openness": -60}, {"martial": -40, "piety": -30},
	]
	var governments: Array[String] = ["Theocracy", "Military Junta", "Democracy", "Kingdom", "Total State", "Merchant Council"]
	for k: int in 6:
		var facts := {"tribe": "Kolu", "government": governments[k], "culture": cultures[k], "dystopia": 60 if k == 4 else 10, "island": "meadow"}
		var banner := Settlement.make_banner(heraldry.accept(heraldry.offline(facts, k * 7919 + 5), facts))
		banner.position = Vector3(k * 0.7 - 1.75, 0.0, 0.1)
		world.add_child(banner)
	for k: int in MonumentKind.POSES.size():
		var statue := BuildingArt.make("statue", TINT, 4)
		var figure := statue.get_node("Figure")
		statue.remove_child(figure)
		figure.free()
		statue.add_child(BuildingArt.statue_figure(MonumentKind.POSES[k]))
		statue.position = Vector3(k * 0.62 - 2.2, 0.0, -1.3)
		world.add_child(statue)
	var temple := BuildingArt.make("temple", TINT, 4)
	temple.add_child(Settlement.make_temple_sign("flame"))
	temple.position = Vector3(1.9, 0.0, -1.3)
	world.add_child(temple)
	var poster := PosterKind.new()
	var laws: Array[String] = ["surveillance_net", "secret_police", "factory_discipline", "state_religion", "social_credit", "broadcast_propaganda"]
	for k: int in laws.size():
		var facts := {"tribe": "Kolu", "law": laws[k], "government": "Total State", "ruler": "Asha"}
		var board := Settlement.make_poster(poster.accept(poster.offline(facts, k * 31 + 2), facts))
		board.position = Vector3(k * 0.5 - 1.25, 0.0, 1.1)
		world.add_child(board)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == _wanted:
		var out := String(_options.get("out", "/tmp/gallery.png"))
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false


## The diorama's dusk: painted sky, violet ambient light filling the shadows, a warm low sun.
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
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.05
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.80, 0.62)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0.0)
	world.add_child(sun)
