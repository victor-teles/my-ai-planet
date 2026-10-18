class_name PosterKind
extends AssetKind
## Propaganda: a poster for every dark law in force, put up on walls, broadcast towers and
## surveillance masts as the law passes, in the regime's own voice. The spec is {"slogan",
## "ground" and "ink" (palette indices for the paper and the print), "emblem" (clean SVG)}.
## Subjects are "tribe|law"; a law passed again, or a new government, gets a new poster.

const GROUP := "heraldry"
## The motif each law's posters show when the AI draws nothing usable (EmblemGrammar charges).
const MOTIFS := {
	"bonded_labor": "hand", "emergency_powers": "tower", "class_marriage": "crown", "state_religion": "sun",
	"factory_discipline": "wheel", "secret_police": "eye", "censorship": "hand", "surveillance_net": "eye",
	"social_credit": "star", "birth_permits": "grain", "corporate_charter": "wheel", "broadcast_propaganda": "wave",
}
## Offline slogans per law. {tribe} and {ruler} are filled in; lines naming a ruler need one.
const SLOGANS := {
	"bonded_labor": ["Work is your debt to the {tribe}", "Every hand owes the hearth", "Toil today, belong tomorrow"],
	"emergency_powers": ["Order first. Freedom later.", "Hard days. Stand together. Obey.", "{ruler} keeps the {tribe} safe"],
	"class_marriage": ["Know your place, love your kind", "Like weds like", "Each class to its own hearth"],
	"state_religion": ["One faith, one hearth", "The sky sees the faithless", "Pray as the {tribe} pray"],
	"factory_discipline": ["The whistle is the law", "Idle hands betray the {tribe}", "More work, more pride"],
	"secret_police": ["Loyal hearts sleep soundly", "Report the restless", "Your neighbor may be listening"],
	"censorship": ["Speak well or not at all", "Approved words only", "Careless words help the enemy"],
	"surveillance_net": ["The Eye keeps you safe", "Nothing hidden, nothing to fear", "Smile: you are seen"],
	"social_credit": ["A good score is a good life", "Earn your place every day", "The worthy are rewarded"],
	"birth_permits": ["Every child by permit", "Plan the family, plan the future", "Fewer cradles, fuller bowls"],
	"corporate_charter": ["What is good for the Company is good for you", "Work. Buy. Belong.", "The Company provides"],
	"broadcast_propaganda": ["One voice for the {tribe}", "Tune in, stay true", "{ruler} speaks for all"],
}
## A regime signs some of its posters in its own words, when there is room.
const SIGN_OFFS := {
	"Military Junta": ["By order of the army.", "Discipline is strength."], "Theocracy": ["The sky wills it.", "Pray and obey."],
	"Total State": ["The State provides.", "Trust the State.", "The State is your family."],
	"Police State": ["The State is watching.", "Order is freedom."], "Corporate State": ["Brought to you by the Company.", "The Company cares."],
	"Kingdom": ["By the crown's command.", "Long live the crown."], "Monarchy": ["By the crown's command.", "Long live the crown."],
	"Empire": ["By imperial decree.", "One empire, one will."],
}
## Paper and print pairs (palette indices) for the offline posters.
const COLORS: Array[Array] = [[22, 30], [31, 24], [27, 17], [16, 23], [30, 22], [17, 31], [6, 27]]
const MAX_SLOGAN := 70


func task() -> String:
	return "poster"


func priority() -> int:
	return 45


func subjects(state: WorldState) -> Array[String]:
	var found: Array[String] = []
	for t: int in state.tribe_count():
		for law: String in Society.laws_of(state, t):
			if Laws.is_dystopian(law):
				found.append("%s|%s" % [state.tribe_names[t], law])
	return found


func signature(state: WorldState, subject: String) -> String:
	var parts := subject.split("|")
	var t := state.tribe_index(parts[0])
	if parts.size() != 2 or t == -1 or not Society.has_law(state, t, parts[1]):
		return ""
	return "passed %d|%s" % [int(state.tribe_laws[t][parts[1]]), Society.government(state, t)]


func context(state: WorldState, subject: String) -> Dictionary:
	var parts := subject.split("|")
	var law := parts[1] if parts.size() > 1 else ""
	var facts := {"tribe": parts[0], "law": law, "law_name": Laws.name_of(law), "palette": ArtPalette.describe(GROUP)}
	if Laws.LAWS.has(law):
		facts["what_it_does"] = String(Laws.LAWS[law]["description"])
	var t := state.tribe_index(parts[0])
	if t == -1:
		return facts
	facts["government"] = Society.government(state, t)
	facts["age"] = Knowledge.age_name(state.age_of(t))
	facts["darkness"] = Society.dystopia_kind(state, t)
	facts["fear"] = state.tribe_fear[t]
	var ruler := state.chief_of(parts[0])
	if ruler != -1:
		facts["ruler"] = state.person_names[ruler]
	if state.tribe_dynasty[t]:
		facts["house"] = state.tribe_dynasty[t]
	var motto := String(AssetBook.spec(state, "heraldry", parts[0]).get("motto", ""))
	if motto:
		facts["regime_motto"] = motto
	return facts


func accept(reply: Dictionary, facts: Dictionary) -> Variant:
	var slogan := String(reply.get("slogan", "")).strip_edges().trim_prefix('"').trim_suffix('"').strip_edges()
	if slogan.length() < 3 or slogan.length() > MAX_SLOGAN or slogan.contains("<"):
		return null
	var ground := ArtPalette.clamp_index(int(reply.get("ground", 0)), GROUP)
	var ink := ArtPalette.clamp_index(int(reply.get("ink", 0)), GROUP)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([facts.get("tribe", ""), facts.get("law", ""), slogan])
	if absf(EmblemGrammar.lightness(ground) - EmblemGrammar.lightness(ink)) < 0.2:
		ink = EmblemGrammar.contrasting(ground, GROUP, rng) # print the paper can't hide
	var emblem := SvgGuard.sanitize(String(reply.get("emblem", "")), GROUP)
	if emblem.is_empty():
		emblem = SvgGuard.sanitize(EmblemGrammar.emblem(String(MOTIFS.get(facts.get("law", ""), "star")), ink, ground, rng.randi()), GROUP)
	return {"slogan": slogan, "ground": ground, "ink": ink, "emblem": emblem}


func offline(facts: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var law := String(facts.get("law", ""))
	var lines: Array[String] = []
	for line: String in SLOGANS.get(law, ["Obey and prosper"]):
		if facts.has("ruler") or not line.contains("{ruler}"):
			lines.append(line)
	var slogan := lines[rng.randi_range(0, lines.size() - 1)].format({"tribe": facts.get("tribe", ""), "ruler": facts.get("ruler", "")})
	var sign_offs: Array = SIGN_OFFS.get(String(facts.get("government", "")), [""])
	var sign_off := String(sign_offs[rng.randi_range(0, sign_offs.size() - 1)])
	if sign_off and rng.randf() < 0.25 and slogan.length() + sign_off.length() + 1 <= MAX_SLOGAN:
		slogan = "%s%s %s" % [slogan, "" if slogan.ends_with(".") else ".", sign_off]
	var colors: Array = COLORS[rng.randi_range(0, COLORS.size() - 1)]
	return {
		"slogan": slogan,
		"ground": colors[0],
		"ink": colors[1],
		"emblem": EmblemGrammar.emblem(String(MOTIFS.get(law, "star")), colors[1], colors[0], rng.randi()),
	}
