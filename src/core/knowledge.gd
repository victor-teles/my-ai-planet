class_name Knowledge
extends RefCounted
## What a tribe knows how to do. Every tribe starts with the basics; everything else is
## discovered by someone (clever, curious people working at the right job find things first)
## and then spreads to friendly neighbors. Each discovery opens new jobs, buildings and laws.
##
## Knowledge climbs through five ages. A tribe enters an age when it learns the age's gate tech
## (bronze, iron, steam power, electricity). Some techs need an ore: an island without it makes
## them far harder to find, so every island's history runs at its own pace.

## age -> {"name", "gate" (the tech that opens it)}
const AGES: Array[Dictionary] = [
	{"id": "stone", "name": "First Fires", "gate": ""},
	{"id": "bronze", "name": "Age of Bronze", "gate": "bronze"},
	{"id": "iron", "name": "Age of Iron", "gate": "iron_working"},
	{"id": "steam", "name": "Smoke & Steam", "gate": "steam_power"},
	{"id": "wired", "name": "Wired Age", "gate": "electricity"},
]
const STARTING: Array[String] = ["fire", "foraging", "hunting", "shelter"]
## tech -> {"name", "age", "requires", "found_by" (jobs most likely to find it), "difficulty",
##   "ore" (optional: the island's ore it needs), "unlocks", "bonus" (optional: effect -> multiplier,
##   see bonus())}
const TECHS := {
	"fire": {"name": "Fire", "age": 0, "requires": [], "found_by": [], "difficulty": 1.0, "unlocks": "the campfire"},
	"foraging": {"name": "Foraging", "age": 0, "requires": [], "found_by": [], "difficulty": 1.0, "unlocks": "foragers"},
	"hunting": {"name": "Hunting", "age": 0, "requires": [], "found_by": [], "difficulty": 1.0, "unlocks": "hunters"},
	"shelter": {"name": "Shelter", "age": 0, "requires": [], "found_by": [], "difficulty": 1.0, "unlocks": "tents and builders"},
	"stone_tools": {"name": "Stone tools", "age": 0, "requires": [], "found_by": ["hunter", "woodcutter", "builder"], "difficulty": 1.0,
		"unlocks": "toolmakers, quarriers and the workshop"},
	"fishing": {"name": "Fishing", "age": 0, "requires": [], "found_by": ["forager", "hunter"], "difficulty": 1.0,
		"unlocks": "fishers"},
	"herbal_lore": {"name": "Herbal lore", "age": 0, "requires": [], "found_by": ["forager"], "difficulty": 1.2,
		"unlocks": "healers and the healer's hut"},
	"rites": {"name": "Rites", "age": 0, "requires": [], "found_by": [], "difficulty": 1.3,
		"unlocks": "shamans and the shrine"},
	"pottery": {"name": "Pottery", "age": 0, "requires": ["fire"], "found_by": ["forager", "toolmaker"], "difficulty": 1.4,
		"unlocks": "potters and the storehouse"},
	"weaving": {"name": "Weaving", "age": 0, "requires": [], "found_by": ["forager", "hunter"], "difficulty": 1.4,
		"unlocks": "weavers and warm clothes"},
	"carpentry": {"name": "Carpentry", "age": 0, "requires": ["stone_tools"], "found_by": ["woodcutter", "builder", "toolmaker"], "difficulty": 1.6,
		"unlocks": "huts, longhouses and the palisade"},
	"agriculture": {"name": "Farming", "age": 0, "requires": ["herbal_lore", "pottery"], "found_by": ["forager", "healer", "potter"], "difficulty": 2.0,
		"unlocks": "farmers and fields"},
	# Age of Bronze
	"copper_working": {"name": "Copper working", "age": 1, "requires": ["pottery", "stone_tools"], "found_by": ["quarrier", "toolmaker", "potter"],
		"difficulty": 2.2, "ore": "copper", "unlocks": "miners, the mine and the smithy"},
	"bronze": {"name": "Bronze", "age": 1, "requires": ["copper_working"], "found_by": ["smith", "miner"], "difficulty": 2.6, "ore": "tin",
		"unlocks": "smiths, guards and the Age of Bronze", "bonus": {"war": 1.2}},
	"writing": {"name": "Writing", "age": 1, "requires": ["rites", "pottery"], "found_by": ["shaman", "potter"], "difficulty": 2.4,
		"unlocks": "scholars, the school and written law", "bonus": {"discovery": 1.25}},
	"masonry": {"name": "Masonry", "age": 1, "requires": ["stone_tools", "carpentry"], "found_by": ["quarrier", "builder"], "difficulty": 2.0,
		"unlocks": "stone houses, the temple, stone walls and great houses"},
	"the_wheel": {"name": "The wheel", "age": 1, "requires": ["carpentry"], "found_by": ["builder", "toolmaker", "woodcutter"], "difficulty": 2.0,
		"unlocks": "carts: more wood and stone hauled", "bonus": {"haul": 1.2}},
	"irrigation": {"name": "Irrigation", "age": 1, "requires": ["agriculture"], "found_by": ["farmer"], "difficulty": 2.2,
		"unlocks": "watered fields", "bonus": {"farm": 1.25}},
	# Age of Iron
	"iron_working": {"name": "Iron working", "age": 2, "requires": ["bronze"], "found_by": ["smith", "miner"], "difficulty": 3.5, "ore": "iron",
		"unlocks": "iron tools and weapons, and the Age of Iron", "bonus": {"war": 1.25}},
	"mathematics": {"name": "Mathematics", "age": 2, "requires": ["writing"], "found_by": ["scholar", "merchant"], "difficulty": 3.0,
		"unlocks": "surveys and sums", "bonus": {"discovery": 1.1}},
	"coinage": {"name": "Coinage", "age": 2, "requires": ["bronze", "writing"], "found_by": ["merchant", "smith", "scholar"], "difficulty": 2.8,
		"unlocks": "merchants, the market and taxes"},
	"philosophy": {"name": "Philosophy", "age": 2, "requires": ["writing", "mathematics"], "found_by": ["scholar", "shaman"], "difficulty": 3.2,
		"unlocks": "the assembly, and doubt", "bonus": {"discovery": 1.1}},
	"medicine": {"name": "Medicine", "age": 2, "requires": ["herbal_lore", "writing"], "found_by": ["healer", "scholar"], "difficulty": 3.0,
		"unlocks": "trained healers", "bonus": {"care": 1.4}},
	# Smoke & Steam
	"printing": {"name": "Printing", "age": 3, "requires": ["writing", "iron_working"], "found_by": ["scholar", "smith"], "difficulty": 3.6,
		"unlocks": "books, pamphlets and censors", "bonus": {"discovery": 1.3}},
	"gunpowder": {"name": "Gunpowder", "age": 3, "requires": ["iron_working", "mathematics"], "found_by": ["smith", "guard", "scholar"], "difficulty": 3.5,
		"unlocks": "guns: armies and police grow strong", "bonus": {"war": 1.4}},
	"steam_power": {"name": "Steam power", "age": 3, "requires": ["iron_working", "mathematics"], "found_by": ["smith", "scholar", "miner"], "difficulty": 4.0, "ore": "coal",
		"unlocks": "factories, row houses and the Age of Smoke & Steam", "bonus": {"farm": 1.2, "haul": 1.3}},
	"telegraph": {"name": "Telegraph", "age": 3, "requires": ["steam_power", "mathematics"], "found_by": ["scholar", "factory_worker"], "difficulty": 4.2,
		"unlocks": "messages faster than horses, and secret police"},
	"vaccines": {"name": "Vaccines", "age": 3, "requires": ["medicine", "printing"], "found_by": ["healer", "scholar"], "difficulty": 4.0,
		"unlocks": "fevers tamed", "bonus": {"sickness": 0.5, "care": 1.3}},
	# Wired Age
	"electricity": {"name": "Electricity", "age": 4, "requires": ["steam_power", "telegraph"], "found_by": ["scholar", "factory_worker"], "difficulty": 5.3,
		"unlocks": "light, apartment blocks and the Wired Age", "bonus": {"farm": 1.15}},
	"radio": {"name": "Radio", "age": 4, "requires": ["electricity"], "found_by": ["scholar", "factory_worker"], "difficulty": 4.6,
		"unlocks": "broadcast towers: one voice in every home"},
	"computing": {"name": "Computing", "age": 4, "requires": ["electricity", "mathematics"], "found_by": ["scholar", "official"], "difficulty": 5.2,
		"unlocks": "machines that count people", "bonus": {"discovery": 1.2}},
	"genetics": {"name": "Genetics", "age": 4, "requires": ["vaccines", "computing"], "found_by": ["healer", "scholar"], "difficulty": 5.2,
		"unlocks": "reading the blood: birth permits", "bonus": {"sickness": 0.8}},
	"networks": {"name": "Networks", "age": 4, "requires": ["computing", "radio"], "found_by": ["scholar", "official", "merchant"], "difficulty": 5.5,
		"unlocks": "everyone connected, and everyone watched", "bonus": {"discovery": 1.3}},
}
const ORDER: Array[String] = [
	"fire", "foraging", "hunting", "shelter", "stone_tools", "fishing", "herbal_lore", "rites",
	"pottery", "weaving", "carpentry", "agriculture",
	"copper_working", "bronze", "writing", "masonry", "the_wheel", "irrigation",
	"iron_working", "mathematics", "coinage", "philosophy", "medicine",
	"printing", "gunpowder", "steam_power", "telegraph", "vaccines",
	"electricity", "radio", "computing", "genetics", "networks",
]
## Every effect a tech's "bonus" can change.
const BONUSES: Array[String] = ["discovery", "farm", "haul", "war", "care", "sickness"]
## The chance a bright idea about a tech still works out on an island that lacks its ore: the people
## must make do with scraps washed ashore or traded from the wrecks of passing boats.
const NO_ORE := 0.2


