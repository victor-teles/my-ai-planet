extends SceneTree
## Headless report of the long arc, across many islands and several ways of playing the god:
## when each age comes, which destiny the island meets (and when), how dark and unequal its
## societies get, how often they rise up, fight and starve, and how many people live there.
## Uses the offline Oracle (no AI calls), the real Miracles API and the real Influence economy:
## a bot god only casts what it can afford, once a month.
##
## Gods (gods=...):
##   none        hands off: casts nothing, and takes the mildest choice of every dilemma (the one that
##               changes the least; balance_report takes the first instead)
##   benevolent  Rain in a drought, Harvest for the hungry, Awaken the darkest society, a Muse near
##               the Influence cap; takes the kindest, freest choice of a dilemma
##   wrathful    Drought, Smite and Plague on the greatest realm, in turn (Plague only once it has
##               WRATH_PLAGUE_AT people, else Smite); takes the cruelest choice
##   meddler     Sanctify, Smite and Awaken the greatest realm's ruler, in turn; dilemma choices in turn
##   kingmaker   Sanctifies the greatest realm's ruler, smites a kind or wise one; the darkest choice
##   liberator   Awakens the darkest society, smites a harsh ruler; the freest choice
## A run stops when the island meets its destiny (after=N runs N more years).
##
##   godot --headless --path Godot -s res://tools/society_report.gd -- seeds=12 years=360 gods=none,benevolent
##   seeds=12 means seeds 1 to 12; seeds=5-8 means 5 to 8; seeds=1,4,9 just those. rows=0 hides the
##   per-run lines. The balance pass used the 18 islands of SEEDS below (all biomes, 1 to 3 peoples).
##   merge=/some/dir prints the summary of every "ROW {json}" line in the dir's *.txt files, so
##   batches can run in parallel: see tools/society_report.sh.

const GODS: Array[String] = ["none", "benevolent", "wrathful", "meddler", "kingmaker", "liberator"]
const AGE_SHORT: Array[String] = ["", "Bronze", "Iron", "Steam", "Wired"]
const COUNTED: Array[String] = [
	"revolution", "coup", "capture", "uprising_crushed", "protests", "crackdown", "war", "famine", "epidemic",
	"schism", "tribe_split", "tribe_extinct", "vassal", "disaster", "law_passed", "arrest",
]
## Every biome, and one, two and three founding peoples.
const SEEDS := "1,2,3,4,5,6,7,8,9,10,11,12,13,19,21,23,36,37"
const WRATH_PLAGUE_AT := 60
const POP_MARKS: Array[int] = [50, 100, 150, 200, 250, 300, 350, 400]


func _initialize() -> void:
	_run()


func _run() -> void:
	var options := {"seeds": SEEDS, "years": "360", "gods": "none", "rows": "1", "after": "0", "merge": ""}
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=")
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	var rows: Array[Dictionary] = []
	if String(options["merge"]):
		rows = _read_rows(String(options["merge"]))
	else:
		var gods: Array[String] = []
		for god: String in String(options["gods"]).split(","):
			assert(god in GODS, "Unknown god: " + god)
			gods.append(god)
		var seeds := _seed_list(String(options["seeds"]))
		print("Long arc: %d years, seeds %s, gods %s. Ages are the year a tribe first reached them; '-' never." % [int(options["years"]), String(options["seeds"]), ",".join(gods)])
		for god: String in gods:
			for seed_value: int in seeds:
				var row := await _simulate(seed_value, int(options["years"]), god, int(options["after"]))
				rows.append(row)
				print("ROW ", JSON.stringify(row))
	if options["rows"] != "0":
		_print_rows(rows)
	_print_summary(rows)
	quit()


func _seed_list(spec: String) -> Array[int]:
	var seeds: Array[int] = []
	if spec.contains(","):
		for part: String in spec.split(","):
			seeds.append(int(part))
	elif spec.contains("-"):
		var ends := spec.split("-")
		for s: int in range(int(ends[0]), int(ends[1]) + 1):
			seeds.append(s)
	else:
		for s: int in range(1, int(spec) + 1):
			seeds.append(s)
	return seeds


# --- One run ------------------------------------------------------------------------

