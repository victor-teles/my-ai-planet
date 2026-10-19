class_name MonumentKind
extends AssetKind
## The look and words of a finished statue or temple: a statue's pose and plinth inscription
## come from the vanity of the ruler it was raised to (their name, traits and government); a
## temple's iconography and inscription from the tribe's faith and its prophets' doctrines.
## The spec is {"pose" (a preset of VillagerArt.statue), "inscription", "iconography" (the emblem
## on the pediment, an EmblemGrammar charge)}. Subjects are building ids; a monument keeps its
## spec for as long as it stands.

const TYPES: Array[String] = ["statue", "temple"]
const POSES: Array[String] = ["raised_fist", "sword", "pointing", "open_arms", "scroll", "staff"]
const ICONS: Array[String] = ["sun", "moon", "star", "flame", "eye", "tree", "wave", "hand", "mountain"]
const PROPHET_EVENTS := {"prophet": "began to preach", "prophet_silenced": "was silenced for heresy", "reform": "humbled the old priests", "schism": "led the faithful away to found this tribe"}
## Trait -> pose -> weight, for a statue's pose.
const TRAIT_POSES := {
	"fierce": {"sword": 3.0}, "brave": {"sword": 2.0, "raised_fist": 2.0}, "proud": {"raised_fist": 3.0, "pointing": 1.0},
	"wise": {"scroll": 3.0}, "curious": {"pointing": 2.0, "scroll": 1.0}, "kind": {"open_arms": 3.0},
	"devout": {"staff": 3.0}, "greedy": {"pointing": 2.0}, "cheerful": {"open_arms": 2.0}, "lazy": {"staff": 1.0},
}
const GOVERNMENT_POSES := {
	"Military Junta": {"sword": 3.0}, "Warband": {"sword": 3.0}, "Theocracy": {"staff": 3.0}, "Rule of Shamans": {"staff": 3.0},
	"Total State": {"raised_fist": 3.0, "pointing": 2.0}, "Police State": {"raised_fist": 2.0, "pointing": 2.0},
	"Republic": {"scroll": 2.0, "open_arms": 2.0}, "Democracy": {"scroll": 2.0, "open_arms": 2.0}, "Assembly": {"scroll": 2.0},
}
const EPITHETS := {
	"proud": "the Magnificent", "fierce": "the Unbowed", "brave": "the Bold", "wise": "the Wise", "kind": "the Beloved",
	"greedy": "the Generous", "devout": "the Pious", "curious": "the Seeker", "cheerful": "the Bright", "lazy": "the Serene",
}
## Government -> what its ruler is called on a plinth, and what they are thanked for.
const TITLES := {
	"Chiefdom": ["Chief", "plenty"], "Kingdom": ["Sovereign", "peace"], "Monarchy": ["Sovereign", "peace"], "Empire": ["Emperor", "glory"],
	"Despotate": ["Protector", "order"], "Autocracy": ["Protector", "order"], "Police State": ["Guardian", "safety"],
	"Total State": ["Leader", "unity"], "Military Junta": ["General", "victory"], "Warband": ["Warlord", "victory"],
	"Theocracy": ["Holy Guide", "grace"], "Rule of Shamans": ["Holy Guide", "grace"], "Plutocracy": ["First Merchant", "wealth"],
	"Corporate State": ["Director", "prosperity"], "Merchant Oligarchy": ["First Merchant", "wealth"],
}
const ICON_NAMES := {
	"sun": "Sun", "moon": "Moon", "star": "Guiding Star", "flame": "Undying Flame", "eye": "Watchful Eye",
	"tree": "First Tree", "wave": "Deep Water", "hand": "Open Hand", "mountain": "Holy Mountain",
}
const TEACHINGS := {
	"sun": "the sun returns to the faithful", "moon": "the night is never empty", "star": "every soul has its star",
	"flame": "the fire lives in everyone", "eye": "the sky sees every heart", "tree": "all life grows from one root",
	"wave": "all waters meet at last", "hand": "the sky works through our hands", "mountain": "the high places are holy",
}
const MAX_INSCRIPTION := 90


func task() -> String:
	return "monument"


func priority() -> int:
	return 55


