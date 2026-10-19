class_name Species
extends RefCounted
## The valley's animals and the genes they share. A table only: nothing here breeds,
## hunts or draws. Genes nudge the way they do for people, and a white coat shows only
## when both copies carry it, so it can skip a generation.

const WHITE_AT := 220 ## a coat copy at or above this carries white
const WHITE_FOUNDER_CHANCE := 0.04 ## few founders carry it; one copy stays hidden
## Genome order. Pattern and white are looks only, so the pool chart does not track them.
const GENES: Array[String] = [
	"size", "speed", "coat", "pattern", "horns", "fertility", "longevity", "hardiness",
	"temper", "wariness", "yield", "white",
]
const TRACKED: Array[String] = [
	"size", "speed", "coat", "horns", "fertility", "longevity", "hardiness", "temper", "wariness", "yield",
]
const INFO := {
	"size": {"name": "Size", "low": "small", "high": "large"},
	"speed": {"name": "Speed", "low": "slow", "high": "fast"},
	"coat": {"name": "Coat", "low": "thin", "high": "thick"},
	"pattern": {"name": "Pattern", "low": "plain", "high": "marked"},
	"horns": {"name": "Horns", "low": "small", "high": "large"},
	"fertility": {"name": "Fertility", "low": "few young", "high": "many young"},
	"longevity": {"name": "Longevity", "low": "short-lived", "high": "long-lived"},
	"hardiness": {"name": "Hardiness", "low": "frail", "high": "hardy"},
	"temper": {"name": "Temper", "low": "calm", "high": "wild"},
	"wariness": {"name": "Wariness", "low": "bold", "high": "wary"},
	"yield": {"name": "Yield", "low": "poor", "high": "rich"},
	"white": {"name": "White coat", "low": "colored", "high": "white"},
}
## Wild ids in the order wild_in returns. Domestic ids are not part of that list.
const WILD: Array[String] = ["deer", "boar", "wolf", "horse", "goat", "cat", "bear", "sheep"]
const DOMESTIC: Array[String] = ["sheep_flock", "goat_herd", "cattle", "pig", "draft_horse", "dog"]
## id -> {"name", "diet" (grazer, browser, predator, omnivore), "herd", "biomes" (empty when
##   domestic), "breed_month" (0-11), "litter", "lifespan" (years), "gives", "danger" (0-1),
##   "tameable", "domestic", "from" (wild ancestor id, or "")}
const SPECIES := {
	"deer": {"name": "Deer", "diet": "grazer", "herd": 8, "biomes": ["meadow", "taiga"], "breed_month": 3, "litter": 1, "lifespan": 12, "gives": ["meat", "hide"], "danger": 0.05, "tameable": false, "domestic": false, "from": ""},
	"boar": {"name": "Boar", "diet": "omnivore", "herd": 6, "biomes": ["meadow", "jungle"], "breed_month": 2, "litter": 4, "lifespan": 8, "gives": ["meat", "hide"], "danger": 0.4, "tameable": false, "domestic": false, "from": ""},
	"wolf": {"name": "Wolf", "diet": "predator", "herd": 5, "biomes": ["meadow", "steppe", "taiga"], "breed_month": 2, "litter": 4, "lifespan": 10, "gives": ["meat", "hide"], "danger": 0.55, "tameable": true, "domestic": false, "from": ""},
	"horse": {"name": "Wild horse", "diet": "grazer", "herd": 8, "biomes": ["steppe"], "breed_month": 4, "litter": 1, "lifespan": 18, "gives": ["meat", "hide"], "danger": 0.15, "tameable": true, "domestic": false, "from": ""},
	"goat": {"name": "Goat", "diet": "browser", "herd": 10, "biomes": ["steppe", "highland"], "breed_month": 3, "litter": 2, "lifespan": 12, "gives": ["meat", "hide", "milk"], "danger": 0.1, "tameable": true, "domestic": false, "from": ""},
	"cat": {"name": "Big cat", "diet": "predator", "herd": 2, "biomes": ["jungle"], "breed_month": 8, "litter": 2, "lifespan": 14, "gives": ["meat", "hide"], "danger": 0.6, "tameable": false, "domestic": false, "from": ""},
	"bear": {"name": "Bear", "diet": "omnivore", "herd": 1, "biomes": ["taiga"], "breed_month": 5, "litter": 2, "lifespan": 20, "gives": ["meat", "hide"], "danger": 0.7, "tameable": false, "domestic": false, "from": ""},
	"sheep": {"name": "Wild sheep", "diet": "grazer", "herd": 10, "biomes": ["highland"], "breed_month": 3, "litter": 1, "lifespan": 10, "gives": ["meat", "hide", "wool"], "danger": 0.05, "tameable": true, "domestic": false, "from": ""},
	"sheep_flock": {"name": "Sheep", "diet": "grazer", "herd": 12, "biomes": [], "breed_month": 3, "litter": 1, "lifespan": 10, "gives": ["meat", "hide", "wool"], "danger": 0.02, "tameable": true, "domestic": true, "from": "sheep"},
	"goat_herd": {"name": "Goat", "diet": "browser", "herd": 12, "biomes": [], "breed_month": 3, "litter": 2, "lifespan": 12, "gives": ["meat", "hide", "milk"], "danger": 0.05, "tameable": true, "domestic": true, "from": "goat"},
	"cattle": {"name": "Cattle", "diet": "grazer", "herd": 8, "biomes": [], "breed_month": 4, "litter": 1, "lifespan": 15, "gives": ["meat", "hide", "milk", "draft"], "danger": 0.08, "tameable": true, "domestic": true, "from": ""},
	"pig": {"name": "Pig", "diet": "omnivore", "herd": 8, "biomes": [], "breed_month": 2, "litter": 6, "lifespan": 8, "gives": ["meat", "hide"], "danger": 0.05, "tameable": true, "domestic": true, "from": "boar"},
	"draft_horse": {"name": "Horse", "diet": "grazer", "herd": 6, "biomes": [], "breed_month": 4, "litter": 1, "lifespan": 20, "gives": ["meat", "draft"], "danger": 0.05, "tameable": true, "domestic": true, "from": "horse"},
	"dog": {"name": "Dog", "diet": "predator", "herd": 2, "biomes": [], "breed_month": 2, "litter": 4, "lifespan": 12, "gives": ["hide"], "danger": 0.1, "tameable": true, "domestic": true, "from": "wolf"},
}

