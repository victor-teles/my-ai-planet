extends TestCase

## Simulation.create(42) advanced 20 years, then state.checksum().
## 0ad2a1bee87b6235e5a44af2d0b165149d48145be66530e38dcd8387e5350437 was the world before animals.
const CHECKSUM_SEED_42_YEAR_20 := "8d6b63f7047b6f7102a1c7cf0e967a813f05de6959e56de4a39a3dcd42e4de8e"


## Captured before gene tables: Genetics.founder(SimRng.new(1), 0).
func _recorded_founder() -> PackedByteArray:
	return PackedByteArray([
		29, 6, 168, 144, 52, 113, 145, 115, 81, 76, 82, 183, 123, 116, 181, 156,
		169, 93, 116, 117, 183, 126, 153, 73, 131, 145, 221, 138,
	])


func test_founder_bytes_match_the_recorded_human() -> void:
	var recorded := _recorded_founder()
	assert_eq(Genetics.founder(SimRng.new(1), 0), recorded)
	assert_eq(Genetics.founder(SimRng.new(1), 0, Genetics.human_table()), recorded)
	assert_eq(Genetics.GENES, Genetics.human_table().genes)
	assert_eq(Genetics.INFO, Genetics.human_table().info)
	assert_eq(Genetics.TRACKED, Genetics.human_table().tracked)
	assert_eq(Genetics.ANCESTRIES, Genetics.human_table().ancestries)
	assert_eq(Genetics.human_table().mutation_chance, Genetics.MUTATION_CHANCE)
	assert_eq(Genetics.human_table().big_mutation_chance, Genetics.BIG_MUTATION_CHANCE)
	var left := SimRng.new(11)
	var right := SimRng.new(11)
	var mother := Genetics.founder(left, 0)
	var father := Genetics.founder(left, 4)
	var mother_again := Genetics.founder(right, 0, Genetics.human_table())
	var father_again := Genetics.founder(right, 4, Genetics.human_table())
	assert_eq(mother, mother_again)
	assert_eq(father, father_again)
	var omitted: Dictionary = Genetics.inherit(left, mother, father)
	var explicit: Dictionary = Genetics.inherit(right, mother_again, father_again, Genetics.human_table())
	assert_eq(omitted["genome"], explicit["genome"])
	assert_eq(omitted["mutations"], explicit["mutations"])


func test_other_table_inherits_mutates_and_hides_recessive() -> void:
	var table := _animal_table(0.0, 0.0)
	var at := int((table.recessive["white"] as Dictionary)["at"])
	var mother := PackedByteArray([40, 41, 50, 51, 60, 61, 200, 220])
	var father := PackedByteArray([70, 71, 80, 81, 90, 91, 5, 15])
	assert_true(table.shows(mother, "white"))
	assert_true(not table.shows(father, "white"))
	assert_eq(Genetics.express(mother, "size", table), (40 + 41) / 510.0)
	var rng := SimRng.new(8)
	for child_n: int in 30:
		var heredity: Dictionary = Genetics.inherit(rng, mother, father, table)
		var child: PackedByteArray = heredity["genome"]
		assert_eq((heredity["mutations"] as Array).size(), 0, "no mutation when the table's chances are zero (%d)" % child_n)
		for g: int in table.genes.size():
			assert_true(child[g * 2] in [mother[g * 2], mother[g * 2 + 1]], "copy of %s from the mother" % table.genes[g])
			assert_true(child[g * 2 + 1] in [father[g * 2], father[g * 2 + 1]], "copy of %s from the father" % table.genes[g])
		assert_true(not table.shows(child, "white"), "one white copy stays hidden")
	var edge := PackedByteArray([0, 0, 0, 0, 0, 0, at, at - 1])
	assert_true(not table.shows(edge, "white"), "just under the table's threshold does not carry")
	edge[7] = at
	assert_true(table.shows(edge, "white"), "both copies at the table's threshold show")
	var mutating := _animal_table(1.0, 0.0)
	var parent := PackedByteArray()
	parent.resize(mutating.genes.size() * 2)
	parent.fill(100)
	var mutated: Dictionary = Genetics.inherit(SimRng.new(4), parent, parent, mutating)
	var born: PackedByteArray = mutated["genome"]
	assert_eq(born.size(), mutating.genes.size() * 2)
	for i: int in born.size():
		assert_ne(born[i], 100, "the table's mutation chance moves allele %d" % i)
	assert_true(mutating.genes[3] in mutated["mutations"], "a mutation names its gene")


func test_seed_42_twenty_years_keeps_the_recorded_checksum() -> void:
	var sim := Simulation.create(42)
	sim.advance(20 * WorldState.DAYS_PER_YEAR)
	assert_eq(sim.state.checksum(), CHECKSUM_SEED_42_YEAR_20)


## Four genes, with white recessive at or above 180. Not the human table.
func _animal_table(mutation: float, big_mutation: float) -> GeneTable:
	var table := GeneTable.new()
	var genes: Array[String] = ["size", "speed", "temper", "white"]
	var tracked: Array[String] = ["size", "speed", "temper"]
	table.genes = genes
	table.tracked = tracked
	table.mutation_chance = mutation
	table.big_mutation_chance = big_mutation
	table.info = {
		"size": {"name": "Size", "low": "small", "high": "large"},
		"speed": {"name": "Speed", "low": "slow", "high": "fast"},
		"temper": {"name": "Temper", "low": "calm", "high": "wild"},
		"white": {"name": "White coat", "low": "", "high": "white"},
	}
	table.recessive = {"white": {"mode": "above", "at": 180}}
	return table
