class_name Genetics
extends RefCounted
## DNA. Every person carries two copies (alleles, 0-255) of each gene, one from each parent.
## Most genes are additive: what shows is the average of the two copies. Eye shape and frailty
## are recessive: they only show when both copies carry them, so they can skip a generation.
## Children get one random copy of each gene from each parent, and now and then a copy mutates.
## Nothing here chooses who lives: genes only nudge survival, work and attraction, and the
## valley's gene pool drifts and adapts on its own.
## founder, inherit and the read-outs take an optional GeneTable and use the human one when it is omitted.

const RECESSIVE_AT := 128 ## an eye-shape copy at or above this carries the narrow-eye allele
const FRAIL_BELOW := 24 ## a frailty copy below this carries the frailty allele
const MUTATION_CHANCE := 0.015 ## per copy, per birth: a small shift
const BIG_MUTATION_CHANCE := 0.002 ## per copy, per birth: a brand new allele
const FRAIL_FOUNDER_CHANCE := 0.06

static var _human: GeneTable = null

## Aliases of the human table, so existing callers keep reading Genetics.GENES and the rest.
static var GENES: Array[String]:
	get:
		return human_table().genes

static var INFO: Dictionary:
	get:
		return human_table().info

static var TRACKED: Array[String]:
	get:
		return human_table().tracked

static var ANCESTRIES: Array[Array]:
	get:
		return human_table().ancestries


static func human_table() -> GeneTable:
	if _human == null:
		_human = _make_human()
	return _human


static func _table(table: GeneTable) -> GeneTable:
	return table if table != null else human_table()


static func _make_human() -> GeneTable:
	var table := GeneTable.new()
	var genes: Array[String] = [
		"pigment", "hair", "eyes", "height", "build", "strength", "vitality", "longevity",
		"fertility", "intellect", "temper", "sociability", "curiosity", "frailty",
	]
	var tracked: Array[String] = ["strength", "vitality", "longevity", "fertility", "intellect", "height", "temper", "sociability", "curiosity"]
	var ancestries: Array[Array] = [
		[30, 150, 0.0], [70, 40, 1.0], [130, 30, 0.0], [210, 15, 0.0], [130, 20, 0.5],
	]
	table.genes = genes
	table.tracked = tracked
	table.ancestries = ancestries
	table.info = {
		"pigment": {"name": "Skin", "low": "fair", "high": "dark"},
		"hair": {"name": "Hair", "low": "dark", "high": "fair"},
		"eyes": {"name": "Eye shape", "low": "round", "high": "narrow"},
		"height": {"name": "Height", "low": "short", "high": "tall"},
		"build": {"name": "Build", "low": "slim", "high": "stout"},
		"strength": {"name": "Strength", "low": "weak", "high": "strong"},
		"vitality": {"name": "Vitality", "low": "sickly", "high": "hardy"},
		"longevity": {"name": "Longevity", "low": "short-lived", "high": "long-lived"},
		"fertility": {"name": "Fertility", "low": "few children", "high": "many children"},
		"intellect": {"name": "Intellect", "low": "simple", "high": "clever"},
		"temper": {"name": "Temper", "low": "calm", "high": "hot-headed"},
		"sociability": {"name": "Sociability", "low": "shy", "high": "outgoing"},
		"curiosity": {"name": "Curiosity", "low": "content", "high": "restless"},
		"frailty": {"name": "Frailty", "low": "", "high": ""},
	}
	table.mutation_chance = MUTATION_CHANCE
	table.big_mutation_chance = BIG_MUTATION_CHANCE
	table.recessive = {
		"eyes": {"mode": "above", "at": RECESSIVE_AT},
		"frailty": {"mode": "below", "at": FRAIL_BELOW},
	}
	table.founder_rules = {
		"pigment": {"kind": "ancestry", "index": 0, "low": -25, "high": 25},
		"hair": {"kind": "ancestry", "index": 1, "low": -20, "high": 30},
		"eyes": {"kind": "branch", "chance_index": 2, "yes_low": 140, "yes_high": 255, "no_low": 0, "no_high": 120},
		"frailty": {"kind": "branch", "chance": FRAIL_FOUNDER_CHANCE, "yes_low": 0, "yes_high": FRAIL_BELOW - 1, "no_low": 80, "no_high": 255},
	}
	return table


static func gene_index(gene: String) -> int:
	return GENES.find(gene)


## 0..1: how strongly an additive gene shows (the mean of both copies).
static func express(genome: PackedByteArray, gene: String, table: GeneTable = null) -> float:
	var g := _table(table).index_of(gene) * 2
	return (genome[g] + genome[g + 1]) / 510.0


static func has_narrow_eyes(genome: PackedByteArray, table: GeneTable = null) -> bool:
	return _table(table).shows(genome, "eyes")


## How many frailty alleles: 0 healthy, 1 a carrier (no effect), 2 frail.
static func frailty_copies(genome: PackedByteArray, table: GeneTable = null) -> int:
	return _table(table).allele_count(genome, "frailty")


