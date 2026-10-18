class_name WorkSystem
extends SimSystem
## Once a month each tribe takes stock and organizes itself:
## - someone may discover something new, and friendly tribes teach each other what they know;
## - the council decides how many hands each job needs (food first, then building, then crafts)
##   and people take the work that suits them, keeping their old job when they can;
## - workers grow more skilled, and apprentices learn from a parent;
## - the chief picks the next thing to build, and families move into new homes.
## Later techs are harder to find, much harder without their ore; scholars, writing and print speed
## the search, and censors and state priests slow it.

const DISCOVERY_CHANCE := 0.0008 ## per adult, per month, before intellect and curiosity
const EASY := 1.6 ## techs this hard or easier are found as soon as someone stumbles on them
const HARD := 3.5 ## how steeply harder techs resist being found: success is (EASY / difficulty) ^ HARD
const RESEARCH := 1.5 ## how much a scholar per ten people adds to the search
## Above this many adults, more heads find things only as the square root of their number: a city
## of 160 thinks twice as fast as a village of 40, not four times. Keeps great realms from racing
## through the late ages in a few years.
const CROWD_THINKS := 40.0
## The work each temperament is drawn to.
const LIKES := {
	"brave": ["hunter", "guard"], "fierce": ["hunter", "quarrier", "guard"], "kind": ["healer", "forager"],
	"wise": ["healer", "shaman", "toolmaker", "scholar", "official"], "devout": ["shaman"], "curious": ["fisher", "toolmaker", "scholar"],
	"cheerful": ["potter", "weaver", "merchant"], "proud": ["builder", "hunter", "official"],
	"greedy": ["farmer", "potter", "merchant"], "lazy": ["fisher", "weaver", "official"],
}
const SPREAD_CHANCE := 0.035 ## per known tech, per month, between friendly tribes
const SPREAD_AT := 10 ## relation needed to share knowledge
const SKILL_GAIN := 0.75 ## per month of work, before intellect: about 12 years to master a trade
const APPRENTICE_AT := 12
const WOOD_RESERVE := 25.0
## The food each food worker brings in per day over a whole year, before crowding.
const YEARLY_FOOD := {"forager": 2.35, "hunter": 2.8, "fisher": 2.5, "farmer": 2.9}


func get_id() -> String:
	return "work"


func get_interval() -> int:
	return WorldState.DAYS_PER_MONTH


func update(state: WorldState) -> void:
	for t: int in state.tribe_count():
		_discover(state, t)
	_spread(state)
	for t: int in state.tribe_count():
		_assign_jobs(state, t)
		_train(state, t)
		_plan(state, t)
		settle_homes(state, t)
		if state.month() == 0 and _housing_short(state, state.tribe_names[t]) == 0:
			_take_down_empty_home(state, t)
		measure_work(state, t)


# --- Knowledge ----------------------------------------------------------------------

func _discover(state: WorldState, t: int) -> void:
	var open := Knowledge.discoverable(state.tribe_knowledge[t])
	if open.is_empty():
		return
	var tribe := state.tribe_names[t]
	var known := state.tribe_knowledge[t]
	var scholars := float(state.tribe_work[t].get("scholar", 0.0))
	var search := (1.0 + RESEARCH * scholars * 10.0 / maxf(state.tribe_population[t], 10.0)) * state.tech_bonus(t, "discovery") * Society.effect(state, t, "discovery")
	var adults := 0
	for p: int in state.people_of(tribe):
		if People.is_adult(state, p):
			adults += 1
	search *= minf(1.0, sqrt(CROWD_THINKS / maxf(adults, 1.0)))
	for p: int in state.people_of(tribe):
		if not People.is_adult(state, p) or state.person_detained[p] > 0:
			continue
		var genome := state.person_genomes[p]
		var chance := DISCOVERY_CHANCE * (0.4 + 1.2 * Genetics.express(genome, "intellect")) * (0.6 + 0.8 * Genetics.express(genome, "curiosity"))
		if People.has_trait(state, p, "curious"):
			chance *= 1.8
		if People.has_trait(state, p, "wise"):
			chance *= 1.2
		if not state.rng.chance(chance * search):
			continue
		var tech := _pick_tech(state, p, open)
		# Hard things take more than one bright idea.
		if not state.rng.chance(pow(minf(EASY / Knowledge.difficulty(tech, state.world), 1.0), HARD) * Knowledge.scarcity(tech, state.world)):
			return
		discover(state, t, p, tech)
		return


