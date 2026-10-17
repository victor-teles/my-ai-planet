class_name InfluenceSystem
extends SimSystem
## The player earns Influence slowly over time, a little faster when there are more tribes to believe.

const BASE_PER_YEAR := 0.4
const PER_TRIBE_PER_YEAR := 0.1


func get_id() -> String:
	return "influence"


func get_interval() -> int:
	return WorldState.MONTHS_PER_YEAR


func update(state: WorldState) -> void:
	var gain := BASE_PER_YEAR + PER_TRIBE_PER_YEAR * state.tribe_count()
	state.influence = minf(state.influence + gain, WorldState.MAX_INFLUENCE)
