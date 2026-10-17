class_name InfluenceSystem
extends SimSystem
## The player earns Influence slowly over time, a little faster when there are more tribes to believe
## and when devout chiefs lead them.

const BASE_PER_YEAR := 0.12
const PER_TRIBE_PER_YEAR := 0.012


func get_id() -> String:
	return "influence"


func get_interval() -> int:
	return WorldState.MONTHS_PER_YEAR


func update(state: WorldState) -> void:
	var gain := BASE_PER_YEAR + PER_TRIBE_PER_YEAR * state.tribe_count()
	for tribe_name: String in state.tribe_names:
		gain += Citizens.chief_effect(state, tribe_name, "faith")
	state.influence = minf(state.influence + gain, WorldState.MAX_INFLUENCE)