static func name_of(tech: String) -> String:
	return String(TECHS[tech]["name"]) if TECHS.has(tech) else tech


## Techs this tribe could discover next: not known yet, with everything they need known.
static func discoverable(known: PackedStringArray) -> Array[String]:
	var open: Array[String] = []
	for tech: String in ORDER:
		if tech in known:
			continue
		var ready := true
		for need: String in TECHS[tech]["requires"]:
			if need not in known:
				ready = false
		if ready:
			open.append(tech)
	return open


## The highest age whose gate the tribe has passed: 0 (First Fires) to 4 (Wired Age).
static func age_of(known: PackedStringArray) -> int:
	var reached := 0
	for a: int in AGES.size():
		var gate := String(AGES[a]["gate"])
		if gate.is_empty() or gate in known:
			reached = a
	return reached


static func age_name(age: int) -> String:
	return String(AGES[clampi(age, 0, AGES.size() - 1)]["name"])


## Whether a tech opens a new age, and which.
static func opens_age(tech: String) -> int:
	for a: int in AGES.size():
		if String(AGES[a]["gate"]) == tech:
			return a
	return -1


## How hard a tech is to find on this island: its difficulty, eased where its ore is rich.
static func difficulty(tech: String, world: Dictionary) -> float:
	var info: Dictionary = TECHS[tech]
	var base := float(info["difficulty"])
	var amount := WorldGen.ore(world, String(info.get("ore", "")))
	return base / (0.6 + 0.4 * amount) if info.has("ore") and amount > 0.0 else base


## 1, or NO_ORE if the island lacks the tech's ore.
static func scarcity(tech: String, world: Dictionary) -> float:
	var info: Dictionary = TECHS[tech]
	return NO_ORE if info.has("ore") and WorldGen.ore(world, String(info["ore"])) <= 0.0 else 1.0


## The product of every known tech's multiplier for an effect: "discovery", "farm", "haul",
## "war", "care", "sickness". 1.0 when nothing known changes it.
static func bonus(known: PackedStringArray, effect: String) -> float:
	var total := 1.0
	for tech: String in known:
		var info: Dictionary = TECHS.get(tech, {})
		if info.has("bonus"):
			total *= float((info["bonus"] as Dictionary).get(effect, 1.0))
	return total
