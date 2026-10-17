class_name Citizens
extends RefCounted
## The named people of the valley: one notable citizen for every few people, so each figure
## walking around a camp is someone with a name, an age and two traits. The oldest citizen of
## a tribe is its chief, and the chief's traits steer how the tribe lives.

const PEOPLE_PER_CITIZEN := 6
const MAX_PER_TRIBE := 14
const COMING_OF_AGE_MIN := 16 ## years old when a citizen becomes notable
const COMING_OF_AGE_MAX := 30

## What a trait does when its owner leads the tribe. Missing keys mean no effect.
##   relation: added to the tribe's relation with every other tribe each year
##   war: strength in war (multiplier)    gather: food gathered (multiplier)
##   starve: starvation deaths (multiplier)    split: chance to split (multiplier)
##   faith: Influence the god earns per year
const TRAITS := {
	"brave": {"war": 1.25, "description": "Fights hard: the tribe is stronger in war."},
	"fierce": {"relation": -2, "war": 1.15, "description": "Quick to anger: neighbors cool toward the tribe."},
	"kind": {"relation": 2, "description": "Welcomes strangers: neighbors warm to the tribe."},
	"cheerful": {"relation": 1, "description": "Laughs easily: neighbors like the tribe a little more."},
	"wise": {"starve": 0.6, "description": "Rations well: fewer die in hungry months."},
	"proud": {"relation": -1, "split": 0.5, "description": "Holds the tribe together, but looks down on others."},
	"curious": {"split": 1.6, "description": "Dreams of the far hills: the young leave sooner."},
	"devout": {"faith": 0.04, "description": "Prays often: the god gains more Influence."},
	"greedy": {"gather": 1.06, "relation": -1, "description": "Hoards: more food, fewer friends."},
	"lazy": {"gather": 0.93, "description": "Rests often: the tribe gathers less."},
}
const TRAIT_ORDER: Array[String] = ["brave", "fierce", "kind", "cheerful", "wise", "proud", "curious", "devout", "greedy", "lazy"]


## How many notable citizens a tribe of this size has (also the number of figures drawn).
static func target_count(population: int) -> int:
	return clampi(ceili(float(population) / PEOPLE_PER_CITIZEN), 1, MAX_PER_TRIBE)


static func random_traits(rng: SimRng) -> PackedStringArray:
	var first := rng.pick_index(TRAIT_ORDER.size())
	var second := (first + 1 + rng.pick_index(TRAIT_ORDER.size() - 1)) % TRAIT_ORDER.size()
	return PackedStringArray([TRAIT_ORDER[first], TRAIT_ORDER[second]])


static func traits_of(state: WorldState, c: int) -> PackedStringArray:
	return state.citizen_traits[c].split("|")


static func age(state: WorldState, c: int) -> int:
	return WorldState.year_of(state.tick - state.citizen_born[c])


## Index of the tribe's chief (its oldest citizen), or -1 if it has no citizens.
static func chief(state: WorldState, tribe_name: String) -> int:
	var best := -1
	for c: int in state.citizen_ids.size():
		if state.citizen_tribes[c] == tribe_name and (best == -1 or state.citizen_born[c] < state.citizen_born[best]):
			best = c
	return best


## The combined effect of a tribe chief's traits: a multiplier (default 1) or a sum (default 0).
static func chief_effect(state: WorldState, tribe_name: String, effect: String) -> float:
	var leader := chief(state, tribe_name)
	var multiply := effect in ["war", "gather", "starve", "split"]
	var total := 1.0 if multiply else 0.0
	if leader == -1:
		return total
	for trait_id: String in traits_of(state, leader):
		var value := float(TRAITS[trait_id].get(effect, 1.0 if multiply else 0.0))
		total = total * value if multiply else total + value
	return total


static func index_of(state: WorldState, id: int) -> int:
	return Array(state.citizen_ids).find(id)


## Everything worth knowing about a citizen, for the inspector and the AI.
static func describe(state: WorldState, c: int) -> Dictionary:
	var tribe_name := state.citizen_tribes[c]
	var t := state.tribe_index(tribe_name)
	var needs := {}
	for need: String in Needs.NAMES:
		needs[need] = snappedf(Needs.get_need(state, t, need), 0.01)
	var neighbors: Array[Dictionary] = []
	for other: String in state.tribe_names:
		var value := state.relation(tribe_name, other)
		if other != tribe_name and value != 0:
			neighbors.append({"tribe": other, "relation": value, "word": WorldState.relation_word(value)})
	neighbors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absi(a["relation"]) > absi(b["relation"]))
	var recent: Array[Dictionary] = []
	for event: Dictionary in state.events.slice(maxi(state.events.size() - 8, 0)):
		recent.append({"year": WorldState.year_of(int(event["tick"])), "type": event["type"], "data": event["data"]})
	var water := state.tribe_water[t]
	return {
		"name": state.citizen_names[c],
		"age": age(state, c),
		"is_chief": chief(state, tribe_name) == c,
		"traits": Array(traits_of(state, c)),
		"tribe": tribe_name,
		"tribe_population": state.tribe_population[t],
		"needs": needs,
		"mood": Needs.mood_word(Needs.mood(state, t)),
		"drinks_from": state.water_names[water],
		"water_fullness": snappedf(state.water_level[water], 0.01),
		"neighbors": neighbors,
		"in_drought": state.drought_months_left > 0,
		"god_kindness": state.kindness,
		"year": state.year(),
		"recent_events": recent,
	}
