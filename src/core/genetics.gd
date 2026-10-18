class_name Genetics
extends RefCounted
## DNA. Every person carries two copies (alleles, 0-255) of each gene, one from each parent.
## Most genes are additive: what shows is the average of the two copies. Eye shape and frailty
## are recessive: they only show when both copies carry them, so they can skip a generation.
## Children get one random copy of each gene from each parent, and now and then a copy mutates.
## Nothing here chooses who lives: genes only nudge survival, work and attraction, and the
## valley's gene pool drifts and adapts on its own.

## Gene ids in genome order. A genome is a PackedByteArray of 2 bytes per gene.
const GENES: Array[String] = [
	"pigment", "hair", "eyes", "height", "build", "strength", "vitality", "longevity",
	"fertility", "intellect", "temper", "sociability", "curiosity", "frailty",
]
const INFO := {
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
## The genes shown in the evolution chart, in the order they're drawn.
const TRACKED: Array[String] = ["strength", "vitality", "longevity", "fertility", "intellect", "height", "temper", "sociability", "curiosity"]
const RECESSIVE_AT := 128 ## an eye-shape copy at or above this carries the narrow-eye allele
const FRAIL_BELOW := 24 ## a frailty copy below this carries the frailty allele
const MUTATION_CHANCE := 0.015 ## per copy, per birth: a small shift
const BIG_MUTATION_CHANCE := 0.002 ## per copy, per birth: a brand new allele
const FRAIL_FOUNDER_CHANCE := 0.06

## Ancestries the first people come from: [pigment, hair, narrow-eye share].
const ANCESTRIES: Array[Array] = [
	[30, 150, 0.0], [70, 40, 1.0], [130, 30, 0.0], [210, 15, 0.0], [130, 20, 0.5],
]


static func gene_index(gene: String) -> int:
	return GENES.find(gene)


## 0..1: how strongly an additive gene shows (the mean of both copies).
static func express(genome: PackedByteArray, gene: String) -> float:
	var g := GENES.find(gene) * 2
	return (genome[g] + genome[g + 1]) / 510.0


static func has_narrow_eyes(genome: PackedByteArray) -> bool:
	var g := gene_index("eyes") * 2
	return genome[g] >= RECESSIVE_AT and genome[g + 1] >= RECESSIVE_AT


## How many frailty alleles: 0 healthy, 1 a carrier (no effect), 2 frail.
static func frailty_copies(genome: PackedByteArray) -> int:
	var g := gene_index("frailty") * 2
	return int(genome[g] < FRAIL_BELOW) + int(genome[g + 1] < FRAIL_BELOW)


static func is_frail(genome: PackedByteArray) -> bool:
	return frailty_copies(genome) == 2


## A founder's genome, drawn from one ancestry, with everything else spread around the middle.
static func founder(rng: SimRng, ancestry: int) -> PackedByteArray:
	var origin: Array = ANCESTRIES[posmod(ancestry, ANCESTRIES.size())]
	var genome := PackedByteArray()
	genome.resize(GENES.size() * 2)
	for g: int in GENES.size():
		for copy: int in 2:
			var value := 128 + rng.randi_range(-55, 55)
			match GENES[g]:
				"pigment":
					value = int(origin[0]) + rng.randi_range(-25, 25)
				"hair":
					value = int(origin[1]) + rng.randi_range(-20, 30)
				"eyes":
					value = rng.randi_range(140, 255) if rng.chance(float(origin[2])) else rng.randi_range(0, 120)
				"frailty":
					value = rng.randi_range(0, FRAIL_BELOW - 1) if rng.chance(FRAIL_FOUNDER_CHANCE) else rng.randi_range(80, 255)
			genome[g * 2 + copy] = clampi(value, 0, 255)
	return genome


## A child's genome: one copy of every gene from each parent, chosen at random, with rare mutations.
## Returns {"genome": PackedByteArray, "mutations": Array[String]} (the genes that mutated).
static func inherit(rng: SimRng, mother: PackedByteArray, father: PackedByteArray) -> Dictionary:
	var genome := PackedByteArray()
	genome.resize(GENES.size() * 2)
	var mutations: Array[String] = []
	for g: int in GENES.size():
		var from_mother := mother[g * 2 + rng.randi_range(0, 1)]
		var from_father := father[g * 2 + rng.randi_range(0, 1)]
		for copy: int in 2:
			var value: int = from_mother if copy == 0 else from_father
			if rng.chance(BIG_MUTATION_CHANCE):
				value = rng.randi_range(0, 255)
				mutations.append(GENES[g])
			elif rng.chance(MUTATION_CHANCE):
				value = clampi(value + rng.randi_range(4, 28) * (1 if rng.chance(0.5) else -1), 0, 255)
				mutations.append(GENES[g])
			genome[g * 2 + copy] = value
	return {"genome": genome, "mutations": mutations}


## A word for how a gene shows in this person, for the inspector and the AI ("strong", "calm").
static func word(genome: PackedByteArray, gene: String) -> String:
	var value := express(genome, gene)
	var info: Dictionary = INFO[gene]
	if value >= 0.62:
		return "very " + String(info["high"]) if value >= 0.78 else String(info["high"])
	if value <= 0.38:
		return "very " + String(info["low"]) if value <= 0.22 else String(info["low"])
	return "average"


## The genes that stand out in this person, as words: ["strong", "clever", "frail"].
static func notable(genome: PackedByteArray) -> Array[String]:
	var words: Array[String] = []
	for gene: String in ["strength", "vitality", "longevity", "fertility", "intellect", "height", "temper", "sociability", "curiosity"]:
		var value := express(genome, gene)
		if value >= 0.66 or value <= 0.34:
			words.append(word(genome, gene))
	if is_frail(genome):
		words.append("frail from birth")
	return words


## Mean expression (0-100) of every tracked gene over a set of genomes, plus frailty counts.
static func pool_stats(genomes: Array[PackedByteArray]) -> Dictionary:
	var sums := {}
	for gene: String in TRACKED:
		sums[gene] = 0.0
	var frail := 0
	var carriers := 0
	for genome: PackedByteArray in genomes:
		for gene: String in TRACKED:
			sums[gene] = float(sums[gene]) + express(genome, gene)
		var copies := frailty_copies(genome)
		frail += int(copies == 2)
		carriers += int(copies == 1)
	var means := {}
	for gene: String in TRACKED:
		means[gene] = roundi(100.0 * float(sums[gene]) / maxf(genomes.size(), 1.0))
	return {"genes": means, "frail": frail, "carriers": carriers}


static func to_hex(genome: PackedByteArray) -> String:
	return genome.hex_encode()


static func from_hex(text: String) -> PackedByteArray:
	return text.hex_decode()