static func is_frail(genome: PackedByteArray, table: GeneTable = null) -> bool:
	return frailty_copies(genome, table) == 2


## A founder's genome, drawn from one ancestry, with everything else spread around the middle.
static func founder(rng: SimRng, ancestry: int, table: GeneTable = null) -> PackedByteArray:
	var resolved := _table(table)
	var origin: Array = []
	if not resolved.ancestries.is_empty():
		origin = resolved.ancestries[posmod(ancestry, resolved.ancestries.size())]
	var genome := PackedByteArray()
	genome.resize(resolved.genes.size() * 2)
	for g: int in resolved.genes.size():
		var rule: Dictionary = resolved.founder_rules.get(resolved.genes[g], {})
		for copy: int in 2:
			# Mid roll first, even when a rule replaces it: recorded human seeds include that draw.
			var value := 128 + rng.randi_range(-55, 55)
			var kind := String(rule.get("kind", ""))
			if kind == "ancestry":
				value = int(origin[int(rule["index"])]) + rng.randi_range(int(rule["low"]), int(rule["high"]))
			elif kind == "branch":
				var probability := float(rule["chance"]) if rule.has("chance") else float(origin[int(rule["chance_index"])])
				var hit := rng.chance(probability)
				value = rng.randi_range(int(rule["yes_low"]), int(rule["yes_high"])) if hit else rng.randi_range(int(rule["no_low"]), int(rule["no_high"]))
			genome[g * 2 + copy] = clampi(value, 0, 255)
	return genome


## A child's genome: one copy of every gene from each parent, chosen at random, with rare mutations.
## Returns {"genome": PackedByteArray, "mutations": Array[String]} (the genes that mutated).
static func inherit(rng: SimRng, mother: PackedByteArray, father: PackedByteArray, table: GeneTable = null) -> Dictionary:
	var resolved := _table(table)
	var genome := PackedByteArray()
	genome.resize(resolved.genes.size() * 2)
	var mutations: Array[String] = []
	for g: int in resolved.genes.size():
		var from_mother := mother[g * 2 + rng.randi_range(0, 1)]
		var from_father := father[g * 2 + rng.randi_range(0, 1)]
		for copy: int in 2:
			var value: int = from_mother if copy == 0 else from_father
			if rng.chance(resolved.big_mutation_chance):
				value = rng.randi_range(0, 255)
				mutations.append(resolved.genes[g])
			elif rng.chance(resolved.mutation_chance):
				value = clampi(value + rng.randi_range(4, 28) * (1 if rng.chance(0.5) else -1), 0, 255)
				mutations.append(resolved.genes[g])
			genome[g * 2 + copy] = value
	return {"genome": genome, "mutations": mutations}


## A word for how a gene shows in this person, for the inspector and the AI ("strong", "calm").
static func word(genome: PackedByteArray, gene: String, table: GeneTable = null) -> String:
	var resolved := _table(table)
	var value := express(genome, gene, resolved)
	var info: Dictionary = resolved.info[gene]
	if value >= 0.62:
		return "very " + String(info["high"]) if value >= 0.78 else String(info["high"])
	if value <= 0.38:
		return "very " + String(info["low"]) if value <= 0.22 else String(info["low"])
	return "average"


## The genes that stand out in this person, as words: ["strong", "clever", "frail"].
static func notable(genome: PackedByteArray, table: GeneTable = null) -> Array[String]:
	var resolved := _table(table)
	var words: Array[String] = []
	for gene: String in resolved.tracked:
		var value := express(genome, gene, resolved)
		if value >= 0.66 or value <= 0.34:
			words.append(word(genome, gene, resolved))
	if resolved.index_of("frailty") >= 0 and is_frail(genome, resolved):
		words.append("frail from birth")
	return words


## Mean expression (0-100) of every tracked gene over a set of genomes, plus frailty counts.
static func pool_stats(genomes: Array[PackedByteArray], table: GeneTable = null) -> Dictionary:
	var resolved := _table(table)
	var sums := {}
	for gene: String in resolved.tracked:
		sums[gene] = 0.0
	var frail := 0
	var carriers := 0
	var tracks_frailty := resolved.index_of("frailty") >= 0
	for genome: PackedByteArray in genomes:
		for gene: String in resolved.tracked:
			sums[gene] = float(sums[gene]) + express(genome, gene, resolved)
		if tracks_frailty:
			var copies := frailty_copies(genome, resolved)
			frail += int(copies == 2)
			carriers += int(copies == 1)
	var means := {}
	for gene: String in resolved.tracked:
		means[gene] = roundi(100.0 * float(sums[gene]) / maxf(genomes.size(), 1.0))
	return {"genes": means, "frail": frail, "carriers": carriers}


static func to_hex(genome: PackedByteArray) -> String:
	return genome.hex_encode()


static func from_hex(text: String) -> PackedByteArray:
	return text.hex_decode()