func _simulate(seed_value: int, years: int, god: String, after: int) -> Dictionary:
	var session := Session.new(Simulation.create(seed_value), Oracle.new(OfflineTemplatesProvider.new()))
	await session.begin()
	var state := session.sim.state
	var world := state.world
	var ores := ""
	for k: int in WorldGen.ORES.size():
		ores += ["Cu", "Sn", "Fe", "C"][k] if WorldGen.ore(world, WorldGen.ORES[k]) > 0.0 else "-"
	var row := {
		"seed": seed_value, "god": god, "biome": String(world["biome"]), "peoples": (world["peoples"] as Array).size(), "ores": ores,
		"ages": [-1, -1, -1, -1, -1], "destiny": "", "destiny_year": -1, "years": 0,
		"peak_dys": 0, "avg_dys": 0.0, "end_dys": 0, "peak_ineq": 0, "avg_ineq": 0.0,
		"pop": {}, "min_pop_100": state.total_population(), "extinct": -1, "peak_pop": state.total_population(),
		"counts": {}, "miracles": {}, "influence": 0.0, "tribes_max": state.tribe_count(),
	}
	row["ages"][0] = 0
	var memo := {"turn": 0, "awakened": {}, "choice": 0}
	var counted := state.next_event_id - 1
	var dys_total := 0.0
	var ineq_total := 0.0
	var stop_year := -1
	for year: int in years:
		for month: int in WorldState.MONTHS_PER_YEAR:
			var left := WorldState.DAYS_PER_MONTH
			while left > 0:
				while session.phase != Session.Phase.PLAYING:
					if session.phase == Session.Phase.DECIDING:
						session.choose(_dilemma_choice(session.dilemma, god, memo))
					elif session.phase == Session.Phase.REVEAL:
						await session.continue_after_reveal()
					else:
						await process_frame
				if left == WorldState.DAYS_PER_MONTH:
					_play_god(session, god, memo, row)
				var influence_before := state.influence
				left -= session.advance(left)
				row["influence"] = float(row["influence"]) + maxf(state.influence - influence_before, 0.0)
			# The world only keeps its newest events, so count them as they happen.
			for event: Dictionary in state.events:
				if int(event["id"]) <= counted:
					continue
				var type := String(event["type"])
				if type in COUNTED:
					row["counts"][type] = int(row["counts"].get(type, 0)) + 1
				if type == "new_age":
					var age := int(event["data"]["age"])
					if int(row["ages"][age]) == -1:
						row["ages"][age] = state.year()
			counted = state.next_event_id - 1
		_yearly(state, row)
		var y := year + 1
		row["years"] = y
		dys_total += Society.gloom(state) * 100.0
		ineq_total += _mean_inequality(state)
		if y in POP_MARKS:
			row["pop"][str(y)] = state.total_population()
		if y <= 100:
			row["min_pop_100"] = mini(int(row["min_pop_100"]), state.total_population())
		if state.total_population() == 0 and int(row["extinct"]) == -1:
			row["extinct"] = y
		if not state.destiny.is_empty() and stop_year == -1:
			row["destiny"] = String(state.destiny["kind"])
			row["destiny_year"] = int(state.destiny["year"])
			stop_year = y + after
		if stop_year != -1 and y >= stop_year:
			break
	row["avg_dys"] = snappedf(dys_total / maxf(float(row["years"]), 1.0), 0.1)
	row["avg_ineq"] = snappedf(ineq_total / maxf(float(row["years"]), 1.0), 0.1)
	row["influence"] = snappedf(float(row["influence"]), 0.1)
	var realm := DestinySystem.greatest_realm(state)
	row["end_dys"] = Society.dystopia(state, realm) if realm != -1 else 0
	if realm != -1:
		var m := Society.metrics(state, realm)
		row["end"] = "%s, free %d, ineq %d, ctrl %d, fear %d" % [m["government"], m["freedom"], m["inequality"], m["control"], m["fear"]]
		row["end_laws"] = ",".join(Society.laws_of(state, realm))
	row["pop_end"] = state.total_population()
	return row


func _yearly(state: WorldState, row: Dictionary) -> void:
	row["peak_pop"] = maxi(int(row["peak_pop"]), state.total_population())
	row["tribes_max"] = maxi(int(row["tribes_max"]), state.tribe_count())
	for t: int in state.tribe_count():
		if state.tribe_population[t] < SocietySystem.LAW_MIN_POPULATION:
			continue
		row["peak_dys"] = maxi(int(row["peak_dys"]), Society.dystopia(state, t))
		row["peak_ineq"] = maxi(int(row["peak_ineq"]), Society.inequality(state, t))


