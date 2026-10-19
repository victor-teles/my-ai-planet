class_name WaterSystem
extends SimSystem
## Rain fills the pond and springs; every tribe drinks from one of them. A source with more
## drinkers than it can serve slowly runs low, and each month a tribe at a sinking source moves
## to the one with the most room, if that one is clearly fuller.

const REFILL := 0.08 ## fullness gained per month at normal rain
const USE := 0.08 ## fullness lost per month when drinkers equal capacity
const MOVE_BELOW := 0.5 ## a tribe whose source is below this fullness looks for another
const MOVE_GAIN := 0.25 ## ...and moves only to one at least this much fuller
const LOW_WATER_QUIET_DAYS := 24 * WorldState.DAYS_PER_MONTH ## a source wobbling around the line is reported once, not every dip


func get_id() -> String:
	return "water"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	for w: int in state.water_names.size():
		var before := state.water_level[w]
		var use := USE * state.drinkers(w) / state.water_capacity[w]
		state.water_level[w] = clampf(before + REFILL * state.rainfall - use, 0.0, 1.0)
		if before >= Needs.LOW_WATER and state.water_level[w] < Needs.LOW_WATER and not _reported_lately(state, state.water_names[w]):
			state.log_event("water_low", {"water": state.water_names[w]})
	# Monthly, not yearly: with people dying of thirst within months, waiting for the new year
	# would let a whole tribe die beside a full spring.
	_move_thirsty_tribes(state)


func _move_thirsty_tribes(state: WorldState) -> void:
	for i: int in state.tribe_count():
		var current := state.tribe_water[i]
		if state.water_level[current] >= MOVE_BELOW:
			continue
		var best := state.roomiest_water()
		var room := state.water_capacity[best] * state.water_level[best] - state.drinkers(best)
		var fuller := state.water_level[best] >= state.water_level[current] + MOVE_GAIN
		if best != current and fuller and room >= state.tribe_population[i] * 0.5:
			state.tribe_water[i] = best
			state.log_event("tribe_moved", {"tribe": state.tribe_names[i], "water": state.water_names[best]})


func _reported_lately(state: WorldState, water_name: String) -> bool:
	for j: int in range(state.events.size() - 1, -1, -1):
		var event := state.events[j]
		if state.tick - int(event["tick"]) >= LOW_WATER_QUIET_DAYS:
			return false
		if event["type"] == "water_low" and event["data"]["water"] == water_name:
			return true
	return false
