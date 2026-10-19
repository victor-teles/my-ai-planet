extends TestCase
## The animals on screen: looks from genes, a model for every species, flocking, and a herd
## view that only reads the world.


func _genome(level: int, white_copies: int = 0) -> PackedByteArray:
	var genome := PackedByteArray()
	for gene: String in Species.GENES:
		if gene == "white":
			genome.append(240 if white_copies >= 1 else 10)
			genome.append(240 if white_copies >= 2 else 10)
		else:
			genome.append(level)
			genome.append(level)
	return genome


func test_looks_come_from_genes_and_are_the_same_every_time() -> void:
	var genome := _genome(128)
	var adult := 4 * WorldState.DAYS_PER_YEAR
	var a := AnimalArt.appearance_of("deer", genome, 7, false, adult)
	var b := AnimalArt.appearance_of("deer", genome, 7, false, adult)
	assert_eq(a, b, "same genes, same id, same age")
	var big := AnimalArt.appearance_of("deer", _genome(240), 7, false, adult)
	var small := AnimalArt.appearance_of("deer", _genome(20), 7, false, adult)
	assert_true(float(big["height"]) > float(small["height"]), "the size gene makes a bigger deer")
	assert_true(float(big["horns"]) > float(small["horns"]), "the horns gene grows the antlers")
	assert_eq(String(a["model"]), "stag", "a grown male deer is a stag")
	var doe := AnimalArt.appearance_of("deer", genome, 7, true, adult)
	assert_eq(String(doe["model"]), "deer")
	assert_eq(float(doe["horns"]), 0.0, "a doe has no antlers")
	var fawn := AnimalArt.appearance_of("deer", genome, 7, false, 30)
	assert_true(float(fawn["height"]) < float(a["height"]) * 0.7, "a fawn is small")
	assert_eq(float(fawn["horns"]), 0.0, "a fawn has no antlers yet")


func test_a_white_coat_needs_both_copies() -> void:
	var adult := 3 * WorldState.DAYS_PER_YEAR
	var none := AnimalArt.appearance_of("deer", _genome(128, 0), 1, true, adult)
	var carrier := AnimalArt.appearance_of("deer", _genome(128, 1), 1, true, adult)
	var white := AnimalArt.appearance_of("deer", _genome(128, 2), 1, true, adult)
	assert_true(not bool(none["white"]) and not bool(carrier["white"]), "one copy stays hidden")
	assert_eq(carrier["coat"], none["coat"], "a carrier looks like any other")
	assert_true(bool(white["white"]), "two copies show")
	assert_eq(white["coat"], AnimalArt.WHITE_COAT)


func test_every_species_has_a_model_with_its_clips() -> void:
	for species_id: String in Species.SPECIES:
		assert_true(AnimalArt.LOOKS.has(species_id), "%s has looks" % species_id)
		var models := AnimalArt.models_of(species_id)
		assert_true(not models.is_empty(), "%s has a model" % species_id)
		for model_id: String in models:
			assert_true(AnimalArt.MODELS.has(model_id), "%s: model %s is listed" % [species_id, model_id])
			var info: Dictionary = AnimalArt.MODELS[model_id]
			assert_true(ResourceLoader.exists(String(info["file"])), "%s exists" % info["file"])
			var root := (load(String(info["file"])) as PackedScene).instantiate()
			var players := root.find_children("*", "AnimationPlayer", true, false)
			assert_eq(players.size(), 1, "%s has its clips" % model_id)
			if players.size() == 1:
				var player := players[0] as AnimationPlayer
				var clips: Dictionary = AnimalArt.CLIPS[String(info["clips"])]
				for what: String in ["idle", "graze", "walk", "run"]:
					assert_true(player.has_animation(String(clips[what])), "%s plays %s" % [model_id, what])
			root.free()


func test_an_animal_node_is_built_and_shaded() -> void:
	var looks := AnimalArt.appearance_of("wolf", _genome(128), 3, true, 1000)
	var animal := AnimalArt.make(looks)
	var shaded := 0
	var ink := 0
	for node: Node in animal.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if String(mesh.name).ends_with("Ink"):
			ink += 1
		elif mesh.get_surface_override_material(0) is ShaderMaterial:
			shaded += 1
	assert_true(shaded >= 1, "the body takes the animal shader")
	assert_true(ink >= 1, "and an ink outline")
	animal.free()


func test_flocking_pulls_a_stray_in_and_matches_the_herd() -> void:
	var stray := Steering.mover(Vector3(3.0, 0.0, 0.0), 0.0, 0.0, 0.1, 0.4, 1.0, 3.0, 0.4, 1)
	var mates: Array = []
	for n: int in 4:
		var mate := Steering.mover(Vector3(-0.3 + n * 0.2, 0.0, 0.0), 0.0, 0.3, 0.1, 0.4, 1.0, 3.0, 0.4, 10 + n)
		mates.append(mate)
	var pull := Steering.cohesion(stray, mates, 4.0)
	assert_true(pull.x < -0.1, "a stray is pulled toward the herd")
	var close := Steering.cohesion(mates[0], mates, 5.0)
	assert_true(close.length() < 0.01, "one already among them is not")
	var along := Steering.alignment(stray, mates, 5.0)
	assert_true(along.z > 0.2, "it takes up the herd's heading")
	assert_eq(Steering.cohesion(stray, [], 5.0), Vector3.ZERO)
	var target := Vector3(3.0, 0.0, 5.0)
	assert_eq(Steering.flock_target(stray, target, [], 5.0), target, "alone, it goes straight for its target")


## The view reads the world and never writes it: a world watched by the herd view ends up
## exactly like the same world unwatched.
func test_the_herd_view_never_changes_the_world() -> void:
	var watched := Simulation.create(42)
	var alone := Simulation.create(42)
	var herds := Herds.new()
	herds.setup(IslandShape.new(watched.state.world, 42), null, 42)
	var before := watched.state.checksum()
	for frame: int in 30:
		herds.sync(watched.state, 1.0 / 30.0, {}, null)
	assert_eq(watched.state.checksum(), before, "drawing changes nothing")
	assert_eq(herds.count(), watched.state.animal_ids.size(), "one animal drawn for each in the world")
	for month: int in 14:
		watched.advance(WorldState.DAYS_PER_MONTH)
		alone.advance(WorldState.DAYS_PER_MONTH)
		for frame: int in 5:
			herds.sync(watched.state, 0.2, {}, null)
		assert_eq(herds.count(), watched.state.animal_ids.size(), "month %d" % month)
	assert_eq(watched.state.checksum(), alone.state.checksum(), "same seed, watched or not")
	for id: int in watched.state.animal_ids:
		assert_true(herds.position_of(id) == null or herds.activity_of(id) != "", "every animal is doing something")
	herds.free()
