extends TestCase
## The species table: twelve animal genes, wild herds by biome, and domestic lines
## that are not part of the wild.


func test_animal_genes_and_white_coat() -> void:
	var table := Species.animal_table()
	var genes: Array[String] = [
		"size", "speed", "coat", "pattern", "horns", "fertility", "longevity", "hardiness",
		"temper", "wariness", "yield", "white",
	]
	assert_eq(table.genes, genes)
	var tracked: Array[String] = [
		"size", "speed", "coat", "horns", "fertility", "longevity", "hardiness", "temper", "wariness", "yield",
	]
	assert_eq(table.tracked, tracked)
	assert_eq(table.mutation_chance, Genetics.MUTATION_CHANCE)
	assert_eq(table.big_mutation_chance, Genetics.BIG_MUTATION_CHANCE)
	for gene: String in genes:
		var info: Dictionary = table.info[gene]
		assert_true(info.has("name") and info.has("low") and info.has("high"), gene)
	var white: Dictionary = table.recessive["white"]
	assert_eq(table.recessive.size(), 1)
	assert_eq(String(white["mode"]), "above")
	assert_eq(int(white["at"]), 220)
	var rule: Dictionary = table.founder_rules["white"]
	assert_eq(table.founder_rules.size(), 1)
	assert_eq(String(rule["kind"]), "branch")
	assert_eq(float(rule["chance"]), 0.04)
	assert_eq(int(rule["yes_low"]), 220)
	assert_eq(int(rule["yes_high"]), 255)
	assert_eq(int(rule["no_low"]), 0)
	assert_eq(int(rule["no_high"]), 40)
	assert_eq(Genetics.founder(SimRng.new(1), 0, table).size(), 24)
	var hidden := _with_white(221, 10)
	var shown := _with_white(221, 221)
	assert_true(not table.shows(hidden, "white"), "one white copy stays hidden")
	assert_true(table.shows(shown, "white"), "two copies at or above 220 show")


func test_wild_biomes_and_domestic_lines() -> void:
	var meadow: Array[String] = ["deer", "boar", "wolf"]
	var jungle: Array[String] = ["boar", "cat"]
	var none: Array[String] = []
	assert_eq(Species.wild_in("meadow"), meadow)
	assert_eq(Species.wild_in("jungle"), jungle)
	assert_eq(Species.wild_in("nope"), none)
	for biome: String in WorldGen.BIOME_ORDER:
		assert_true(not Species.wild_in(biome).is_empty(), biome)
	var domestic: Array[String] = ["sheep_flock", "goat_herd", "cattle", "pig", "draft_horse", "dog"]
	assert_eq(Species.domestic_ids(), domestic)
	assert_eq(Species.get_species("missing"), {})
	assert_eq(String(Species.get_species("dog")["from"]), "wolf")
	assert_true("wool" in Species.get_species("sheep_flock")["gives"])
	assert_true(float(Species.get_species("bear")["danger"]) > float(Species.get_species("deer")["danger"]))
	for biome: String in WorldGen.BIOME_ORDER:
		for id: String in domestic:
			assert_true(id not in Species.wild_in(biome), "%s is not wild in %s" % [id, biome])


func _with_white(left: int, right: int) -> PackedByteArray:
	var table := Species.animal_table()
	var genome := PackedByteArray()
	genome.resize(table.genes.size() * 2)
	var at := table.index_of("white") * 2
	genome[at] = left
	genome[at + 1] = right
	return genome