func subjects(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	for b: int in state.building_ids.size():
		if state.building_types[b] in TYPES and state.is_built(b):
			found.append(str(state.building_ids[b]))
	return found


func signature(state: WorldState, subject: String) -> String:
	var b := state.building_index(subject.to_int()) if subject.is_valid_int() else -1
	if b == -1 or not state.is_built(b) or state.building_types[b] not in TYPES:
		return ""
	return "%s|%s|%d" % [state.building_types[b], state.building_tribes[b], state.building_done[b]]


func context(state: WorldState, subject: String) -> Dictionary:
	var b := state.building_index(subject.to_int()) if subject.is_valid_int() else -1
	if b == -1:
		return {"monument": "statue", "tribe": ""}
	var tribe := state.building_tribes[b]
	var t := state.tribe_index(tribe)
	var type := state.building_types[b]
	var facts := {"monument": type, "tribe": tribe, "raised_in_year": WorldState.year_of(maxi(state.building_done[b], 0))}
	if t == -1:
		return facts
	facts["government"] = Society.government(state, t)
	facts["age"] = Knowledge.age_name(state.age_of(t))
	if type == "statue":
		var ruler := state.chief_of(tribe)
		if ruler != -1:
			facts["ruler"] = {
				"name": People.full_name(state, ruler), "traits": Array(People.traits_of(state, ruler)),
				"age": People.age(state, ruler), "years_ruling": floori(SocietySystem.reign_years(state, t)),
			}
		if state.tribe_dynasty[t]:
			facts["house"] = state.tribe_dynasty[t]
		facts["dystopia"] = Society.dystopia(state, t)
	else:
		facts["faith"] = {
			"piety": int(state.tribe_culture[t].get("piety", 0)), "priests_power": Society.power(state, t, "priests"),
			"state_religion": Society.has_law(state, t, "state_religion"),
		}
		var prophets := _prophets(state, tribe)
		if not prophets.is_empty():
			facts["prophets"] = prophets
	return facts


func accept(reply: Dictionary, _facts: Dictionary) -> Variant:
	var inscription := String(reply.get("inscription", "")).strip_edges().trim_prefix('"').trim_suffix('"').strip_edges()
	if inscription.length() < 3 or inscription.length() > MAX_INSCRIPTION or inscription.contains("<"):
		return null
	var pose := String(reply.get("pose", ""))
	var icon := String(reply.get("iconography", ""))
	return {"pose": pose if pose in POSES else POSES[0], "inscription": inscription, "iconography": icon if icon in ICONS else ICONS[0]}


func offline(facts: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var government := String(facts.get("government", ""))
	var icon := EmblemGrammar.pick(_icon_weights(facts), rng)
	if String(facts.get("monument", "")) == "temple":
		return {"pose": "staff", "inscription": _temple_words(facts, icon, rng), "iconography": icon}
	var weights := {}
	for pose: String in POSES:
		weights[pose] = 1.0
	var ruler: Dictionary = facts.get("ruler", {})
	for trait_id: Variant in ruler.get("traits", []):
		for pose: String in TRAIT_POSES.get(String(trait_id), {}):
			weights[pose] = float(weights[pose]) + float(TRAIT_POSES[String(trait_id)][pose])
	for pose: String in GOVERNMENT_POSES.get(government, {}):
		weights[pose] = float(weights[pose]) + float(GOVERNMENT_POSES[government][pose])
	return {"pose": EmblemGrammar.pick(weights, rng), "inscription": _statue_words(facts, rng), "iconography": icon}


# --- Offline writing ----------------------------------------------------------------

## What the tribe's prophets did, oldest first (at most three).
static func _prophets(state: WorldState, tribe: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in state.events:
		var type := String(event["type"])
		var data: Dictionary = event["data"]
		if PROPHET_EVENTS.has(type) and String(data.get("tribe", "")) == tribe and data.has("name"):
			found.append({"name": String(data["name"]), "what": PROPHET_EVENTS[type], "year": WorldState.year_of(int(event["tick"]))})
	return found.slice(maxi(found.size() - 3, 0))


static func _icon_weights(facts: Dictionary) -> Dictionary:
	var weights := {}
	for icon: String in ICONS:
		weights[icon] = 1.0
	var faith: Dictionary = facts.get("faith", {})
	if bool(faith.get("state_religion", false)):
		weights["eye"] = 4.0
		weights["sun"] = 4.0
	if int(faith.get("piety", 0)) >= 30:
		weights["flame"] = float(weights["flame"]) + 2.0
		weights["star"] = float(weights["star"]) + 2.0
	if not (facts.get("prophets", []) as Array).is_empty():
		weights["flame"] = float(weights["flame"]) + 3.0
		weights["hand"] = float(weights["hand"]) + 2.0
	match String(facts.get("government", "")):
		"Theocracy", "Rule of Shamans":
			weights["sun"] = float(weights["sun"]) + 3.0
		"Total State", "Police State":
			weights["eye"] = float(weights["eye"]) + 4.0
		"Military Junta", "Warband":
			weights["mountain"] = float(weights["mountain"]) + 2.0
	return weights


static func _statue_words(facts: Dictionary, rng: RandomNumberGenerator) -> String:
	var ruler: Dictionary = facts.get("ruler", {})
	var tribe := String(facts.get("tribe", ""))
	var year := int(facts.get("raised_in_year", 0))
	if ruler.is_empty():
		return "Raised by the %s in year %d" % [tribe, year]
	var name := String(ruler["name"]).get_slice(" ", 0)
	var epithet := "the Great"
	for trait_id: Variant in ruler.get("traits", []):
		if EPITHETS.has(String(trait_id)):
			epithet = EPITHETS[String(trait_id)]
			break
	var title: Array = TITLES.get(String(facts.get("government", "")), ["Elder", "wisdom"])
	var lines: Array[String] = [
		"%s %s, %s of the %s" % [name, epithet, title[0], tribe],
		"To %s, who gave the %s %s" % [name, tribe, title[1]],
		"%s %s. Raised in year %d" % [name, epithet, year],
	]
	if facts.has("house"):
		lines.append("%s of house %s, %s of the %s" % [name, facts["house"], title[0], tribe])
	var line := lines[rng.randi_range(0, lines.size() - 1)]
	return line if line.length() <= MAX_INSCRIPTION else lines[2]


static func _temple_words(facts: Dictionary, icon: String, rng: RandomNumberGenerator) -> String:
	var tribe := String(facts.get("tribe", ""))
	var prophets: Array = facts.get("prophets", [])
	if not prophets.is_empty() and rng.randf() < 0.75:
		var prophet: Dictionary = prophets[-1]
		return "Here %s taught that %s" % [String(prophet["name"]), TEACHINGS[icon]]
	var lines: Array[String] = [
		"To the %s that watches over the %s" % [ICON_NAMES[icon], tribe],
		"Raised by the %s in year %d, for the %s" % [tribe, int(facts.get("raised_in_year", 0)), ICON_NAMES[icon]],
		"Enter humbly: %s" % TEACHINGS[icon],
	]
	return lines[rng.randi_range(0, lines.size() - 1)]