## The tech someone stumbles on: what their work points them toward, easy things first.
func _pick_tech(state: WorldState, p: int, open: Array[String]) -> String:
	var weights: Array[float] = []
	var total := 0.0
	for tech: String in open:
		var info: Dictionary = Knowledge.TECHS[tech]
		var weight := 1.0 / Knowledge.difficulty(tech, state.world)
		if state.person_jobs[p] in info["found_by"]:
			weight *= 3.0
		if tech == "rites" and People.has_trait(state, p, "devout"):
			weight *= 4.0
		weights.append(weight)
		total += weight
	var roll := state.rng.randf() * total
	for k: int in open.size():
		roll -= weights[k]
		if roll <= 0.0:
			return open[k]
	return open[-1]


static func discover(state: WorldState, t: int, p: int, tech: String) -> void:
	var age_before := state.age_of(t)
	state.learn(t, tech)
	var skill := Jobs.skill_index(state.person_jobs[p])
	if skill != -1:
		state.person_skills[p][skill] = mini(state.person_skills[p][skill] + 10, 100)
	state.log_event("discovery", {"tribe": state.tribe_names[t], "tech": tech, "id": state.person_ids[p], "name": state.person_names[p]})
	state.life(state.person_ids[p], "Discovered %s." % Knowledge.name_of(tech).to_lower(), "discovery")
	announce_age(state, t, age_before)


## Logs a tribe entering a new age, and whether it is the first on the island to get there.
static func announce_age(state: WorldState, t: int, age_before: int) -> void:
	var age := state.age_of(t)
	if age <= age_before:
		return
	var first := true
	for other: int in state.tribe_count():
		if other != t and state.age_of(other) >= age:
			first = false
	for event: Dictionary in state.events:
		if event["type"] == "new_age" and int(event["data"].get("age", 0)) >= age:
			first = false
	state.log_event("new_age", {"tribe": state.tribe_names[t], "age": age, "name": Knowledge.age_name(age), "first": 1 if first else 0})


func _spread(state: WorldState) -> void:
	for i: int in state.tribe_count():
		for j: int in range(i + 1, state.tribe_count()):
			if state.relation(state.tribe_names[i], state.tribe_names[j]) < SPREAD_AT:
				continue
			for pair: Array in [[i, j], [j, i]]:
				var from: int = pair[0]
				var to: int = pair[1]
				for tech: String in Knowledge.ORDER:
					var spread := SPREAD_CHANCE * minf(EASY / Knowledge.difficulty(tech, state.world), 1.0)
					if state.knows(from, tech) and not state.knows(to, tech) and tech in Knowledge.discoverable(state.tribe_knowledge[to]) and state.rng.chance(spread):
						var age_before := state.age_of(to)
						state.learn(to, tech)
						state.log_event("tech_spread", {"tech": tech, "from": state.tribe_names[from], "to": state.tribe_names[to]})
						announce_age(state, to, age_before)
						break


# --- Jobs ---------------------------------------------------------------------------

## How well someone suits a job: practice, the gene the work needs, their parents' trade and
## their temperament.
static func suitability(state: WorldState, p: int, job: String) -> float:
	var info: Dictionary = Jobs.DEFINITIONS[job]
	var score := float(state.person_skills[p][Jobs.skill_index(job)])
	score += 30.0 * Genetics.express(state.person_genomes[p], String(info["gene"]))
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		var q := state.index_of(parent)
		var parent_job := state.person_jobs[q] if q != -1 else String((state.dead.get(str(parent), {}) as Dictionary).get("job", ""))
		if parent_job == job:
			score += 12.0
	for trait_id: String in People.traits_of(state, p):
		if job in LIKES.get(trait_id, []):
			score += 10.0
	return score


