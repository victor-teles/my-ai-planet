class_name EventText
extends RefCounted
## Turns logged events into words, for the life feed, the pop-ups and the offline chronicle.
## Also sorts them: the big turns of history ("major") versus the small events of daily life.

## Category -> [icon, color]. The feed filters by category.
const CATEGORIES := {
	"birth": ["✶", Color(0.36, 0.62, 0.36)],
	"death": ["✝", Color(0.42, 0.36, 0.46)],
	"love": ["♥", Color(0.85, 0.36, 0.48)],
	"work": ["⚒", Color(0.62, 0.46, 0.28)],
	"building": ["⌂", Color(0.66, 0.48, 0.24)],
	"discovery": ["✦", Color(0.30, 0.50, 0.75)],
	"tribe": ["⚑", Color(0.55, 0.32, 0.62)],
	"conflict": ["⚔", Color(0.80, 0.30, 0.25)],
	"politics": ["⚖", Color(0.62, 0.22, 0.42)],
	"world": ["☁", Color(0.35, 0.50, 0.62)],
	"god": ["✧", Color(0.85, 0.62, 0.18)],
}
const CATEGORY_ORDER: Array[String] = ["birth", "death", "love", "work", "building", "discovery", "tribe", "politics", "conflict", "world", "god"]
const TYPE_CATEGORY := {
	"birth": "birth", "death": "death", "coming_of_age": "birth",
	"romance": "love", "marriage": "love", "proposal_refused": "love", "separation": "love",
	"job": "work", "apprentice": "work", "adoption": "tribe",
	"building_started": "building", "building_done": "building", "building_planned": "building",
	"discovery": "discovery", "tech_spread": "discovery",
	"new_chief": "tribe", "tribe_split": "tribe", "tribes_merged": "tribe", "tribe_extinct": "tribe",
	"tribe_moved": "tribe", "newcomers": "tribe", "gifts": "tribe",
	"war": "conflict", "fight": "conflict", "raid": "conflict", "incident": "conflict",
	"famine": "world", "epidemic": "world", "drought_started": "world", "drought_ended": "world", "water_low": "world",
	"miracle": "god", "dilemma": "god", "prophecy_fulfilled": "god", "prophecy_broken": "god", "destiny": "god",
	"new_age": "discovery", "disaster": "world",
	"law_passed": "politics", "law_repealed": "politics", "law_blocked": "politics", "law_refused": "politics", "new_dynasty": "politics",
	"protests": "politics", "protests_faded": "politics", "concession": "politics", "crackdown": "politics",
	"revolution": "politics", "uprising_crushed": "politics", "rebels_fled": "politics", "coup": "politics",
	"capture": "politics", "prophet": "politics", "prophet_silenced": "politics", "schism": "politics", "reform": "politics",
	"succession_contested": "politics", "succession_settled": "politics", "succession_split": "politics",
	"succession_war": "politics", "arrest": "politics", "exiled": "politics", "election": "politics",
	"nobles_raised": "politics", "bondage": "politics", "freed": "politics",
	"vassal": "conflict", "vassal_revolt": "conflict", "annexed": "tribe",
}
## The turns of history the Oracle and chronicle care about. Everything else is daily life.
const MAJOR: Array[String] = [
	"discovery", "tech_spread", "building_done", "new_chief", "tribe_split", "tribes_merged", "tribe_extinct",
	"tribe_moved", "newcomers", "war", "raid", "incident", "famine", "epidemic", "drought_started", "drought_ended", "water_low",
	"miracle", "dilemma", "prophecy_fulfilled", "prophecy_broken", "gifts",
	"destiny", "new_age", "disaster", "law_passed", "law_repealed", "law_blocked", "new_dynasty", "protests", "concession",
	"crackdown", "revolution", "uprising_crushed", "rebels_fled", "coup", "capture", "prophet", "prophet_silenced", "schism",
	"reform", "succession_contested", "succession_settled", "succession_split", "succession_war", "election", "bondage",
	"vassal", "vassal_revolt", "annexed",
]


static func category(event: Dictionary) -> String:
	var type := String(event["type"])
	if type == "death" and int((event["data"] as Dictionary).get("chief", 0)) == 1:
		return "tribe"
	return String(TYPE_CATEGORY.get(type, "world"))