## Population-weighted inequality of the island's tribes.
func _mean_inequality(state: WorldState) -> float:
	var total := 0.0
	var people := 0
	for t: int in state.tribe_count():
		total += Society.inequality(state, t) * state.tribe_population[t]
		people += state.tribe_population[t]
	return total / maxf(people, 1.0)


# --- The bot gods -------------------------------------------------------------------

func _play_god(session: Session, god: String, memo: Dictionary, row: Dictionary) -> void:
	var state := session.sim.state
	if god == "none" or state.tribe_count() == 0:
		return
	var realm := DestinySystem.greatest_realm(state)
	var realm_name := state.tribe_names[realm] if realm != -1 else state.tribe_names[0]
	var cast := ""
	var target := ""
	match god:
		"benevolent":
			var dark := _darkest(state, memo)
			var hungry := _hungriest(state)
			if dark != -1 and state.influence >= 3.0:
				cast = "awaken"
				target = state.tribe_names[dark]
			elif state.drought_months_left > 0 and state.influence >= 3.0:
				cast = "rain"
			elif hungry != -1 and state.influence >= 2.0:
				cast = "harvest"
				target = state.tribe_names[hungry]
			elif state.influence >= 10.0:
				cast = "muse"
				target = state.tribe_names[_least_advanced(state)]
		"wrathful":
			# A god of wrath, not of extinction: the plague falls on realms big enough to bear it.
			var turn: String = ["drought", "smite", "plague"][int(memo["turn"]) % 3]
			if turn == "plague" and Society.realm_population(state, state.tribe_index(realm_name)) < WRATH_PLAGUE_AT:
				turn = "smite"
			if state.influence >= float(Miracles.DEFINITIONS[turn]["cost"]) and Miracles.why_not(state, turn, realm_name).is_empty():
				cast = turn
				target = realm_name
		"meddler":
			var turn: String = ["sanctify", "smite", "awaken"][int(memo["turn"]) % 3]
			if state.influence >= float(Miracles.DEFINITIONS[turn]["cost"]):
				cast = turn
				target = realm_name
		"kingmaker":
			var ruler := state.chief_of(realm_name)
			if ruler != -1 and (People.has_trait(state, ruler, "kind") or People.has_trait(state, ruler, "wise")):
				cast = "smite" if state.influence >= 4.0 else ""
			elif state.influence >= 3.0 and (state.tribe_legitimacy[state.tribe_index(realm_name)] < 85 or state.influence >= 10.0):
				cast = "sanctify"
			target = realm_name
		"liberator":
			var dark := _darkest(state, memo)
			var ruler := state.chief_of(realm_name)
			var harsh := ruler != -1 and (People.has_trait(state, ruler, "fierce") or People.has_trait(state, ruler, "proud") or People.has_trait(state, ruler, "greedy"))
			if dark != -1 and state.influence >= 3.0:
				cast = "awaken"
				target = state.tribe_names[dark]
			elif harsh and Society.power(state, state.tribe_index(realm_name), "ruler") >= 45 and state.influence >= 4.0:
				cast = "smite"
				target = realm_name
	if cast.is_empty():
		return
	if session.cast_miracle(cast, target):
		row["miracles"][cast] = int(row["miracles"].get(cast, 0)) + 1
		memo["turn"] = int(memo["turn"]) + 1
		if cast == "awaken":
			memo["awakened"][target] = state.tick


## The darkest society worth waking (dystopia 30+ or a dark law, not awakened in the last 3 years), or -1.
func _darkest(state: WorldState, memo: Dictionary) -> int:
	var best := -1
	var best_score := 29
	for t: int in state.tribe_count():
		if state.tribe_population[t] < SocietySystem.LAW_MIN_POPULATION:
			continue
		if state.tick - int(memo["awakened"].get(state.tribe_names[t], -99999)) < 3 * WorldState.DAYS_PER_YEAR:
			continue
		var score := Society.dystopia(state, t)
		for law: String in state.tribe_laws[t]:
			if Laws.is_dystopian(law):
				score += 10
		if score > best_score:
			best = t
			best_score = score
	return best


## The tribe going hungry or nearly out of food, or -1.
func _hungriest(state: WorldState) -> int:
	var best := -1
	var least := 20.0
	for t: int in state.tribe_count():
		var days := state.tribe_food[t] / maxf(state.tribe_population[t], 1.0)
		if (state.tribe_hungry_days[t] > 0 or days < 20.0) and days < least:
			best = t
			least = days
	return best


