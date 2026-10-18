class_name Dilemma
extends RefCounted
## A choice put to the player. The AI writes the situation and the choices; each choice is a list of
## effects from a fixed vocabulary that the sim checks and clamps before anything happens.

## effect type -> [min amount, max amount, needs a tribe]
const EFFECTS := {
	"food": [-4.0, 4.0, true], ## months of food for the tribe (+ adds, - takes away)
	"population": [-25.0, 15.0, true], ## percent of the tribe: strangers join (+) or sickness takes them (-)
	"split": [0.0, 0.0, true], ## part of the tribe leaves and founds a new one
	"rain": [-12.0, 12.0, false], ## + months of blessed rain, - months of drought
	"influence": [-3.0, 3.0, false],
	"kindness": [-2.0, 2.0, false],
	"relation": [-40.0, 40.0, true], ## how the card's tribe and this tribe feel about each other
	"law": [-1.0, 1.0, true], ## 1 puts the effect's "law" in force in the tribe (if its age allows), -1 strikes it down
	"unrest": [-30.0, 30.0, true],
	"legitimacy": [-30.0, 30.0, true], ## how much the tribe accepts its rulers
}
const MIN_SPLIT_POPULATION := 20

var title: String = ""
var situation: String = ""
var tribe: String = "" ## the tribe the dilemma is about, or "" for the whole valley
## [{"label", "hint", "effects": [{"type", "tribe", "amount"}]}]
var choices: Array[Dictionary] = []


## Turns an AI proposal into a dilemma, or returns null if it can't be played in this world.
## Effects naming tribes that don't exist are dropped; amounts are clamped.
static func from_proposal(proposal: Dictionary, state: WorldState) -> Dilemma:
	var dilemma := Dilemma.new()
	dilemma.title = String(proposal.get("title", "")).strip_edges()
	dilemma.situation = String(proposal.get("situation", "")).strip_edges()
	dilemma.tribe = String(proposal.get("tribe", ""))
	if dilemma.tribe and state.tribe_index(dilemma.tribe) == -1:
		return null
	for raw: Variant in proposal.get("choices", []):
		if not raw is Dictionary:
			continue
		var effects: Array[Dictionary] = []
		for effect: Variant in raw.get("effects", []):
			var clean := _clean_effect(effect, state, dilemma.tribe)
			if not clean.is_empty():
				effects.append(clean)
		var label := String(raw.get("label", "")).strip_edges()
		if label:
			dilemma.choices.append({"label": label, "hint": String(raw.get("hint", "")).strip_edges(), "effects": effects})
	if dilemma.title.is_empty() or dilemma.situation.is_empty() or dilemma.choices.size() < 2:
		return null
	return dilemma


static func _clean_effect(effect: Variant, state: WorldState, card_tribe: String) -> Dictionary:
	if not effect is Dictionary or not EFFECTS.has(effect.get("type")):
		return {}
	var type := String(effect["type"])
	var rule: Array = EFFECTS[type]
	var target := String(effect.get("tribe", ""))
	if rule[2] and state.tribe_index(target) == -1:
		return {}
	if type == "relation" and (card_tribe.is_empty() or card_tribe == target):
		return {}
	var amount := clampf(float(effect.get("amount", 0.0)), rule[0], rule[1])
	var clean := {"type": type, "tribe": target if rule[2] else "", "amount": amount}
	if type == "law":
		var law := String(effect.get("law", ""))
		if not Laws.LAWS.has(law) or amount == 0.0:
			return {}
		clean["law"] = law
	return clean


## True if every tribe this dilemma mentions still exists (worlds move on while the AI writes).
func still_valid(state: WorldState) -> bool:
	if tribe and state.tribe_index(tribe) == -1:
		return false
	for choice: Dictionary in choices:
		for effect: Dictionary in choice["effects"]:
			if effect["tribe"] and state.tribe_index(effect["tribe"]) == -1:
				return false
	return true


## Applies a choice's effects and logs it, so the chronicle can cite the decision.
func choose(state: WorldState, index: int) -> void:
	var choice: Dictionary = choices[clampi(index, 0, choices.size() - 1)]
	for effect: Dictionary in choice["effects"]:
		_apply(state, effect)
	state.record_intervention(leaning(choice))
	state.log_event("dilemma", {"title": title, "choice": choice["label"]})
	state.settle()


