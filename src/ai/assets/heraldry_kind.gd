class_name HeraldryKind
extends AssetKind
## Every tribe's banner: an emblem and a motto for whoever holds power, a ruling house where power
## is inherited, the one who rules where one person does (a chief, a despot, a general, a merchant
## prince), or the people where nobody rules alone. The spec is {"motto", "field" (the banner's
## color, a palette index), "charge" (what the emblem shows), "emblem" (clean SVG, see SvgGuard)}.
## A new dynasty, a coup, a revolution or a change of government replaces the banner.

const GROUP := "heraldry"
## What the culture leans toward (axis and sign) -> charges it favors.
const CULTURE_CHARGES := {
	"piety+": ["sun", "moon", "flame", "eye"], "piety-": ["wheel", "grain", "hand"],
	"martial+": ["tower", "flame", "mountain"], "martial-": ["tree", "grain", "fish"],
	"openness+": ["wave", "fish", "star"], "openness-": ["mountain", "tower", "eye"],
	"hierarchy+": ["crown", "tower"], "hierarchy-": ["hand", "tree"],
}
const FACTION_CHARGES := {
	"ruler": ["crown", "sun", "star"], "priests": ["sun", "eye", "flame", "moon"],
	"warriors": ["tower", "flame", "star"], "merchants": ["wheel", "grain", "fish"], "council": ["hand", "tree", "grain"],
}
const BIOME_CHARGES := {"meadow": ["grain", "tree"], "steppe": ["sun", "grain"], "jungle": ["tree", "fish"], "taiga": ["tree", "moon"], "highland": ["mountain", "star"]}
## Field colors a culture's lean favors (heraldry palette indices).
const CULTURE_FIELDS := {
	"piety+": [17, 26, 30], "martial+": [22, 23, 16], "openness+": [28, 29, 18],
	"hierarchy+": [27, 22, 17], "hierarchy-": [18, 20, 30], "dystopia": [16, 31, 22, 27],
}
## Virtues a lean prizes, for offline mottos.
const VIRTUES := {
	"piety+": ["Faith", "Devotion", "Prayer", "the sky's grace"], "piety-": ["Reason", "Craft", "Plain truth"],
	"martial+": ["Courage", "Iron", "Valor", "Steadfastness"], "martial-": ["Peace", "Patience", "Mercy"],
	"openness+": ["Welcome", "Wonder", "the open road"], "openness-": ["Vigilance", "the old ways", "Kinship"],
	"hierarchy+": ["Order", "Honor", "Duty"], "hierarchy-": ["Fellowship", "Fairness", "All hands"],
	"dystopia": ["Order", "Obedience", "Vigilance", "Unity"],
}
const SAYINGS := {
	"sun": ["The sun rises for us", "We rise with the sun"], "moon": ["The moon keeps watch", "By moonlight we endure"],
	"star": ["We follow the star", "One star, one road"], "tree": ["Deep roots, long shade", "The tree remembers"],
	"wave": ["As the tide, we return", "The water carries us"], "eye": ["The Eye never sleeps", "Seen and kept safe"],
	"crown": ["Crowned by the sky", "The crown endures"], "flame": ["The flame endures", "Our fire never fails"],
	"hand": ["Many hands, one hearth", "Open hands, open doors"], "mountain": ["We do not bend", "Stone outlasts the storm"],
	"wheel": ["The wheel turns for all", "Work makes us whole"], "tower": ["Stone stands", "Behind our walls, peace"],
	"fish": ["The waters feed us", "Swift and many"], "grain": ["From the soil, plenty", "Bread for every table"],
}


func task() -> String:
	return "heraldry"


func priority() -> int:
	return 30


