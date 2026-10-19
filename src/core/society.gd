class_name Society
extends RefCounted
## Questions about how a tribe is ruled: its laws and culture, who holds power, how free, equal,
## watched and afraid its people are, what kind of government that adds up to, and how far it has
## slid toward a dystopia. Everything here reads WorldState; SocietySystem and CrisisSystem decide
## what happens.
##
## Nothing about a government is chosen from a list. Five factions (the ruler, the council of the
## free, the priests, the warriors and the merchants) each hold some power, built from the laws
## in force, the jobs people do, the buildings standing and who owns the wealth. The government is
## named after whoever comes out on top, in the words of the tribe's age.

## Each tribe's culture is a lean on four axes, -100 to 100. It drifts with its rulers, its laws and
## what happens to it, and it decides which laws the people will bear.
##   hierarchy: equals (-) or ranks (+)    piety: worldly (-) or devout (+)
##   martial: peaceable (-) or warlike (+)  openness: closed and wary (-) or open and curious (+)
const CULTURE_AXES: Array[String] = ["hierarchy", "piety", "martial", "openness"]
const FACTIONS: Array[String] = ["ruler", "council", "priests", "warriors", "merchants"]
const FACTION_NAMES := {"ruler": "the ruler", "council": "the free council", "priests": "the priests", "warriors": "the warriors", "merchants": "the merchants"}
## Loyalty below this makes a dissident.
const DISSENT_AT := 25
## How free a people is with no laws at all, before anyone watches them.
const FREEDOM_BASE := 50.0


# --- Laws ---------------------------------------------------------------------------

static func has_law(state: WorldState, t: int, law: String) -> bool:
	return state.tribe_laws[t].has(law)


## The laws in force, oldest first.
static func laws_of(state: WorldState, t: int) -> Array[String]:
	var found: Array[String] = []
	for law: String in Laws.ORDER:
		if state.tribe_laws[t].has(law):
			found.append(law)
	return found


## The combined effect of a tribe's laws: a product for multiplying effects (default 1), a sum for
## the rest (default 0).
static func effect(state: WorldState, t: int, key: String) -> float:
	var none := 1.0 if key in Laws.MULTIPLY else 0.0
	if t < 0:
		return none
	return float(state.law_sums(t).get(key, none))


static func flag(state: WorldState, t: int, key: String) -> bool:
	return t >= 0 and state.law_sums(t).has(key)


# --- People -------------------------------------------------------------------------

static func adults_of(state: WorldState, t: int) -> Array[int]:
	var tribe := state.tribe_names[t]
	var found: Array[int] = []
	for p: int in state.person_ids.size():
		if state.person_tribes[p] == tribe and People.is_adult(state, p):
			found.append(p)
	return found


## "noble", "bonded" or "commoner".
static func class_of(state: WorldState, p: int) -> String:
	var status := state.person_status[p]
	return status if status else "commoner"


static func is_dissident(state: WorldState, p: int) -> bool:
	return state.person_loyalty[p] < DISSENT_AT and state.person_detained[p] == 0 and People.is_adult(state, p)


static func count_where(state: WorldState, t: int, what: String) -> int:
	var tribe := state.tribe_names[t]
	var count := 0
	for p: int in state.person_ids.size():
		if state.person_tribes[p] != tribe:
			continue
		match what:
			"noble":
				count += 1 if state.person_status[p] == "noble" else 0
			"bonded":
				count += 1 if state.person_status[p] == "bonded" else 0
			"detained":
				count += 1 if state.person_detained[p] > 0 else 0
			"dissident":
				count += 1 if is_dissident(state, p) else 0
	return count


# --- Measures (0 to 100) ------------------------------------------------------------

## How unequal the wealth of the tribe's adults is: the Gini coefficient, as a percentage.
static func inequality(state: WorldState, t: int) -> int:
	var wealth: Array[int] = []
	for p: int in adults_of(state, t):
		wealth.append(maxi(state.person_wealth[p], 0))
	if wealth.size() < 2:
		return 0
	wealth.sort()
	var total := 0.0
	var weighted := 0.0
	for k: int in wealth.size():
		total += wealth[k]
		weighted += (k + 1) * wealth[k]
	if total <= 0.0:
		return 0
	var n := float(wealth.size())
	return clampi(roundi(100.0 * ((2.0 * weighted) / (n * total) - (n + 1.0) / n)), 0, 100)


