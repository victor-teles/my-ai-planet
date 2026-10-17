class_name RelationsSystem
extends SimSystem
## Once a year the tribes' feelings for each other shift: old feelings fade, sharing a full
## spring makes neighbors, sharing a failing one makes rivals, and the hungry envy the fed.
## Rivals may go to war; friends may merge when one of them has grown too small to stand alone.

const FADE := 2 ## relations drift this much toward 0 every year
const SHARED_WATER_GOOD := 2
const SHARED_WATER_BAD := -8
const ENVY := -4 ## a hungry tribe toward a well-fed one
const CONTENT_TOGETHER := 1
const WAR_AT := -50
const WAR_CHANCE := 0.2
const WAR_LOSER_SHARE := 0.15
const WAR_WINNER_SHARE := 0.06
const WAR_PLUNDER_MONTHS := 3.0
const WAR_EXHAUSTION := 40 ## a war releases some of the hatred that started it
const MERGE_AT := 30
const MERGE_CHANCE := 0.35
const MERGE_SMALL := 25 ## a tribe this small (or a quarter of its friend's size) may join its friend


func get_id() -> String:
	return "relations"


func get_interval() -> int:
	return WorldState.MONTHS_PER_YEAR


func update(state: WorldState) -> void:
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			_drift(state, i, j)
	_wars(state)
	_merges(state)


func _drift(state: WorldState, i: int, j: int) -> void:
	var a := state.tribe_names[i]
	var b := state.tribe_names[j]
	var value := state.relation(a, b)
	value -= signi(value) * mini(absi(value), FADE)
	if state.tribe_water[i] == state.tribe_water[j]:
		value += SHARED_WATER_GOOD if Needs.water(state, i) >= 1.0 else SHARED_WATER_BAD
	var food_i := Needs.food(state, i)
	var food_j := Needs.food(state, j)
	if (food_i < 0.4 and food_j > 0.8) or (food_j < 0.4 and food_i > 0.8):
		value += ENVY
	elif food_i > 0.8 and food_j > 0.8:
		value += CONTENT_TOGETHER
	state.set_relation(a, b, value)


## Pairs whose relation is at or below `limit` (or at or above it when `above`), as name pairs,
## so tribes vanishing mid-loop can't shift the indexes under us.
func _pairs(state: WorldState, limit: int, above: bool) -> Array[PackedStringArray]:
	var pairs: Array[PackedStringArray] = []
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			var value := state.relation(state.tribe_names[i], state.tribe_names[j])
			if (value >= limit) if above else (value <= limit):
				pairs.append(PackedStringArray([state.tribe_names[i], state.tribe_names[j]]))
	return pairs


func _wars(state: WorldState) -> void:
	for pair: PackedStringArray in _pairs(state, WAR_AT, false):
		var i := state.tribe_index(pair[0])
		var j := state.tribe_index(pair[1])
		if i == -1 or j == -1 or not state.rng.chance(WAR_CHANCE):
			continue
		var strength_i := state.tribe_population[i] * (0.75 + 0.5 * state.rng.randf())
		var strength_j := state.tribe_population[j] * (0.75 + 0.5 * state.rng.randf())
		var winner := i if strength_i >= strength_j else j
		var loser := j if winner == i else i
		var loser_deaths := ceili(state.tribe_population[loser] * WAR_LOSER_SHARE)
		var winner_deaths := ceili(state.tribe_population[winner] * WAR_WINNER_SHARE)
		var plunder := minf(state.tribe_food[loser], state.tribe_population[loser] * WAR_PLUNDER_MONTHS)
		state.tribe_population[loser] -= loser_deaths
		state.tribe_population[winner] -= winner_deaths
		state.tribe_food[loser] -= plunder
		state.tribe_food[winner] += plunder
		state.change_relation(pair[0], pair[1], WAR_EXHAUSTION)
		state.log_event("war", {
			"winner": state.tribe_names[winner], "loser": state.tribe_names[loser],
			"deaths": loser_deaths + winner_deaths,
		})
		for k: int in [maxi(i, j), mini(i, j)]:
			if state.tribe_population[k] <= 0:
				state.log_event("tribe_extinct", {"tribe": state.tribe_names[k]})
				state.remove_tribe(k)


func _merges(state: WorldState) -> void:
	for pair: PackedStringArray in _pairs(state, MERGE_AT, true):
		var i := state.tribe_index(pair[0])
		var j := state.tribe_index(pair[1])
		if i == -1 or j == -1:
			continue
		var big := i if state.tribe_population[i] >= state.tribe_population[j] else j
		var small := j if big == i else i
		var small_enough := state.tribe_population[small] <= maxf(MERGE_SMALL, state.tribe_population[big] / 4.0)
		if not small_enough or not state.rng.chance(MERGE_CHANCE):
			continue
		var people := state.tribe_population[small]
		state.tribe_population[big] += people
		state.tribe_food[big] += state.tribe_food[small]
		state.log_event("tribes_merged", {"from": state.tribe_names[small], "into": state.tribe_names[big], "people": people})
		state.remove_tribe(small)
