class_name InfluenceSystem
extends SimSystem
## The player earns Influence slowly over time, a little faster when there are more tribes to believe
## when devout chiefs lead them, and when shamans tend shrines.

const BASE_PER_YEAR := 0.12
const PER_TRIBE_PER_YEAR := 0.012
const SHAMAN_PER_YEAR := 0.05
const SHRINE_PER_YEAR := 0.05


func get_id() -> String:
	return "influence"


func get_interval() -> int:
	return WorldState.DAYS_PER_YEAR


func update(state: WorldState) -> void:
	var gain := BASE_PER_YEAR + PER_TRIBE_PER_YEAR * state.tribe_count()
	for t: int in state.tribe_count():
		gain += People.chief_effect(state, state.tribe_names[t], "faith")
		gain += minf(float(state.tribe_work[t].get("shaman", 0.0)), 2.0) * SHAMAN_PER_YEAR
		gain += SHRINE_PER_YEAR * state.count_buildings(state.tribe_names[t], "shrine")
		gain += Society.effect(state, t, "faith")
	state.influence = minf(state.influence + gain, WorldState.MAX_INFLUENCE)
