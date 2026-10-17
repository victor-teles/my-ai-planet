extends SceneTree
## Headless balance report across many seeds, using offline AI and always taking the first dilemma choice.
##   godot --headless --path Godot -s res://tools/balance_report.gd [-- years=300 seeds=12]

func _initialize() -> void:
	_run()


func _run() -> void:
	var options := {"years": "300", "seeds": "12"}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=")
		options[parts[0]] = parts[1]
	var years := int(options["years"])
	var seeds := int(options["seeds"])
	var totals := {}
	print("A bot plays kindly: whenever it holds 6 Influence it sends Rain in a drought, else Harvest to the hungriest tribe.")
	print("seed  pop@50 pop@100 pop@200 pop@end tribes  droughts drought%  famines  infl/yr  prophecies(F/B) avg_len  dilemmas")
	for seed_value: int in range(1, seeds + 1):
		var row := await _simulate(seed_value, years)
		for key: String in row:
			totals[key] = float(totals.get(key, 0.0)) + float(row[key])
		print("%4d  %6d %7d %7d %7d %6d  %8d %7.1f%%  %7d  %7.2f  %8d/%-6d %7.1f  %8d" % [
			seed_value, row["pop50"], row["pop100"], row["pop200"], row["pop_end"], row["tribes"],
			row["droughts"], row["drought_pct"], row["famines"], row["influence_per_year"],
			row["fulfilled"], row["broken"], row["avg_prophecy_years"], row["dilemmas"],
		])
	print("mean  %6.0f %7.0f %7.0f %7.0f %6.1f  %8.1f %7.1f%%  %7.1f  %7.2f  %8.1f/%-6.1f %7.1f  %8.1f" % [
		totals["pop50"] / seeds, totals["pop100"] / seeds, totals["pop200"] / seeds, totals["pop_end"] / seeds,
		totals["tribes"] / seeds, totals["droughts"] / seeds, totals["drought_pct"] / seeds, totals["famines"] / seeds,
		totals["influence_per_year"] / seeds, totals["fulfilled"] / seeds, totals["broken"] / seeds,
		totals["avg_prophecy_years"] / seeds, totals["dilemmas"] / seeds,
	])
	quit()


func _simulate(seed_value: int, years: int) -> Dictionary:
	var session := Session.new(Simulation.create(seed_value), Oracle.new(OfflineTemplatesProvider.new()))
	await session.begin()
	var state := session.sim.state
	var row := {"pop50": 0, "pop100": 0, "pop200": 0, "drought_months": 0, "influence_earned": 0.0}
	var miracles := 0
	var prophecy_years: Array[int] = []
	for year: int in years:
		for month: int in WorldState.MONTHS_PER_YEAR:
			var influence_before := state.influence
			while session.phase != Session.Phase.PLAYING:
				if session.phase == Session.Phase.DECIDING:
					session.choose(0)
				elif session.phase == Session.Phase.REVEAL:
					var resolved := state.resolved_prophecy
					prophecy_years.append(WorldState.year_of(resolved.resolved_tick - resolved.start_tick))
					await session.continue_after_reveal()
			if state.influence >= 6.0:
				var hungriest := 0
				for i: int in state.tribe_count():
					if state.tribe_food[i] / state.tribe_population[i] < state.tribe_food[hungriest] / state.tribe_population[hungriest]:
						hungriest = i
				session.cast_miracle("rain" if state.drought_months_left > 0 else "harvest", state.tribe_names[hungriest])
				influence_before = state.influence
			session.advance(1)
			# Influence is capped, so count what was earned rather than what is held.
			row["influence_earned"] += maxf(state.influence - influence_before, 0.0)
			if state.drought_months_left > 0:
				row["drought_months"] += 1
		if year == 50:
			row["pop50"] = state.total_population()
		elif year == 100:
			row["pop100"] = state.total_population()
		elif year == 200:
			row["pop200"] = state.total_population()
	var counts := {}
	# The world keeps the last WorldState.MAX_EVENTS events; 300 years stays under that.
	for event: Dictionary in state.events:
		counts[event["type"]] = int(counts.get(event["type"], 0)) + 1
	var total_years := float(years)
	return {
		"pop50": row["pop50"], "pop100": row["pop100"], "pop200": row["pop200"],
		"pop_end": state.total_population(), "tribes": state.tribe_count(),
		"droughts": int(counts.get("drought_started", 0)),
		"drought_pct": 100.0 * row["drought_months"] / (total_years * WorldState.MONTHS_PER_YEAR),
		"famines": int(counts.get("famine", 0)),
		"influence_per_year": row["influence_earned"] / total_years,
		"fulfilled": int(counts.get("prophecy_fulfilled", 0)), "broken": int(counts.get("prophecy_broken", 0)),
		"avg_prophecy_years": 0.0 if prophecy_years.is_empty() else float(prophecy_years.reduce(func(a: int, b: int) -> int: return a + b, 0)) / prophecy_years.size(),
		"dilemmas": int(counts.get("dilemma", 0)),
	}