static func icon(event: Dictionary) -> String:
	return String(CATEGORIES[category(event)][0])


static func color(event: Dictionary) -> Color:
	return CATEGORIES[category(event)][1]


static func is_major(event: Dictionary) -> bool:
	var type := String(event["type"])
	if type == "death":
		var data: Dictionary = event["data"]
		return int(data.get("chief", 0)) == 1 or String(data.get("cause", "")) in ["war", "plague", "the uprising", "the succession war"]
	return type in MAJOR


static func major(events: Array[Dictionary]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in events:
		if is_major(event):
			found.append(event)
	return found


## How many events of each type happened at or after a tick.
static func count_since(events: Array[Dictionary], since_tick: int) -> Dictionary:
	var counts := {}
	for j: int in range(events.size() - 1, -1, -1):
		if int(events[j]["tick"]) < since_tick:
			break
		var type := String(events[j]["type"])
		counts[type] = int(counts.get(type, 0)) + 1
	return counts


## One line for the feed: "Kael and Mirra married by the fire of the Wokowoul."
static func text(event: Dictionary) -> String:
	var data: Dictionary = event["data"]
	match String(event["type"]):
		"birth":
			var parents := "%s and %s" % [_s(data, "mother_name"), _s(data, "father_name")] if _s(data, "father_name") else _s(data, "mother_name")
			var line := "%s was born to %s" % [_s(data, "name"), parents]
			if _s(data, "named_after"):
				line += ", named after %s" % _s(data, "named_after")
			if int(data.get("twin", 0)) == 1:
				line += " (a twin)"
			return line + "."
		"death":
			var who := "Chief %s" % _s(data, "name") if int(data.get("chief", 0)) == 1 else _s(data, "name")
			match _s(data, "cause"):
				"old age":
					return "%s died of old age at %d." % [who, int(data["age"])]
				"childbirth":
					return "%s died giving birth, at %d." % [who, int(data["age"])]
				"war":
					return "%s fell fighting the %s, at %d." % [who, _s(data, "enemy") if _s(data, "enemy") else "enemy", int(data["age"])]
				"accident":
					return "%s was killed in an accident %s, at %d." % [who, _s(data, "while") if _s(data, "while") else "at work", int(data["age"])]
				"a fight":
					return "%s was killed in a fight with %s, at %d." % [who, _s(data, "by"), int(data["age"])]
				"hunger", "thirst", "sickness", "plague":
					return "%s died of %s at %d." % [who, _s(data, "cause"), int(data["age"])]
				"lightning":
					return "%s was struck down by lightning from a clear sky, at %d." % [who, int(data["age"])]
				"the uprising", "the succession war":
					return "%s fell in %s, at %d." % [who, _s(data, "cause"), int(data["age"])]
				"exile":
					return "%s was driven from the island, at %d." % [who, int(data["age"])]
			return "%s died at %d." % [who, int(data.get("age", 0))]
		"coming_of_age":
			return "%s came of age: %s." % [_s(data, "name"), _s(data, "traits")]
		"romance":
			return "%s and %s are falling in love." % [_s(data, "a_name"), _s(data, "b_name")]
		"marriage":
			if _s(data, "moved_from"):
				return "%s left the %s to marry %s of the %s." % [_s(data, "mover_name"), _s(data, "moved_from"), _s(data, "stayer_name"), _s(data, "tribe")]
			return "%s and %s were joined by the fire of the %s." % [_s(data, "a_name"), _s(data, "b_name"), _s(data, "tribe")]
		"proposal_refused":
			return "%s asked %s to share a hearth, and was turned down." % [_s(data, "a_name"), _s(data, "b_name")]
		"separation":
			return "%s and %s parted ways." % [_s(data, "a_name"), _s(data, "b_name")]
		"fight":
			return "%s and %s came to blows." % [_s(data, "a_name"), _s(data, "b_name")]
		"job":
			if int(data.get("first", 0)) == 1:
				return "%s became the first %s of the %s." % [_s(data, "name"), Jobs.name_of(_s(data, "job")), _s(data, "tribe")]
			return "%s %s." % [_s(data, "name"), _s(data, "why") if _s(data, "why") else "became a " + Jobs.name_of(_s(data, "job"))]
		"apprentice":
			return "%s began learning to be a %s from %s." % [_s(data, "name"), Jobs.name_of(_s(data, "job")), _s(data, "teacher")]
		"adoption":
			return "Orphaned, %s was taken in by %s." % [_s(data, "name"), _s(data, "by")]
		"building_planned":
			return "The %s plan a %s and need %s." % [_s(data, "tribe"), Buildings.name_of(_s(data, "building")), _s(data, "needs")]
		"building_started":
			return "The %s began building a %s." % [_s(data, "tribe"), Buildings.name_of(_s(data, "building"))]
		"building_done":
			var line := "The %s finished a %s" % [_s(data, "tribe"), Buildings.name_of(_s(data, "building"))]
			if _s(data, "builders"):
				line += ", built by %s" % _s(data, "builders")
			return line + "."
		"discovery":
			return "%s discovered %s! The %s now have %s." % [_s(data, "name"), Knowledge.name_of(_s(data, "tech")).to_lower(), _s(data, "tribe"), String(Knowledge.TECHS[_s(data, "tech")]["unlocks"])]
		"tech_spread":
			return "The %s learned %s from the %s." % [_s(data, "to"), Knowledge.name_of(_s(data, "tech")).to_lower(), _s(data, "from")]
		"new_chief":
			match _s(data, "reason"):
				"founding":
					return "%s leads the %s." % [_s(data, "name"), _s(data, "tribe")]
				"death":
					return "The %s mourned their chief and chose %s (%s) to lead them." % [_s(data, "tribe"), _s(data, "name"), _s(data, "traits")]
				"council":
					return "The %s gathered and chose %s (%s) as their new chief." % [_s(data, "tribe"), _s(data, "name"), _s(data, "traits")]
				"inheritance":
					return "%s (%s) inherited the seat of the %s." % [_s(data, "name"), _s(data, "traits"), _s(data, "tribe")]
			return "%s now leads the %s." % [_s(data, "name"), _s(data, "tribe")]
		"tribe_split":
			if _s(data, "leader_name"):
				return "%s led %d people away from the %s to found the %s." % [_s(data, "leader_name"), int(data["people"]), _s(data, "from"), _s(data, "to")]
			return "The %s left the %s." % [_s(data, "to"), _s(data, "from")]
		"tribes_merged":
			return "The %s joined the %s (%d people)." % [_s(data, "from"), _s(data, "into"), int(data.get("people", 0))]
		"tribe_extinct":
			return "The %s are gone." % _s(data, "tribe")
		"tribe_moved":
			return "The %s now drink from %s." % [_s(data, "tribe"), _s(data, "water")]
		"newcomers":
			return "%d strangers arrived and joined the %s." % [int(data.get("people", 0)), _s(data, "tribe")]
		"gifts":
			return "Chief %s of the %s sent gifts of food to the %s." % [_s(data, "chief"), _s(data, "from"), _s(data, "to")]
		"war":
			var line := "War! The %s defeated the %s" % [_s(data, "winner"), _s(data, "loser")]
			if int(data.get("deaths", 0)) > 0:
				line += "; %d fell" % int(data["deaths"])
			return line + "."
		"incident":
			return "%s of the %s and %s of the %s fell out over %s." % [_s(data, "a_name"), _s(data, "tribe"), _s(data, "b_name"), _s(data, "other"), _s(data, "what")]
		"raid":
			return "Starving, the %s raided the stores of the %s." % [_s(data, "tribe"), _s(data, "victim")]
		"famine":
			return "The stores of the %s are empty. Hunger has come." % _s(data, "tribe")
		"epidemic":
			return "A fever spreads through the %s: %d are sick." % [_s(data, "tribe"), int(data.get("sick", 0))]
		"drought_started":
			return "The rains fail. A drought begins."
		"drought_ended":
			return "The rains return."
		"water_low":
			return "%s is running low." % _s(data, "water").capitalize()
		"dilemma":
			return "The god decided: %s." % _s(data, "choice")
		"prophecy_fulfilled":
			return "The prophecy came true."
		"prophecy_broken":
			return "The prophecy was broken."
		"miracle":
			match _s(data, "miracle"):
				"rain":
					return "The sky opened: the god sent rain."
				"harvest":
					return "The god blessed the %s with a great harvest." % _s(data, "tribe")
				"drought":
					return "The god held back the rain."
				"plague":
					return "The god sent a plague upon the %s; %d died." % [_s(data, "tribe"), int(data.get("deaths", 0))]
				"muse":
					return "The god whispered to %s of the %s." % [_s(data, "name"), _s(data, "tribe")]
				"smite":
					return "Lightning struck down %s, ruler of the %s." % [_s(data, "name"), _s(data, "tribe")]
				"awaken":
					return "The god opened the eyes of the %s: they see their rulers plainly now." % _s(data, "tribe")
				"sanctify":
					return "The god blessed %s, ruler of the %s, in front of everyone." % [_s(data, "name"), _s(data, "tribe")]
	var political := _politics(event)
	if political:
		return political
	return String(event["type"]).replace("_", " ")


## The lines for the ages, disasters and politics.
static func _politics(event: Dictionary) -> String:
	var data: Dictionary = event["data"]
	var tribe := _s(data, "tribe")
	match String(event["type"]):
		"new_age":
			if int(data.get("first", 0)) == 1:
				return "The %s are the first on the island to enter the %s." % [tribe, _s(data, "name")]
			return "The %s enter the %s." % [tribe, _s(data, "name")]
		"disaster":
			match _s(data, "kind"):
				"storms":
					return "A storm tore down the %s's %s." % [tribe, Buildings.name_of(_s(data, "building"))]
				"quakes":
					return "The earth shook and the %s's %s fell." % [tribe, Buildings.name_of(_s(data, "building"))]
				"locusts":
					return "Locusts stripped the fields of the %s." % tribe
				"blizzards":
					return "A blizzard buried the island; stores and firewood ran short."
			return "Disaster struck the %s." % tribe
		"destiny":
			return "%s: the island's story has found its ending." % _s(data, "name")
		"law_passed":
			var by := " by %s" % _s(data, "name") if _s(data, "name") else ""
			var why := " (%s)" % _s(data, "reason") if _s(data, "reason") else ""
			return "The %s now live under %s, decreed%s%s." % [tribe, Laws.name_of(_s(data, "law")).to_lower(), by, why]
		"law_repealed":
			var why := ": %s" % _s(data, "reason") if _s(data, "reason") else ""
			return "The %s struck down %s%s." % [tribe, Laws.name_of(_s(data, "law")).to_lower(), why]
		"law_blocked":
			return "The council of the %s refused %s's %s." % [tribe, _s(data, "name"), Laws.name_of(_s(data, "law")).to_lower()]
		"law_refused":
			return "%s demanded %s; %s refused them." % [Society.FACTION_NAMES.get(_s(data, "faction"), "The people").capitalize(), Laws.name_of(_s(data, "law")).to_lower(), _s(data, "name") if _s(data, "name") else "the ruler"]
		"new_dynasty":
			return "%s founds house %s: the %s will be ruled by their blood." % [_s(data, "name"), _s(data, "house"), tribe]
		"protests":
			return "%s led the %s into the open, angry at %s." % [_s(data, "name"), tribe, _s(data, "grievance")]
		"protests_faded":
			return "The anger in the %s has cooled." % tribe
		"concession":
			if _s(data, "law"):
				return "%s gave way to the crowd and struck down %s." % [_s(data, "name"), Laws.name_of(_s(data, "law")).to_lower()]
			return "%s gave way to the crowd and opened the stores." % _s(data, "name")
		"crackdown":
			if int(data.get("count", 0)) > 0:
				return "%s's guards broke up the crowds; %s were taken." % [_s(data, "name"), _s(data, "names")]
			return "%s's guards broke up the crowds." % _s(data, "name")
		"revolution":
			var line := "Revolution! %s led the %s against %s, and won" % [_s(data, "leader_name"), tribe, _s(data, "old") if _s(data, "old") else "their rulers"]
			return line + ("; %d fell." % int(data["deaths"]) if int(data.get("deaths", 0)) > 0 else ".")
		"uprising_crushed":
			var line := "The uprising of the %s was crushed" % tribe
			if _s(data, "leader_name"):
				line += "; %s's cause is lost" % _s(data, "leader_name")
			return line + ("; %d fell." % int(data["deaths"]) if int(data.get("deaths", 0)) > 0 else ".")
		"rebels_fled":
			return "%d rebels fled the %s and founded the %s." % [int(data.get("people", 0)), _s(data, "from"), tribe]
		"coup":
			return "Coup! %s and the warriors seized power over the %s%s." % [_s(data, "name"), tribe, " from %s" % _s(data, "old") if _s(data, "old") else ""]
		"capture":
			return "%s, the richest merchant of the %s, bought the seat of power%s." % [_s(data, "name"), tribe, " from %s" % _s(data, "old") if _s(data, "old") else ""]
		"prophet":
			return "%s has begun to preach a new truth among the %s." % [_s(data, "name"), tribe]
		"prophet_silenced":
			return "The priests of the %s silenced the prophet %s." % [tribe, _s(data, "name")]
		"schism":
			return "The prophet %s led %d followers away from the %s to found the %s." % [_s(data, "name"), int(data.get("people", 0)), _s(data, "from"), tribe]
		"reform":
			return "%s's preaching changed the faith of the %s; the old priests lost their hold." % [_s(data, "name"), tribe]
		"succession_contested":
			return "%s claims the seat of the %s from the heir, %s." % [_s(data, "name"), tribe, _s(data, "heir")]
		"succession_settled":
			return "%s holds the seat of the %s; %s bent the knee." % [_s(data, "name"), tribe, _s(data, "rival")]
		"succession_split":
			return "%s would not bend the knee, and led %d away from the %s to found the %s." % [_s(data, "name"), int(data.get("people", 0)), _s(data, "from"), tribe]
		"succession_war":
			return "War of succession in the %s: %s took the seat; %d fell." % [tribe, _s(data, "name"), int(data.get("deaths", 0))]
		"arrest":
			return "%s of the %s was taken into custody %s." % [_s(data, "name"), tribe, _s(data, "why")]
		"exiled":
			if _s(data, "to"):
				return "%s was driven out of the %s %s, and found refuge with the %s." % [_s(data, "name"), tribe, _s(data, "why"), _s(data, "to")]
			return "%s was driven out of the %s %s." % [_s(data, "name"), tribe, _s(data, "why")]
		"election":
			if int(data.get("rigged", 0)) == 1:
				return "%s won the election of the %s again, as always." % [_s(data, "name"), tribe]
			if int(data.get("kept", 0)) == 1:
				return "The %s voted, and kept %s." % [tribe, _s(data, "name")]
			return "The %s voted %s out and %s in." % [tribe, _s(data, "loser"), _s(data, "name")]
		"nobles_raised":
			return "The %s now count %s among their nobles." % [tribe, _s(data, "names")]
		"bondage":
			return "Unable to pay their debts, %s fell into bondage among the %s." % [_s(data, "names"), tribe]
		"freed":
			return "%d bonded people of the %s were set free." % [int(data.get("count", 0)), tribe]
		"vassal":
			return "The %s bowed to the %s and must pay them tribute." % [tribe, _s(data, "overlord")]
		"vassal_revolt":
			if int(data.get("won", 0)) == 1:
				return "The %s rose up against the %s and threw off their rule." % [tribe, _s(data, "overlord")]
			return "The %s rose up against the %s, and were beaten back." % [tribe, _s(data, "overlord")]
		"annexed":
			return "The %s were absorbed into the %s (%d people)." % [_s(data, "from"), tribe, int(data.get("people", 0))]
	return ""


static func _s(data: Dictionary, key: String) -> String:
	return String(data.get(key, ""))


## The person an event is mostly about (to inspect from the feed), or -1.
static func subject(event: Dictionary) -> int:
	var data: Dictionary = event["data"]
	for key: String in ["id", "a", "leader", "mover"]:
		if data.has(key):
			return int(data[key])
	return -1


## The tribe an event happened in, if any (to place its pop-up).
static func tribe_of(event: Dictionary) -> String:
	var data: Dictionary = event["data"]
	for key: String in ["tribe", "to", "loser", "into", "from"]:
		if data.has(key):
			return String(data[key])
	return ""