func _least_advanced(state: WorldState) -> int:
	var best := 0
	for t: int in state.tribe_count():
		if state.tribe_knowledge[t].size() < state.tribe_knowledge[best].size() and not Knowledge.discoverable(state.tribe_knowledge[t]).is_empty():
			best = t
	return best


## Which dilemma choice each god takes. The hands-off god the one that changes least; the kind what
## feeds people and frees them; the cruel the opposite; the meddler goes down the list.
func _dilemma_choice(card: Dilemma, god: String, memo: Dictionary) -> int:
	if card == null:
		return 0
	if god == "none":
		var mildest := 0
		var least := INF
		for k: int in card.choices.size():
			var change := 0.0
			for effect: Dictionary in card.choices[k]["effects"]:
				var limits: Array = Dilemma.EFFECTS[effect["type"]]
				change += 1.0 if effect["type"] == "split" else absf(float(effect["amount"])) / maxf(maxf(absf(float(limits[0])), absf(float(limits[1]))), 1.0)
			if change < least:
				mildest = k
				least = change
		return mildest
	if god == "meddler":
		memo["choice"] = int(memo["choice"]) + 1
		return int(memo["choice"]) % card.choices.size()
	var best := 0
	var best_score := -INF
	for k: int in card.choices.size():
		var choice: Dictionary = card.choices[k]
		var mercy := float(Dilemma.leaning(choice))
		var free := 0.0
		for effect: Dictionary in choice["effects"]:
			if String(effect["type"]) == "law":
				var law := String(effect["law"])
				var direction := signf(float(effect["amount"]))
				free += direction * (-2.0 if Laws.is_dystopian(law) else float(Laws.LAWS[law]["freedom"]) / 10.0)
		var score := mercy + 2.0 * free
		if god == "wrathful":
			score = -mercy
		elif god == "kingmaker":
			score = -free
		elif god == "liberator":
			score = free
		if score > best_score:
			best = k
			best_score = score
	return best


# --- Reading and printing -----------------------------------------------------------

func _read_rows(dir_path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".txt"):
			continue
		for line: String in FileAccess.get_file_as_string(dir_path.path_join(file_name)).split("\n"):
			if line.begins_with("ROW "):
				var data: Variant = JSON.parse_string(line.substr(4))
				if data is Dictionary:
					rows.append(data)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ga := GODS.find(String(a["god"]))
		var gb := GODS.find(String(b["god"]))
		return ga < gb or (ga == gb and int(a["seed"]) < int(b["seed"])))
	return rows


func _print_rows(rows: Array[Dictionary]) -> void:
	print("\ngod        seed biome    ppl ores     Bronze Iron Steam Wired  destiny        year  dys pk/avg/end ineq pk/avg  rev coup capt crush wars famine fever  pop 100/200/300/end  miracles")
	for row: Dictionary in rows:
		var ages: Array = row["ages"]
		var counts: Dictionary = row["counts"]
		var pop: Dictionary = row["pop"]
		var miracles: Array[String] = []
		for id: String in row["miracles"]:
			miracles.append("%s %d" % [id, int(row["miracles"][id])])
		print("%-10s %4d %-8s %3d %-8s %6s %4s %5s %5s  %-14s %4s  %3d/%3.0f/%3d   %3d/%3.0f   %3d %4d %4d %5d %4d %6d %5d  %4s/%4s/%4s/%4d  %s" % [
			row["god"], int(row["seed"]), row["biome"], int(row["peoples"]), row["ores"],
			_year(ages[1]), _year(ages[2]), _year(ages[3]), _year(ages[4]),
			DestinySystem.name_of(String(row["destiny"])) if row["destiny"] else "-", _year(row["destiny_year"]),
			int(row["peak_dys"]), float(row["avg_dys"]), int(row["end_dys"]), int(row["peak_ineq"]), float(row["avg_ineq"]),
			int(counts.get("revolution", 0)), int(counts.get("coup", 0)), int(counts.get("capture", 0)), int(counts.get("uprising_crushed", 0)),
			int(counts.get("war", 0)), int(counts.get("famine", 0)), int(counts.get("epidemic", 0)),
			_year(pop.get("100", -1)), _year(pop.get("200", -1)), _year(pop.get("300", -1)), int(row["pop_end"]),
			", ".join(miracles),
		])