## How many hands each job needs this month.
func _targets(state: WorldState, t: int, workers: int, eaten: float) -> Dictionary:
	var tribe := state.tribe_names[t]
	var population := state.tribe_population[t]
	var want := {}
	var known := state.tribe_knowledge[t]
	if "herbal_lore" in known and population >= 10:
		want["healer"] = clampi(roundi(population / 35.0), 1, 3)
	if "stone_tools" in known and population >= 10:
		want["toolmaker"] = clampi(roundi(population / 40.0), 1, 2)
	if "pottery" in known and population >= 16:
		want["potter"] = 1 if population < 60 else 2
	if "weaving" in known and population >= 16:
		want["weaver"] = 1 if population < 60 else 2
	if "rites" in known and population >= 22:
		want["shaman"] = 1
	# The later ages' trades, each where its workplace stands.
	if state.count_buildings(tribe, "school") > 0:
		want["scholar"] = clampi(roundi(population / 30.0), 1, 4)
	if state.count_buildings(tribe, "mine") > 0 and state.tribe_metal[t] < 40.0:
		want["miner"] = clampi(roundi(population / 40.0), 1, 3)
	if state.count_buildings(tribe, "smithy") > 0 and (state.tribe_metal[t] > 1.0 or want.has("miner")):
		want["smith"] = clampi(roundi(population / 45.0), 1, 3)
	if state.count_buildings(tribe, "market") > 0:
		want["merchant"] = clampi(roundi(population / 35.0), 1, 4)
	if state.count_buildings(tribe, "factory") > 0:
		want["factory_worker"] = state.count_buildings(tribe, "factory") * 5
	if "bronze" in known:
		var guards := roundi(population * Society.effect(state, t, "guards"))
		var ruler := state.chief_of(tribe)
		if state.tribe_unrest[t] >= 50 and ruler != -1 and (People.has_trait(state, ruler, "fierce") or People.has_trait(state, ruler, "proud")):
			guards += 2
		if guards > 0:
			want["guard"] = guards
	var officials := roundi(population * Society.effect(state, t, "officials"))
	if "writing" in known and officials > 0:
		want["official"] = officials
	# Building: builders for the project, cutters for the materials it (or the plan) still needs.
	var wood_needed := WOOD_RESERVE
	var stone_needed := 0.0
	var project := state.building_index(state.tribe_project[t])
	if project != -1:
		var left := int(Buildings.TYPES[state.building_types[project]]["work"]) - state.building_progress[project]
		want["builder"] = clampi(ceili(left / 40.0), 1, maxi(1, workers / 5))
	var plan := _plan_type(state.tribe_plan[t])
	if plan:
		wood_needed += float(Buildings.TYPES[plan]["wood"])
		stone_needed += float(Buildings.TYPES[plan]["stone"])
	var wood_short := wood_needed - state.tribe_wood[t]
	if wood_short > 0.0:
		want["woodcutter"] = clampi(ceili(wood_short / 60.0), 1, maxi(1, workers / 6))
	if "stone_tools" in known and stone_needed - state.tribe_stone[t] > 0.0:
		want["quarrier"] = clampi(ceili((stone_needed - state.tribe_stone[t]) / 40.0), 1, maxi(1, workers / 8))
	# Food: enough hands to feed everyone through the year, more when the stores are low.
	var days_stored := state.tribe_food[t] / maxf(eaten, 1.0)
	var buffer := 0.5 if days_stored < 30.0 else (0.3 if days_stored < 90.0 else (0.12 if days_stored < 150.0 else 0.0))
	var field_room := state.count_buildings(tribe, "field") * int(EconomySystem.FARMERS_PER_FIELD)
	var food_workers := ceili(eaten * (1.0 + buffer) / _food_per_worker(state, t, eaten * (1.0 + buffer) / 2.2, field_room))
	# If hands are short, crafts and building wait; food comes first.
	var others := 0
	for job: String in want:
		others += int(want[job])
	# Rulers who fear their people keep their guards even when the stores run low.
	for job: String in ["merchant", "scholar", "factory_worker", "miner", "smith", "shaman", "weaver", "potter", "quarrier", "toolmaker", "woodcutter", "builder", "official", "guard", "healer"]:
		if others + food_workers <= workers or not want.has(job):
			continue
		var cut := mini(int(want[job]), others + food_workers - workers)
		want[job] = int(want[job]) - cut
		others -= cut
	var food := maxi(workers - others, 0)
	var farmers := mini(food, field_room)
	want["farmer"] = farmers
	var wild := food - farmers
	var fishers := roundi(wild * 0.3) if "fishing" in known else 0
	var hunters := roundi((wild - fishers) * 0.4)
	want["fisher"] = fishers
	want["hunter"] = hunters
	want["forager"] = wild - fishers - hunters
	return want


## The food a food worker brings in over a year, from what the land, the fields and the tools give.
func _food_per_worker(state: WorldState, t: int, needed: float, field_room: int) -> float:
	var world := state.world
	var known := state.tribe_knowledge[t]
	var wild := (WorldGen.rate(world, "forage") + WorldGen.rate(world, "hunt") + WorldGen.rate(world, "fish")) / 3.0
	var fields := WorldGen.rate(world, "farm") * state.tech_bonus(t, "farm")
	var farmed := minf(field_room / maxf(needed, 1.0), 1.0)
	var tools := (1.0 + EconomySystem.TOOL_POWER[state.age_of(t)] * state.tribe_tools[t]) / (1.0 + 0.35 * state.tribe_tools[t])
	return 2.2 * lerpf(wild, maxf(fields, wild), farmed) * tools


