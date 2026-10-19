class_name StyleKind
extends AssetKind
## A tribe's look, written once per age, government and destiny: how it builds (a grammar of
## roofs, wall materials, ornament, towers and proportions, fed to BuildingArt) and what its
## people wear by class (fed to VillagerArt). Colors are art-bible palette indices, clamped onto
## the right group. The village shows the society: a Theocracy grows spires, a Total State goes
## grey and brutalist, a Free Commons stays colorful; nobles dress finer, the bonded drab, and
## guards wear a uniform under a junta.
##
## Spec: {"architecture": {"roof", "material", "wall", "roof_color", "trim", "ornament", "towers",
## "proportion"}, "fashion": {"commoner", "noble", "bonded", "guard", "trim", "pattern", "accessory"}}.

const ROOFS: Array[String] = ["cone", "gable", "dome", "stepped", "flat", "spire"]
const MATERIALS: Array[String] = ["daub", "timber", "stone", "plaster", "brick", "concrete"]
## The first age each wall material can be built in.
const MATERIAL_AGE := {"daub": 0, "timber": 0, "stone": 1, "plaster": 1, "brick": 2, "concrete": 3}
## What a material too new for the tribe's age falls back to.
const MATERIAL_FALLBACK := {"concrete": "brick", "brick": "stone", "stone": "timber", "plaster": "daub"}
const ORNAMENTS: Array[String] = ["none", "carved", "painted", "banners", "gilded", "grim"]
const PROPORTIONS: Array[String] = ["squat", "balanced", "tall"]
const PATTERNS: Array[String] = ["plain", "stripes", "hem", "checks", "sash"]
const ACCESSORIES: Array[String] = ["none", "headband", "hat", "hood", "scarf", "feather"]
const MAX_TOWERS := 2
## Palette groups each color may come from (the first is where a stray index is clamped to).
const ARCHITECTURE_GROUPS := {"wall": ["walls"], "roof_color": ["roofs"], "trim": ["trim"]}
const FASHION_GROUPS := {
	"commoner": ["cloth", "drab"], "noble": ["cloth", "bright"], "bonded": ["drab"],
	"guard": ["cloth", "drab"], "trim": ["trim"],
}
## Government -> regime, the family of looks the offline writer starts from.
const REGIMES := {
	"Rule of Shamans": "holy", "Theocracy": "holy",
	"Total State": "iron", "Police State": "iron", "Military Junta": "iron",
	"Corporate State": "gilded", "Plutocracy": "gilded", "Merchant Oligarchy": "gilded", "Merchant Council": "gilded",
	"Kingdom": "crown", "Monarchy": "crown", "Empire": "crown", "Chiefdom": "crown", "Despotate": "crown",
	"Autocracy": "crown", "Warband": "crown",
}
## Destiny -> regime: a realm's ending outweighs the name of its government.
const DESTINY_REGIMES := {"holy_order": "holy", "panopticon": "iron", "iron_fist": "iron", "bloodline": "iron",
	"gilded_cage": "gilded", "free_commons": "free"}
