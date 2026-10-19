extends SceneTree
## Year-by-year report of one world, no player: population, births and deaths (with causes),
## marriages, discoveries, buildings, food, jobs and the gene pool; then each tribe's society: its age,
## government, freedom, control, inequality, fear, legitimacy, unrest, dystopia and laws; then the
## wild animals: each species' count, births, deaths by cause, hunters' kills and the meat they gave.
##   godot --headless --path Godot -s res://tools/life_report.gd [-- seed=42 years=60 every=5]


func _initialize() -> void:
	var options := {"seed": "42", "years": "60", "every": "5"}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=")
		options[parts[0]] = parts[1]
	var sim := Simulation.create(int(options["seed"]))
	var state := sim.state
	var every := int(options["every"])
	var counted := state.next_event_id - 1
	var counts := {}
	var causes := {}
	var started := Time.get_ticks_msec()
	print(WorldGen.describe(state.world), " Ores: ", state.world["ores"], " Peoples: ", state.world["peoples"].size())
	print("year  pop tribes  births deaths marriages  techs built  food(d) hungry  jobs")
	for year: int in int(options["years"]):
		# Counted monthly: the world keeps only its newest events, and a busy year has more.
		for month: int in WorldState.MONTHS_PER_YEAR:
			sim.advance(WorldState.DAYS_PER_MONTH)
			for event: Dictionary in state.events:
				if int(event["id"]) <= counted:
					continue
				counts[event["type"]] = int(counts.get(event["type"], 0)) + 1
				if event["type"] == "death":
					causes[event["data"]["cause"]] = int(causes.get(event["data"]["cause"], 0)) + 1
			counted = state.next_event_id - 1
		if (year + 1) % every != 0:
			continue
		var jobs := {}
		for job: String in state.person_jobs:
			if job:
				jobs[job] = int(jobs.get(job, 0)) + 1
		var food := 0.0
		for t: int in state.tribe_count():
			food += state.tribe_food[t]
		var built := 0
		for b: int in state.building_ids.size():
			if state.is_built(b) and state.building_types[b] != "fire":
				built += 1
		print("%4d %4d %6d  %6d %6d %9d  %5d %5d  %7.0f  %s  %s" % [
			state.year(), state.total_population(), state.tribe_count(), int(counts.get("birth", 0)), int(counts.get("death", 0)),
			int(counts.get("marriage", 0)), Prophecy.measure("discoveries", state), built,
			food / maxf(state.total_population(), 1.0), str(Array(state.tribe_hungry_days)), jobs,
		])
		for t: int in state.tribe_count():
			var m := Society.metrics(state, t)
			var laws: Array[String] = []
			for law: String in Society.laws_of(state, t):
				laws.append(law)
			print("      %-12s %3d %-6s %-18s %-10s free %3d ctrl %3d ineq %3d fear %3d legit %3d unrest %3d DYS %3d %s%s%s" % [
				state.tribe_names[t], state.tribe_population[t], Knowledge.AGES[int(m["age"])]["id"], m["government"], m["scale"],
				m["freedom"], m["control"], m["inequality"], m["fear"], m["legitimacy"], m["unrest"], m["dystopia"], laws,
				" vassal of " + state.tribe_overlord[t] if state.tribe_overlord[t] else "", " crisis " + str(state.tribe_crisis[t]["type"]) if not state.tribe_crisis[t].is_empty() else "",
			])
		print("      animals %s  herds %d%%  hunter food to date %.0f" % [_living(state), roundi(100.0 * AnimalSystem.hunt_fullness(state)), AnimalSystem.hunter_meat(state)])
	print("\nevents: ", counts)
	print("death causes: ", causes)
	print("generations: %d   frail: %s" % [People.max_generation(state), state.gene_history[-1] if not state.gene_history.is_empty() else {}])
	if not state.gene_history.is_empty():
		print("genes then: ", state.gene_history[0]["genes"])
		print("genes now:  ", state.gene_history[-1]["genes"])
	for t: int in state.tribe_count():
		var types := {}
		for b: int in state.buildings_of(state.tribe_names[t]):
			types[state.building_types[b]] = int(types.get(state.building_types[b], 0)) + 1
		print("%s: %d people, knows %s, buildings %s, wood %.0f stone %.0f tools %.2f" % [state.tribe_names[t], state.tribe_population[t], Array(state.tribe_knowledge[t]), types, state.tribe_wood[t], state.tribe_stone[t], state.tribe_tools[t]])
	print("pollution %.0f  destiny %s  progress %s" % [state.pollution, state.destiny, state.destiny_progress])
	print("animals    living  seeded  born  aged starved preyed hunted   meat")
	for species_id: String in state.animal_tally:
		var row: Dictionary = state.animal_tally[species_id]
		var seeded := state.animal_seeded.find(species_id)
		print("  %-8s %6d  %6d %5d %5d %7d %6d %6d %6.0f%s" % [
			species_id, AnimalSystem.living(state, species_id), state.animal_seeded_counts[seeded] if seeded != -1 else 0,
			int(row["born"]), int(row["aged"]), int(row["starved"]), int(row["preyed"]), int(row["hunted"]), float(row["meat"]),
			"  gone" if state.animal_wiped.has(species_id) else "",
		])
	print("hunter food %.0f" % AnimalSystem.hunter_meat(state))
	print("ran in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit()


## species -> living count, in the order they were seeded.
static func _living(state: WorldState) -> Dictionary:
	var living := {}
	for species_id: String in state.animal_seeded:
		living[species_id] = AnimalSystem.living(state, species_id)
	return living

