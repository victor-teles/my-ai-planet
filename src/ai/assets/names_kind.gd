class_name NamesKind
extends AssetKind
## Laws and places in a tribe's own words: what the Kolu call their surveillance network ("the
## Watchful Eye of Kolu") or their temple ("the House of Tashen"). Only words: the sim keeps the
## ids, and the feed and panels show the names (see LocalNames). Written again when the tribe
## enters a new age or changes government, which is when its laws and buildings change.
## The stored spec is {"laws": {law id: name}, "buildings": {building type: name}}.

const MAX_NAME := 40
const MAX_LAWS := 14
const WORDS := 6 ## words of the tongue the prompt (and the offline names) draw on
## The buildings a village talks about by name. Homes and fields are just homes and fields.
const PLACES: Array[String] = [
	"workshop", "healer_hut", "storehouse", "shrine", "palisade", "longhouse", "mine", "smithy", "school",
	"temple", "great_house", "market", "stone_wall", "barracks", "watchtower", "statue", "prison", "factory",
	"broadcast_tower", "surveillance_mast",
]
## Offline names: a few templates per id. {word} and {word2} are words of the tribe's tongue,
## {tribe} its name. No leading "the": sentences add it.
const LAW_NAMES := {
	"elder_council": ["Circle of {word}", "{word} of the Grey Heads", "Elders' {word}"],
	"shared_stores": ["{word} Bowl", "Common Basket of {tribe}", "Sharing of {word}"],
	"chiefs_share": ["{word}'s Portion", "Chief's {word}", "Due of the {word} Hearth"],
	"taboos": ["{word} Taboos", "Forbidden Ways of {word}", "Sacred {word}"],
	"exile": ["Long Walk of {word}", "{word} Casting-Out", "{word} Banishment"],
	"hereditary_rule": ["Blood of {word}", "{word} Succession", "Unbroken Line of {tribe}"],
	"written_law": ["Tablets of {word}", "{word} Code", "Carved Word of {tribe}"],
	"temple_tithe": ["{word}'s Tenth", "Gift to {word}", "Temple Due of {tribe}"],
	"bonded_labor": ["{word} Bond", "Debt-Yoke of {word}", "Binding of {word}"],
	"warrior_band": ["Spears of {word}", "{word} Band", "Shield-Kin of {tribe}"],
	"emergency_powers": ["{word}'s Hour", "Storm Mandate of {word}", "Iron Season of {word}"],
	"taxation": ["{word} Levy", "Coin of {word}", "Counting of {tribe}"],
	"class_marriage": ["{word} Vows", "Like to Like of {word}", "Rule of the {word} Hearths"],
	"state_religion": ["One Faith of {word}", "Creed of {word}", "{word} Orthodoxy"],
	"standing_army": ["Host of {word}", "{word} Legion", "Ever-Ready of {tribe}"],
	"assembly": ["{word} Moot", "Gathering of {tribe}", "Voice of {word}"],
	"factory_discipline": ["{word} Whistle", "Rule of the {word} Bell", "Shift Code of {tribe}"],
	"secret_police": ["Quiet Hand of {word}", "{word} Listeners", "Grey Coats of {tribe}"],
	"censorship": ["{word} Seal", "Clean Word of {tribe}", "Silence of {word}"],
	"suffrage": ["Every Voice of {tribe}", "{word} Ballot", "Stones of {word}"],
	"labor_rights": ["{word} Charter", "Rest-Day of {word}", "Workers' {word}"],
	"clean_air": ["Clear Sky of {word}", "{word} Breath Act", "Green {word}"],
	"surveillance_net": ["Watchful Eye of {tribe}", "{word}'s Thousand Eyes", "Eye of {word}"],
	"social_credit": ["{word} Ledger", "Book of Worth of {tribe}", "{word} Standing"],
	"birth_permits": ["{word} Cradle Writ", "Blessing of {word}", "Cradle Permit of {word}"],
	"corporate_charter": ["{word} Company Charter", "Contract of {word}", "{word} Holdings"],
	"broadcast_propaganda": ["Voice of {word}", "{word} Hour", "One Song of {tribe}"],
	"open_net": ["Open {word}", "{word} Commons", "Web of {tribe}"],
	"universal_dividend": ["{word} Share", "Gift of {word}", "Dividend of {tribe}"],
}
const PLACE_NAMES := {
	"workshop": ["{word} Workshop", "Bench of {word}"],
	"healer_hut": ["House of {word}", "{word} Healing Lodge"],
	"storehouse": ["{word} Granary", "Store of {word}"],
	"shrine": ["Shrine of {word}", "{word} Stones"],
	"palisade": ["{word} Stockade", "Fence of {tribe}"],
	"longhouse": ["{word} Longhall", "Hall of {word}"],
	"mine": ["{word} Pits", "Deep of {word}"],
	"smithy": ["{word} Forge", "Anvil of {word}"],
	"school": ["House of {word}", "{word} School"],
	"temple": ["Temple of {word}", "{word} Sanctum", "House of {word2}"],
	"great_house": ["{word} Hall", "Seat of {word}"],
	"market": ["{word} Market", "Bazaar of {word}"],
	"stone_wall": ["Wall of {word}", "{word} Ramparts"],
	"barracks": ["{word} Barracks", "Spear-House of {word}"],
	"watchtower": ["{word} Watch", "Tower of {word}"],
	"statue": ["Statue of {word}", "{word} Colossus"],
	"prison": ["{word} Keep", "Stone Hold of {word}"],
	"factory": ["{word} Works", "Mill of {word}"],
	"broadcast_tower": ["{word} Mast", "Tower of the {word} Voice"],
	"surveillance_mast": ["Eye of {word}", "{word} Watchpost"],
}