func _year(value: Variant) -> String:
	return "-" if int(value) < 0 else str(int(value))


func _print_summary(rows: Array[Dictionary]) -> void:
	var by_god := {}
	for row: Dictionary in rows:
		if not by_god.has(row["god"]):
			by_god[row["god"]] = []
		(by_god[row["god"]] as Array).append(row)
	var biomes := {}
	var peoples := {}
	for row: Dictionary in rows:
		if row["god"] == rows[0]["god"]:
			biomes[row["biome"]] = int(biomes.get(row["biome"], 0)) + 1
			peoples[str(int(row["peoples"]))] = int(peoples.get(str(int(row["peoples"])), 0)) + 1
	print("\nIslands: %s; founding peoples: %s" % [biomes, peoples])
	print("\nPer god (ages: median year among runs that got there, and how many did; destinies: share of runs)")
	print("god        runs  Bronze      Iron        Steam       Wired      | dys pk/avg ineq pk/avg | rev  coup capt crush wars famine fever | pop100 pop200 peak  died<100 extinct | infl/run miracles")
	for god: String in GODS:
		if not by_god.has(god):
			continue
		var list: Array = by_god[god]
		var n := float(list.size())
		var cells: Array[String] = []
		for age: int in range(1, 5):
			var reached: Array[int] = []
			for row: Dictionary in list:
				if int(row["ages"][age]) >= 0:
					reached.append(int(row["ages"][age]))
			reached.sort()
			cells.append("%4s %2d/%-2d" % [_year(reached[reached.size() / 2]) if not reached.is_empty() else "-", reached.size(), list.size()])
		var mean := func(key: String) -> float:
			var total := 0.0
			for row: Dictionary in list:
				total += float(row[key])
			return total / n
		var count := func(key: String) -> float:
			var total := 0.0
			for row: Dictionary in list:
				total += float((row["counts"] as Dictionary).get(key, 0))
			return total / n
		var pop_at := func(mark: String) -> String:
			var total := 0.0
			var runs := 0
			for row: Dictionary in list:
				if (row["pop"] as Dictionary).has(mark):
					total += float(row["pop"][mark])
					runs += 1
			return "%6.0f" % (total / runs) if runs > 0 else "     -"
		var early_deaths := 0
		var extinct := 0
		var miracles := 0.0
		for row: Dictionary in list:
			early_deaths += 1 if int(row["min_pop_100"]) == 0 else 0
			extinct += 1 if int(row["extinct"]) != -1 else 0
			for id: String in row["miracles"]:
				miracles += float(row["miracles"][id])
		print("%-10s %4d  %s  %s  %s  %s | %3.0f/%4.1f  %3.0f/%4.1f  | %4.1f %4.1f %4.1f %5.1f %4.1f %6.1f %5.1f | %s %s %5.0f %4d %8d | %7.1f %6.1f" % [
			god, list.size(), cells[0], cells[1], cells[2], cells[3],
			mean.call("peak_dys"), mean.call("avg_dys"), mean.call("peak_ineq"), mean.call("avg_ineq"),
			count.call("revolution"), count.call("coup"), count.call("capture"), count.call("uprising_crushed"), count.call("war"), count.call("famine"), count.call("epidemic"),
			pop_at.call("100"), pop_at.call("200"), mean.call("peak_pop"), early_deaths, extinct,
			mean.call("influence"), miracles / n,
		])
	print("\nDestinies (share of runs; median year)")
	var header := "god        "
	for kind: String in DestinySystem.ORDER:
		header += "%-13s" % kind
	print(header + "none         dark/free")
	for god: String in GODS:
		if not by_god.has(god):
			continue
		var list: Array = by_god[god]
		var line := "%-10s " % god
		var dark := 0
		var free := 0
		for kind: String in DestinySystem.ORDER + [""]:
			var years: Array[int] = []
			for row: Dictionary in list:
				if String(row["destiny"]) == kind:
					years.append(int(row["destiny_year"]))
			years.sort()
			if kind == "free_commons":
				free = years.size()
			elif kind:
				dark += years.size()
			var cell := "%3.0f%%" % (100.0 * years.size() / list.size())
			if kind and not years.is_empty():
				cell += " y%d" % years[years.size() / 2]
			line += "%-13s" % cell
		print(line + "%3.0f%%/%3.0f%%" % [100.0 * dark / list.size(), 100.0 * free / list.size()])
