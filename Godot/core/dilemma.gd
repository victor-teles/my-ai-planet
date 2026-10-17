class_name Dilemma
extends RefCounted
## A choice put to the player. The AI writes the situation and the choices; each choice is a list of
## effects from a fixed vocabulary that the sim checks and clamps before anything happens.

## effect type -> [min amount, max amount, needs a tribe]
const EFFECTS := {
	"food": [-4.0, 4.0, true], ## months of food for the tribe (+ adds, - takes away)
	"population": [-25.0, 15.0, true], ## percent of the tribe
	"split": [0.0, 0.0, true], ## part of the tribe leaves and founds a new one
	"rain": [-12.0, 12.0, false], ## + months of blessed rain, - months of drought
	"influence": [-3.0, 3.0, false],
	"kindness": [-2.0, 2.0, false],
	"relation": [-40.0, 40.0, true], ## how the card's tribe and this tribe feel about each other
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
	return {"type": type, "tribe": target if rule[2] else "", "amount": amount}


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
	state.log_event("dilemma", {"title": title, "choice": choice["label"]})
	state.settle()


func _apply(state: WorldState, effect: Dictionary) -> void:
	var i := state.tribe_index(effect["tribe"])
	var amount: float = effect["amount"]
	match String(effect["type"]):
		"food":
			if i != -1:
				state.tribe_food[i] = maxf(state.tribe_food[i] + state.tribe_population[i] * amount, 0.0)
		"population":
			if i != -1:
				state.tribe_population[i] = maxi(roundi(state.tribe_population[i] * (1.0 + amount / 100.0)), 1)
		"split":
			if i != -1 and state.tribe_population[i] >= MIN_SPLIT_POPULATION:
				@warning_ignore("integer_division")
				state.split_tribe(i, state.tribe_population[i] / 3)
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