static var _allowed: RegEx


func task() -> String:
	return "names"


func priority() -> int:
	return 60


func subjects(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	found.assign(Array(state.tribe_names))
	return found


func signature(state: WorldState, subject: String) -> String:
	var t := state.tribe_index(subject)
	return "" if t == -1 else "age %d|%s" % [state.age_of(t), Society.government(state, t)]


## The tribe's words, its laws in force and those its age may bring, and the places it has or
## knows how to build.
func context(state: WorldState, subject: String) -> Dictionary:
	var t := state.tribe_index(subject)
	if t == -1:
		return {"tribe": subject, "age": "", "government": "", "words": [], "laws": [], "buildings": []}
	var age := state.age_of(t)
	var laws: Array[Dictionary] = []
	for law: String in Society.laws_of(state, t):
		laws.append({"id": law, "name": Laws.name_of(law), "in_force": true, "dark": Laws.is_dystopian(law)})
	for law: String in Laws.ORDER:
		var info: Dictionary = Laws.LAWS[law]
		var tech := String(info["tech"])
		if laws.size() < MAX_LAWS and not Society.has_law(state, t, law) and int(info["age"]) <= age and (tech.is_empty() or tech in state.tribe_knowledge[t]):
			laws.append({"id": law, "name": Laws.name_of(law), "in_force": false, "dark": Laws.is_dystopian(law)})
	var places: Array[Dictionary] = []
	var standing := {}
	for b: int in state.buildings_of(subject):
		standing[state.building_types[b]] = true
	for type: String in PLACES:
		if standing.has(type) or String(Buildings.TYPES[type]["tech"]) in state.tribe_knowledge[t]:
			places.append({"id": type, "name": Buildings.name_of(type)})
	return {
		"tribe": subject,
		"age": Knowledge.age_name(age),
		"government": Society.government(state, t),
		"words": words_of(state, subject),
		"laws": laws.slice(0, MAX_LAWS),
		"buildings": places,
	}


## Keeps the names of known ids only, tidied and short; null if nothing usable is left of a reply
## that had something to name.
func accept(reply: Dictionary, facts: Dictionary) -> Variant:
	var spec := {"laws": _keep(reply.get("laws", []), facts.get("laws", [])), "buildings": _keep(reply.get("buildings", []), facts.get("buildings", []))}
	var asked := (facts.get("laws", []) as Array).size() + (facts.get("buildings", []) as Array).size()
	if asked > 0 and (spec["laws"] as Dictionary).is_empty() and (spec["buildings"] as Dictionary).is_empty():
		return null
	return spec


func offline(facts: Dictionary, _seed_value: int) -> Dictionary:
	var words: Array = facts.get("words", [])
	var tribe := String(facts.get("tribe", ""))
	var reply := {"laws": [], "buildings": []}
	for group: String in ["laws", "buildings"]:
		for item: Dictionary in facts.get(group, []):
			var id := String(item["id"])
			(reply[group] as Array).append({"id": id, "name": offline_name(group, id, words, tribe)})
	return reply


## The offline name for one law or building of a tribe: always the same for the same tribe and
## words, so the names stay put from age to age until an AI writes better ones.
@warning_ignore("integer_division")
static func offline_name(group: String, id: String, words: Array, tribe: String) -> String:
	var templates: Array = (LAW_NAMES if group == "laws" else PLACE_NAMES).get(id, [])
	if templates.is_empty():
		return ""
	var pool: Array = words if not words.is_empty() else [tribe]
	var pick := absi(hash([tribe, group, id]))
	var word := String(pool[pick % pool.size()])
	var word2 := String(pool[(pick / 7 + 1) % pool.size()])
	for k: int in templates.size():
		var name := String(templates[(pick + k) % templates.size()]).format({"word": word, "word2": word2, "tribe": tribe})
		if name.length() <= MAX_NAME:
			return name
	return word


## A few words of a tribe's tongue, the same every time, none that the content guard would flag
## (even in Gentle Mode).
static func words_of(state: WorldState, tribe: String) -> Array[String]:
	var found: Array[String] = []
	for word: String in Language.words(Language.of_tribe(state, tribe), hash([state.seed_value, tribe, "words"]), WORDS + 2):
		if ContentGuard.check_text(word, true).is_empty() and found.size() < WORDS:
			found.append(word)
	return found


## A reply's names for the ids that were asked about: trimmed, no leading "the", letters, spaces,
## apostrophes and hyphens only, at most MAX_NAME characters.
static func _keep(entries: Variant, asked: Variant) -> Dictionary:
	var known := {}
	for item: Variant in asked if asked is Array else []:
		if item is Dictionary:
			known[String((item as Dictionary).get("id", ""))] = true
	var kept := {}
	for entry: Variant in entries if entries is Array else []:
		if not entry is Dictionary:
			continue
		var id := String((entry as Dictionary).get("id", ""))
		var name := tidy(String((entry as Dictionary).get("name", "")))
		if known.has(id) and not kept.has(id) and not name.is_empty():
			kept[id] = name
	return kept


## A name made fit to show, or "" if it can't be.
static func tidy(text: String) -> String:
	var name := " ".join(text.strip_edges().split(" ", false))
	if name.to_lower().begins_with("the "):
		name = name.substr(4)
	if _allowed == null:
		_allowed = RegEx.create_from_string("^[\\p{L}][\\p{L} '\\-]*$")
	if name.length() < 2 or name.length() > MAX_NAME or _allowed.search(name) == null:
		return ""
	return name