func subjects(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	found.assign(Array(state.tribe_names))
	return found


## Whose banner it is: "house <name>" (inherited rule), "ruler <person id>" (one person rules
## alone: a despot, general or merchant prince) or "the people". A First Fires chiefdom's chiefs
## come and go with the seasons of life, so its banner stays the people's until someone seizes it.
static func holder_of(state: WorldState, t: int) -> String:
	if state.tribe_dynasty[t]:
		return "house " + state.tribe_dynasty[t]
	var top := Society.top_faction(state, t)
	if top == "ruler" and state.age_of(t) == 0:
		return "the people"
	if top in ["ruler", "warriors", "merchants"] and Society.power(state, t, top) >= 25 and state.chief_of(state.tribe_names[t]) != -1:
		return "ruler %d" % state.tribe_chiefs[t]
	return "the people"


## Which faction rules ("ruler", "council", "priests", "warriors", "merchants"), or "equals" when
## none does. A government's name also follows the age and the head count ("Assembly" becomes
## "Republic"); only a change of who rules is a new government for the banner.
static func regime_of(state: WorldState, t: int) -> String:
	var top := Society.top_faction(state, t)
	if Society.power(state, t, top) < 25 or (top == "ruler" and state.age_of(t) == 0):
		return "equals" # a First Fires chief leads the band; they don't rule it
	return top


## A new holder (a house, a strongman, the people) or a new ruling faction replaces the banner.
func signature(state: WorldState, subject: String) -> String:
	var t := state.tribe_index(subject)
	return "%s|%s" % [holder_of(state, t), regime_of(state, t)] if t != -1 else ""


func context(state: WorldState, subject: String) -> Dictionary:
	var t := state.tribe_index(subject)
	if t == -1:
		return {"tribe": subject, "palette": ArtPalette.describe(GROUP)}
	var holder := holder_of(state, t)
	var facts := {
		"tribe": subject,
		"banner_of": "the people of the %s" % subject,
		"government": Society.government(state, t),
		"age": Knowledge.age_name(state.age_of(t)),
		"strongest_faction": Society.FACTION_NAMES[Society.top_faction(state, t)],
		"culture": _culture(state, t),
		"island": String(state.world.get("biome", "")),
		"drinks_from": state.water_names[state.tribe_water[t]],
		"dystopia": Society.dystopia(state, t),
		"palette": ArtPalette.describe(GROUP),
	}
	var ruler := state.chief_of(subject)
	if holder.begins_with("house "):
		facts["banner_of"] = "the %s of the %s" % [holder, subject]
	elif holder.begins_with("ruler ") and ruler != -1:
		facts["banner_of"] = "the rule of %s over the %s" % [state.person_names[ruler], subject]
	if ruler != -1:
		facts["ruler"] = {"name": People.full_name(state, ruler), "traits": Array(People.traits_of(state, ruler))}
	var dark: Array[String] = []
	for law: String in Society.laws_of(state, t):
		if Laws.is_dystopian(law):
			dark.append(Laws.name_of(law))
	if not dark.is_empty():
		facts["dark_laws"] = dark
	var before := String(AssetBook.spec(state, task(), subject).get("motto", ""))
	if before and AssetBook.signature(state, task(), subject) != signature(state, subject):
		facts["old_motto"] = before
	return facts


func accept(reply: Dictionary, facts: Dictionary) -> Variant:
	var motto := String(reply.get("motto", "")).strip_edges().trim_prefix('"').trim_suffix('"').strip_edges()
	if motto.length() < 2 or motto.length() > 60 or motto.contains("<"):
		return null
	var field := ArtPalette.clamp_index(int(reply.get("field", 0)), GROUP)
	var charge := String(reply.get("charge", ""))
	if charge not in EmblemGrammar.CHARGES:
		charge = "star"
	var emblem := SvgGuard.sanitize(String(reply.get("emblem", "")), GROUP)
	if emblem.is_empty():
		# The AI's drawing didn't survive: the game draws its charge instead.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([facts.get("tribe", ""), motto])
		emblem = SvgGuard.sanitize(EmblemGrammar.emblem(charge, EmblemGrammar.contrasting(field, GROUP, rng), field, rng.randi()), GROUP)
	return {"motto": motto, "field": field, "charge": charge, "emblem": _visible(emblem, field)}


func offline(facts: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var leans := _leans(facts)
	var charge := EmblemGrammar.pick(_charge_weights(facts, leans), rng)
	var fields: Array[int] = []
	for lean: String in leans:
		for index: int in CULTURE_FIELDS.get(lean, []):
			fields.append(index)
	if fields.is_empty():
		fields.assign(ArtPalette.GROUPS[GROUP])
	var field: int = fields[rng.randi_range(0, fields.size() - 1)]
	var color := EmblemGrammar.contrasting(field, GROUP, rng)
	var accent := EmblemGrammar.contrasting(color, GROUP, rng, [field])
	var ordinary := EmblemGrammar.ORDINARIES[rng.randi_range(0, EmblemGrammar.ORDINARIES.size() - 1)] if rng.randf() < 0.6 else "none"
	return {
		"motto": _motto(charge, leans, String(facts.get("government", "")), rng),
		"field": field,
		"charge": charge,
		"emblem": EmblemGrammar.emblem(charge, color, accent, rng.randi(), ordinary),
	}


# --- Offline writing ----------------------------------------------------------------

static func _culture(state: WorldState, t: int) -> Dictionary:
	var culture := {}
	for axis: String in Society.CULTURE_AXES:
		culture[axis] = int(state.tribe_culture[t].get(axis, 0))
	return culture


## The culture's strong leans ("piety+", "martial-"...), strongest first, and "dystopia" when dark.
static func _leans(facts: Dictionary) -> Array[String]:
	var culture: Dictionary = facts.get("culture", {})
	var axes := culture.keys()
	axes.sort_custom(func(a: String, b: String) -> bool: return absi(int(culture[a])) > absi(int(culture[b])) or (absi(int(culture[a])) == absi(int(culture[b])) and a < b))
	var leans: Array[String] = []
	if int(facts.get("dystopia", 0)) >= 40:
		leans.append("dystopia")
	for axis: String in axes:
		if absi(int(culture[axis])) >= 20:
			leans.append("%s%s" % [axis, "+" if int(culture[axis]) > 0 else "-"])
	return leans


static func _charge_weights(facts: Dictionary, leans: Array[String]) -> Dictionary:
	var weights := {}
	for charge: String in EmblemGrammar.CHARGES:
		weights[charge] = 0.3
	var add := func(charges: Array, amount: float) -> void:
		for charge: String in charges:
			weights[charge] = float(weights[charge]) + amount
	for lean: String in leans:
		add.call(CULTURE_CHARGES.get(lean, []), 2.0)
	for faction: String in Society.FACTION_NAMES:
		if Society.FACTION_NAMES[faction] == String(facts.get("strongest_faction", "")):
			add.call(FACTION_CHARGES[faction], 2.0)
	add.call(BIOME_CHARGES.get(String(facts.get("island", "")), []), 1.0)
	if "dystopia" in leans:
		add.call(["eye", "tower", "wheel"], 3.0)
	if String(facts.get("banner_of", "")).begins_with("the house"):
		add.call(["crown"], 2.0)
	return weights


static func _motto(charge: String, leans: Array[String], government: String, rng: RandomNumberGenerator) -> String:
	var virtues: Array[String] = []
	for lean: String in leans:
		for virtue: String in VIRTUES.get(lean, []):
			virtues.append(virtue)
	if virtues.size() < 2:
		virtues.append_array(["Courage", "Kinship", "Plenty"])
	var first := virtues[rng.randi_range(0, virtues.size() - 1)]
	var second := virtues[rng.randi_range(0, virtues.size() - 1)]
	while second == first:
		second = virtues[rng.randi_range(0, virtues.size() - 1)]
	var options: Array[String] = ["%s and %s" % [_sentence(first), second.to_lower()], "By %s we endure" % first.to_lower(), "%s above all" % _sentence(first)]
	options.append_array(SAYINGS.get(charge, []))
	match government:
		"Military Junta", "Warband":
			options.append("Strength through %s" % first.to_lower())
		"Theocracy", "Rule of Shamans":
			options.append("The sky wills it")
		"Total State", "Police State":
			options.append("Unity, order, vigilance")
		"Democracy", "Republic", "Assembly":
			options.append("Many voices, one hearth")
	return options[rng.randi_range(0, options.size() - 1)]


static func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


## The emblem with a color that would vanish into the field swapped for one that shows on it.
static func _visible(emblem: String, field: int) -> String:
	var token := '"p%d"' % field
	var used := RegEx.create_from_string('"p(\\d+)"').search_all(emblem)
	for found: RegExMatch in used:
		if found.get_string() != token:
			return emblem # some of it shows
	if used.is_empty():
		return emblem # unpainted: drawn in ink
	var rng := RandomNumberGenerator.new()
	rng.seed = field
	return emblem.replace(token, '"p%d"' % EmblemGrammar.contrasting(field, GROUP, rng))