## How watched and policed people are: the laws, the guards and officials on duty, and the eyes
## the age's machines give them.
static func control(state: WorldState, t: int) -> int:
	var total := float(state.law_sums(t)["control"])
	var work: Dictionary = state.tribe_work[t]
	var enforcers := float(work.get("guard", 0.0)) + 0.6 * float(work.get("official", 0.0))
	var enforcement := minf(enforcers * 300.0 / maxf(state.tribe_population[t], 10.0), 35.0)
	total += enforcement * (1.0 + effect(state, t, "surveillance"))
	return clampi(roundi(total), 0, 100)


## How free people are to speak, move, marry and refuse: the laws, less the bonded and the detained.
static func freedom(state: WorldState, t: int) -> int:
	var total := FREEDOM_BASE + float(state.law_sums(t)["freedom"])
	var population := maxf(state.tribe_population[t], 1.0)
	total -= 40.0 * count_where(state, t, "bonded") / population
	total -= 150.0 * count_where(state, t, "detained") / population
	total -= 0.4 * control(state, t)
	return clampi(roundi(total), 0, 100)


## How far a tribe has slid toward a dystopia: watched, unfree, afraid and unequal, under laws
## built to keep it that way.
static func dystopia(state: WorldState, t: int) -> int:
	var score := 0.35 * control(state, t) + 0.25 * (100 - freedom(state, t)) + 0.2 * state.tribe_fear[t] + 0.2 * inequality(state, t)
	for law: String in state.tribe_laws[t]:
		if Laws.is_dystopian(law):
			score += 4.0
	return clampi(roundi(score - 15.0), 0, 100)


## The kind of darkness a tribe is sliding into: "surveillance", "genetic", "corporate",
## "theocratic", "military" or "tyranny".
static func dystopia_kind(state: WorldState, t: int) -> String:
	if has_law(state, t, "surveillance_net") or has_law(state, t, "social_credit"):
		return "surveillance"
	if has_law(state, t, "birth_permits"):
		return "genetic"
	var top := top_faction(state, t)
	if top == "merchants" or has_law(state, t, "corporate_charter"):
		return "corporate"
	if top == "priests" or has_law(state, t, "state_religion"):
		return "theocratic"
	if top == "warriors":
		return "military"
	return "tyranny"


## Population-weighted dystopia of the whole island, 0 to 1. The view darkens with it.
static func gloom(state: WorldState) -> float:
	var total := 0.0
	var people := 0
	for t: int in state.tribe_count():
		total += dystopia(state, t) * state.tribe_population[t]
		people += state.tribe_population[t]
	return total / maxf(people, 1.0) / 100.0


# --- Power and government -----------------------------------------------------------

static func power(state: WorldState, t: int, faction: String) -> int:
	return int(state.tribe_power[t].get(faction, 0))


static func top_faction(state: WorldState, t: int) -> String:
	var best := "council"
	var best_power := -1
	for faction: String in FACTIONS:
		var value := power(state, t, faction)
		if value > best_power:
			best = faction
			best_power = value
	return best


static func vassals_of(state: WorldState, tribe: String) -> Array[String]:
	var found: Array[String] = []
	for t: int in state.tribe_count():
		if state.tribe_overlord[t] == tribe:
			found.append(state.tribe_names[t])
	return found


static func realm_population(state: WorldState, t: int) -> int:
	var total := state.tribe_population[t]
	for vassal: String in vassals_of(state, state.tribe_names[t]):
		total += state.tribe_population[state.tribe_index(vassal)]
	return total