static var _animals: GeneTable = null


static func get_species(id: String) -> Dictionary:
	if not SPECIES.has(id):
		return {}
	return SPECIES[id]


## Wild species that live in this biome, in WILD order. An unknown biome is empty.
static func wild_in(biome: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in WILD:
		var home: Array = SPECIES[id]["biomes"]
		if biome in home:
			ids.append(id)
	return ids


static func domestic_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.append_array(DOMESTIC)
	return ids


static func animal_table() -> GeneTable:
	if _animals == null:
		_animals = _make_animals()
	return _animals


static func _make_animals() -> GeneTable:
	var table := GeneTable.new()
	table.genes.assign(GENES)
	table.tracked.assign(TRACKED)
	table.info = INFO.duplicate(true)
	table.mutation_chance = Genetics.MUTATION_CHANCE
	table.big_mutation_chance = Genetics.BIG_MUTATION_CHANCE
	table.recessive = {"white": {"mode": "above", "at": WHITE_AT}}
	# Branch, not a mid roll: carriers start at the recessive line, the rest well below it.
	table.founder_rules = {
		"white": {
			"kind": "branch",
			"chance": WHITE_FOUNDER_CHANCE,
			"yes_low": WHITE_AT,
			"yes_high": 255,
			"no_low": 0,
			"no_high": 40,
		},
	}
	return table