## How dark a free or royal realm must be before its look follows its dystopia.
const DARK_AT := 55
## regime -> the offline writer's choices (palette indices, roofs, ornaments...).
const LOOKS := {
	"holy": {
		"roofs": ["spire"], "walls": [6, 11, 4], "roof_colors": [17, 14, 22],
		"trims": [17, 26, 30], "ornaments": ["gilded", "gilded", "carved"], "towers": [1, 2], "proportions": ["tall"],
		"commoner": [30, 24, 11, 26], "noble": [26, 27, 22], "bonded": [21, 12], "guard": [30, 22, 26],
		"cloth_trims": [17, 22, 26], "patterns": ["sash", "hem"], "accessories": ["hood", "hood", "headband"],
	},
	"iron": {
		"roofs": ["flat", "flat", "stepped"], "walls": [7, 8, 12, 5], "roof_colors": [8, 15, 16, 5],
		"trims": [16, 15, 22], "ornaments": ["grim"], "towers": [1, 2], "proportions": ["tall", "balanced"],
		"commoner": [12, 7, 5, 14], "noble": [27, 22], "bonded": [12, 7, 16], "guard": [8, 16, 27],
		"cloth_trims": [22, 15, 16], "patterns": ["plain"], "accessories": ["none", "hat"],
	},
	"gilded": {
		"roofs": ["gable", "flat", "dome"], "walls": [9, 11, 12, 6], "roof_colors": [17, 14, 13, 15],
		"trims": [17, 24, 2], "ornaments": ["gilded", "painted", "banners"], "towers": [0, 1], "proportions": ["tall", "balanced"],
		"commoner": [11, 30, 28, 3], "noble": [17, 24, 22], "bonded": [21, 14, 12], "guard": [27, 28],
		"cloth_trims": [17, 24], "patterns": ["stripes", "hem"], "accessories": ["hat", "scarf"],
	},
	"crown": {
		"roofs": ["gable", "stepped", "cone"], "walls": [4, 5, 11, 0], "roof_colors": [14, 22, 13, 1],
		"trims": [22, 17, 26], "ornaments": ["banners", "banners", "carved"], "towers": [1, 2], "proportions": ["balanced"],
		"commoner": [0, 1, 21, 19, 28], "noble": [22, 27, 26], "bonded": [21, 12, 5], "guard": [22, 27],
		"cloth_trims": [17, 22], "patterns": ["hem", "plain"], "accessories": ["hat", "none", "headband"],
	},
	"free": {
		"roofs": [], "walls": [11, 0, 9, 4, 6], "roof_colors": [13, 20, 22, 9, 1],
		"trims": [23, 24, 28, 29, 26], "ornaments": ["painted", "painted", "carved"], "towers": [0], "proportions": ["squat", "balanced"],
		"commoner": [23, 24, 25, 28, 29, 18, 26], "noble": [22, 26, 29, 28], "bonded": [21, 12], "guard": [28, 29, 18],
		"cloth_trims": [23, 24, 28, 29, 30], "patterns": ["stripes", "checks", "hem"], "accessories": ["headband", "feather", "scarf", "hat"],
	},
}
## Free peoples build for their island: roofs by biome.
const BIOME_ROOFS := {
	"meadow": ["gable", "cone"], "steppe": ["dome", "flat"], "jungle": ["cone", "cone", "gable"],
	"taiga": ["gable", "gable", "cone"], "highland": ["stepped", "gable"],
}
## Roof colors of the First Fires: thatch, bark and turf, by biome.
const EARLY_ROOFS := {"meadow": [1, 1, 2], "steppe": [1, 3], "jungle": [1, 20], "taiga": [2, 20], "highland": [3, 1, 5]}
## Laws worth telling the AI about when it picks a look.
const TELLING_LAWS: Array[String] = [
	"state_religion", "temple_tithe", "taboos", "surveillance_net", "social_credit", "secret_police", "censorship",
	"broadcast_propaganda", "standing_army", "warrior_band", "emergency_powers", "hereditary_rule", "class_marriage",
	"bonded_labor", "corporate_charter", "factory_discipline", "birth_permits", "assembly", "suffrage", "open_net",
	"universal_dividend", "labor_rights", "elder_council", "shared_stores",
]
const MAX_LAWS := 8


func task() -> String:
	return "style"


## Styles come first: every village needs one, and posters and banners hang on its walls.
func priority() -> int:
	return 10


func subjects(state: WorldState) -> Array[String]:
	var names: Array[String] = []
	names.assign(Array(state.tribe_names))
	return names


## "age 2|Theocracy|" or "age 4|Total State|panopticon": a new age, a new government or the
## tribe's destiny met makes a new look.
func signature(state: WorldState, subject: String) -> String:
	var t := state.tribe_index(subject)
	if t == -1:
		return ""
	return "age %d|%s|%s" % [state.age_of(t), government_of(state, t), _destiny(state, subject)]