## What kind of government the tribe has, in the words of its age: "Council of Elders",
## "Kingdom", "Theocracy", "Military Junta", "Corporate State", "Total State"...
static func government(state: WorldState, t: int) -> String:
	var age := state.age_of(t)
	var top := top_faction(state, t)
	if power(state, t, top) < 25:
		return "Band of equals" if state.tribe_population[t] < 30 else "Free tribe"
	match top:
		"council":
			if age == 0:
				return "Council of Elders"
			if not flag(state, t, "elections"):
				return "Council"
			return ["Council of Elders", "Assembly", "Republic", "Republic", "Democracy"][age]
		"ruler":
			if age == 0:
				return "Chiefdom"
			if age >= 4 and has_law(state, t, "surveillance_net"):
				return "Total State"
			if age >= 3 and has_law(state, t, "secret_police"):
				return "Police State"
			if vassals_of(state, state.tribe_names[t]).size() >= 2:
				return "Empire"
			if has_law(state, t, "hereditary_rule"):
				return "Kingdom" if age < 3 else "Monarchy"
			return "Despotate" if age < 3 else "Autocracy"
		"priests":
			return "Rule of Shamans" if age == 0 else "Theocracy"
		"warriors":
			return "Warband" if age == 0 else "Military Junta"
		"merchants":
			return ["Merchant Council", "Merchant Oligarchy", "Merchant Oligarchy", "Plutocracy", "Corporate State"][age]
	return "Tribe"


## How big a polity it has grown into: "Band", "Tribe", "Chiefdom", "City-state", "Kingdom",
## "Nation" or "Empire".
static func scale(state: WorldState, t: int) -> String:
	var age := state.age_of(t)
	var own := state.tribe_population[t]
	var realm := realm_population(state, t)
	var vassals := vassals_of(state, state.tribe_names[t]).size()
	if vassals >= 2:
		return "Empire"
	if age >= 3 and realm >= 100:
		return "Nation"
	if age >= 1 and realm >= 100:
		return "Kingdom"
	if age >= 1 and own >= 45:
		return "City-state"
	if realm >= 60 or vassals >= 1:
		return "Chiefdom"
	return "Tribe" if own >= 25 else "Band"


## The family name of the ruling house, or "" if power isn't inherited.
static func dynasty(state: WorldState, t: int) -> String:
	return state.tribe_dynasty[t]


# --- For the panels and the AI ------------------------------------------------------

## Everything about a tribe's society at a glance.
static func metrics(state: WorldState, t: int) -> Dictionary:
	var population := maxf(state.tribe_population[t], 1.0)
	var adults := adults_of(state, t).size()
	return {
		"age": state.age_of(t),
		"government": government(state, t),
		"scale": scale(state, t),
		"freedom": freedom(state, t),
		"control": control(state, t),
		"inequality": inequality(state, t),
		"fear": state.tribe_fear[t],
		"legitimacy": state.tribe_legitimacy[t],
		"unrest": state.tribe_unrest[t],
		"dystopia": dystopia(state, t),
		"nobles": count_where(state, t, "noble"),
		"bonded": count_where(state, t, "bonded"),
		"detained": count_where(state, t, "detained"),
		"dissidents": count_where(state, t, "dissident"),
		"dissent_share": snappedf(count_where(state, t, "dissident") / maxf(adults, 1.0), 0.01),
		"population": roundi(population),
	}


## Compact view for the AI: the shape of the tribe's society and what is troubling it.
static func summary(state: WorldState, t: int) -> Dictionary:
	var m := metrics(state, t)
	var laws: Array[String] = []
	for law: String in laws_of(state, t):
		laws.append(law)
	var culture := {}
	for axis: String in CULTURE_AXES:
		culture[axis] = int(state.tribe_culture[t].get(axis, 0))
	var result := {
		"age": Knowledge.age_name(int(m["age"])),
		"age_level": m["age"],
		"government": m["government"],
		"scale": m["scale"],
		"strongest_faction": FACTION_NAMES[top_faction(state, t)],
		"laws": laws,
		"culture": culture,
		"freedom": m["freedom"], "control": m["control"], "inequality": m["inequality"], "fear": m["fear"],
		"legitimacy": m["legitimacy"], "unrest": m["unrest"], "dystopia": m["dystopia"],
	}
	if state.tribe_dynasty[t]:
		result["dynasty"] = "house " + state.tribe_dynasty[t]
	if state.tribe_overlord[t]:
		result["vassal_of"] = state.tribe_overlord[t]
	var vassals := vassals_of(state, state.tribe_names[t])
	if not vassals.is_empty():
		result["vassals"] = vassals
	var crisis: Dictionary = state.tribe_crisis[t]
	if not crisis.is_empty():
		result["crisis"] = "%s (%s)" % [String(crisis["type"]).replace("_", " "), String(crisis["stage"]).replace("_", " ")]
	return result