## How merciful (> 0) or wrathful (< 0) a choice is, -2 to 2, for the god's disposition: gifts of
## food, people and rain and kind deeds are mercy; taking them, cruelty and dark laws are wrath.
static func leaning(choice: Dictionary) -> int:
	var score := 0
	for effect: Dictionary in choice["effects"]:
		var amount: float = effect["amount"]
		match String(effect["type"]):
			"food", "population", "rain", "kindness":
				score += signi(roundi(amount))
			"law":
				if Laws.is_dystopian(String(effect.get("law", ""))):
					score -= signi(roundi(amount))
	return clampi(score, -2, 2)


func _apply(state: WorldState, effect: Dictionary) -> void:
	var i := state.tribe_index(effect["tribe"])
	var amount: float = effect["amount"]
	match String(effect["type"]):
		"food":
			if i != -1:
				state.tribe_food[i] = maxf(state.tribe_food[i] + state.tribe_population[i] * amount * WorldState.DAYS_PER_MONTH, 0.0)
		"population":
			if i != -1:
				var change := roundi(state.tribe_population[i] * amount / 100.0)
				if change > 0:
					newcomers(state, effect["tribe"], change)
				else:
					_sickness(state, effect["tribe"], mini(-change, state.tribe_population[i] - 1))
		"split":
			if i != -1 and state.tribe_population[i] >= MIN_SPLIT_POPULATION and state.has_room_for_tribe():
				RelationsSystem.split_by_choice(state, i)
		"rain":
			if amount > 0.0:
				state.drought_months_left = 0
				state.blessed_rain_months = roundi(amount)
			elif amount < 0.0:
				state.blessed_rain_months = 0
				state.drought_months_left = maxi(state.drought_months_left, roundi(-amount))
		"influence":
			state.influence = clampf(state.influence + amount, 0.0, WorldState.MAX_INFLUENCE)
		"kindness":
			state.kindness += roundi(amount)
		"relation":
			if i != -1 and state.tribe_index(tribe) != -1:
				state.change_relation(tribe, effect["tribe"], roundi(amount))
		"law":
			if i == -1:
				return
			var law := String(effect["law"])
			if amount > 0.0 and law in SocietySystem.available(state, i):
				SocietySystem.enact(state, i, law, "the god willed it")
			elif amount < 0.0:
				SocietySystem.repeal(state, i, law, "the god willed it")
		"unrest":
			if i != -1:
				state.tribe_unrest[i] = clampi(state.tribe_unrest[i] + roundi(amount), 0, 100)
		"legitimacy":
			if i != -1:
				state.tribe_legitimacy[i] = clampi(state.tribe_legitimacy[i] + roundi(amount), 0, 100)


## Strangers from beyond the hills join a tribe: young adults with fresh blood.
static func newcomers(state: WorldState, tribe_name: String, count: int) -> void:
	var ancestry := state.rng.pick_index(Genetics.ANCESTRIES.size())
	for k: int in count:
		var born := state.tick - state.rng.randi_range(16, 32) * WorldState.DAYS_PER_YEAR - state.rng.randi_range(0, WorldState.DAYS_PER_YEAR - 1)
		var p := state.add_person(tribe_name, "f" if state.rng.chance(0.5) else "m", born, Genetics.founder(state.rng, ancestry), -1, -1, NameGen.family_name(state.rng), NameGen.person_name(state.rng))
		People.form_traits(state, p)
		state.person_health[p] = People.max_health(state.person_genomes[p], People.age(state, p))
		state.life(state.person_ids[p], "Came from beyond the hills and joined the %s." % tribe_name, "tribe")
	state.log_event("newcomers", {"tribe": tribe_name, "people": count})
	WorkSystem.settle_homes(state, state.tribe_index(tribe_name))


## A sickness takes the weakest.
static func _sickness(state: WorldState, tribe_name: String, count: int) -> void:
	for k: int in count:
		var weakest := -1
		for p: int in state.people_of(tribe_name):
			if weakest == -1 or state.person_health[p] < state.person_health[weakest]:
				weakest = p
		if weakest == -1:
			return
		state.kill_person(weakest, "sickness")