func _assign_jobs(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var workers: Array[int] = []
	var eaten := 0.0
	for p: int in members:
		var years := People.age(state, p)
		eaten += float(EconomySystem.EATS[People.stage_at(years)])
		if state.person_detained[p] > 0:
			state.person_jobs[p] = ""
		elif years >= People.RETIRE_AT:
			if state.person_jobs[p]:
				state.life(state.person_ids[p], "Laid down %s work to teach the young." % Jobs.name_of(state.person_jobs[p]), "work")
				state.person_jobs[p] = ""
		elif years >= People.ADULT_AT:
			workers.append(p)
		elif years >= APPRENTICE_AT:
			_apprentice(state, p)
		else:
			state.person_jobs[p] = ""
	var want := _targets(state, t, workers.size(), eaten)
	var counts := {}
	var pool: Array[int] = []
	for p: int in workers:
		var job := state.person_jobs[p]
		if job.is_empty() or not want.has(job) or not Jobs.is_known(job, state.tribe_knowledge[t]):
			pool.append(p)
		else:
			counts[job] = int(counts.get(job, 0)) + 1
	# Jobs with too many hands let go of whoever suits them least.
	# Food workers keep their job if the food jobs only differ by one hand, so people don't swap
	# every month, unless another job is waiting for hands.
	var short_elsewhere := pool.size() < 1
	for job: String in want:
		if job not in Jobs.FOOD_JOBS and int(want[job]) > int(counts.get(job, 0)):
			short_elsewhere = true
	var food_short := 0
	for job: String in Jobs.FOOD_JOBS:
		food_short += maxi(int(want.get(job, 0)) - int(counts.get(job, 0)), 0)
	for job: String in Jobs.ORDER:
		var extra := int(counts.get(job, 0)) - int(want.get(job, 0))
		if job in Jobs.FOOD_JOBS and job != "farmer" and food_short <= 1 and not short_elsewhere:
			extra -= 1
		if extra <= 0:
			continue
		var holders: Array[int] = []
		for p: int in workers:
			if state.person_jobs[p] == job and p not in pool:
				holders.append(p)
		holders.sort_custom(func(a: int, b: int) -> bool: return suitability(state, a, job) < suitability(state, b, job))
		for k: int in extra:
			pool.append(holders[k])
		counts[job] = int(want.get(job, 0))
	# Jobs short of hands take whoever suits them best, most needed first.
	var hungry := state.tribe_food[t] < eaten * 45.0
	for job: String in ["healer", "guard", "builder", "farmer", "fisher", "hunter", "official", "factory_worker", "miner", "smith",
			"woodcutter", "quarrier", "toolmaker", "scholar", "merchant", "potter", "weaver", "shaman", "forager"]:
		var short := int(want.get(job, 0)) - int(counts.get(job, 0))
		while short > 0 and not pool.is_empty():
			var best := 0
			for k: int in range(1, pool.size()):
				if suitability(state, pool[k], job) > suitability(state, pool[best], job):
					best = k
			_take_job(state, t, pool[best], job, hungry)
			pool.remove_at(best)
			short -= 1
	for p: int in pool:
		_take_job(state, t, p, "forager", hungry)


func _take_job(state: WorldState, t: int, p: int, job: String, hungry: bool) -> void:
	var old := state.person_jobs[p]
	if old == job:
		return
	state.person_jobs[p] = job
	var tribe := state.tribe_names[t]
	var first := true
	for q: int in state.people_of(tribe):
		if q != p and state.person_jobs[q] == job:
			first = false
			break
	if first and not _ever_had(state, tribe, job):
		state.log_event("job", {"tribe": tribe, "id": state.person_ids[p], "name": state.person_names[p], "job": job, "first": 1})
		state.life(state.person_ids[p], "Became the first %s of the %s." % [Jobs.name_of(job), tribe], "work")
		return
	var why := _why(state, p, old, job, hungry)
	state.life(state.person_ids[p], why.capitalize().left(1) + why.substr(1) + ".", "work")
	# Only the choices that tell a story reach the feed; daily reshuffles stay in the life story.
	if not old.is_empty() and (why.begins_with("followed") or why.contains("stores ran low")):
		state.log_event("job", {"tribe": tribe, "id": state.person_ids[p], "name": state.person_names[p], "job": job, "why": why})


## Whether this tribe has ever had someone in this job (so "the first" is said once).
func _ever_had(state: WorldState, tribe: String, job: String) -> bool:
	for event: Dictionary in state.events:
		var data: Dictionary = event["data"]
		if event["type"] == "job" and String(data.get("tribe", "")) == tribe and String(data.get("job", "")) == job:
			return true
	return false


## A few words on why someone took a job: "followed her mother into healing".
func _why(state: WorldState, p: int, old: String, job: String, hungry: bool) -> String:
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		var q := state.index_of(parent)
		if q != -1 and state.person_jobs[q] == job:
			return "followed %s %s and became a %s" % [People.possessive(state, p), "mother" if parent == state.person_mothers[p] else "father", Jobs.name_of(job)]
	if hungry and job in Jobs.FOOD_JOBS and old and old not in Jobs.FOOD_JOBS:
		return "left %s work to become a %s as the stores ran low" % [Jobs.name_of(old), Jobs.name_of(job)]
	if job == "builder":
		return "was called to build for the tribe"
	if job == "guard":
		return "was given a spear and a post"
	if old.is_empty():
		return "began working as a %s" % Jobs.name_of(job)
	return "gave up %s work to become a %s" % [Jobs.name_of(old), Jobs.name_of(job)]


## A youth learns the trade of a parent (the mother's or the father's, whichever works), and
## follows them if they change work.
func _apprentice(state: WorldState, p: int) -> void:
	for parent: int in [state.person_mothers[p], state.person_fathers[p]]:
		var q := state.index_of(parent)
		if q != -1 and state.person_jobs[q] and state.person_jobs[q] == state.person_jobs[p]:
			return
	var parents: Array[int] = [state.person_mothers[p], state.person_fathers[p]]
	if state.rng.chance(0.5):
		parents.reverse()
	for parent: int in parents:
		var q := state.index_of(parent)
		if q != -1 and state.person_jobs[q]:
			var first_trade := state.person_jobs[p].is_empty()
			state.person_jobs[p] = state.person_jobs[q]
			if not first_trade:
				state.life(state.person_ids[p], "Followed %s %s into %s work." % [People.possessive(state, p), "mother" if parent == state.person_mothers[p] else "father", Jobs.name_of(state.person_jobs[q])], "work")
				return
			state.log_event("apprentice", {"tribe": state.person_tribes[p], "id": state.person_ids[p], "name": state.person_names[p], "job": state.person_jobs[q], "teacher": state.person_names[q]})
			state.life(state.person_ids[p], "Began learning to be a %s from %s %s." % [Jobs.name_of(state.person_jobs[q]), People.possessive(state, p), "mother" if parent == state.person_mothers[p] else "father"], "work")
			return
	if state.person_jobs[p] != "forager":
		state.person_jobs[p] = "forager"
		state.life(state.person_ids[p], "Began helping the foragers.", "work")


## Practice makes skill; clever people learn faster, and so do the young when elders teach.
func _train(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var members := state.people_of(tribe)
	var teachers := 0
	var learners := 0
	for p: int in members:
		var years := People.age(state, p)
		if years >= People.RETIRE_AT:
			teachers += 1
		elif years >= APPRENTICE_AT and years < People.ADULT_AT:
			learners += 1
	var teaching := 1.0 + minf(float(teachers) / maxf(learners, 1.0), 1.0) * 0.5
	for p: int in members:
		var skill := Jobs.skill_index(state.person_jobs[p])
		if skill == -1:
			continue
		var gain := SKILL_GAIN * (0.6 + 0.8 * Genetics.express(state.person_genomes[p], "intellect"))
		if People.age(state, p) < People.ADULT_AT:
			gain *= 1.5 * teaching
		state.person_skills[p][skill] = mini(state.person_skills[p][skill] + state.rng.round_stochastic(gain), 100)


## Works out how much each job gets done per day, for the economy, from this month's workers.
static func measure_work(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var work := {}
	for p: int in state.person_ids.size():
		if state.person_tribes[p] != tribe or state.person_jobs[p].is_empty() or state.person_sick[p] > 0 or state.person_detained[p] > 0:
			continue
		var job := state.person_jobs[p]
		var info: Dictionary = Jobs.DEFINITIONS[job]
		var strength := 0.7 + 0.6 * state.person_skills[p][Jobs.skill_index(job)] / 100.0
		strength *= 0.85 + 0.3 * Genetics.express(state.person_genomes[p], String(info["gene"]))
		strength *= 0.8 + 0.4 * state.person_mood[p] / 100.0
		strength *= 0.5 + 0.5 * state.person_health[p] / 100.0
		var years := People.age(state, p)
		if years < People.ADULT_AT:
			strength *= 0.5
		elif years >= People.ELDER_AT:
			strength *= 0.75
		if state.person_due[p] != -1 and state.person_due[p] - state.tick < 60:
			strength *= 0.5
		elif _nursing(state, p):
			strength *= 0.6
		if People.has_trait(state, p, "lazy"):
			strength *= 0.85
		work[job] = snappedf(float(work.get(job, 0.0)) + strength, WorldState.FLOAT_STEP)
	# The job can stay hunter. Days the herd cannot regrow are foraging, so the camp stays fed.
	# meat_from_hunt does not use this cap: work set by hand can still empty the valley.
	var raw := float(work.get("hunter", 0.0))
	var cap := AnimalSystem.sustainable_hunt_work(AnimalSystem.prey_count(state))
	if raw > cap:
		work["hunter"] = snappedf(cap, WorldState.FLOAT_STEP)
		work["forager"] = snappedf(float(work.get("forager", 0.0)) + (raw - cap), WorldState.FLOAT_STEP)
	state.tribe_work[t] = work


## A mother with a baby under a year old works half days.
static func _nursing(state: WorldState, p: int) -> bool:
	if not People.is_female(state, p):
		return false
	var id := state.person_ids[p]
	for q: int in state.person_ids.size():
		if state.person_mothers[q] == id and state.tick - state.person_born[q] < WorldState.DAYS_PER_YEAR:
			return true
	return false


# --- Building -----------------------------------------------------------------------

## A plan is a building type, or "hut@<id>" to rebuild an old tent as a hut.
static func _plan_type(plan: String) -> String:
	return plan.get_slice("@", 0)


func _plan(state: WorldState, t: int) -> void:
	if state.tribe_project[t] != -1:
		return
	var tribe := state.tribe_names[t]
	var plan := state.tribe_plan[t]
	if plan.is_empty():
		plan = _choose_project(state, t)
		if plan.is_empty():
			return
	var type := _plan_type(plan)
	var info: Dictionary = Buildings.TYPES[type]
	if state.tribe_wood[t] < float(info["wood"]) or state.tribe_stone[t] < float(info["stone"]):
		if state.tribe_plan[t] != plan:
			state.tribe_plan[t] = plan
			var needs := PackedStringArray()
			if float(info["wood"]) > state.tribe_wood[t]:
				needs.append("%d wood" % ceili(float(info["wood"]) - state.tribe_wood[t]))
			if float(info["stone"]) > state.tribe_stone[t]:
				needs.append("%d stone" % ceili(float(info["stone"]) - state.tribe_stone[t]))
			state.log_event("building_planned", {"tribe": tribe, "building": type, "needs": " and ".join(needs)})
		return
	state.tribe_wood[t] -= float(info["wood"])
	state.tribe_stone[t] -= float(info["stone"])
	state.tribe_plan[t] = ""
	var b := -1
	if plan.contains("@"):
		b = state.building_index(plan.get_slice("@", 1).to_int())
		if b != -1:
			state.building_types[b] = type
			state.building_progress[b] = 0
			state.building_done[b] = -1
	if b == -1:
		b = state.add_building(tribe, type, Buildings.free_slot(state, tribe, type)).index
	state.tribe_project[t] = state.building_ids[b]
	state.log_event("building_started", {"tribe": tribe, "building": type, "building_id": state.building_ids[b], "rebuild": 1 if plan.contains("@") else 0})


## What the chief wants built next, or "" if nothing is needed. A plan is a type, or
## "<type>@<id>" to rebuild an old building as something better.
func _choose_project(state: WorldState, t: int) -> String:
	var tribe := state.tribe_names[t]
	var population := state.tribe_population[t]
	var known := state.tribe_knowledge[t]
	var carpentry := "carpentry" in known
	if _housing_short(state, tribe) >= 2:
		if carpentry and not "masonry" in known and population >= 40 and state.count_buildings(tribe, "longhouse") < population / 35:
			return "longhouse"
		return best_home(known, population)
	if "stone_tools" in known and population >= 14 and _count_any(state, tribe, "workshop") == 0:
		return "workshop"
	if "herbal_lore" in known and _count_any(state, tribe, "healer_hut") == 0 and population >= 16:
		return "healer_hut"
	if "pottery" in known and population >= 18 and _count_any(state, tribe, "storehouse") < 1 + population / 70:
		return "storehouse"
	if "agriculture" in known and _count_any(state, tribe, "field") < mini(8, ceili(population / 10.0)) and _island_fields(state) < state.field_room():
		return "field"
	if "rites" in known and population >= 25 and _count_any(state, tribe, "shrine") == 0:
		return "shrine"
	var age_places := _age_project(state, t)
	if age_places:
		return age_places
	var walls := _count_any(state, tribe, "palisade") + _count_any(state, tribe, "stone_wall")
	if population >= 30 and state.ticks_since("war", "", 25 * WorldState.DAYS_PER_YEAR) < 25 * WorldState.DAYS_PER_YEAR:
		if "masonry" in known and _count_any(state, tribe, "stone_wall") == 0:
			for b: int in state.buildings_of(tribe):
				if state.building_types[b] == "palisade" and state.is_built(b):
					return "stone_wall@%d" % state.building_ids[b]
			if walls == 0:
				return "stone_wall"
		elif carpentry and walls == 0:
			return "palisade"
	# Rebuild the humblest home as the best the tribe knows how to build.
	var best := best_home(known, population)
	var rank := Buildings.HOMES.find(best)
	var humblest := -1
	for b: int in state.buildings_of(tribe):
		var home := Buildings.HOMES.find(state.building_types[b])
		if home != -1 and home < rank and state.building_types[b] != "longhouse" and state.is_built(b):
			if humblest == -1 or home < Buildings.HOMES.find(state.building_types[humblest]):
				humblest = b
	if humblest != -1:
		return "%s@%d" % [best, state.building_ids[humblest]]
	return ""


## The best home a tribe knows how to build: denser as the ages pass.
static func best_home(known: PackedStringArray, population: int) -> String:
	if "electricity" in known and population >= 45:
		return "apartment"
	if "steam_power" in known and population >= 30:
		return "rowhouse"
	if "masonry" in known:
		return "stone_house"
	if "carpentry" in known:
		return "hut"
	return "tent"


## The places of the later ages: where people dig, smelt, learn, trade and pray, and where power
## shows itself: the great house, the barracks, the watchtowers, the prison, the ruler's statue, the
## factories, the broadcast tower and the masts that watch.
func _age_project(state: WorldState, t: int) -> String:
	var tribe := state.tribe_names[t]
	var population := state.tribe_population[t]
	var known := state.tribe_knowledge[t]
	if "copper_working" in known and population >= 20 and _count_any(state, tribe, "mine") == 0:
		return "mine"
	if "copper_working" in known and population >= 20 and _count_any(state, tribe, "smithy") == 0:
		return "smithy"
	if "writing" in known and population >= 20 and _count_any(state, tribe, "school") < 1 + population / 80:
		return "school"
	if "coinage" in known and population >= 25 and _count_any(state, tribe, "market") == 0:
		return "market"
	var piety := int(state.tribe_culture[t].get("piety", 0))
	if "masonry" in known and "rites" in known and population >= 35 and _count_any(state, tribe, "temple") == 0 and (piety >= 0 or Society.power(state, t, "priests") >= 30):
		return "temple"
	var ruler := state.chief_of(tribe)
	var ruler_power := Society.power(state, t, "ruler")
	if "masonry" in known and ruler_power >= 45 and _count_any(state, tribe, "great_house") == 0:
		return "great_house"
	if float(state.tribe_work[t].get("guard", 0.0)) >= 3.0 and _count_any(state, tribe, "barracks") == 0:
		return "barracks"
	var control := Society.control(state, t)
	if "bronze" in known and control >= 35 and _count_any(state, tribe, "watchtower") < 1 + control / 35:
		return "watchtower"
	if "masonry" in known and Society.flag(state, t, "detain") and Society.count_where(state, t, "detained") >= 2 and _count_any(state, tribe, "prison") == 0:
		return "prison"
	if "masonry" in known and ruler != -1 and ruler_power >= 60 and (People.has_trait(state, ruler, "proud") or People.has_trait(state, ruler, "greedy")) and _count_any(state, tribe, "statue") == 0:
		return "statue"
	if "steam_power" in known and _count_any(state, tribe, "factory") < 1 + population / 45:
		return "factory"
	if "radio" in known and population >= 30 and _count_any(state, tribe, "broadcast_tower") == 0:
		return "broadcast_tower"
	if Society.has_law(state, t, "surveillance_net") and _count_any(state, tribe, "surveillance_mast") < 1 + population / 60:
		return "surveillance_mast"
	return ""


## Fields on the whole island, built or being built.
func _island_fields(state: WorldState) -> int:
	var count := 0
	for type: String in state.building_types:
		if type == "field":
			count += 1
	return count


func _count_any(state: WorldState, tribe: String, type: String) -> int:
	var count := 0
	for b: int in state.buildings_of(tribe):
		if state.building_types[b] == type:
			count += 1
	return count


## How many people lack a proper bed (no home, crowded homes, couples sharing with another
## couple), less the beds standing empty.
func _housing_short(state: WorldState, tribe: String) -> int:
	var residents := {}
	var couples := {}
	var short := 0
	for p: int in state.people_of(tribe):
		var home := state.person_homes[p]
		if home == -1:
			short += 1
			continue
		residents[home] = int(residents.get(home, 0)) + 1
		if state.person_partners[p] != -1 and People.is_adult(state, p):
			couples[home] = int(couples.get(home, 0)) + 1
	var free := 0
	for b: int in state.buildings_of(tribe):
		if not Buildings.is_home(state.building_types[b]):
			continue
		var id := state.building_ids[b]
		var capacity := Buildings.capacity(state.building_types[b])
		var living := int(residents.get(id, 0))
		short += maxi(living - capacity, 0)
		if int(couples.get(id, 0)) >= 4:
			short += 2
		if living == 0:
			free += capacity
	return maxi(short - free, 0)


## Who lives where. Crowded homes send someone out to a free home: a young couple with their
## children first, then a grown son or daughter. Then everyone without a home finds a bed, with a
## partner or parent if there's room, else wherever there is.
static func settle_homes(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	var capacity := {}
	var residents := {}
	for b: int in state.buildings_of(tribe):
		if Buildings.is_home(state.building_types[b]) and (state.is_built(b) or state.building_progress[b] > 0):
			capacity[state.building_ids[b]] = Buildings.capacity(state.building_types[b])
			residents[state.building_ids[b]] = []
	var members := state.people_of(tribe)
	for p: int in members:
		var home := state.person_homes[p]
		if home != -1 and not residents.has(home):
			state.person_homes[p] = -1
		elif home != -1:
			(residents[home] as Array).append(p)
	for pass_number: int in 4:
		var moved := false
		for home: int in residents:
			var living: Array = residents[home]
			if living.size() <= int(capacity[home]) and _couples_in(state, living) < 2:
				continue
			var unit := _leaving_unit(state, living)
			if unit.is_empty():
				continue
			var destination := -1
			for other: int in residents:
				var room := int(capacity[other]) - (residents[other] as Array).size()
				if other != home and room >= unit.size() and (destination == -1 or (residents[other] as Array).is_empty()):
					destination = other
			if destination == -1:
				continue
			for p: int in unit:
				state.person_homes[p] = destination
				living.erase(p)
				(residents[destination] as Array).append(p)
			state.life(state.person_ids[unit[0]], "Moved into a home of %s own." % ("their" if unit.size() > 1 else People.possessive(state, unit[0])), "home")
			moved = true
		if not moved:
			break
	for p: int in members:
		if state.person_homes[p] != -1:
			continue
		var best := -1
		for id: int in [state.person_partners[p], state.person_mothers[p], state.person_fathers[p]]:
			var q := state.index_of(id)
			if q != -1 and state.person_tribes[q] == tribe and state.person_homes[q] != -1:
				var home := state.person_homes[q]
				if (residents[home] as Array).size() < int(capacity[home]) + 2:
					best = home
					break
		if best == -1:
			for home: int in residents:
				var room := int(capacity[home]) - (residents[home] as Array).size()
				if room > 0 and (best == -1 or room > int(capacity[best]) - (residents[best] as Array).size()):
					best = home
		if best != -1:
			state.person_homes[p] = best
			(residents[best] as Array).append(p)


static func _couples_in(state: WorldState, living: Array) -> int:
	var count := 0
	for p: int in living:
		var partner := state.index_of(state.person_partners[p])
		if partner != -1 and partner in living:
			count += 1
	@warning_ignore("integer_division")
	return count / 2


## Who moves out of a crowded home: the youngest couple (with their children), if there's more than
## one couple; else the eldest grown, unmarried son or daughter.
static func _leaving_unit(state: WorldState, living: Array) -> Array[int]:
	var couples: Array[int] = []
	for p: int in living:
		var partner := state.index_of(state.person_partners[p])
		if partner != -1 and partner in living and state.person_ids[p] < state.person_partners[p]:
			couples.append(p)
	if couples.size() >= 2:
		couples.sort_custom(func(a: int, b: int) -> bool: return state.person_born[a] > state.person_born[b])
		var p := couples[0]
		var unit: Array[int] = [p, state.index_of(state.person_partners[p])]
		for q: int in living:
			var parents := [state.person_mothers[q], state.person_fathers[q]]
			if (state.person_ids[p] in parents or state.person_partners[p] in parents) and People.age(state, q) < People.ADULT_AT:
				unit.append(q)
		return unit
	var eldest := -1
	for p: int in living:
		if state.person_partners[p] == -1 and People.is_adult(state, p) and People.age(state, p) < 40:
			var has_parent_here := false
			for q: int in living:
				if state.person_ids[q] in [state.person_mothers[p], state.person_fathers[p]]:
					has_parent_here = true
			if has_parent_here and (eldest == -1 or state.person_born[p] < state.person_born[eldest]):
				eldest = p
	var single: Array[int] = []
	if eldest != -1:
		single.append(eldest)
	return single


## Once a year, when a tribe has far more beds than people, an empty home comes down and half
## its wood is reused.
func _take_down_empty_home(state: WorldState, t: int) -> void:
	var tribe := state.tribe_names[t]
	if Needs.home_capacity(state, tribe) <= state.tribe_population[t] * 1.2 + 6:
		return
	var used := {}
	for p: int in state.people_of(tribe):
		used[state.person_homes[p]] = true
	for b: int in state.buildings_of(tribe):
		var id := state.building_ids[b]
		if Buildings.is_home(state.building_types[b]) and state.is_built(b) and not used.has(id):
			state.tribe_wood[t] += float(Buildings.TYPES[state.building_types[b]]["wood"]) * 0.5
			state.remove_building(b)
			return
