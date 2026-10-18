class_name EvolutionSystem
extends SimSystem
## Once a year, writes down the valley's gene pool (the average of every tracked gene over the
## living, and how many carry or suffer from frailty), so the player can watch it drift and adapt.

const MAX_YEARS := 600


func get_id() -> String:
	return "evolution"


func get_interval() -> int:
	return WorldState.DAYS_PER_YEAR


func update(state: WorldState) -> void:
	var stats := Genetics.pool_stats(state.person_genomes)
	stats["year"] = state.year()
	stats["pop"] = state.total_population()
	stats["generation"] = People.max_generation(state)
	state.gene_history.append(stats)
	if state.gene_history.size() > MAX_YEARS:
		state.gene_history.remove_at(0)