func context(state: WorldState, subject: String) -> Dictionary:
	var t := state.tribe_index(subject)
	if t == -1:
		return {}
	var age := state.age_of(t)
	var culture := {}
	for axis: String in Society.CULTURE_AXES:
		culture[axis] = int(state.tribe_culture[t].get(axis, 0))
	var laws: Array[String] = []
	for law: String in TELLING_LAWS:
		if Society.has_law(state, t, law) and laws.size() < MAX_LAWS:
			laws.append(Laws.name_of(law))
	var dystopia := Society.dystopia(state, t)
	var materials: Array[String] = []
	for material: String in MATERIALS:
		if int(MATERIAL_AGE[material]) <= age:
			materials.append(material)
	var destiny := _destiny(state, subject)
	return {
		"tribe": subject,
		"island": String(state.world.get("biome", "meadow")),
		"age": Knowledge.age_name(age),
		"age_level": age,
		"government": government_of(state, t),
		"strongest_faction": Society.FACTION_NAMES[Society.top_faction(state, t)],
		"culture": culture,
		"laws": laws,
		"freedom": Society.freedom(state, t),
		"inequality": Society.inequality(state, t),
		"dystopia": dystopia,
		"dystopia_kind": Society.dystopia_kind(state, t) if dystopia >= 30 else "none",
		"nobles": Society.count_where(state, t, "noble"),
		"bonded": Society.count_where(state, t, "bonded"),
		"destiny": DestinySystem.name_of(destiny) if destiny else "none",
		"destiny_id": destiny,
		"materials": materials,
		"palette": {
			"walls": ArtPalette.describe("walls"),
			"roofs": ArtPalette.describe("roofs"),
			"trim": ArtPalette.describe("trim"),
			"cloth": ArtPalette.describe("cloth"),
			"bright": ArtPalette.describe("bright"),
			"drab": ArtPalette.describe("drab"),
		},
	}


## Clamps every index onto its palette group, towers onto 0 to MAX_TOWERS and the material onto
## the tribe's age; a word outside the grammar rejects the reply.
func accept(reply: Dictionary, facts: Dictionary) -> Variant:
	var building: Variant = reply.get("architecture")
	var clothes: Variant = reply.get("fashion")
	if not building is Dictionary or not clothes is Dictionary:
		return null
	var words_fit := _words_fit(building, {"roof": ROOFS, "material": MATERIALS, "ornament": ORNAMENTS, "proportion": PROPORTIONS}) \
		and _words_fit(clothes, {"pattern": PATTERNS, "accessory": ACCESSORIES})
	if not words_fit or not _are_numbers(building, ARCHITECTURE_GROUPS.keys() + ["towers"]) or not _are_numbers(clothes, FASHION_GROUPS.keys()):
		return null
	var material := String(building["material"])
	var age := int(facts.get("age_level", 0))
	while int(MATERIAL_AGE[material]) > age:
		material = MATERIAL_FALLBACK[material]
	var architecture := {
		"roof": String(building["roof"]),
		"material": material,
		"ornament": String(building["ornament"]),
		"towers": clampi(int(building["towers"]), 0, MAX_TOWERS),
		"proportion": String(building["proportion"]),
	}
	for key: String in ARCHITECTURE_GROUPS:
		architecture[key] = clamp_onto(int(building[key]), ARCHITECTURE_GROUPS[key])
	var fashion := {"pattern": String(clothes["pattern"]), "accessory": String(clothes["accessory"])}
	for key: String in FASHION_GROUPS:
		fashion[key] = clamp_onto(int(clothes[key]), FASHION_GROUPS[key])
	return {"architecture": architecture, "fashion": fashion}


