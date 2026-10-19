class_name DestinySystem
extends SimSystem
## Where the island's long story ends. Once a tribe has reached Smoke & Steam, each year the sim
## asks what the island's greatest realm has become; when the same answer holds for long enough,
## that is the island's destiny, and the Oracle writes its last chronicle. The world keeps living
## afterwards, but its story has been told.
##
## Most destinies are dark, because the road there is easy: watch everyone, own everything, purify
## the blood, obey the faith or the army. One is free. One is ashes.

const HOLD_YEARS := 12
## Wealth inequality (a Gini, 0 to 100) the Free Commons can live with, and that makes a Gilded Cage.
## Even the freest realms in the balance runs sit at 35 to 41: merchants and factories make some rich.
const FREE_INEQUALITY := 40
const GILDED_INEQUALITY := 55
## Fear that makes rule by the army (the warriors on top, or in the Wired Age a ruler leaning on a
## standing army) an Iron Fist. Fear fades 2 a month to what the laws keep
## alive, so this needs a junta that also polices (or a god the people dread).
const IRON_FIST_FEAR := 40
## kind -> {"name", "age" (the least age it can happen in), "dark", "text"}
const KINDS := {
	"panopticon": {"name": "The Panopticon", "age": 4, "dark": true,
		"text": "Every street has an eye and every word a record. Nobody is beaten; nobody needs to be."},
	"gilded_cage": {"name": "The Gilded Cage", "age": 4, "dark": true,
		"text": "The companies own the homes, the work and the news. The few are richer than any king; the many are customers."},
	"bloodline": {"name": "The Perfect Bloodline", "age": 4, "dark": true,
		"text": "The state reads every couple's blood and decides who is born. The frail are gone, and so is something else."},
	"holy_order": {"name": "The Holy Order", "age": 3, "dark": true,
		"text": "One faith, one voice, one truth. Doubt is a crime, and the priests are never wrong."},
	"iron_fist": {"name": "The Iron Fist", "age": 3, "dark": true,
		"text": "The generals rule, the soldiers watch, and everyone else keeps their head down."},
	"free_commons": {"name": "The Free Commons", "age": 4, "dark": false,
		"text": "Machines and votes in every hand. Nobody owns anybody, and the island argues freely about what comes next."},
	"ashes": {"name": "Ashes", "age": 0, "dark": true,
		"text": "The smoke, the wars and the hunger did what no god could. The island is quiet now."},
}
const ORDER: Array[String] = ["panopticon", "gilded_cage", "bloodline", "holy_order", "iron_fist", "free_commons", "ashes"]


func get_id() -> String:
	return "destiny"


func get_interval() -> int:
	return WorldState.DAYS_PER_YEAR


func update(state: WorldState) -> void:
	if not state.destiny.is_empty():
		return
	if state.total_population() == 0 and state.year() > 0:
		_fulfil(state, "ashes", "")
		return
	var t := greatest_realm(state)
	if t == -1:
		return
	var tribe := state.tribe_names[t]
	var age := state.age_of(t)
	var now := conditions(state, t)
	for kind: String in ORDER:
		var held := int(state.destiny_progress.get(kind, 0))
		if kind in now and age >= int(KINDS[kind]["age"]):
			state.destiny_progress[kind] = held + 1
			if held + 1 >= HOLD_YEARS:
				_fulfil(state, kind, tribe)
				return
		elif held > 0:
			state.destiny_progress.erase(kind)


## The tribe with the most people in its realm (itself and its vassals), or -1.
static func greatest_realm(state: WorldState) -> int:
	var best := -1
	var most := 0
	for t: int in state.tribe_count():
		if state.tribe_overlord[t]:
			continue
		var people := Society.realm_population(state, t)
		if people > most:
			best = t
			most = people
	return best


## The destinies a tribe looks headed for right now.
static func conditions(state: WorldState, t: int) -> Array[String]:
	var m := Society.metrics(state, t)
	var found: Array[String] = []
	var top := Society.top_faction(state, t)
	if (Society.has_law(state, t, "surveillance_net") or Society.has_law(state, t, "social_credit")) and int(m["control"]) >= 75 and int(m["freedom"]) <= 25:
		found.append("panopticon")
	if (Society.has_law(state, t, "corporate_charter") or top == "merchants") and int(m["inequality"]) >= GILDED_INEQUALITY:
		found.append("gilded_cage")
	if Society.has_law(state, t, "birth_permits") and int(m["dystopia"]) >= 50:
		found.append("bloodline")
	if top == "priests" and Society.has_law(state, t, "state_religion") and int(m["freedom"]) <= 30:
		found.append("holy_order")
	var army_rules := top == "warriors" or (top == "ruler" and Society.has_law(state, t, "standing_army") and state.age_of(t) >= 4)
	if army_rules and int(m["fear"]) >= IRON_FIST_FEAR:
		found.append("iron_fist")
	if int(m["freedom"]) >= 75 and int(m["inequality"]) <= FREE_INEQUALITY and int(m["dystopia"]) <= 20 and Society.flag(state, t, "elections"):
		found.append("free_commons")
	if state.pollution >= 85.0 and state.total_population() < 40:
		found.append("ashes")
	return found


## How close each destiny is: kind -> years held so far (of HOLD_YEARS). For the panels.
static func progress(state: WorldState) -> Dictionary:
	return state.destiny_progress.duplicate()


static func _fulfil(state: WorldState, kind: String, tribe: String) -> void:
	state.destiny = {"kind": kind, "tribe": tribe, "year": state.year()}
	state.log_event("destiny", {"kind": kind, "tribe": tribe, "name": String(KINDS[kind]["name"])})


static func name_of(kind: String) -> String:
	return String(KINDS[kind]["name"]) if KINDS.has(kind) else kind
