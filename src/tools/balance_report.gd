extends SceneTree
## Headless balance report across many seeds, using offline AI and always taking the first dilemma choice.
## The last columns follow the long arc: the highest age reached, the darkest society at the end,
## revolutions, coups, and the island's destiny (and the year it came), if it met one.
##   godot --headless --path Godot -s res://tools/balance_report.gd [-- years=300 seeds=6]

const COLUMNS: Array[String] = [
	"pop25", "pop50", "pop100", "pop_end", "tribes", "births", "deaths", "marriages", "discoveries", "buildings",
	"droughts", "famines", "epidemics", "wars", "splits", "merges", "fulfilled", "broken", "dilemmas",
	"age", "dystopia", "revolutions", "coups",
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var options := {"years": "100", "seeds": "6"}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=")
		options[parts[0]] = parts[1]
	var years := int(options["years"])
	var seeds := int(options["seeds"])
	var totals := {}
	print("A bot plays kindly: whenever it holds 6 Influence it sends Rain in a drought, else Harvest to the hungriest tribe.")
	print("seed pop@25 pop@50 pop@100 pop@end tribes births deaths marry disc build drought famine fever wars split merge proph(F/B) dilem infl/yr drought% age dys revol coups destiny")
	for seed_value: int in range(1, seeds + 1):
		var row := await _simulate(seed_value, years)
		var destiny := String(row["destiny"])
		row.erase("destiny")
		for key: String in row:
			totals[key] = float(totals.get(key, 0.0)) + float(row[key])
		print(_line("%4d" % seed_value, row) + " " + destiny)
	var mean := {}
	for key: String in totals:
		mean[key] = float(totals[key]) / seeds
	print(_line("mean", mean))
	quit()


func _line(label: String, row: Dictionary) -> String:
	return "%s %6.0f %6.0f %7.0f %7.0f %6.1f %6.0f %6.0f %5.0f %4.1f %5.0f %7.1f %6.1f %5.1f %4.1f %5.1f %5.1f %5.1f/%-5.1f %5.1f %7.2f %7.1f%% %3.1f %3.0f %5.1f %5.1f" % [
		label, row["pop25"], row["pop50"], row["pop100"], row["pop_end"], row["tribes"], row["births"], row["deaths"],
		row["marriages"], row["discoveries"], row["buildings"], row["droughts"], row["famines"], row["epidemics"],
		row["wars"], row["splits"], row["merges"], row["fulfilled"], row["broken"], row["dilemmas"],
		row["influence_per_year"], row["drought_pct"], row["age"], row["dystopia"], row["revolutions"], row["coups"],
	]


func _simulate(seed_value: int, years: int) -> Dictionary:
	var session := Session.new(Simulation.create(seed_value), Oracle.new(OfflineTemplatesProvider.new()))
	await session.begin()
	var state := session.sim.state
	var row := {"pop25": 0, "pop50": 0, "pop100": 0}
	var drought_months := 0
	var influence_earned := 0.0
	var counts := {}
	var counted_id := state.next_event_id - 1
	for year: int in years:
		for month: int in WorldState.MONTHS_PER_YEAR:
			while session.phase != Session.Phase.PLAYING:
				if session.phase == Session.Phase.DECIDING:
					session.choose(0)
				elif session.phase == Session.Phase.REVEAL:
					await session.continue_after_reveal()
			if state.influence >= 6.0 and state.tribe_count() > 0:
				var hungriest := 0
				for i: int in state.tribe_count():
					if state.tribe_food[i] / maxf(state.tribe_population[i], 1.0) < state.tribe_food[hungriest] / maxf(state.tribe_population[hungriest], 1.0):
						hungriest = i
				session.cast_miracle("rain" if state.drought_months_left > 0 else "harvest", state.tribe_names[hungriest])
			var influence_before := state.influence
			session.advance(WorldState.DAYS_PER_MONTH)
			# Influence is capped, so count what was earned rather than what is held.
			influence_earned += maxf(state.influence - influence_before, 0.0)
			if state.drought_months_left > 0:
				drought_months += 1
			# The world only keeps its newest events, so count them as they happen.
			for event: Dictionary in state.events:
				if int(event["id"]) > counted_id:
					counts[event["type"]] = int(counts.get(event["type"], 0)) + 1
			counted_id = state.next_event_id - 1
		for mark: int in [25, 50, 100]:
			if year + 1 == mark:
				row["pop%d" % mark] = state.total_population()
	var total_years := float(years)
	return {
		"pop25": row["pop25"], "pop50": row["pop50"], "pop100": row["pop100"],
		"pop_end": state.total_population(), "tribes": state.tribe_count(),
		"births": int(counts.get("birth", 0)), "deaths": int(counts.get("death", 0)), "marriages": int(counts.get("marriage", 0)),
		"discoveries": Prophecy.measure("discoveries", state), "buildings": Prophecy.measure("building_count", state),
		"droughts": int(counts.get("drought_started", 0)), "famines": int(counts.get("famine", 0)),
		"epidemics": int(counts.get("epidemic", 0)), "wars": int(counts.get("war", 0)),
		"splits": int(counts.get("tribe_split", 0)), "merges": int(counts.get("tribes_merged", 0)),
		"fulfilled": int(counts.get("prophecy_fulfilled", 0)), "broken": int(counts.get("prophecy_broken", 0)),
		"dilemmas": int(counts.get("dilemma", 0)),
		"influence_per_year": influence_earned / total_years,
		"drought_pct": 100.0 * drought_months / (total_years * WorldState.MONTHS_PER_YEAR),
		"age": Prophecy.measure("highest_age", state), "dystopia": Prophecy.measure("max_dystopia", state),
		"revolutions": int(counts.get("revolution", 0)), "coups": int(counts.get("coup", 0)),
		"destiny": "%s (year %d)" % [DestinySystem.name_of(String(state.destiny["kind"])), int(state.destiny["year"])] if not state.destiny.is_empty() else "-",
	}