## Written from the tribe's regime (its government, darkened by its dystopia or its destiny), then
## bent by its island, its age and its culture. Seeded, so the same tribe always gets the same look.
func offline(facts: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var regime := regime_of(facts)
	var look: Dictionary = LOOKS[regime]
	var age := int(facts.get("age_level", 0))
	var biome := String(facts.get("island", "meadow"))
	var culture: Dictionary = facts.get("culture", {})
	var piety := int(culture.get("piety", 0))
	var martial := int(culture.get("martial", 0))
	var openness := int(culture.get("openness", 0))
	var hierarchy := int(culture.get("hierarchy", 0))

	var roofs: Array = look["roofs"] if not (look["roofs"] as Array).is_empty() else BIOME_ROOFS.get(biome, ["gable"])
	var roof := String(_pick(rng, roofs))
	if piety > 50 and regime != "iron" and rng.randf() < 0.4:
		roof = "spire"
	# Culture leans a free people's looks (the others build what their rulers want): the open
	# paint, the closed carve, the ranked build tall and the equal low.
	var ornament := String(_pick(rng, look["ornaments"]))
	var proportion := String(_pick(rng, look["proportions"]))
	if regime == "free":
		if openness > 40:
			ornament = "painted"
		elif openness < -40:
			ornament = "carved"
		if hierarchy > 50:
			proportion = "tall"
		elif hierarchy < -50:
			proportion = "squat"
	var towers := int(_pick(rng, look["towers"]))
	if martial > 40:
		towers += 1
	var roof_color := int(_pick(rng, look["roof_colors"]))
	var wall := int(_pick(rng, look["walls"]))
	if age == 0:
		# First Fires: thatch, bark or turf over daub and timber, whoever rules.
		roof_color = int(_pick(rng, EARLY_ROOFS.get(biome, [1])))
		if regime == "iron":
			roof_color = 3
		wall = 0 if regime in ["free", "crown"] else int(_pick(rng, [0, 2, 11] if regime == "holy" else [2, 5]))
	return {
		"architecture": {
			"roof": roof,
			"material": _material(rng, regime, age, biome),
			"wall": wall,
			"roof_color": roof_color,
			"trim": int(_pick(rng, look["trims"])),
			"ornament": ornament,
			"towers": mini(towers, MAX_TOWERS),
			"proportion": proportion,
		},
		"fashion": {
			"commoner": int(_pick(rng, look["commoner"])),
			"noble": int(_pick(rng, look["noble"])),
			"bonded": int(_pick(rng, look["bonded"])),
			"guard": int(_pick(rng, look["guard"])),
			"trim": int(_pick(rng, look["cloth_trims"])),
			"pattern": String(_pick(rng, look["patterns"])),
			"accessory": String(_pick(rng, look["accessories"])),
		},
	}


## "holy", "iron", "gilded", "crown" or "free": the family of looks a tribe's facts call for.
static func regime_of(facts: Dictionary) -> String:
	var destiny := String(facts.get("destiny_id", ""))
	if DESTINY_REGIMES.has(destiny):
		return DESTINY_REGIMES[destiny]
	var regime := String(REGIMES.get(String(facts.get("government", "")), "free"))
	if regime in ["free", "crown"] and int(facts.get("dystopia", 0)) >= DARK_AT:
		match String(facts.get("dystopia_kind", "")):
			"theocratic":
				return "holy"
			"corporate":
				return "gilded"
			"none":
				return regime
		return "iron"
	return regime


## True if each key of words holds one of its allowed words.
static func _words_fit(object: Dictionary, words: Dictionary) -> bool:
	for key: String in words:
		if not String(object.get(key, "")) in (words[key] as Array):
			return false
	return true


## True if each key holds a number.
static func _are_numbers(object: Dictionary, keys: Array) -> bool:
	for key: Variant in keys:
		var value: Variant = object.get(key)
		if not (value is int or value is float):
			return false
	return true


## An index on the palette, kept if it is in any of the groups, else moved to the nearest of the first.
static func clamp_onto(index: int, groups: Array) -> int:
	index = clampi(index, 0, ArtPalette.size() - 1)
	for group: String in groups:
		if index in ArtPalette.GROUPS[group]:
			return index
	return ArtPalette.clamp_index(index, groups[0])


## The newest material the age allows, as each regime builds it.
static func _material(rng: RandomNumberGenerator, regime: String, age: int, biome: String) -> String:
	var by_age: Array
	match regime:
		"iron":
			by_age = [["timber"], ["stone"], ["stone"], ["concrete"], ["concrete"]]
		"holy":
			by_age = [["daub", "timber"], ["stone", "plaster"], ["stone", "plaster"], ["stone", "plaster"], ["plaster", "stone"]]
		"gilded":
			by_age = [["timber"], ["plaster", "stone"], ["brick", "plaster"], ["brick", "brick", "concrete"], ["concrete", "plaster", "brick"]]
		_:
			by_age = [["daub", "daub", "timber"], ["timber", "stone", "plaster"], ["stone", "plaster", "brick"], ["brick", "brick", "plaster"], ["plaster", "brick", "concrete"]]
	var choices: Array = by_age[clampi(age, 0, 4)]
	if biome in ["taiga", "jungle"] and age <= 1 and regime != "iron":
		return "timber"
	return String(_pick(rng, choices))


static func _pick(rng: RandomNumberGenerator, from: Array) -> Variant:
	return from[rng.randi_range(0, from.size() - 1)]


## The government a style (or a tribe's local names) is written for. The leaderless "Band of
## equals" and "Free tribe" are one look, so a village that grows past 30 people doesn't ask again.
static func government_of(state: WorldState, t: int) -> String:
	var government := Society.government(state, t)
	return "Free tribe" if government == "Band of equals" else government


## The destiny this tribe has met ("" if none, or if it is another tribe's).
static func _destiny(state: WorldState, subject: String) -> String:
	if state.destiny.is_empty():
		return ""
	var tribe := String(state.destiny.get("tribe", ""))
	return String(state.destiny.get("kind", "")) if tribe == subject or tribe.is_empty() else ""
