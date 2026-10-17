class_name CitizenSystem
extends SimSystem
## Once a year citizens grow older and some die (sooner in hard times); new ones come of age
## until each tribe has as many as its size calls for. When a chief dies, the next oldest leads.

const OLD_AGE := 45 ## years; past this the yearly chance of dying climbs
const OLD_AGE_RISK := 0.015 ## added yearly death chance for each year past OLD_AGE
const BASE_RISK := 0.01
const HARDSHIP_RISK := 0.04 ## added when the tribe's worst need is nearly unmet


func get_id() -> String:
	return "citizens"


func get_interval() -> int:
	return WorldState.MONTHS_PER_YEAR


func update(state: WorldState) -> void:
	var chiefs := {}
	for tribe_name: String in state.tribe_names:
		var leader := Citizens.chief(state, tribe_name)
		chiefs[tribe_name] = state.citizen_ids[leader] if leader != -1 else -1
	_deaths(state)
	for t: int in state.tribe_count():
		_fill(state, t)
	for tribe_name: String in state.tribe_names:
		var leader := Citizens.chief(state, tribe_name)
		if leader != -1 and chiefs.get(tribe_name, -1) != state.citizen_ids[leader]:
			state.log_event("new_chief", {
				"tribe": tribe_name, "name": state.citizen_names[leader],
				"traits": state.citizen_traits[leader].replace("|", ", "),
			})


func _deaths(state: WorldState) -> void:
	for c: int in range(state.citizen_ids.size() - 1, -1, -1):
		var t := state.tribe_index(state.citizen_tribes[c])
		var risk := BASE_RISK + maxf(Citizens.age(state, c) - OLD_AGE, 0.0) * OLD_AGE_RISK
		var worst := 1.0
		for need: String in Needs.NAMES:
			worst = minf(worst, Needs.get_need(state, t, need))
		if worst < 0.2:
			risk += HARDSHIP_RISK
		if state.rng.chance(risk):
			if Citizens.chief(state, state.citizen_tribes[c]) == c:
				state.log_event("chief_died", {"tribe": state.citizen_tribes[c], "name": state.citizen_names[c], "age": Citizens.age(state, c)})
			state.remove_citizen(c)


## Adds citizens coming of age, or (after a tribe shrinks) lets the youngest fade from the story.
func _fill(state: WorldState, t: int) -> void:
	var tribe_name := state.tribe_names[t]
	var members := state.citizens_of(tribe_name)
	var target := Citizens.target_count(state.tribe_population[t])
	for k: int in range(members.size(), target):
		state.add_citizen(tribe_name, state.rng.randi_range(Citizens.COMING_OF_AGE_MIN, Citizens.COMING_OF_AGE_MAX))
	if members.size() > target:
		members.sort_custom(func(a: int, b: int) -> bool: return state.citizen_born[a] > state.citizen_born[b])
		var extra := members.slice(0, members.size() - target)
		extra.sort()
		for k: int in range(extra.size() - 1, -1, -1):
			state.remove_citizen(extra[k])
