class_name WaterSystem
extends SimSystem
## Rain fills the pond and springs; every tribe drinks from one of them. A source with more
## drinkers than it can serve slowly runs low, and once a year a thirsty tribe moves to the
## source with the most room.

const REFILL := 0.08 ## fullness gained per month at normal rain
const USE := 0.08 ## fullness lost per month when drinkers equal capacity
const MOVE_BELOW := 0.6 ## a tribe whose water need is below this looks for another source


func get_id() -> String:
	return "water"


func update(state: WorldState) -> void:
	for w: int in state.water_names.size():
		var before := state.water_level[w]
		var use := USE * state.drinkers(w) / state.water_capacity[w]
		state.water_level[w] = clampf(before + REFILL * state.rainfall - use, 0.0, 1.0)
		if before >= Needs.LOW_WATER and state.water_level[w] < Needs.LOW_WATER:
			state.log_event("water_low", {"water": state.water_names[w]})
	if state.month() == 0:
		_move_thirsty_tribes(state)


func _move_thirsty_tribes(state: WorldState) -> void:
	for i: int in state.tribe_count():
		if Needs.water(state, i) >= MOVE_BELOW:
			continue
		var best := state.roomiest_water()
		var room := state.water_capacity[best] * state.water_level[best] - state.drinkers(best)
		if best != state.tribe_water[i] and room >= state.tribe_population[i]:
			state.tribe_water[i] = best
			state.log_event("tribe_moved", {"tribe": state.tribe_names[i], "water": state.water_names[best]})
